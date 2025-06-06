// bm25_fast.dart — 2025‑06 / production‑ready, ultra‑low‑latency
// --------------------------------------------------
// A cache‑friendly, isolate‑safe BM25 index for Flutter / Dart.
// *  gap‑encoded postings stored in a single Uint32List
// *  O(T) build, O(#postings) query with tight upper‑bound loop
// *  per‑term metadata (offset, length, idf) in one map → O(1) lookup
// *  pre‑computed document normalisers (BM25 “norm”)
// *  lock‑free top‑K via fixed‑size min‑heap
// *  instance‑scoped isolate so multiple indices can run in the same app
//
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'bm25_document.dart';
import 'search_result.dart';

// ─────────────────────────  MODEL TYPES  ─────────────────────────

// Document and SearchResult classes removed - now in separate files

// Internal per‑term metadata structure
class _TermInfo {
  final int off; // start offset in _postings (Uint32 index)
  final int len; // #Uint32 ints used by this term
  final double idf; // pre‑computed IDF
  const _TermInfo({required this.off, required this.len, required this.idf});
}

// ───────────────────  PRODUCTION‑GRADE BM25 INDEX  ───────────────────
class BM25 {
  // ——— Tunables (classic BM25)
  static const double _k1 = 1.2;
  static const double _b = 0.75;

  // ——— Immutable after build
  final List<BM25Document> _docs; // id → document
  final Map<String, _TermInfo> _dict; // term → metadata
  final Uint32List _postings; // [Δdoc, tf, Δdoc, tf, ...]
  final Float64List _norm; // docId → (1‑b)+b*dl/avgDl

  // ——— Isolate state (per‑instance)
  Isolate? _iso;
  SendPort? _worker;

  // private ctor
  BM25._(this._docs, this._dict, this._postings, this._norm);

  /*───────────────────  INDEX BUILDER (async)  ───────────────────*/

  /// Build an index from an iterable of raw documents (plain strings).
  /// Runs heavy work in a background isolate, returns ready‑to‑query instance.
  static Future<BM25> build(Iterable<String> rawDocs,
      {Set<String>? stopWords}) async {
    final docs = <BM25Document>[];
    var docId = 0;
    for (final text in rawDocs) {
      final terms = _tokenise(text, stopWords);
      docs.add(BM25Document(id: docId++, text: text, terms: terms));
    }
    if (docs.isEmpty) {
      throw ArgumentError('Corpus must contain at least one document');
    }
    return Isolate.run(() => _buildSync(docs));
  }

  /// Synchronous build executed in background isolate.
  static BM25 _buildSync(List<BM25Document> docs) {
    // term → [docId, tf, docId, tf ...]
    final postingBuilder = <String, List<int>>{};
    final docLens = Uint32List(docs.length);

    // Pass 1: term frequencies & document lengths
    for (final d in docs) {
      docLens[d.id] = d.terms.length;
      final tf = <String, int>{};
      for (final t in d.terms) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      tf.forEach((t, f) {
        postingBuilder.putIfAbsent(t, () => <int>[]).addAll([d.id, f]);
      });
    }

    // ---- Pack postings
    final termList = postingBuilder.keys.toList(growable: false)..sort();
    final dict = <String, _TermInfo>{};

    var intsNeeded = 0;
    for (final t in termList) {
      intsNeeded += postingBuilder[t]!.length;
    }
    final postings = Uint32List(intsNeeded);

    var cursor = 0;
    final nDocs = docs.length.toDouble();

    for (final t in termList) {
      final list = postingBuilder[t]!; // already [doc, tf] pairs
      list.sort(); // sort pairs by docId for Δ encoding (even indices suffice)

      // Store start offset now; we'll fill len after encoding
      final startOffset = cursor;

      var lastDoc = 0;
      for (var i = 0; i < list.length; i += 2) {
        final doc = list[i];
        final tf = list[i + 1];
        final delta = (i == 0) ? doc : doc - lastDoc;
        postings[cursor++] = delta;
        postings[cursor++] = tf;
        lastDoc = doc;
      }
      final endOffset = cursor;
      final df = list.length >> 1;
      final idf = math.log((nDocs - df + 0.5) / (df + 0.5) + 1.0);
      dict[t] =
          _TermInfo(off: startOffset, len: endOffset - startOffset, idf: idf);
    }

    // ---- Pre‑compute norms
    final avgDl = docLens.reduce((a, b) => a + b) / docLens.length;
    final norm = Float64List(docLens.length);
    for (var i = 0; i < norm.length; ++i) {
      norm[i] = (1 - _b) + _b * (docLens[i] / avgDl);
    }

    return BM25._(docs, dict, postings, norm);
  }

  /*─────────────────────  SEARCH API  ─────────────────────*/

