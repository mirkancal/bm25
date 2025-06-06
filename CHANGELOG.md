# Changelog

## 2.5.0

### New Features
- **Ultra-fast BM25 implementation**: Complete rewrite with significant performance improvements
  - Cache-friendly design with gap-encoded postings in single Uint32List
  - O(T) build time, O(#postings) query time with tight upper-bound loop
  - Lock-free top-K selection using fixed-size min-heap
  - Instance-scoped isolate for concurrent searches
- **Native metadata filtering**: Filter search results by arbitrary metadata fields
  - Support for single value and multi-value filters
  - Efficient field indexing for fast filtering
  - Example: `search('query', filter: {'filePath': 'docs/intro.md'})`
- **PartitionedBM25**: New class for managing per-partition indices
  - Create separate indices based on document attributes
  - Search within specific partitions or across multiple partitions
  - Ideal for large corpora with natural divisions (e.g., per-file indices)
- **Improved document handling**: BM25Document now includes metadata field
  - Store arbitrary key-value pairs with documents
  - Use metadata for filtering and partitioning

### Improvements
- Better memory efficiency with typed arrays
- Improved tokenization performance
- Enhanced concurrent search handling

### API Changes
- `BM25.build()` now accepts `indexFields` parameter for metadata indexing
- `search()` method now accepts optional `filter` parameter
- New `PartitionedBM25` class with `searchIn()` and `searchMany()` methods

## 2.0.0

### Breaking Changes
- **BREAKING**: Renamed `Document` class to `BM25Document` to avoid naming conflicts with other libraries
- **BREAKING**: Renamed `document.dart` file to `bm25_document.dart`

### Migration Guide
Update your imports and class references:
```dart
// Before
import 'package:bm25/src/document.dart';
Document doc = Document(...);

// After
import 'package:bm25/bm25.dart';
BM25Document doc = BM25Document(...);
```

## 1.0.0

- Initial release
- Implement BM25 ranking algorithm
- Support for document search and ranking
- Document chunking capabilities
- Configurable BM25 parameters (k1 and b)
- Comprehensive test coverage