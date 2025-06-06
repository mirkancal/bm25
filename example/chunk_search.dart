import 'package:bm25/bm25.dart';

// Example: BM25 on document chunks for RAG applications
class ChunkSearchExample {
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
    final BM25 bm25;
    final List<Chunk> chunks;
    
    HybridChunkSearch(this.chunks) 
      : bm25 = BM25(
          documents: chunks.map((chunk) => 
            Document(
              id: chunk.id,
              content: chunk.content,
              metadata: {
                'documentId': chunk.documentId,
                'chunkIndex': chunk.chunkIndex,
              },
            )
          ).toList(),
        );
    
    List<Chunk> search(
      String query, {
      int? limit,
      bool useVectorSearch = true,
      double bm25Weight = 0.5,
    }) {
      // Get BM25 results
      var bm25Results = bm25.search(query, limit: limit);
      
      // In real implementation, combine with vector search
      // var vectorResults = vectorStore.search(query);
      // return combineResults(bm25Results, vectorResults, bm25Weight);
      
      // For now, just return BM25 results
      return bm25Results.map((result) {
        return chunks.firstWhere((c) => c.id == result.document.id);
      }).toList();
    }
  }
}

void main() {
  print('Chunk-based BM25 search example created!');
}