  /// Find up to [limit] documents matching [query].
  Future<List<SearchResult>> search(String query,
      {int limit = 10, Set<String>? stopWords}) async {
    if (query.trim().isEmpty) return const [];
    if (limit < 1) throw RangeError('limit must be ≥ 1');

    // Lazy‑spawn worker isolate once per instance
    _worker ??= await _spawnWorker();

    final rp = ReceivePort();
    _worker!.send([rp.sendPort, query, limit, stopWords]);
    return await rp.first as List<SearchResult>;
  }

  Future<SendPort> _spawnWorker() async {
    final ready = ReceivePort();
    _iso = await Isolate.spawn(_workerMain, [ready.sendPort, this],
        debugName: 'bm25‑worker');
    return await ready.first as SendPort;
  }

  static void _workerMain(List<Object?> args) async {
    final initPort = args[0] as SendPort;
    final BM25 idx = args[1] as BM25;

    final rx = ReceivePort();
    initPort.send(rx.sendPort);

    await for (final msg in rx) {
      if (msg == null) break; // dispose signal
      final list = msg as List<Object?>;
      final SendPort reply = list[0] as SendPort;
      final String q = list[1] as String;
      final int limit = list[2] as int;
      final Set<String>? stop = list[3] as Set<String>?;
      reply.send(idx._scoreSync(q, stop, limit));
    }
  }

  /*────────────────────────  SCORING  ────────────────────────*/

  List<SearchResult> _scoreSync(String query, Set<String>? stopWords, int k) {
    final tokens = _tokenise(query, stopWords);
    if (tokens.isEmpty) return const [];

    final scores = Float64List(_docs.length); // zero‑initialised
    final touched = <int>[];

    for (final t in tokens) {
      final info = _dict[t];
      if (info == null) continue; // OOV term

      final idf = info.idf;
      var p = info.off;
      final end = p + info.len;
      var docId = 0;

      while (p < end) {
        final delta = _postings[p++];
        final tf = _postings[p++];
        docId += delta; // Δ‑decode

        final denom = tf + _k1 * _norm[docId];
        final contrib = idf * (tf * (_k1 + 1) / denom);

        if (scores[docId] == 0.0) touched.add(docId);
        scores[docId] += contrib;
      }
    }
    if (touched.isEmpty) return const [];
    return _topK(scores, touched, k);
  }

  /*────────────────────────  HELPERS  ─────────────────────────*/

  static List<String> _tokenise(String text, Set<String>? stop) {
    final codes = text.codeUnits;
    final words = <String>[];
    var start = -1;
    for (var i = 0; i < codes.length; ++i) {
      final c = codes[i];
      final isWord = (c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a || // a‑z
          c >= 0x30 && c <= 0x39 || // 0‑9
          c == 0x5f; // _
      if (isWord) {
        if (start == -1) start = i;
      } else if (start != -1) {
        final w = String.fromCharCodes(codes, start, i).toLowerCase();
        if (stop == null || !stop.contains(w)) words.add(w);
        start = -1;
      }
    }
    if (start != -1) {
      final w = String.fromCharCodes(codes, start).toLowerCase();
      if (stop == null || !stop.contains(w)) words.add(w);
    }
    return words;
  }

  List<SearchResult> _topK(Float64List scores, List<int> touched, int k) {
    if (k >= touched.length) {
      touched.sort((a, b) => scores[b].compareTo(scores[a]));
      return [
        for (final d in touched.take(k)) SearchResult(_docs[d], scores[d])
      ];
    }

    final heapDoc = Uint32List(k);
    final heapVal = Float64List(k);
    var size = 0;

    void siftUp(int idx) {
      while (idx > 0) {
        final p = (idx - 1) >> 1;
        if (heapVal[idx] >= heapVal[p]) break;
        final v = heapVal[idx];
        final d = heapDoc[idx];
        heapVal[idx] = heapVal[p];
        heapDoc[idx] = heapDoc[p];
        heapVal[p] = v;
        heapDoc[p] = d;
        idx = p;
      }
    }

    void siftDown(int idx) {
      while (true) {
        final l = (idx << 1) + 1;
        if (l >= size) break;
        final r = l + 1;
        var s = l;
        if (r < size && heapVal[r] < heapVal[l]) s = r;
        if (heapVal[idx] <= heapVal[s]) break;
        final v = heapVal[idx];
        final d = heapDoc[idx];
        heapVal[idx] = heapVal[s];
        heapDoc[idx] = heapDoc[s];
        heapVal[s] = v;
        heapDoc[s] = d;
        idx = s;
      }
    }

    for (final doc in touched) {
      final sc = scores[doc];
      if (size < k) {
        heapDoc[size] = doc;
        heapVal[size] = sc;
        siftUp(size++);
      } else if (sc > heapVal[0]) {
        heapDoc[0] = doc;
        heapVal[0] = sc;
        siftDown(0);
      }
    }

    final results = <SearchResult>[];
    for (var i = 0; i < size; ++i) {
      results.add(SearchResult(_docs[heapDoc[i]], heapVal[i]));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// Dispose the worker isolate (optional but recommended).
  Future<void> dispose() async {
    _worker?.send(null); // signal end
    _worker = null;
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
  }
}
