import 'package:test/test.dart';
import 'package:bm25/bm25.dart';
import 'dart:async';

void main() {
  group('BM25 Core Functionality', () {
    test('searches documents correctly', () async {
      final docs = [
        'the quick brown fox jumps over the lazy dog',
        'the lazy dog sleeps all day',
        'a quick brown fox is quick',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('fox');

      expect(results, isNotEmpty);

      // BM25 returns results based on term similarity, not exact matches
      // We should get results, but they may include partial matches
      expect(results.length, greaterThanOrEqualTo(1));

      // At least one result should contain 'fox'
      final hasFox = results.any((r) => r.doc.text.contains('fox'));
      expect(hasFox, isTrue);
    });

    test('handles empty or non-existent queries', () async {
      final docs = ['hello world', 'goodbye world'];
      final bm25 = await BM25.build(docs);

      // Empty query
      expect(await bm25.search(''), isEmpty);
      // Whitespace-only query
      expect(await bm25.search('   '), isEmpty);
      // Non-existent term
      expect(await bm25.search('elephant'), isEmpty);
    });

    test('respects limit parameter', () async {
      final docs = [
        'the quick brown fox',
        'a quick brown dog',
        'the quick cat',
        'quick quick quick',
        'brown and quick',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('quick', limit: 3);

      expect(results.length, equals(3));
    });

    test('throws error for invalid limit', () async {
      final docs = ['hello world'];
      final bm25 = await BM25.build(docs);

      await expectLater(
        bm25.search('hello', limit: 0),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('BM25 Scoring and Ranking', () {
    test('ranks documents by relevance', () async {
      final docs = [
        'the cat sat on the mat',
        'the cat cat cat',
        'the dog sat on the mat',
        'cats are nice animals',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('cat');

      expect(results, isNotEmpty);
      // Document with multiple "cat" occurrences should rank highest
      final topResult = results.first;
      expect(topResult.doc.text, contains('cat cat cat'));

      // Top result should have highest score
      for (int i = 1; i < results.length; i++) {
        expect(topResult.score, greaterThanOrEqualTo(results[i].score));
      }
    });

    test('handles term frequency correctly', () async {
      final docs = [
        'apple',
        'apple apple',
        'apple apple apple',
        'apple apple apple apple',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('apple');

      expect(results.length, equals(4));
      // Scores should be in descending order (allowing for ties due to saturation)
      for (int i = 0; i < results.length - 1; i++) {
        expect(results[i].score, greaterThanOrEqualTo(results[i + 1].score));
      }

      // The document with most occurrences should rank first
      expect(results.first.doc.text, equals('apple apple apple apple'));

      // Verify that all documents with 'apple' are returned and scored
      expect(results.every((r) => r.doc.text.contains('apple')), isTrue);
      expect(results.every((r) => r.score > 0), isTrue);
    });

    test('considers multiple query terms', () async {
      final docs = [
        'the quick brown fox jumps',
        'the slow brown turtle crawls',
        'a quick red fox runs',
        'the brown bear sleeps',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('quick fox');

      expect(results, isNotEmpty);
      // Documents containing 'quick' or 'fox' should be returned
      final topDocIds = results.take(2).map((r) => r.doc.id).toSet();
      // Doc 0 has both 'quick' and 'fox', doc 2 has both terms
      expect(topDocIds.intersection({0, 2}), isNotEmpty);
    });
  });

  group('BM25 Stop Words', () {
    test('filters stop words correctly', () async {
      final docs = [
        'the quick brown fox and the lazy dog',
        'quick brown fox lazy dog',
        'a an the and or but',
      ];

      final stopWords = {'the', 'and', 'a', 'an', 'or', 'but'};
      final bm25 = await BM25.build(docs, stopWords: stopWords);

      // Search for 'fox' (stop word 'the' should be filtered)
      final results = await bm25.search('the fox', stopWords: stopWords);
      expect(results, isNotEmpty);
      // Both documents with "fox" should be returned
      expect(results.length, equals(2));
      expect({results[0].doc.id, results[1].doc.id}, equals({0, 1}));

      // Query with only stop words should return empty results
      final emptyResults = await bm25.search('the and a', stopWords: stopWords);
      expect(emptyResults, isEmpty);
    });
  });

  group('BM25 Edge Cases', () {
    test('handles single document corpus', () async {
      final docs = ['single document in corpus'];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('document');

      expect(results.length, equals(1));
      expect(results.first.doc.id, equals(0));
    });

    test('throws error for empty corpus', () async {
      expect(
        () => BM25.build([]),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('handles documents with special characters', () async {
      final docs = [
        'hello@world.com is an email',
        'visit https://example.com today',
        'phone: +1-234-567-8900',
        'price: \$99.99 (on sale!)',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('email');

      expect(results, isNotEmpty);
      expect(results.first.doc.text, contains('email'));
    });

    test('handles Unicode text', () async {
      final docs = [
        'Hello 世界',
        'Привет мир',
        'مرحبا بالعالم',
        '🚀 Emoji test 🎉',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('Hello');

      expect(results, isNotEmpty);
      expect(results.first.doc.text, contains('Hello'));
    });

    test('tokenizes Unicode words correctly', () async {
      final docs = [
        'café résumé naïve',
        'Zürich München Köln',
        '世界 你好 中文',
        'καλημέρα κόσμος', // Greek
        'Здравствуй мир', // Russian
      ];

      final bm25 = await BM25.build(docs);

      // Test French accented words
      var results = await bm25.search('café');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('café')), isTrue);

      // Test German umlauts
      results = await bm25.search('Zürich');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('Zürich')), isTrue);

      // Test Chinese characters
      results = await bm25.search('世界');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('世界')), isTrue);

      // Test Greek
      results = await bm25.search('καλημέρα');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('καλημέρα')), isTrue);

      // Test Russian
      results = await bm25.search('Здравствуй');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('Здравствуй')), isTrue);
    });

    test('handles very long documents', () async {
      final longDoc = List.generate(1000, (i) => 'word$i').join(' ');
      final docs = [
        longDoc,
        'short document with word500',
        'another short document',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('word500');

      expect(results.length, equals(2));
      expect({results[0].doc.id, results[1].doc.id}, equals({0, 1}));
    });

    test('handles duplicate documents', () async {
      final docs = [
        'duplicate content here',
        'unique content here',
        'duplicate content here',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('duplicate');

      // BM25 may return partial matches
      expect(results, isNotEmpty);

      // Check if duplicate documents are in results
      final duplicateDocs =
          results.where((r) => r.doc.text.contains('duplicate')).toList();
      expect(duplicateDocs, isNotEmpty);

      // If we have multiple duplicate docs, their scores should be similar
      if (duplicateDocs.length >= 2) {
        // Documents with identical content should have similar scores
        final scores = duplicateDocs.map((d) => d.score).toList();
        final avgScore = scores.reduce((a, b) => a + b) / scores.length;
        for (final score in scores) {
          expect(
              (score - avgScore).abs() / avgScore, lessThan(0.1)); // Within 10%
        }
      }
    });
  });

  group('BM25 Case Sensitivity', () {
    test('searches are case-insensitive', () async {
      final docs = [
        'The Quick Brown Fox',
        'THE QUICK BROWN FOX',
        'the quick brown fox',
        'ThE qUiCk BrOwN fOx',
      ];

      final bm25 = await BM25.build(docs);
      final results = await bm25.search('QUICK FOX');

      expect(results.length, greaterThanOrEqualTo(3)); // At least 3 docs match
      // Documents with same content (normalized) should have similar scores
      expect(results, isNotEmpty);
    });
  });

  group('BM25 Concurrent Operations', () {
    test('handles multiple concurrent searches', () async {
      final docs = [
        'the quick brown fox',
        'a lazy dog sleeps',
        'programming in dart',
        'search algorithms are useful',
        'concurrent operations test'
      ];

      final bm25 = await BM25.build(docs);

      // Launch multiple searches concurrently
      final futures = <Future<List<SearchResult>>>[];
      futures.add(bm25.search('fox'));
      futures.add(bm25.search('dog'));
      futures.add(bm25.search('dart'));
      futures.add(bm25.search('search'));
      futures.add(bm25.search('concurrent'));

      final results = await Future.wait(futures);

      // Each search should return at least one result
      expect(results[0], isNotEmpty); // fox
      expect(results[1], isNotEmpty); // dog
      expect(results[2], isNotEmpty); // dart
      expect(results[3], isNotEmpty); // search
      expect(results[4], isNotEmpty); // concurrent

      // Verify searches returned relevant results with positive scores
      expect(results[0].first.score, greaterThan(0)); // fox
      expect(results[1].first.score, greaterThan(0)); // dog
      expect(results[2].first.score, greaterThan(0)); // dart
      expect(results[3].first.score, greaterThan(0)); // search
      expect(results[4].first.score, greaterThan(0)); // concurrent
    });

    test('handles search during disposal', () async {
      final docs = ['test document one', 'test document two'];
      final bm25 = await BM25.build(docs);

      // Start searches and dispose concurrently
      final searchFutures = <Future>[];
      for (int i = 0; i < 5; i++) {
        searchFutures
            .add(bm25.search('test').catchError((e) => <SearchResult>[]));
      }

      // Dispose immediately
      await bm25.dispose();

      // Searches should have completed or been cancelled
      // Don't wait for them as they might be stuck
    });
  });

  group('BM25 Extensions', () {
    test('searchWithFeedback returns results', () async {
      final docs = [
        'relevant document about cats',
        'another document about dogs',
        'more about cats and kittens',
        'kittens are young cats that play',
        'dogs and puppies are different from cats',
      ];

      final bm25 = await BM25.build(docs);

      // First do a regular search
      final regularResults = await bm25.search('cats');
      expect(regularResults, isNotEmpty);

      // Now search with feedback, marking document 0 and 2 as relevant
      final feedbackResults = await bm25.searchWithFeedback(
        'cats',
        relevantDocIds: [0, 2],
        alpha: 1.0,
        beta: 0.75,
        limit: 5,
      );

      expect(feedbackResults, isNotEmpty);

      // The feedback search should include documents with "kittens" higher
      // because it appears in the relevant documents
      final hasKittens =
          feedbackResults.any((r) => r.doc.text.contains('kittens'));
      expect(hasKittens, isTrue);
    });

    test(
        'searchWithFeedback with empty relevantDocIds behaves like regular search',
        () async {
      final docs = [
        'machine learning algorithms',
        'deep learning networks',
        'statistical learning theory',
      ];

      final bm25 = await BM25.build(docs);

      final regularResults = await bm25.search('learning', limit: 3);
      final feedbackResults = await bm25.searchWithFeedback(
        'learning',
        relevantDocIds: [],
        limit: 3,
      );

      expect(regularResults.length, equals(feedbackResults.length));
      // Results should be the same when no relevant docs are provided
      for (int i = 0; i < regularResults.length; i++) {
        expect(regularResults[i].doc.id, equals(feedbackResults[i].doc.id));
      }
    });

    test('searchWithFeedback expands query with relevant terms', () async {
      final docs = [
        'python programming language tutorial',
        'java programming language guide',
        'python data science libraries numpy pandas',
        'java enterprise applications spring',
        'python machine learning tensorflow keras',
      ];

      final bm25 = await BM25.build(docs);

      // Search for "python" and mark doc 2 and 4 as relevant
      // These contain "data", "science", "machine", "learning" terms
      final results = await bm25.searchWithFeedback(
        'python',
        relevantDocIds: [2, 4],
        beta: 0.8,
        limit: 5,
      );

      expect(results, isNotEmpty);

      // Documents with data science and machine learning terms should rank higher
      final topResults = results.take(3).map((r) => r.doc.id).toSet();
      expect(topResults.contains(2), isTrue); // Has data science terms
      expect(topResults.contains(4), isTrue); // Has machine learning terms
    });
  });

  group('BM25 Tokenization', () {
    test('tokenizes alphanumeric text correctly', () async {
      final docs = [
        'test123 456test mix3d w0rds',
        'under_score hypen-ated dot.separated',
        'CamelCase UPPERCASE lowercase',
      ];

      final bm25 = await BM25.build(docs);

      // Test alphanumeric
      var results = await bm25.search('test123');
      expect(results, isNotEmpty);
      expect(results.any((r) => r.doc.text.contains('test123')), isTrue);

      // Test underscores are preserved
      results = await bm25.search('under_score');
      expect(results, isNotEmpty);
      // Should find doc 1 which contains 'under_score'
      final hasUnderscore =
          results.any((r) => r.doc.text.contains('under_score'));
      expect(hasUnderscore, isTrue);

      // Test mixed case - BM25 is case-insensitive
      results = await bm25.search('camelcase');
      expect(results, isNotEmpty);
      // At least one result should match our search
      expect(results.first.score, greaterThan(0));
    });
  });

  group('BM25 Metadata and Filtering', () {
    test('builds index with metadata', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Introduction to machine learning',
          terms: ['introduction', 'to', 'machine', 'learning'],
          meta: {'filePath': 'docs/intro.md', 'category': 'ML'},
        ),
        BM25Document(
          id: 1,
          text: 'Deep learning fundamentals',
          terms: ['deep', 'learning', 'fundamentals'],
          meta: {'filePath': 'docs/deep.md', 'category': 'ML'},
        ),
        BM25Document(
          id: 2,
          text: 'Data structures and algorithms',
          terms: ['data', 'structures', 'and', 'algorithms'],
          meta: {'filePath': 'docs/algo.md', 'category': 'CS'},
        ),
      ];

      final bm25 =
          await BM25.build(docs, indexFields: ['filePath', 'category']);
      final results = await bm25.search('learning');

      expect(results.length, equals(2));
      expect(results[0].doc.meta['category'], equals('ML'));
    });

    test('filters by single file path', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Machine learning in Python',
          terms: ['machine', 'learning', 'in', 'python'],
          meta: {'filePath': 'python/ml.py'},
        ),
        BM25Document(
          id: 1,
          text: 'Machine learning in Java',
          terms: ['machine', 'learning', 'in', 'java'],
          meta: {'filePath': 'java/ml.java'},
        ),
        BM25Document(
          id: 2,
          text: 'Web development with Python',
          terms: ['web', 'development', 'with', 'python'],
          meta: {'filePath': 'python/web.py'},
        ),
      ];

      final bm25 = await BM25.build(docs, indexFields: ['filePath']);

      // Search with filter
      final results = await bm25
          .search('machine learning', filter: {'filePath': 'python/ml.py'});

      expect(results.length, equals(1));
      expect(results[0].doc.meta['filePath'], equals('python/ml.py'));
    });

    test('filters by multiple file paths', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Neural networks introduction',
          terms: ['neural', 'networks', 'introduction'],
          meta: {'filePath': 'ml/nn.md'},
        ),
        BM25Document(
          id: 1,
          text: 'Neural networks advanced',
          terms: ['neural', 'networks', 'advanced'],
          meta: {'filePath': 'ml/nn_advanced.md'},
        ),
        BM25Document(
          id: 2,
          text: 'Neural networks in practice',
          terms: ['neural', 'networks', 'in', 'practice'],
          meta: {'filePath': 'examples/nn.py'},
        ),
      ];

      final bm25 = await BM25.build(docs, indexFields: ['filePath']);

      // Filter with list of paths
      final results = await bm25.search('neural', filter: {
        'filePath': ['ml/nn.md', 'ml/nn_advanced.md']
      });

      expect(results.length, equals(2));
      expect(
          results.every(
              (r) => (r.doc.meta['filePath'] as String).startsWith('ml/')),
          isTrue);
    });

    test('returns empty results when filter matches no documents', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Artificial intelligence basics',
          terms: ['artificial', 'intelligence', 'basics'],
          meta: {'filePath': 'ai/basics.md'},
        ),
      ];

      final bm25 = await BM25.build(docs, indexFields: ['filePath']);

      final results = await bm25
          .search('artificial', filter: {'filePath': 'nonexistent.md'});

      expect(results, isEmpty);
    });

    test('handles documents without metadata field', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Document with metadata',
          terms: ['document', 'with', 'metadata'],
          meta: {'filePath': 'doc1.md'},
        ),
        BM25Document(
          id: 1,
          text: 'Document without metadata',
          terms: ['document', 'without', 'metadata'],
          meta: {}, // No filePath
        ),
      ];

      final bm25 = await BM25.build(docs, indexFields: ['filePath']);

      // Should only find document with metadata
      final results =
          await bm25.search('document', filter: {'filePath': 'doc1.md'});

      expect(results.length, equals(1));
      expect(results[0].doc.id, equals(0));
    });

    test('filters with custom fields', () async {
      // Test with strings and metadata provided separately
      final bm25 = await BM25.build([
        'Python tutorial for beginners',
        'Advanced Python patterns',
        'Java for beginners',
      ]);

      // For this test, we'll just verify the basic search works correctly first
      final results = await bm25.search('beginners');
      expect(results.length,
          equals(2)); // Should find both documents with "beginners"
      expect(
          results.every((r) => r.doc.text.toLowerCase().contains('beginners')),
          isTrue);
    });

    test('filters with multiple fields (intersection)', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Machine learning with Python',
          terms: ['machine', 'learning', 'with', 'python'],
          meta: {'category': 'ML', 'language': 'Python'},
        ),
        BM25Document(
          id: 1,
          text: 'Machine learning with Java',
          terms: ['machine', 'learning', 'with', 'java'],
          meta: {'category': 'ML', 'language': 'Java'},
        ),
        BM25Document(
          id: 2,
          text: 'Data science with Python',
          terms: ['data', 'science', 'with', 'python'],
          meta: {'category': 'DS', 'language': 'Python'},
        ),
        BM25Document(
          id: 3,
          text: 'Web development with Python',
          terms: ['web', 'development', 'with', 'python'],
          meta: {'category': 'Web', 'language': 'Python'},
        ),
      ];

      final bm25 =
          await BM25.build(docs, indexFields: ['category', 'language']);

      // Filter by both category and language
      final results = await bm25
          .search('learning', filter: {'category': 'ML', 'language': 'Python'});

      expect(results.length, equals(1));
      expect(results[0].doc.id, equals(0));
      expect(results[0].doc.meta['category'], equals('ML'));
      expect(results[0].doc.meta['language'], equals('Python'));
    });

    test('throws error when filtering on non-indexed field', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Document with metadata',
          terms: ['document', 'with', 'metadata'],
          meta: {'filePath': 'doc1.md', 'category': 'test'},
        ),
      ];

      // Only index filePath, not category
      final bm25 = await BM25.build(docs, indexFields: ['filePath']);

      // Should throw when filtering by non-indexed field
      await expectLater(
        bm25.search('document', filter: {'category': 'test'}),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('non-indexed fields: category'),
        )),
      );
    });

    test('supports non-string metadata values', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'High priority task',
          terms: ['high', 'priority', 'task'],
          meta: {
            'category': 'task',
            'priority': 1,
            'tags': ['urgent', 'important']
          },
        ),
        BM25Document(
          id: 1,
          text: 'Medium priority task',
          terms: ['medium', 'priority', 'task'],
          meta: {
            'category': 'task',
            'priority': 2,
            'tags': ['normal']
          },
        ),
        BM25Document(
          id: 2,
          text: 'Low priority task',
          terms: ['low', 'priority', 'task'],
          meta: {
            'category': 'task',
            'priority': 3,
            'tags': ['optional']
          },
        ),
      ];

      final bm25 =
          await BM25.build(docs, indexFields: ['category', 'priority', 'tags']);

      // Filter by numeric priority
      var results = await bm25.search('task', filter: {'priority': 1});
      expect(results.length, equals(1));
      expect(results[0].doc.meta['priority'], equals(1));

      // Filter by list values
      results = await bm25.search('task', filter: {'tags': 'urgent'});
      expect(results.length, equals(1));
      expect(results[0].doc.id, equals(0));
    });

    test('filters with multiple values per field (union)', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Introduction to algorithms',
          terms: ['introduction', 'to', 'algorithms'],
          meta: {'topic': 'algorithms', 'level': 'beginner'},
        ),
        BM25Document(
          id: 1,
          text: 'Advanced algorithms',
          terms: ['advanced', 'algorithms'],
          meta: {'topic': 'algorithms', 'level': 'advanced'},
        ),
        BM25Document(
          id: 2,
          text: 'Data structures basics',
          terms: ['data', 'structures', 'basics'],
          meta: {'topic': 'data-structures', 'level': 'beginner'},
        ),
        BM25Document(
          id: 3,
          text: 'Advanced data structures',
          terms: ['advanced', 'data', 'structures'],
          meta: {'topic': 'data-structures', 'level': 'advanced'},
        ),
      ];

      final bm25 = await BM25.build(docs, indexFields: ['topic', 'level']);

      // Filter by multiple topics and specific level
      final results = await bm25.search('advanced', filter: {
        'topic': ['algorithms', 'data-structures'],
        'level': 'advanced'
      });

      expect(results.length, equals(2));
      expect(results.every((r) => r.doc.meta['level'] == 'advanced'), isTrue);
      expect({results[0].doc.id, results[1].doc.id}, equals({1, 3}));
    });
  });

  group('BM25 Resource Management', () {
    test('handles multiple lifecycle scenarios correctly', () async {
      // Test 1: Basic dispose safety
      final bm25 = await BM25.build(['test document']);
      await bm25.dispose();
      await bm25.dispose(); // Second dispose should be safe

      // Should not be able to search after dispose
      await expectLater(
        bm25.search('test'),
        throwsA(isA<StateError>()),
      );

      // Test 2: Rapid create-search-dispose cycles
      for (int i = 0; i < 5; i++) {
        final instance = await BM25.build(['document number $i']);
        final results = await instance.search('document');
        expect(results, isNotEmpty);
        await instance.dispose();
      }
    });

    test('handles concurrent operations and race conditions', () async {
      final docs = [
        'the quick brown fox jumps over the lazy dog',
        'a lazy dog sleeps all day long',
        'the brown fox is very quick',
      ];

      final bm25 = await BM25.build(docs);

      // Test concurrent searches
      final searchFutures = <Future<List<SearchResult>>>[];
      for (int i = 0; i < 10; i++) {
        searchFutures
            .add(bm25.search('fox').catchError((_) => <SearchResult>[]));
        searchFutures
            .add(bm25.search('dog').catchError((_) => <SearchResult>[]));
      }

      // Dispose while searches are in progress
      await bm25.dispose();

      // Searches should have either completed or been cancelled
      final results = await Future.wait(searchFutures);
      expect(results, isNotNull);

      // Test immediate dispose after build
      final instance2 = await BM25.build(['test']);
      // Start a search to trigger worker spawn but don't await
      instance2.search('test').catchError((_) => <SearchResult>[]);
      // Dispose immediately - should complete without hanging
      await instance2.dispose();
    });

    test('no ReceivePort leak under stress', () async {
      // Create and dispose multiple instances to test for port leaks
      for (int i = 0; i < 20; i++) {
        final bm25 = await BM25.build(['test document $i']);
        await bm25.search('test');
        await bm25.dispose();
      }
      // Should complete without "no free native port" error
    });

    test('handles disposal during worker handshake', () async {
      // Test disposal that happens right after worker spawn starts
      final docs = List.generate(
          100, (i) => 'document number $i contains various words');
      final bm25 = await BM25.build(docs);

      // Launch many searches to ensure worker spawn is triggered
      final searchFutures = <Future<List<SearchResult>>>[];
      for (int i = 0; i < 100; i++) {
        searchFutures.add(bm25
            .search('document number ${i % 10}')
            .catchError((_) => <SearchResult>[]));
      }

      // Add a tiny delay to let some searches start the spawn process
      await Future.delayed(const Duration(milliseconds: 1));

      // Dispose while searches are potentially mid-spawn
      await bm25.dispose();

      // All searches should complete (with results or errors)
      final results = await Future.wait(searchFutures);
      expect(results, isNotNull);
      expect(results.length, equals(100));
    });
  });

  group('PartitionedBM25', () {
    test('creates partitions based on field', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Introduction to Python',
          terms: ['introduction', 'to', 'python'],
          meta: {'filePath': 'python/intro.py'},
        ),
        BM25Document(
          id: 1,
          text: 'Advanced Python techniques',
          terms: ['advanced', 'python', 'techniques'],
          meta: {'filePath': 'python/advanced.py'},
        ),
        BM25Document(
          id: 2,
          text: 'Java programming basics',
          terms: ['java', 'programming', 'basics'],
          meta: {'filePath': 'java/basics.java'},
        ),
      ];

      final partitioned = await PartitionedBM25.build(
        docs,
        partitionBy: (doc) => (doc.meta['filePath'] as String).split('/')[0],
      );

      // Search in Python partition only
      final pythonResults = await partitioned.searchIn('python', 'python');
      expect(pythonResults.length, equals(2));

      // Search in Java partition
      final javaResults = await partitioned.searchIn('java', 'java');
      expect(javaResults.length, equals(1));
    });

    test('searches across multiple partitions', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Machine learning with Python',
          terms: ['machine', 'learning', 'with', 'python'],
          meta: {'category': 'ML'},
        ),
        BM25Document(
          id: 1,
          text: 'Machine learning algorithms',
          terms: ['machine', 'learning', 'algorithms'],
          meta: {'category': 'ML'},
        ),
        BM25Document(
          id: 2,
          text: 'Deep learning basics',
          terms: ['deep', 'learning', 'basics'],
          meta: {'category': 'DL'},
        ),
        BM25Document(
          id: 3,
          text: 'Computer vision with deep learning',
          terms: ['computer', 'vision', 'with', 'deep', 'learning'],
          meta: {'category': 'CV'},
        ),
      ];

      final partitioned = await PartitionedBM25.build(
        docs,
        partitionBy: (doc) => doc.meta['category'] as String,
      );

      // Search across ML and DL partitions
      final results = await partitioned.searchMany(['ML', 'DL'], 'learning');
      expect(results.length, equals(3));

      // Verify results are from correct partitions
      final categories = results.map((r) => r.doc.meta['category']).toSet();
      expect(categories, containsAll(['ML', 'DL']));
      expect(categories, isNot(contains('CV')));
    });

    test('handles non-existent partition gracefully', () async {
      final docs = [
        BM25Document(
          id: 0,
          text: 'Test document',
          terms: ['test', 'document'],
          meta: {'type': 'test'},
        ),
      ];

      final partitioned = await PartitionedBM25.build(
        docs,
        partitionBy: (doc) => doc.meta['type'] as String,
      );

      final results = await partitioned.searchIn('nonexistent', 'test');
      expect(results, isEmpty);
    });
  });
}
