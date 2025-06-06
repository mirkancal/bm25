// Lightweight holder for raw text + arbitrary metadata.
class BM25Document {
  final int id;             // stable, 0-based
  final String text;        // original body (for display/snippets)
  final List<String> terms; // tokenised, lower-cased
  final Map<String, String> meta; // e.g. {'filePath': 'docs/a.pdf'}

  const BM25Document({
    required this.id,
    required this.text,
    required this.terms,
    this.meta = const {},
  });
}
