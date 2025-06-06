// bm25.dart  (formerly bm25_fast.dart)
// --------------------------------------------------
// Ultra-fast BM25 with *native filtering* on arbitrary fields.
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:collection';

import 'bm25_document.dart';
import 'search_result.dart';

// ──────────────────────────  PRIVATE TYPES  ──────────────────────────
class _TermInfo {
  final int off; // postings start offset
  final int len; // postings length (in Uint32s)
  final double idf;
  const _TermInfo(this.off, this.len, this.idf);
}

// ────────────────────────────  BM25 CORE  ────────────────────────────
class BM25 {
  // Tunables
  static const double _k1 = 1.2, _b = 0.75;

  // Immutable corpus state
  final List<BM25Document> _docs;
  final Map<String, _TermInfo> _dict;
  final Uint32List _post;
  final Float64List _norm;

  // Field → value → sorted docIds (for filtering)
  final Map<String, Map<String, Uint32List>> _fieldIndex;

  // Worker isolate handle
  Isolate? _iso;
  SendPort? _worker;

  BM25._(
    this._docs,
    this._dict,
    this._post,
    this._norm,
    this._fieldIndex,
  );

  /*──────────────  PUBLIC BUILD  ──────────────*/
  static Future<BM25> build(
    Iterable<dynamic> docs, {
    List<String> indexFields = const ['filePath'],
    Set<String>? stopWords,
  }) {
    // Handle both string documents and BM25Document objects
    final bm25Docs = <BM25Document>[];
    var id = 0;
    for (final doc in docs) {
      if (doc is String) {
        final terms = _tokenise(doc, stopWords);
        bm25Docs.add(BM25Document(
          id: id++,
          text: doc,
          terms: terms,
        ));
      } else if (doc is BM25Document) {
        // Reassign IDs and retokenize to ensure consistency
        final terms = _tokenise(doc.text, stopWords);
        bm25Docs.add(BM25Document(
          id: id++,
          text: doc.text,
          terms: terms,
          meta: doc.meta,
        ));
      } else {
        throw ArgumentError('Documents must be either String or BM25Document');
      }
    }
    if (bm25Docs.isEmpty) {
      throw ArgumentError('Corpus must contain at least one document');
    }
    return Isolate.run(() => _buildSync(bm25Docs, indexFields, stopWords));
  }

  /*──────────────  SEARCH  ──────────────*/
  Future<List<SearchResult>> search(
    String query, {
    int limit = 10,
    Map<String, Object>? filter, // {'filePath': 'a.pdf'} or list
    Set<String>? stopWords,
  }) async {
    if (query.trim().isEmpty) return const [];
    if (limit < 1) throw RangeError('limit must be ≥ 1');

    _worker ??= await _spawnWorker();
    final rp = ReceivePort();
    _worker!.send([rp.sendPort, query, limit, filter, stopWords]);
    return await rp.first as List<SearchResult>;
  }

  Future<void> dispose() async {
    _worker?.send(null);
    _worker = null;
    _iso?.kill(priority: Isolate.immediate);
    _iso = null;
  }

  /*──────────────  PRIVATE BUILD  ──────────────*/
  static BM25 _buildSync(
    List<BM25Document> docs,
    List<String> fields,
    Set<String>? stop,
  ) {
    // Term → [docId, tf, docId, tf, ...]
    final pb = <String, List<int>>{};
    final docLen = Uint32List(docs.length);

    for (final d in docs) {
      docLen[d.id] = d.terms.length;
      final tf = <String, int>{};
      for (final t in d.terms) {
        if (stop != null && stop.contains(t)) continue;
        tf[t] = (tf[t] ?? 0) + 1;
      }
      tf.forEach((t, n) => pb.putIfAbsent(t, () => []).addAll([d.id, n]));
    }

    // Build postings array
    final terms = pb.keys.toList(growable: false)..sort();
    var needed = 0;
    for (final t in terms) needed += pb[t]!.length;
    final post = Uint32List(needed);

    final dict = <String, _TermInfo>{};
    var cur = 0, nDocs = docs.length;
    for (final t in terms) {
      final list = pb[t]!;
      // Sort pairs by docId - convert to pairs, sort, then flatten
      final pairs = <List<int>>[];
      for (var i = 0; i < list.length; i += 2) {
        pairs.add([list[i], list[i + 1]]);
      }
      pairs.sort((a, b) => a[0].compareTo(b[0]));

      final start = cur;
      var last = 0;
      for (final pair in pairs) {
        final doc = pair[0];
        final tf = pair[1];
        final delta = (last == 0) ? doc : doc - last;
        post[cur++] = delta;
        post[cur++] = tf;
        last = doc;
      }
      final df = list.length >> 1;
      final idf = math.log(((nDocs - df + 0.5) / (df + 0.5)) + 1.0);
      dict[t] = _TermInfo(start, cur - start, idf);
    }

    // Norms
    final avg = docLen.reduce((a, b) => a + b) / docLen.length;
    final norm = Float64List(docLen.length);
    for (var i = 0; i < norm.length; ++i) {
      norm[i] = (1 - _b) + _b * (docLen[i] / avg);
    }

    // Field index
    final fieldIx = <String, Map<String, List<int>>>{};
    for (final f in fields) fieldIx[f] = {};
    for (final d in docs) {
      for (final f in fields) {
        final v = d.meta[f];
        if (v == null) continue;
        fieldIx[f]!.putIfAbsent(v, () => []).add(d.id);
      }
    }
    final frozen = fieldIx.map((f, m) => MapEntry(
        f, m.map((v, l) => MapEntry(v, Uint32List.fromList(l)..sort()))));

    return BM25._(docs, dict, post, norm, frozen);
  }

