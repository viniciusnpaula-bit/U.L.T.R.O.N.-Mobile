# U.L.T.R.O.N. Mobile

Assistente Android Flutter independente do U.L.T.R.O.N. Desktop, direcionado ao Samsung Galaxy A34 5G.

## Requisitos
- Flutter stable / Dart
- Android SDK

## Configuração
1. Instale Flutter e Android SDK.
2. Execute `flutter pub get`.
3. Copie `.env.example` para `.env` e configure `GEMINI_API_KEY`.
4. Execute `flutter run`.

Nunca versione chaves reais. O `.env` é ignorado pelo Git.

## Dispositivo-alvo
Samsung Galaxy A34 5G (Dimensity 1080, Mali-G68). A UI prioriza baixo consumo e não executa LLM local.

## Segurança
Respostas do modelo não autorizam ações sensíveis. Ações privilegiadas exigirão confirmação explícita e autenticação local.
