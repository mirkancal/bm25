// bm25.dart  (formerly bm25_fast.dart)
// --------------------------------------------------
// Ultra-fast BM25 with *native filtering* on arbitrary fields.
import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:collection';
import 'package:async/async.dart';

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

  // Indexed fields for validation
  final Set<String> _indexedFields;

  // Worker isolate handle
  Isolate? _iso;
  SendPort? _worker;
  CancelableOperation<SendPort>? _spawnOp; // Cancellable spawn operation
  bool _isDisposing = false;
  bool _isDisposed = false;

  // Track active searches for graceful disposal
  final List<Future<List<SearchResult>>> _activeSearches = [];

  // Completes exactly once when dispose() starts. All waits can listen to it.
  // This is only initialized in the main instance, not in worker instances.
  late final Completer<void> _disposeSignal = Completer<void>.sync();

  BM25._(
    this._docs,
    this._dict,
    this._post,
    this._norm,
    this._fieldIndex,
    this._indexedFields,
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
  /// Searches the corpus for documents matching the query.
  ///
  /// [filter] - Optional metadata filters. Keys must be indexed fields.
  /// Values must be primitives (String, num, bool) or List of primitives.
  /// Custom objects are not supported due to isolate message passing constraints.
  /// Example: {'filePath': 'doc.pdf', 'tags': ['important', 'review']}
  Future<List<SearchResult>> search(
    String query, {
    int limit = 10,
    Map<String, Object>? filter,
    Set<String>? stopWords,
  }) async {
    if (query.trim().isEmpty) return const [];
    if (limit < 1) throw RangeError('limit must be ≥ 1');

    // Check if disposed or being disposed
    if (_isDisposed) {
      throw StateError('Cannot search: BM25 instance has been disposed');
    }
    if (_isDisposing) {
      throw StateError('Cannot search: BM25 instance is being disposed');
    }

    // A future that completes when we begin disposing.
    final cancelToken = _disposeSignal.future;

    // Check if isolate was killed
    if (_iso == null && _worker != null) {
      // Isolate was killed, reset worker
      _worker = null;
    }

    if (_worker == null) {
      // Double check we're not disposed while waiting
      if (_isDisposed) {
        throw StateError('Cannot search: BM25 instance has been disposed');
      }

      // Prevent double-spawn race with cancellable operation
      _spawnOp ??= CancelableOperation<SendPort>.fromFuture(_spawnWorker());
      try {
        // Race the worker-spawn against disposal.
        _worker = await Future.any<SendPort>([
          _spawnOp!.value,
          cancelToken.then(
              (_) => throw StateError('Search cancelled: BM25 is disposing')),
        ]);
      } catch (e) {
        // If we're disposing, convert any spawn error to a clear message
        if (_isDisposing) {
          throw StateError('Search cancelled: BM25 instance is being disposed');
        }
        // Clear the operation on error so next search can retry
        _spawnOp = null;
        rethrow;
      } finally {
        // Always reset so next search can retry if needed
        _spawnOp = null;
      }
    }

    // Create a future that we can track
    final searchFuture =
        _performSearch(query, limit, filter, stopWords, cancelToken);
    _activeSearches.add(searchFuture);

    try {
      return await searchFuture;
    } finally {
      _activeSearches.remove(searchFuture);
    }
  }

  Future<List<SearchResult>> _performSearch(
    String query,
    int limit,
    Map<String, dynamic>? filter,
    Set<String>? stopWords,
    Future<void> cancelToken,
  ) async {
    // Defensive check in case called after disposal
    if (_isDisposed || _isDisposing) {
      throw StateError('Cannot perform search: instance disposing/disposed');
    }

    final rp = ReceivePort();
    try {
      _worker!.send([rp.sendPort, query, limit, filter, stopWords]);

      // Add timeout to prevent hanging if isolate is killed
      final response = await Future.any<List>([
        rp.first
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => throw StateError(
                  'Search timed out - worker may have been disposed'),
            )
            .then((value) => value as List),
        cancelToken.then<List>(
            (_) => throw StateError('Search cancelled: BM25 is disposing')),
      ]);

      if (response[0] == 'error') {
        throw ArgumentError(response[1] as String);
      }

      return response[1] as List<SearchResult>;
    } finally {
      // Always close the ReceivePort to prevent leaks
      rp.close();
    }
  }

  Future<void> dispose() async {
    // If already disposed, return immediately
    if (_isDisposed) return;

    // Prevent new searches during disposal
    _isDisposing = true;
    // Notify every waiter exactly once.
    if (!_disposeSignal.isCompleted) {
      _disposeSignal.complete();
    }

    // 1. Abort any in-flight spawn immediately
    if (_spawnOp != null) {
      // Cancel and wait for it to complete (either successfully or with error)
      await _spawnOp!.cancel();
      _spawnOp = null;
    }

    // 2. Wait for **all** active searches. No timeout here - those
    //    searches still need the worker; killing it early causes a hang.
    if (_activeSearches.isNotEmpty) {
      try {
        await Future.wait(_activeSearches, eagerError: false);
      } catch (_) {
        // Swallow individual State / Cancelled errors - we only care
        // that every Future completes.
      }
    }

    if (_worker != null && _iso != null) {
      // Create a new port specifically for shutdown acknowledgment
      final shutdownPort = ReceivePort();
      // Send shutdown signal with acknowledgment port
      _worker!.send([null, shutdownPort.sendPort]);

      try {
        // Wait for acknowledgment with timeout
        await shutdownPort.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
      } catch (_) {
        // Timeout occurred or error, proceed with cleanup
      } finally {
        // Always clean up
        shutdownPort.close();
      }

      // Clean up
      _worker = null;
      _spawnOp = null;
      // Use graceful shutdown priority
      _iso?.kill(priority: Isolate.beforeNextEvent);
      _iso = null;
    }

    _isDisposing = false;
    _isDisposed = true;
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
    for (final t in terms) {
      needed += pb[t]!.length;
    }
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
    for (final f in fields) {
      fieldIx[f] = {};
    }
    for (final d in docs) {
      for (final f in fields) {
        final v = d.meta[f];
        if (v == null) continue;

        // Handle lists specially - index each item
        if (v is List) {
          for (final item in v) {
            final key = item.toString();
            fieldIx[f]!.putIfAbsent(key, () => []).add(d.id);
          }
        } else {
          // Convert single values to string for indexing
          final key = v.toString();
          fieldIx[f]!.putIfAbsent(key, () => []).add(d.id);
        }
      }
    }
    final frozen = fieldIx.map((f, m) => MapEntry(
        f, m.map((v, l) => MapEntry(v, Uint32List.fromList(l)..sort()))));

    return BM25._(docs, dict, post, norm, frozen, fields.toSet());
  }

  /*──────────────  WORKER  ──────────────*/
  Future<SendPort> _spawnWorker() async {
    final initPort = ReceivePort();

    try {
      // Create a copy without the isolate-related fields
      final workerData =
          BM25._(_docs, _dict, _post, _norm, _fieldIndex, _indexedFields);

      // Spawn with hard timeout
      _iso = await Isolate.spawn(
        _workerMain,
        [initPort.sendPort, workerData],
        debugName: 'bm25-worker',
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Worker spawn timeout'),
      );

      // Check if we're being disposed
      if (_isDisposing) {
        _iso?.kill();
        _iso = null;
        initPort.close();
        throw StateError('BM25 instance is being disposed');
      }

      // Handshake with hard timeout
      final sendPort = await initPort.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Worker init timeout'),
      ) as SendPort;

      // Close the port now that we have the SendPort
      // We don't need it anymore since we use a separate port for shutdown
      initPort.close();

      return sendPort;
    } catch (e) {
      // Clean up on error
      initPort.close();
      _iso?.kill();
      _iso = null;
      rethrow;
    }
  }

  static void _workerMain(List<Object?> args) async {
    final init = args[0] as SendPort;
    final BM25 idx = args[1] as BM25;
    final rx = ReceivePort();
    init.send(rx.sendPort);

    await for (final msg in rx) {
      if (msg == null) {
        // Shutdown signal received (old protocol, for compatibility)
        rx.close();
        break;
      }

      final list = msg as List;

      // Check if this is a shutdown request with acknowledgment port
      if (list[0] == null && list.length > 1) {
        // New shutdown protocol with acknowledgment
        final ackPort = list[1] as SendPort;
        rx.close();
        ackPort.send(null); // Send acknowledgment
        break;
      }

      final reply = list[0] as SendPort;
      final q = list[1] as String;
      final lim = list[2] as int;
      final filt = list[3] as Map<String, Object>?;
      final stop = list[4] as Set<String>?;

      try {
        final results = idx._scoreSync(q, lim, filt, stop);
        reply.send(['ok', results]);
      } catch (e) {
        reply.send(['error', e.toString()]);
      }
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
      // Validate filter fields
      final invalidFields =
          filter.keys.where((k) => !_indexedFields.contains(k));
      if (invalidFields.isNotEmpty) {
        throw ArgumentError(
            'Filter contains non-indexed fields: ${invalidFields.join(", ")}. '
            'Available indexed fields: ${_indexedFields.join(", ")}');
      }

      // Process all filter entries and compute intersection
      for (final entry in filter.entries) {
        final field = entry.key;
        final vals = (entry.value is Iterable)
            ? entry.value as Iterable
            : [entry.value]; // scalar → single-element list

        // Collect all document IDs for this field's values
        final fieldDocs = HashSet<int>();
        for (final v in vals) {
          final ids = _fieldIndex[field]?[v.toString()];
          if (ids != null) fieldDocs.addAll(ids);
        }

        // Compute intersection with existing allowed set
        if (allowed == null) {
          allowed = fieldDocs;
        } else {
          allowed = HashSet<int>.from(allowed.intersection(fieldDocs));
          if (allowed.isEmpty) return const []; // Early exit if no matches
        }
      }

      if (allowed?.isEmpty ?? false) return const [];
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
  // Unicode-aware word pattern
  static final _unicodeWordPattern =
      RegExp(r'\p{L}[\p{L}\p{N}_]*', unicode: true);

  static List<String> _tokenise(String text, Set<String>? stop) {
    // Fast check for pure ASCII
    bool isPureAscii = true;
    for (int i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) > 127) {
        isPureAscii = false;
        break;
      }
    }

    if (isPureAscii) {
      return _tokeniseAscii(text, stop);
    } else {
      return _tokeniseUnicode(text, stop);
    }
  }

  static List<String> _tokeniseAscii(String text, Set<String>? stop) {
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
        if (w.length >= 2 && (stop == null || !stop.contains(w))) out.add(w);
        start = -1;
      }
    }
    if (start != -1) {
      final w = String.fromCharCodes(codes, start).toLowerCase();
      if (w.length >= 2 && (stop == null || !stop.contains(w))) out.add(w);
    }
    return out;
  }

  static List<String> _tokeniseUnicode(String text, Set<String>? stop) {
    final tokens = <String>[];
    final matches = _unicodeWordPattern.allMatches(text.toLowerCase());

    for (final match in matches) {
      final token = match[0]!;
      if (token.length >= 2 && (stop == null || !stop.contains(token))) {
        tokens.add(token);
      }
    }

    return tokens;
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
