import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/slash_command_parser.dart';

void main() {
  test('recognizes supported slash commands case-insensitively', () {
    expect(SlashCommandParser.parse('/HELP')?.command, UltronCommand.help);
    expect(SlashCommandParser.parse('/security')?.command, UltronCommand.security);
    expect(SlashCommandParser.parse('/history')?.command, UltronCommand.history);
    expect(SlashCommandParser.parse('/settings')?.command, UltronCommand.settings);
  });

  test('does not classify ordinary messages or unknown commands', () {
    expect(SlashCommandParser.parse('Olá'), isNull);
    expect(SlashCommandParser.parse('/unknown'), isNull);
  });
}
