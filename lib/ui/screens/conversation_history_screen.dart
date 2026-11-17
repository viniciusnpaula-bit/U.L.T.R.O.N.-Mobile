import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../services/conversation_history.dart';

class ConversationHistoryScreen extends StatefulWidget {
  const ConversationHistoryScreen({super.key});

  @override
  State<ConversationHistoryScreen> createState() =>
      _ConversationHistoryScreenState();
}

class _ConversationHistoryScreenState extends State<ConversationHistoryScreen> {
  static const _crimson = Color(0xFFE50914);
  static const _rose = Color(0xFFFFA0A0);
  static const _border = Color(0xFF51080D);

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
    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2E0305),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _border),
        ),
        title: const Text(
          'LIMPAR HISTÓRICO LOCAL?',
          style: TextStyle(
            color: _crimson,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Todas as conversas salvas neste aparelho serão apagadas permanentemente.',
          style: TextStyle(color: Color(0xFFF0E6E7), fontSize: 11),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'APAGAR',
              style: TextStyle(color: _crimson, fontWeight: FontWeight.bold),
            ),
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
        backgroundColor: const Color(0xFF0A0002),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.only(bottom: 10),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: _border)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Row(
                          children: [
                            Icon(Icons.arrow_back, size: 15, color: _crimson),
                            SizedBox(width: 4),
                            Text(
                              'VOLTAR',
                              style: TextStyle(
                                color: _crimson,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Row(
                        children: [
                          Icon(Icons.history, size: 15, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'HISTÓRICO DE SESSÕES',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Armazenamento local isolado (SQLite sem backup em nuvem).',
                      style: TextStyle(
                        color: Color(0xFF635355),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: FutureBuilder<List<ChatMessage>>(
                    future: _messages,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: _crimson),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Não foi possível carregar: ${snapshot.error}',
                            style: const TextStyle(
                              color: _rose,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }
                      final messages = snapshot.data ?? const <ChatMessage>[];
                      if (messages.isEmpty) {
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0002),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border),
                            ),
                            child: const Text(
                              'Nenhuma mensagem salva ainda.',
                              style: TextStyle(
                                color: Color(0xFFA89698),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isUser = message.role == ChatRole.user;
                          final timestamp = message.createdAt
                              .toLocal()
                              .toString()
                              .substring(0, 16);
                          return GestureDetector(
                            onLongPress: () {
                              HapticFeedback.selectionClick();
                              Clipboard.setData(
                                ClipboardData(text: message.content),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Mensagem copiada para a área de transferência.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? const Color(0xFF2E0305)
                                    : const Color(0xFF0A0002),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isUser
                                      ? _crimson.withValues(alpha: 0.4)
                                      : _border,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        isUser ? 'OPERADOR' : 'U.L.T.R.O.N.',
                                        style: TextStyle(
                                          color: isUser ? _rose : _crimson,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        timestamp,
                                        style: const TextStyle(
                                          color: Color(0xFF635355),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    message.content,
                                    style: const TextStyle(
                                      color: Color(0xFFF0E6E7),
                                      fontSize: 11,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Isolado Localmente',
                                        style: TextStyle(
                                          color: Color(0xFFFFA0A0),
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E0305),
                      foregroundColor: const Color(0xFFFFA0A0),
                      side: const BorderSide(color: Color(0x6651080D)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text(
                      'LIMPAR HISTÓRICO LOCAL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E0305),
                      foregroundColor: const Color(0xFFF0E6E7),
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'RETORNAR',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
