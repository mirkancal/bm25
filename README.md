# BM25 for Dart

A pure Dart implementation of the BM25 ranking algorithm for full-text search. Perfect for adding relevance-based text search to your Dart/Flutter applications.

## Features

- **Ultra-fast performance** - Optimized implementation with isolate-based parallel processing
- **Metadata filtering** - Filter search results by arbitrary metadata fields
- **Partitioned indices** - Create separate indices for different document categories
- **Pure Dart implementation** - No native dependencies
- **Async support** - Build indices asynchronously for large document sets
- **Customizable parameters** - Fine-tune k1 and b parameters
- **Memory efficient** - Cache-friendly design with typed arrays
- **Easy integration** - Works great with vector search for hybrid search systems

## Installation

```yaml
dependencies:
  bm25: ^2.1.0
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

### Metadata Filtering

Filter search results by metadata fields:

```dart
// Create documents with metadata
final docs = [
  BM25Document(
    id: 0,
    text: 'Introduction to machine learning',
    terms: [], // Will be auto-tokenized
    meta: {'filePath': 'docs/ml/intro.md', 'category': 'ML'},
  ),
  BM25Document(
    id: 1,
    text: 'Deep learning fundamentals',
    terms: [],
    meta: {'filePath': 'docs/ml/deep.md', 'category': 'ML'},
  ),
  BM25Document(
    id: 2,
    text: 'Data structures and algorithms',
    terms: [],
    meta: {'filePath': 'docs/cs/algo.md', 'category': 'CS'},
  ),
];

// Build index with metadata fields
final bm25 = await BM25.build(docs, indexFields: ['filePath', 'category']);

// Search with single value filter
final mlResults = await bm25.search('learning', 
  filter: {'category': 'ML'}
);

// Search with multiple values filter
final results = await bm25.search('algorithms', 
  filter: {'filePath': ['docs/ml/intro.md', 'docs/cs/algo.md']}
);
```

### Partitioned Indices

Create separate indices for different document categories:

```dart
final docs = [
  BM25Document(
    id: 0,
    text: 'Python programming basics',
    terms: [],
    meta: {'language': 'python'},
  ),
  BM25Document(
    id: 1,
    text: 'Advanced Python techniques',
    terms: [],
    meta: {'language': 'python'},
  ),
  BM25Document(
    id: 2,
    text: 'Java programming guide',
    terms: [],
    meta: {'language': 'java'},
  ),
];

// Create partitioned index
final partitioned = await PartitionedBM25.build(
  docs,
  partitionBy: (doc) => doc.meta['language']!,
);

// Search in specific partition
final pythonResults = await partitioned.searchIn('python', 'programming');

// Search across multiple partitions
final results = await partitioned.searchMany(['python', 'java'], 'advanced');
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
  Iterable<dynamic> documents, {  // Accepts String or BM25Document
  List<String> indexFields = const ['filePath'],  // Fields to index for filtering
  Set<String>? stopWords,
})

// Search documents
Future<List<SearchResult>> search(
  String query, {
  int limit = 10,
  Map<String, Object>? filter,  // Filter by metadata fields
  Set<String>? stopWords,
})

// Dispose resources
Future<void> dispose()
```

### PartitionedBM25

Manages multiple BM25 indices partitioned by a key.

```dart
// Build partitioned indices
static Future<PartitionedBM25> build(
  Iterable<BM25Document> docs, {
  required String Function(BM25Document) partitionBy,
  List<String> indexFields = const ['filePath'],
  Set<String>? stopWords,
})

// Search in specific partition
Future<List<SearchResult>> searchIn(
  String key,
  String query, {
  int limit = 10,
})

// Search across multiple partitions
Future<List<SearchResult>> searchMany(
  Iterable<String> keys,
  String query, {
  int limit = 10,
})

// Dispose resources
Future<void> dispose()
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

Represents a searchable document with metadata.

```dart
class BM25Document {
  final int id;                        // Document index
  final String text;                   // Original text
  final List<String> terms;            // Tokenized terms
  final Map<String, String> meta;      // Metadata key-value pairs
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
