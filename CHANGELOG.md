# Changelog

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