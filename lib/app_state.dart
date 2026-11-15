import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

final appState = AppState();

class AppState extends ChangeNotifier {
  final _secure = const FlutterSecureStorage();
  late SharedPreferences _prefs;

  Map<String, String> keys = {};
  Map<String, String> models = {};
  List<String> order = kProviders.map((p) => p.id).toList();
  Set<String> disabled = {};
  List<Conversation> convs = [];
  Conversation? current;
  int tab = 0;
  bool busy = false;

  // "Disjuntor": IA que falhou fica em descanso por um tempo.
  final Map<String, DateTime> _cool = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    for (final p in kProviders) {
      try {
        final k = await _secure.read(key: 'key_${p.id}');
        if (k != null && k.isNotEmpty) keys[p.id] = k;
      } catch (_) {}
      models[p.id] = _prefs.getString('model_${p.id}') ?? p.defaultModel;
    }
    order = _prefs.getStringList('order') ?? order;
    for (final p in kProviders) {
      if (!order.contains(p.id)) order.add(p.id);
    }
    disabled = (_prefs.getStringList('disabled') ?? []).toSet();
    final raw = _prefs.getString('convs');
    if (raw != null) {
      try {
        convs = (jsonDecode(raw) as List)
            .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
  }

  AiProvider byId(String id) => kProviders.firstWhere((p) => p.id == id);

  bool isReady(String id) =>
      (keys[id]?.isNotEmpty ?? false) && !disabled.contains(id);

  List<AiProvider> get readyProviders =>
      order.map(byId).where((p) => isReady(p.id)).toList();

  bool inCooldown(String id) =>
      _cool[id] != null && _cool[id]!.isAfter(DateTime.now());

  // ---------- Configuracoes ----------
  Future<void> setKey(String id, String key) async {
    if (key.isEmpty) {
      keys.remove(id);
      try { await _secure.delete(key: 'key_$id'); } catch (_) {}
    } else {
      keys[id] = key;
      try { await _secure.write(key: 'key_$id', value: key); } catch (_) {}
    }
    _cool.remove(id);
    notifyListeners();
  }

  Future<void> setModel(String id, String model) async {
    final m = model.isEmpty ? byId(id).defaultModel : model;
    models[id] = m;
    await _prefs.setString('model_$id', m);
    notifyListeners();
  }

  Future<void> toggle(String id, bool on) async {
    on ? disabled.remove(id) : disabled.add(id);
    await _prefs.setStringList('disabled', disabled.toList());
    notifyListeners();
  }

  Future<void> reorder(int from, int to) async {
    if (to > from) to -= 1;
    order.insert(to, order.removeAt(from));
    await _prefs.setStringList('order', order);
    notifyListeners();
  }

  // ---------- Rede ----------
  Never _fail(String id, int cooldownMin, String msg) {
    _cool[id] = DateTime.now().add(Duration(minutes: cooldownMin));
    throw AiException(msg);
  }

  Future<String> askOne(AiProvider p, List<Msg> history) async {
    final valid = history.where((m) => m.role == 'user' || m.role == 'assistant').toList();
    final msgs = valid.length > 20 ? valid.sublist(valid.length - 20) : valid;
    try {
      final res = await http
          .post(
            Uri.parse(p.url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${keys[p.id]}',
            },
            body: jsonEncode({
              'model': models[p.id],
              'messages': [for (final m in msgs) {'role': m.role, 'content': m.text}],
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final text = data['choices']?[0]?['message']?['content'];
        if (text is String && text.trim().isNotEmpty) {
          _cool.remove(p.id);
          return text.trim();
        }
        _fail(p.id, 1, 'resposta vazia');
      }
      if (res.statusCode == 429) _fail(p.id, 5, 'limite gratuito atingido');
      if (res.statusCode == 401 || res.statusCode == 403) {
        _fail(p.id, 30, 'chave invalida');
      }
      _fail(p.id, 1, 'erro ${res.statusCode}');
    } on AiException {
      rethrow;
    } on TimeoutException {
      _fail(p.id, 1, 'demorou demais');
    } catch (_) {
      _fail(p.id, 1, 'sem conexao');
    }
  }

  // Tenta as IAs na ordem de prioridade; pula as que estao em descanso.
  Future<Msg> send(List<Msg> history) async {
    final all = readyProviders;
    if (all.isEmpty) {
      throw AiException('Nenhuma IA configurada. Va em Config e adicione uma chave gratis.');
    }
    final fresh = all.where((p) => !inCooldown(p.id)).toList();
    final list = fresh.isNotEmpty ? fresh : all;
    String last = '';
    for (final p in list) {
      try {
        return Msg('assistant', await askOne(p, history), by: p.name);
      } on AiException catch (e) {
        last = '${p.name}: ${e.message}';
      }
    }
    throw AiException('Todas as IAs falharam. Ultimo erro: $last');
  }

  // ---------- Conversas ----------
  void setTab(int i) { tab = i; notifyListeners(); }
  void newChat() { current = null; tab = 0; notifyListeners(); }
  void open(Conversation c) { current = c; tab = 0; notifyListeners(); }

  Future<void> delete(Conversation c) async {
    convs.remove(c);
    if (current == c) current = null;
    await _saveConvs();
    notifyListeners();
  }

  Future<void> _saveConvs() async {
    await _prefs.setString('convs', jsonEncode(convs.map((c) => c.toJson()).toList()));
  }

  Future<void> chat(String text) async {
    current ??= Conversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: text.length > 40 ? '${text.substring(0, 40)}...' : text,
      msgs: [],
    );
    final c = current!;
    if (!convs.contains(c)) convs.add(c);
    c.msgs.add(Msg('user', text));
    busy = true;
    notifyListeners();
    try {
      c.msgs.add(await send(c.msgs));
    } on AiException catch (e) {
      c.msgs.add(Msg('error', e.message));
    } catch (_) {
      c.msgs.add(Msg('error', 'Erro inesperado. Tente novamente.'));
    }
    c.updated = DateTime.now().millisecondsSinceEpoch;
    busy = false;
    await _saveConvs();
    notifyListeners();
  }
}
