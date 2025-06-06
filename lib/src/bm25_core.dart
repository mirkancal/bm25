import 'dart:math' as math;
import 'document.dart';
import 'search_result.dart';

/// BM25 ranking algorithm implementation
class BM25 {
  final double k1;
  final double b;
  final List<Document> _documents;
  final Map<String, int> _documentFrequency = {};
  final double _avgDocLength;
  
  BM25({
    required List<Document> documents,
    this.k1 = 1.2,
    this.b = 0.75,
  }) : _documents = documents,
       _avgDocLength = _calculateAvgDocLength(documents) {
    _buildIndex();
  }
  
  static double _calculateAvgDocLength(List<Document> documents) {
    if (documents.isEmpty) return 0;
    int totalLength = documents.fold(0, (sum, doc) => sum + doc.tokens.length);
    return totalLength / documents.length;
  }
  
  void _buildIndex() {
    for (var doc in _documents) {
      var uniqueTokens = doc.tokens.toSet();
      for (var token in uniqueTokens) {
        _documentFrequency[token] = (_documentFrequency[token] ?? 0) + 1;
      }
    }
  }
  
  double _idf(String term) {
    int n = _documents.length;
    int df = _documentFrequency[term] ?? 0;
    return math.log((n - df + 0.5) / (df + 0.5) + 1);
  }
  
  double _score(Document doc, List<String> queryTerms) {
    double score = 0.0;
    Map<String, int> termFreq = {};
    
    for (var token in doc.tokens) {
      termFreq[token] = (termFreq[token] ?? 0) + 1;
    }
    
    for (var term in queryTerms) {
      if (!termFreq.containsKey(term)) continue;
      
      double tf = termFreq[term]!.toDouble();
      double idf = _idf(term);
      double docLength = doc.tokens.length.toDouble();
      
      double numerator = tf * (k1 + 1);
      double denominator = tf + k1 * (1 - b + b * (docLength / _avgDocLength));
      
      score += idf * (numerator / denominator);
    }
    
    return score;
  }
  
  List<SearchResult> search(String query, {int? limit}) {
    if (query.trim().isEmpty) return [];
    
    var queryTokens = Document._tokenize(query.toLowerCase());
    if (queryTokens.isEmpty) return [];
    
    List<SearchResult> results = [];
    for (var doc in _documents) {
      double score = _score(doc, queryTokens);
      if (score > 0) {
        results.add(SearchResult(document: doc, score: score));
      }
    }
    
    results.sort((a, b) => b.score.compareTo(a.score));
    
    if (limit != null && results.length > limit) {
      results = results.sublist(0, limit);
    }
    
    return results;
  }
}
