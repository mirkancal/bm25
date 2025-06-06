import 'package:bm25/bm25.dart';

void main() async {
  // Sample documents
  final documents = [
    'The quick brown fox jumps over the lazy dog',
    'A fast brown fox leaps above a sleeping dog',
    'The lazy dog sleeps under the tree',
    'Quick foxes are known for their jumping abilities',
    'Dogs can be lazy when they are tired',
  ];

  // Build the BM25 index
  print('Building BM25 index...');
  final bm25 = await BM25.build(documents);

  // Search for documents
  final queries = ['quick fox', 'lazy dog', 'jumping'];
  
  for (final query in queries) {
    print('\nSearching for: "$query"');
    final results = await bm25.search(query, limit: 3);
    
    for (final result in results) {
      print('  Score: ${result.score.toStringAsFixed(4)}, '
            'Doc: "${result.doc.text}"');
    }
  }
}