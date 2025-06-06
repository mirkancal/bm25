# BM25 for Dart

A pure Dart implementation of the BM25 ranking algorithm for full-text search. Perfect for adding relevance-based text search to your Dart/Flutter applications.

## Features

- **Pure Dart implementation** - No native dependencies
- **Async support** - Build indices asynchronously for large document sets
- **Customizable parameters** - Fine-tune k1 and b parameters
- **Memory efficient** - Suitable for mobile and web applications
- **Easy integration** - Works great with vector search for hybrid search systems

## Installation

```yaml
dependencies:
  bm25: ^1.0.0
```

## Quick Start

```dart
import 'package:bm25/bm25.dart';

void main() async {
  // Simple search with strings
  final documents = [
    'The quick brown fox jumps over the lazy dog',
    'The lazy cat sleeps all day',
    'A quick brown dog runs through the park',
    'The fox is cunning and quick',
  ];

  // Build BM25 index
  final bm25 = await BM25.build(documents);
  
  // Search
  final results = await bm25.search('quick fox', limit: 3);
  
  for (final result in results) {
    print('Document ${result.doc.id}: ${result.doc.text}');
    print('Score: ${result.score.toStringAsFixed(3)}');
  }
}
```

## Examples

### Basic Text Search

```dart
import 'package:bm25/bm25.dart';

void main() async {
  final documents = [
    'Flutter is Google\'s UI toolkit for building beautiful applications',
    'Dart is a client-optimized language for fast apps on any platform',
    'BM25 is a ranking function used in information retrieval',
    'Search engines use ranking algorithms to sort results by relevance',
  ];

  final bm25 = await BM25.build(documents);
  
  // Search for documents about ranking
  final results = await bm25.search('ranking algorithms');
  
  // Results are sorted by relevance score
  print('Top result: ${results.first.doc.text}');
  print('Relevance score: ${results.first.score}');
}
```

### Custom Parameters

```dart
// Customize BM25 parameters for your use case
final bm25 = await BM25.build(
  documents,
  k1: 1.5,  // Controls term frequency saturation (default: 1.2)
  b: 0.8,   // Controls length normalization (default: 0.75)
);
```

### Chunked Document Search

For large documents, you might want to search through chunks:

```dart
import 'package:bm25/bm25.dart';

class DocumentChunk {
  final String id;
  final String documentId;
  final int chunkIndex;
  final String content;
  
  DocumentChunk({
    required this.id,
    required this.documentId,
    required this.chunkIndex,
    required this.content,
  });
}

class ChunkedSearch {
  late final Future<BM25> _bm25Future;
  final List<DocumentChunk> chunks;
  
  ChunkedSearch(this.chunks) {
    _bm25Future = BM25.build(chunks.map((c) => c.content));
  }
  
  Future<List<DocumentChunk>> search(String query, {int limit = 10}) async {
    final bm25 = await _bm25Future;
    final results = await bm25.search(query, limit: limit);
    
    return results.map((result) => chunks[result.doc.id]).toList();
  }
}

void main() async {
  // Split a large document into chunks
  final chunks = [
    DocumentChunk(
      id: 'chunk_1',
      documentId: 'doc_1',
      chunkIndex: 0,
      content: 'Flutter transforms the app development process...',
    ),
    DocumentChunk(
      id: 'chunk_2',
      documentId: 'doc_1',
      chunkIndex: 1,
      content: 'Build, test, and deploy beautiful mobile apps...',
    ),
    // ... more chunks
  ];
  
  final search = ChunkedSearch(chunks);
  final results = await search.search('app development');
  
  for (final chunk in results) {
    print('Document: ${chunk.documentId}, Chunk: ${chunk.chunkIndex}');
    print('Content: ${chunk.content}');
  }
}
```

### Hybrid Search (BM25 + Vector Search)

Combine BM25 with vector search for enhanced results:

```dart
class HybridSearch {
  final BM25 bm25;
  final VectorStore vectorStore; // Your vector database
  
  HybridSearch(this.bm25, this.vectorStore);
  
  Future<List<SearchResult>> search(
    String query, {
    double bm25Weight = 0.5,
    int limit = 10,
  }) async {
    // Get BM25 results
    final bm25Results = await bm25.search(query, limit: limit * 2);
    
    // Get vector search results
    final vectorResults = await vectorStore.search(query, limit: limit * 2);
    
    // Combine and re-rank results
    final combinedScores = <int, double>{};
    
    for (final result in bm25Results) {
      combinedScores[result.doc.id] = result.score * bm25Weight;
    }
    
    for (final result in vectorResults) {
      final docId = result.doc.id;
      final vectorScore = result.score * (1 - bm25Weight);
      combinedScores[docId] = (combinedScores[docId] ?? 0) + vectorScore;
    }
    
    // Sort by combined score and return top results
    final sorted = combinedScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.take(limit).map((entry) {
      final doc = bm25Results
          .firstWhere((r) => r.doc.id == entry.key)
          .doc;
      return SearchResult(doc, entry.value);
    }).toList();
  }
}
```

## API Reference

### BM25

The main class for performing BM25 searches.

```dart
// Build a BM25 instance from documents
static Future<BM25> build(
  Iterable<String> documents, {
  double k1 = 1.2,
  double b = 0.75,
})

// Search documents
Future<List<SearchResult>> search(
  String query, {
  int? limit,
})
```

### SearchResult

Contains the search result with relevance score.

```dart
class SearchResult {
  final BM25Document doc;    // The matched document
  final double score;        // BM25 relevance score
}
```

### BM25Document

Represents a searchable document.

```dart
class BM25Document {
  final int id;              // Document index
  final String text;         // Original text
  final List<String> terms;  // Tokenized terms
}
```

## Performance Tips

1. **Pre-build indices**: Build your BM25 instance once and reuse it for multiple searches
2. **Async processing**: Use the async `build` method for large document sets
3. **Limit results**: Use the `limit` parameter to avoid processing unnecessary results
4. **Cache instances**: Store BM25 instances for frequently searched document sets

## Use Cases

- **In-app search**: Add search functionality to your Flutter apps
- **Document retrieval**: Find relevant documents in large collections
- **FAQ systems**: Match user questions to relevant answers
- **Hybrid search**: Combine with vector search for better results
- **Offline search**: No network required, perfect for offline-first apps

## License

MIT
