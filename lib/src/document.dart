/// A document that can be searched
class Document {
  final int id;
  final String text;
  final List<String> terms;

  const Document({
    required this.id,
    required this.text,
    required this.terms,
  });
}
