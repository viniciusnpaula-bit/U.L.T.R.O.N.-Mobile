import 'dart:async';

import 'package:flutter/services.dart';

class NfcHardwareStatus {
  const NfcHardwareStatus({
    required this.available,
    required this.enabled,
  });

  final bool available;
  final bool enabled;
}

class NfcWriteResult {
  const NfcWriteResult({
    required this.uid,
    required this.written,
    this.error,
  });

  final String uid;
  final bool written;
  final String? error;
}

/// Serviço nativo para leitura passiva e gravação NDEF (`ultron://unlock`)
/// de chaves físicas NFC via Android `NfcAdapter.enableReaderMode`.
class NfcAuthService {
  NfcAuthService({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/nfc') {
    _channel.setMethodCallHandler(_handleCall);
  }

  static final NfcAuthService instance = NfcAuthService();

  final MethodChannel _channel;
  final StreamController<String> _tagController =
      StreamController<String>.broadcast();
  final StreamController<NfcWriteResult> _writeController =
      StreamController<NfcWriteResult>.broadcast();
  int _activeReaders = 0;

  Stream<String> get tagStream => _tagController.stream;
  Stream<NfcWriteResult> get writeResultStream => _writeController.stream;

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'onNfcTagDetected') {
      final raw = (call.arguments as String? ?? '').trim().toUpperCase();
      if (raw.isNotEmpty) {
        _tagController.add(raw);
      }
    } else if (call.method == 'onNfcWriteResult') {
      final raw = call.arguments;
      if (raw is Map) {
        _writeController.add(
          NfcWriteResult(
            uid: (raw['uid'] as String? ?? '').trim().toUpperCase(),
            written: raw['written'] == true,
            error: raw['error'] as String?,
          ),
        );
      }
    }
    return null;
  }

  Future<NfcHardwareStatus> getStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getNfcStatus',
      );
      return NfcHardwareStatus(
        available: raw?['available'] == true,
        enabled: raw?['enabled'] == true,
      );
    } catch (_) {
      return const NfcHardwareStatus(available: false, enabled: false);
    }
  }

  Future<void> openNfcSettings() async {
    try {
      await _channel.invokeMethod<bool>('openNfcSettings');
    } catch (_) {}
  }

  Future<String?> consumePendingUnlockUid() async {
    try {
      final raw =
          await _channel.invokeMethod<String>('consumePendingNfcUnlock');
      final uid = raw?.trim().toUpperCase() ?? '';
      return uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

  Future<bool> startReader({bool writeUnlockNdef = false}) async {
    _activeReaders++;
    try {
      final res = await _channel.invokeMethod<bool>(
        'startNfcReader',
        {'writeUnlockNdef': writeUnlockNdef},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopReader() async {
    if (_activeReaders > 0) {
      _activeReaders--;
    }
    if (_activeReaders > 0) return;
    try {
      await _channel.invokeMethod<bool>('stopNfcReader');
    } catch (_) {}
  }
}
