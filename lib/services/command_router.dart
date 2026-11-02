import 'package:flutter/foundation.dart';

enum CommandIntent { ai, openAiSettings, status, clearHistory, unknown }

class CommandResult {
  const CommandResult({required this.intent, required this.message, this.handled = true});
  final CommandIntent intent;
  final String message;
  final bool handled;
}

class CommandRouter {
  const CommandRouter();

  Future<CommandResult> route(
    String input, {
    required Future<String> Function(String prompt) askAi,
    required VoidCallback openAiSettings,
    required String statusSummary,
    required VoidCallback clearHistory,
  }) async {
    final text = input.trim();
    if (text.isEmpty) {
      return const CommandResult(intent: CommandIntent.unknown, message: 'Digite um comando.');
    }
    final normalized = text.toLowerCase();
    if (normalized == '/ajuda' || normalized == 'ajuda' || normalized == 'help') {
      return const CommandResult(
        intent: CommandIntent.unknown,
        message: 'Comandos: /status, /configurar-ia, /limpar. Para conversar, envie uma mensagem normalmente.',
      );
    }
    if (normalized == '/status' || normalized == 'status' || normalized == 'estado dos serviços') {
      return CommandResult(intent: CommandIntent.status, message: statusSummary);
    }
    if (normalized == '/configurar-ia' || normalized == 'configurar ia' || normalized == 'configurações de ia') {
      openAiSettings();
      return const CommandResult(intent: CommandIntent.openAiSettings, message: 'Abrindo configurações de IA.');
    }
    if (normalized == '/limpar' || normalized == 'limpar histórico') {
      clearHistory();
      return const CommandResult(intent: CommandIntent.clearHistory, message: 'Histórico desta sessão limpo.');
    }
    try {
      final answer = await askAi(text);
      return CommandResult(intent: CommandIntent.ai, message: answer);
    } catch (error) {
      return CommandResult(intent: CommandIntent.ai, message: error.toString(), handled: false);
    }
  }
}
