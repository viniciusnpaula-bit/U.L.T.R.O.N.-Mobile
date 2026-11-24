import 'package:flutter/material.dart';

class ActionConfirmationRequest {
  const ActionConfirmationRequest({
    required this.title,
    required this.description,
    this.actionLabel = 'Confirmar',
    this.danger = false,
  });

  final String title;
  final String description;
  final String actionLabel;
  final bool danger;
}

typedef ConfirmationGate = Future<bool> Function(
  ActionConfirmationRequest request,
);

/// Displays an explicit, fail-closed confirmation dialog before executing any
/// sensitive local, Android, or remote Desktop action.
Future<bool> showActionConfirmationDialog(
  BuildContext context,
  ActionConfirmationRequest request,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF111114),
      title: Text(request.title),
      content: Text(request.description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: request.danger
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF10D28),
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(request.actionLabel),
        ),
      ],
    ),
  );
  return result == true;
}
