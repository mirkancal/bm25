/// A document that can be searched
class BM25Document {
  final int id;
  final String text;
  final List<String> terms;

  BM25Document({
    required this.id,
    required this.text,
    required this.terms,
  });
}
