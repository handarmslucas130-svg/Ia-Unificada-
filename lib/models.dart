class AiProvider {
  final String id, name, url, defaultModel, keyHelp;
  const AiProvider(this.id, this.name, this.url, this.defaultModel, this.keyHelp);
}

// Todas usam o formato "OpenAI compativel". Para adicionar uma IA nova: 1 linha aqui.
const kProviders = [
  AiProvider('groq', 'Groq', 'https://api.groq.com/openai/v1/chat/completions',
      'llama-3.3-70b-versatile', 'console.groq.com/keys'),
  AiProvider('gemini', 'Google Gemini',
      'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      'gemini-2.5-flash', 'aistudio.google.com/apikey'),
  AiProvider('openrouter', 'OpenRouter',
      'https://openrouter.ai/api/v1/chat/completions',
      'meta-llama/llama-3.3-70b-instruct:free', 'openrouter.ai/keys'),
  AiProvider('mistral', 'Mistral', 'https://api.mistral.ai/v1/chat/completions',
      'mistral-small-latest', 'console.mistral.ai/api-keys'),
  AiProvider('cerebras', 'Cerebras', 'https://api.cerebras.ai/v1/chat/completions',
      'llama-3.3-70b', 'cloud.cerebras.ai'),
];

class Msg {
  final String role; // user | assistant | error
  final String text;
  final String? by;
  Msg(this.role, this.text, {this.by});
  Map<String, dynamic> toJson() => {'role': role, 'text': text, 'by': by};
  factory Msg.fromJson(Map<String, dynamic> j) =>
      Msg(j['role'], j['text'], by: j['by']);
}

class Conversation {
  String id, title;
  List<Msg> msgs;
  int updated;
  Conversation({required this.id, required this.title, required this.msgs, int? updated})
      : updated = updated ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated,
        'msgs': msgs.map((m) => m.toJson()).toList(),
      };
  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'],
        title: j['title'],
        updated: j['updated'],
        msgs: (j['msgs'] as List)
            .map((m) => Msg.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}
