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

/* Example output:
Building BM25 index...

Searching for: "quick fox"
  Score: 1.6473, Doc: "The quick brown fox jumps over the lazy dog"
  Score: 0.9138, Doc: "A fast brown fox leaps above a sleeping dog"
  Score: 0.8664, Doc: "Quick foxes are known for their jumping abilities"

Searching for: "lazy dog"
  Score: 1.1252, Doc: "The lazy dog sleeps under the tree"
  Score: 1.0142, Doc: "The quick brown fox jumps over the lazy dog"
  Score: 0.5626, Doc: "A fast brown fox leaps above a sleeping dog"

Searching for: "jumping"
  Score: 1.3719, Doc: "Quick foxes are known for their jumping abilities"
*/
