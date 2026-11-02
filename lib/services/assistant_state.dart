enum AssistantState {
  idle,
  processingCommand,
  queryingAi,
  listening,
  speaking,
  executingAction,
  error,
  cancelled,
}

String assistantStateLabel(AssistantState state) {
  switch (state) {
    case AssistantState.idle: return 'Ocioso';
    case AssistantState.processingCommand: return 'Processando comando';
    case AssistantState.queryingAi: return 'Consultando IA';
    case AssistantState.listening: return 'Escutando';
    case AssistantState.speaking: return 'Falando';
    case AssistantState.executingAction: return 'Executando ação';
    case AssistantState.error: return 'Erro';
    case AssistantState.cancelled: return 'Cancelado';
  }
}
