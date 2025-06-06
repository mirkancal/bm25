/// A document that can be searched
class Document {
  final String id;
  final String content;
  final Map<String, dynamic>? metadata;
  final List<String> _tokens;
  
  Document({
    required this.id, 
    required this.content,
    this.metadata,
  }) : _tokens = _tokenize(content.toLowerCase());
  
  static List<String> _tokenize(String text) {
    return text
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }
  
  List<String> get tokens => _tokens;
}
