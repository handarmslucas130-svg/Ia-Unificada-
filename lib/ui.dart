import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

class Home extends StatelessWidget {
  const Home({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (_, __) => Scaffold(
          body: SafeArea(
            child: IndexedStack(index: appState.tab, children: const [
              ChatScreen(),
              CompareScreen(),
              HistoryScreen(),
              SettingsScreen(),
            ]),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: appState.tab,
            onDestinationSelected: appState.setTab,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
              NavigationDestination(icon: Icon(Icons.compare_arrows), label: 'Comparar'),
              NavigationDestination(icon: Icon(Icons.history), label: 'Historico'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Config'),
            ],
          ),
        ),
      );
}

// ---------------- CHAT ----------------
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _s = ScrollController();

  void _down() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_s.hasClients) {
          _s.animateTo(_s.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty || appState.busy) return;
    _c.clear();
    final f = appState.chat(t);
    _down();
    await f;
    _down();
  }

  Widget _bubble(BuildContext ctx, Msg m) {
    final user = m.role == 'user', err = m.role == 'error';
    final cs = Theme.of(ctx).colorScheme;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(ctx).size.width * 0.85),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: err ? cs.errorContainer : user ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (m.by != null)
            Text(m.by!,
                style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.bold)),
          SelectableText(m.text),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (ctx, _) {
          final msgs = appState.current?.msgs ?? [];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                const Expanded(
                    child: Text('IA Unificada',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(
                    tooltip: 'Nova conversa',
                    onPressed: appState.newChat,
                    icon: const Icon(Icons.add_comment_outlined)),
              ]),
            ),
            Expanded(
              child: msgs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          appState.readyProviders.isEmpty
                              ? 'Comece em Config: adicione uma chave gratis de pelo menos uma IA.'
                              : 'Pergunte qualquer coisa.\n${appState.readyProviders.length} IA(s) ativa(s), com troca automatica.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _s,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length + (appState.busy ? 1 : 0),
                      itemBuilder: (c, i) => i < msgs.length
                          ? _bubble(c, msgs[i])
                          : const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Pensando...',
                                  style: TextStyle(fontStyle: FontStyle.italic))),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Mensagem',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: appState.busy ? null : _send, icon: const Icon(Icons.send)),
              ]),
            ),
          ]);
        },
      );
}

// ---------------- COMPARAR ----------------
class _R {
  final String name;
  String? text, error;
  bool loading = true;
  _R(this.name);
}

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});
  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  final _c = TextEditingController();
  List<_R> res = [];

  Future<void> _go() async {
    final q = _c.text.trim();
    if (q.isEmpty) return;
    final ps = appState.readyProviders.take(3).toList();
    if (ps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adicione uma chave em Config primeiro.')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => res = [for (final p in ps) _R(p.name)]);
    await Future.wait([
      for (var i = 0; i < ps.length; i++)
        () async {
          try {
            res[i].text = await appState.askOne(ps[i], [Msg('user', q)]);
          } on AiException catch (e) {
            res[i].error = e.message;
          }
          res[i].loading = false;
          if (mounted) setState(() {});
        }(),
    ]);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Comparar IAs',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _c,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Mesma pergunta para ate 3 IAs',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _go, icon: const Icon(Icons.play_arrow)),
          ]),
        ),
        Expanded(
          child: res.isEmpty
              ? const Center(child: Text('As respostas aparecem lado a lado.\nDeslize para ver todas.', textAlign: TextAlign.center))
              : ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final r in res)
                      SizedBox(
                        width: 300,
                        child: Card(
                          margin: const EdgeInsets.only(right: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.name,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary)),
                              const Divider(),
                              Expanded(
                                child: r.loading
                                    ? const Center(child: CircularProgressIndicator())
                                    : SingleChildScrollView(
                                        child: SelectableText(
                                            r.text ?? 'Falhou: ${r.error}',
                                            style: r.text == null
                                                ? TextStyle(color: Theme.of(context).colorScheme.error)
                                                : null)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ]);
}

// ---------------- HISTORICO ----------------
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (ctx, _) {
          final list = [...appState.convs]..sort((a, b) => b.updated.compareTo(a.updated));
          return Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Historico',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Nenhuma conversa ainda.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (c, i) => Dismissible(
                        key: ValueKey(list[i].id),
                        background: Container(color: Colors.red),
                        onDismissed: (_) => appState.delete(list[i]),
                        child: ListTile(
                          title: Text(list[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${list[i].msgs.length} mensagens'),
                          onTap: () => appState.open(list[i]),
                        ),
                      ),
                    ),
            ),
          ]);
        },
      );
}

// ---------------- CONFIG ----------------
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _edit(BuildContext context, AiProvider p) async {
    final k = TextEditingController(text: appState.keys[p.id] ?? '');
    final m = TextEditingController(text: appState.models[p.id]);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Chave gratis em: ${p.keyHelp}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
                controller: k,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Chave de API')),
            TextField(controller: m, decoration: const InputDecoration(labelText: 'Modelo')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await appState.setKey(p.id, k.text.trim());
              await appState.setModel(p.id, m.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (ctx, _) => ReorderableListView.builder(
          header: const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Config\n\nToque para colocar a chave. Segure e arraste para mudar a prioridade: se a 1a falhar, o app usa a 2a, e assim por diante.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          itemCount: appState.order.length,
          onReorder: appState.reorder,
          itemBuilder: (c, i) {
            final p = appState.byId(appState.order[i]);
            final has = appState.keys[p.id]?.isNotEmpty ?? false;
            final status = !has
                ? 'sem chave'
                : appState.inCooldown(p.id)
                    ? 'em descanso (falhou/limite)'
                    : 'pronta';
            return ListTile(
              key: ValueKey(p.id),
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(p.name),
              subtitle: Text('${appState.models[p.id]} - $status'),
              trailing: Switch(
                  value: !appState.disabled.contains(p.id),
                  onChanged: (v) => appState.toggle(p.id, v)),
              onTap: () => _edit(c, p),
            );
          },
        ),
      );
}
