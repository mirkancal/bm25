# Changelog

## 2.2.3

### New Features
- **Relevance Feedback**: Implemented `searchWithFeedback` extension method using the Rocchio algorithm
  - Enhances search results by incorporating terms from documents marked as relevant
  - Supports customizable alpha (original query weight) and beta (relevant document weight) parameters
  - Uses logarithmic scaling for term repetition to better represent term importance
  - Preserves original query terms to maintain user intent

### Improvements
- Added public `documents` getter to BM25 class for extension access
- Moved filter validation to beginning of search method for early error detection
- Enhanced error handling with NaN/Infinity checks in relevance feedback calculations
- Optimized relevant document lookup with O(1) Set operations and early exit
- Document length normalization prevents bias towards longer documents

### Bug Fixes
- Fixed incomplete `searchWithFeedback` implementation that was just redirecting to regular search
- Fixed ID type mismatch - changed `relevantDocIds` from `List<String>` to `List<int>`
- Fixed alpha parameter not being used in Rocchio algorithm
- Fixed beta parameter only affecting term count instead of term weights
- Fixed edge case where original query terms could be dropped when alpha < 0.1

## 2.2.2

### Bug Fixes
- **Critical**: Fixed race condition in worker lifecycle management
  - Worker spawn operations are now properly memoized using `CancelableOperation` to prevent concurrent spawns
  - Added dedicated shutdown acknowledgment port to ensure graceful worker termination
  - Prevents race conditions where `_initPort` could be accessed after being closed
  
- **Critical**: Fixed deadlock in concurrent search/disposal scenarios
  - Added `_disposeSignal` Completer to notify all waiting operations when disposal begins
  - All async operations now use `Future.any` to race against the disposal signal
  - Searches waiting on cancelled spawn operations are immediately notified instead of hanging
  - Disposal now waits for all active searches without timeout to ensure clean shutdown
  - Fixes edge case where multiple concurrent searches could hang indefinitely during disposal

### Improvements
- Enhanced concurrent operation handling with proper synchronization primitives
- Added defensive checks in `_performSearch` to prevent operations after disposal
- Improved error messages for disposal-related state errors
- Added comprehensive test coverage including stress tests for concurrent disposal scenarios

### Internal Changes
- Changed from lazy to eager initialization of `_disposeSignal` for better performance
- Used `Completer.sync()` for immediate notification without micro-task delay
- Removed redundant disposed state checks after `Future.any` races

## 2.2.1

### Bug Fixes
- **Critical**: Fixed ReceivePort memory leak that caused "no free native port" errors under heavy load
  - `_initPort` is now properly closed after worker initialization
  - Prevents resource exhaustion in long-running applications
- **Critical**: Fixed race condition between `dispose()` and `search()` operations
  - Added tracking of active searches to ensure graceful shutdown
  - `dispose()` now waits for in-flight searches to complete (with 5s timeout)
  - Prevents "send on closed port" exceptions and hanging futures
- Added comprehensive test coverage for resource management and concurrent operations

### Improvements
- Better lifecycle management with `_isDisposed` flag to prevent operations after disposal
- Multiple `dispose()` calls are now safe (idempotent)
- Enhanced error messages for disposal-related state errors

## 2.1.0

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