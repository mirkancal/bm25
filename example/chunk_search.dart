import 'package:bm25/bm25.dart';

// Represents a chunk from your vector store
class Chunk {
  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  final List<double>? embedding; // From vector store

  Chunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
    this.embedding,
  });
}

class HybridChunkSearch {
  late final Future<BM25> _bm25Future;
  final List<Chunk> chunks;

  HybridChunkSearch(this.chunks) {
    _bm25Future = BM25.build(chunks.map((c) => c.content));
  }

  Future<List<Chunk>> search(
    String query, {
    int? limit,
    bool useVectorSearch = true,
    double bm25Weight = 0.5,
  }) async {
    // Get BM25 results
    final bm25 = await _bm25Future;
    var bm25Results = await bm25.search(query, limit: limit ?? 10);

    // In real implementation, combine with vector search
    // var vectorResults = vectorStore.search(query);
    // return combineResults(bm25Results, vectorResults, bm25Weight);

    // For now, just return BM25 results
    return bm25Results.map((result) {
      return chunks[result.doc.id];
    }).toList();
  }
}

void main() {
  print('Chunk-based BM25 search example created!');
}
