import 'dart:math' as math;
import 'package:bm25/bm25.dart';

/// A simple document class that holds content and metadata
class Document {
  Document({
    required this.id,
    required this.content,
    required this.title,
    required this.category,
    this.embedding,
  });

  final String id;
  final String content;
  final String title;
  final String category;
  final List<double>? embedding;
}

/// Result combining BM25 and similarity scores
class HybridSearchResult {
  HybridSearchResult({
    required this.document,
    required this.bm25Score,
    required this.similarityScore,
    required this.finalScore,
  });

  final Document document;
  double bm25Score;
  double similarityScore;
  double finalScore;
}

/// Simple hybrid search combining BM25 with cosine similarity
class HybridSearch {
  HybridSearch({this.bm25Weight = 0.3});

  final double bm25Weight;
  BM25? _bm25Index;
  final List<Document> _documents = [];

  /// Add documents to the search index
  Future<void> addDocuments(List<Document> documents) async {
    _documents.addAll(documents);

    // Create BM25 documents with metadata
    final bm25Docs = documents.map((doc) {
      // BM25.build will handle the tokenization and ID assignment
      return BM25Document(
        id: 0, // Will be reassigned by BM25.build
        text: '${doc.title} ${doc.content}',
        terms: [], // Will be computed by BM25.build
        meta: {
          'id': doc.id,
          'title': doc.title,
          'category': doc.category,
        },
      );
    }).toList();

    // Build BM25 index
    _bm25Index = await BM25.build(
      bm25Docs,
      indexFields: ['category'], // Enable filtering by category
    );
  }

  /// Search using hybrid approach
  Future<List<HybridSearchResult>> search(
    String query, {
    int limit = 5,
    String? category,
    List<double>? queryEmbedding,
  }) async {
    if (_bm25Index == null) {
      throw StateError('No documents indexed. Call addDocuments first.');
    }

    // Perform BM25 search
    final filter = category != null ? {'category': category} : null;
    final bm25Results = await _bm25Index!.search(
      query,
      limit: limit * 3, // Get more candidates for reranking
      filter: filter,
    );

    // Create a map of results
    final resultsMap = <String, HybridSearchResult>{};

    // Process BM25 results
    for (final result in bm25Results) {
      final docId = result.doc.meta['id'] as String;
      final doc = _documents.firstWhere((d) => d.id == docId);

      resultsMap[docId] = HybridSearchResult(
        document: doc,
        bm25Score: _normalizeBM25Score(result.score),
        similarityScore: 0.0,
        finalScore: 0.0,
      );
    }

    // If embeddings are available, calculate similarity scores
    if (queryEmbedding != null) {
      for (final doc in _documents) {
        if (doc.embedding != null) {
          final similarity = _cosineSimilarity(queryEmbedding, doc.embedding!);
          final normalizedSim = (similarity + 1) / 2; // Normalize to [0, 1]

          if (resultsMap.containsKey(doc.id)) {
            resultsMap[doc.id]!.similarityScore = normalizedSim;
          } else {
            // Add documents found only by similarity search
            resultsMap[doc.id] = HybridSearchResult(
              document: doc,
              bm25Score: 0.0,
              similarityScore: normalizedSim,
              finalScore: 0.0,
            );
          }
        }
      }
    }

    // Calculate final scores
    final results = resultsMap.values.toList();
    for (final result in results) {
      result.finalScore = (bm25Weight * result.bm25Score) +
          ((1 - bm25Weight) * result.similarityScore);
    }

    // Sort by final score and return top results
    results.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return results.take(limit).toList();
  }

  /// Normalize BM25 score to [0,1] range
  double _normalizeBM25Score(double score) {
    return score / (score + 1);
  }

  /// Calculate cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same length');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    normA = math.sqrt(normA);
    normB = math.sqrt(normB);

    if (normA == 0.0 || normB == 0.0) {
      return 0.0;
    }

    return dotProduct / (normA * normB);
  }
}

/// Example usage
void main() async {
  // Create sample documents
  final documents = [
    Document(
      id: '1',
      title: 'Introduction to Machine Learning',
      content: 'Machine learning is a subset of artificial intelligence '
          'that enables systems to learn from data.',
      category: 'AI',
      embedding: [0.1, 0.8, 0.3, 0.5], // Simplified embeddings
    ),
    Document(
      id: '2',
      title: 'Deep Learning Fundamentals',
      content: 'Deep learning uses neural networks with multiple layers '
          'to process complex patterns in data.',
      category: 'AI',
      embedding: [0.2, 0.9, 0.4, 0.6],
    ),
    Document(
      id: '3',
      title: 'Data Science Best Practices',
      content: 'Data science involves extracting insights from data '
          'using statistical and computational methods.',
      category: 'Data Science',
      embedding: [0.7, 0.2, 0.8, 0.3],
    ),
    Document(
      id: '4',
      title: 'Natural Language Processing',
      content: 'NLP enables computers to understand, interpret, '
          'and generate human language.',
      category: 'AI',
      embedding: [0.3, 0.7, 0.5, 0.4],
    ),
    Document(
      id: '5',
      title: 'Statistical Analysis Methods',
      content: 'Statistics provides tools for collecting, analyzing, '
          'and interpreting data patterns.',
      category: 'Data Science',
      embedding: [0.8, 0.1, 0.9, 0.2],
    ),
  ];

  // Initialize hybrid search
  final hybridSearch = HybridSearch(bm25Weight: 0.3);
  await hybridSearch.addDocuments(documents);

  // Example 1: Pure BM25 search (no embeddings)
  print('=== BM25 Search Results ===');
  final bm25Results = await hybridSearch.search(
    'machine learning neural networks',
    limit: 3,
  );

  for (final result in bm25Results) {
    print('${result.document.title}');
    print('  BM25 Score: ${result.bm25Score.toStringAsFixed(4)}');
    print('  Category: ${result.document.category}');
    print('');
  }

  // Example 2: Hybrid search with embeddings
  print('\n=== Hybrid Search Results ===');
  final queryEmbedding = [0.15, 0.85, 0.35, 0.55]; // Query embedding
  final hybridResults = await hybridSearch.search(
    'machine learning neural networks',
    limit: 3,
    queryEmbedding: queryEmbedding,
  );

  for (final result in hybridResults) {
    print('${result.document.title}');
    print('  Final Score: ${result.finalScore.toStringAsFixed(4)}');
    print('  BM25 Score: ${result.bm25Score.toStringAsFixed(4)}');
    print('  Similarity Score: ${result.similarityScore.toStringAsFixed(4)}');
    print('  Category: ${result.document.category}');
    print('');
  }

  // Example 3: Filtered search by category
  print('\n=== Filtered Search (AI category only) ===');
  final filteredResults = await hybridSearch.search(
    'data analysis methods',
    limit: 3,
    category: 'AI',
    queryEmbedding: queryEmbedding,
  );

  for (final result in filteredResults) {
    print('${result.document.title}');
    print('  Final Score: ${result.finalScore.toStringAsFixed(4)}');
    print('  Category: ${result.document.category}');
    print('');
  }
}