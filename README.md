# BM25 for Dart

A pure Dart implementation of the BM25 ranking algorithm for full-text search.

## Installation

```yaml
dependencies:
  bm25: ^1.0.0
```

## Quick Start

```dart
import 'package:bm25/bm25.dart';

void main() {
  var documents = [
    Document(id: '1', content: 'The quick brown fox'),
    Document(id: '2', content: 'The lazy dog'),
  ];
  
  var bm25 = BM25(documents: documents);
  var results = bm25.search('fox');
}
```

## License

MIT
