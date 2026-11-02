enum UltronCommand { help, security, history, settings }

class CommandResult {
  const CommandResult(this.command, this.argument);
  final UltronCommand command;
  final String argument;
}

class SlashCommandParser {
  static const commands = <String, UltronCommand>{
    '/help': UltronCommand.help,
    '/security': UltronCommand.security,
    '/history': UltronCommand.history,
    '/settings': UltronCommand.settings,
  };

  static CommandResult? parse(String input) {
    final text = input.trim();
    if (!text.startsWith('/')) return null;
    final parts = text.split(RegExp(r'\s+'));
    final command = commands[parts.first.toLowerCase()];
    if (command == null) return null;
    return CommandResult(command, parts.skip(1).join(' '));
  }
}
