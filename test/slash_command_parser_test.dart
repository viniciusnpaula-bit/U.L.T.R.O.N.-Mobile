import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/slash_command_parser.dart';

void main() {
  test('recognizes supported slash commands case-insensitively and through synonyms', () {
    expect(SlashCommandParser.parse('/HELP')?.command, UltronCommand.help);
    expect(SlashCommandParser.parse('/ajuda')?.command, UltronCommand.help);
    expect(SlashCommandParser.parse('/security')?.command, UltronCommand.security);
    expect(SlashCommandParser.parse('/seguranca')?.command, UltronCommand.security);
    expect(SlashCommandParser.parse('/history')?.command, UltronCommand.history);
    expect(SlashCommandParser.parse('/historico')?.command, UltronCommand.history);
    expect(SlashCommandParser.parse('/settings')?.command, UltronCommand.settings);
    expect(SlashCommandParser.parse('/device')?.command, UltronCommand.device);
    expect(SlashCommandParser.parse('/celular')?.command, UltronCommand.device);
    expect(SlashCommandParser.parse('/lanterna')?.command, UltronCommand.torch);
    expect(SlashCommandParser.parse('/torch')?.command, UltronCommand.torch);
    expect(SlashCommandParser.parse('/skills')?.command, UltronCommand.skills);
    expect(SlashCommandParser.parse('/skill')?.command, UltronCommand.skills);
    expect(SlashCommandParser.parse('/note')?.command, UltronCommand.note);
    expect(SlashCommandParser.parse('/nota')?.command, UltronCommand.note);
    expect(SlashCommandParser.parse('/models')?.command, UltronCommand.models);
    expect(SlashCommandParser.parse('/modelos')?.command, UltronCommand.models);
    expect(SlashCommandParser.parse('/mensagens')?.command, UltronCommand.messages);
    expect(SlashCommandParser.parse('/ler')?.command, UltronCommand.messages);
    expect(SlashCommandParser.parse('/reply')?.command, UltronCommand.reply);
    expect(SlashCommandParser.parse('/responder')?.command, UltronCommand.reply);
    expect(SlashCommandParser.parse('/killswitch')?.command, UltronCommand.killswitch);
    expect(SlashCommandParser.parse('/travarpc')?.command, UltronCommand.killswitch);
    expect(SlashCommandParser.parse('/voice')?.command, UltronCommand.voice);
    expect(SlashCommandParser.parse('/voz')?.command, UltronCommand.voice);
    expect(SlashCommandParser.parse('/clear')?.command, UltronCommand.clear);
    expect(SlashCommandParser.parse('/lock')?.command, UltronCommand.lock);
    expect(SlashCommandParser.parse('/status')?.command, UltronCommand.status);
  });

  test('preserves command arguments separated by whitespace', () {
    final result = SlashCommandParser.parse('/note  revisar   sensores taticos');
    expect(result?.command, UltronCommand.note);
    expect(result?.argument, 'revisar sensores taticos');

    final skillResult = SlashCommandParser.parse('/skill modo_estudo');
    expect(skillResult?.command, UltronCommand.skills);
    expect(skillResult?.argument, 'modo_estudo');

    final replyResult = SlashCommandParser.parse('/reply Estou em reunião');
    expect(replyResult?.command, UltronCommand.reply);
    expect(replyResult?.argument, 'Estou em reunião');
  });

  test('does not classify ordinary messages or unknown commands', () {
    expect(SlashCommandParser.parse('Olá Ultron'), isNull);
    expect(SlashCommandParser.parse('/unknown_tactical_command'), isNull);
    expect(SlashCommandParser.parse('   '), isNull);
  });

  test('commandCatalog provides descriptive items', () {
    final catalog = SlashCommandParser.commandCatalog();
    expect(catalog.isNotEmpty, isTrue);
    expect(catalog.any((c) => c['command']!.contains('/device')), isTrue);
    expect(catalog.any((c) => c['command']!.contains('/lanterna')), isTrue);
    expect(catalog.any((c) => c['command']!.contains('/models')), isTrue);
  });
}
