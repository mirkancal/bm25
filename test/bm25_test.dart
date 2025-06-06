import 'package:test/test.dart';
import 'package:bm25/bm25.dart';

void main() {
  group('BM25', () {
    test('searches documents correctly', () {
      var docs = [
        Document(id: '1', content: 'The quick brown fox'),
        Document(id: '2', content: 'The lazy dog'),
      ];
      
      var bm25 = BM25(documents: docs);
      var results = bm25.search('fox');
      
      expect(results, isNotEmpty);
      expect(results.first.document.id, equals('1'));
    });
  });
}