  /*──────────────  WORKER  ──────────────*/
  Future<SendPort> _spawnWorker() async {
    final ready = ReceivePort();
    _iso = await Isolate.spawn(_workerMain, [ready.sendPort, this],
        debugName: 'bm25-worker');
    return await ready.first as SendPort;
  }

  static void _workerMain(List<Object?> args) async {
    final init = args[0] as SendPort;
    final BM25 idx = args[1] as BM25;
    final rx = ReceivePort();
    init.send(rx.sendPort);

    await for (final msg in rx) {
      if (msg == null) break;
      final list = msg as List;
      final reply = list[0] as SendPort;
      final q = list[1] as String;
      final lim = list[2] as int;
      final filt = list[3] as Map<String, Object>?;
      final stop = list[4] as Set<String>?;
      reply.send(idx._scoreSync(q, lim, filt, stop));
    }
  }

  /*──────────────  SCORER  ──────────────*/
  List<SearchResult> _scoreSync(
    String query,
    int k,
    Map<String, Object>? filter,
    Set<String>? stop,
  ) {
    final toks = _tokenise(query, stop);
    if (toks.isEmpty) return const [];

    // -------- Build allowed set if filter present
    HashSet<int>? allowed;
    if (filter != null && filter.isNotEmpty) {
      allowed = HashSet<int>();
      final kv = filter.entries.first;
      final field = kv.key;
      final vals = (kv.value is Iterable)
          ? kv.value as Iterable
          : [kv.value]; // scalar → single-element list
      for (final v in vals) {
        final ids = _fieldIndex[field]?[v.toString()];
        if (ids != null) allowed.addAll(ids);
      }
      if (allowed.isEmpty) return const [];
    }

    // -------- Score
    final scores = Float64List(_docs.length);
    final touched = <int>[];

    for (final t in toks) {
      final info = _dict[t];
      if (info == null) continue;
      var p = info.off, end = p + info.len, doc = 0;
      final idf = info.idf;

      while (p < end) {
        doc += _post[p++];
        final tf = _post[p++];
        if (allowed != null && !allowed.contains(doc)) continue;

        final denom = tf + _k1 * _norm[doc];
        final delta = idf * (tf * (_k1 + 1) / denom);
        if (scores[doc] == 0) touched.add(doc);
        scores[doc] += delta;
      }
    }
    if (touched.isEmpty) return const [];
    return _topK(scores, touched, k);
  }

  /*──────────────  HELPERS  ──────────────*/
  static List<String> _tokenise(String text, Set<String>? stop) {
    final out = <String>[];
    final codes = text.codeUnits;
    var start = -1;
    bool isWord(int c) =>
        ((c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a) || // a-z
        (c >= 0x30 && c <= 0x39) || // 0-9
        c == 0x5f; // _
    for (var i = 0; i < codes.length; ++i) {
      final c = codes[i];
      if (isWord(c)) {
        if (start == -1) start = i;
      } else if (start != -1) {
        final w = String.fromCharCodes(codes, start, i).toLowerCase();
        if (stop == null || !stop.contains(w)) out.add(w);
        start = -1;
      }
    }
    if (start != -1) {
      final w = String.fromCharCodes(codes, start).toLowerCase();
      if (stop == null || !stop.contains(w)) out.add(w);
    }
    return out;
  }

  List<SearchResult> _topK(Float64List s, List<int> docs, int k) {
    if (docs.isEmpty) return const [];
    if (k >= docs.length) {
      docs.sort((a, b) => s[b].compareTo(s[a]));
      return [for (final d in docs.take(k)) SearchResult(_docs[d], s[d])];
    }
    final heapDoc = Uint32List(k);
    final heapVal = Float64List(k);
    var size = 0;

    void up(int i) {
      while (i > 0) {
        final p = (i - 1) >> 1;
        if (heapVal[i] >= heapVal[p]) break;
        final tempVal = heapVal[i];
        final tempDoc = heapDoc[i];
        heapVal[i] = heapVal[p];
        heapDoc[i] = heapDoc[p];
        heapVal[p] = tempVal;
        heapDoc[p] = tempDoc;
        i = p;
      }
    }

    void down(int i) {
      while (true) {
        final l = (i << 1) + 1;
        if (l >= size) break;
        final r = l + 1;
        var sIdx = l;
        if (r < size && heapVal[r] < heapVal[l]) sIdx = r;
        if (heapVal[i] <= heapVal[sIdx]) break;
        final tempVal = heapVal[i];
        final tempDoc = heapDoc[i];
        heapVal[i] = heapVal[sIdx];
        heapDoc[i] = heapDoc[sIdx];
        heapVal[sIdx] = tempVal;
        heapDoc[sIdx] = tempDoc;
        i = sIdx;
      }
    }

    for (final d in docs) {
      final v = s[d];
      if (size < k) {
        heapDoc[size] = d;
        heapVal[size] = v;
        up(size++);
      } else if (v > heapVal[0]) {
        heapDoc[0] = d;
        heapVal[0] = v;
        down(0);
      }
    }

    final out = <SearchResult>[];
    for (var i = 0; i < size; ++i) {
      out.add(SearchResult(_docs[heapDoc[i]], heapVal[i]));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}
