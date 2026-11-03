import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_history.dart';

class ConversationHistoryScreen extends StatefulWidget {
  const ConversationHistoryScreen({super.key});

  @override
  State<ConversationHistoryScreen> createState() =>
      _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  late Future<List<ChatMessage>> _messages;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _messages = ConversationHistory.instance.messages();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text(
          'Todas as conversas salvas neste aparelho serão apagadas. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('APAGAR'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ConversationHistory.instance.clear();
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Histórico'),
          actions: [
            IconButton(
              tooltip: 'Limpar histórico',
              onPressed: _clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: FutureBuilder<List<ChatMessage>>(
          future: _messages,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Não foi possível carregar: ${snapshot.error}'));
            }
            final messages = snapshot.data ?? const <ChatMessage>[];
            if (messages.isEmpty) {
              return const Center(child: Text('Nenhuma mensagem salva ainda.'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final isUser = message.role == ChatRole.user;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Card(
                    color: isUser ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(isUser ? 'Você' : 'U.L.T.R.O.N.',
                              style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Text(message.content),
                          const SizedBox(height: 4),
                          Text(
                            message.createdAt.toLocal().toString().substring(0, 16),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}
