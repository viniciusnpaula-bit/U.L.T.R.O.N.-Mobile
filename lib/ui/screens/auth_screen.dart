import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/security/auth_gate.dart';
import '../../core/security/pin_vault.dart';
import '../../services/conversation_history.dart';
import '../../services/nfc_auth_service.dart';
import '../theme/ultron_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.gate,
    required this.vault,
    this.nfcService,
  });

  final AuthGate gate;
  final PinVault vault;
  final NfcAuthService? nfcService;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  static const _rose = Color(0xFF9A9AA3);
  static const _border = Color(0xFF222228);
  static const _surface = Color(0xFF18181D);

  String pin = '';
  String? firstEntry;
  String? error;
  String pinStatus = 'AGUARDANDO PIN';
  bool? hasPin;
  bool busy = false;
  int failures = 0;
  Duration lockLeft = Duration.zero;
  List<BiometricType> biometrics = const [];
  bool hasNfcConfigured = false;
  bool nfcHwAvailable = false;
  bool nfcHwEnabled = false;
  bool _nfcReaderStarted = false;
  StreamSubscription<String>? _nfcSub;
  Timer? _lockTimer;

  NfcAuthService get _nfc => widget.nfcService ?? NfcAuthService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nfcSub?.cancel();
    if (_nfcReaderStarted) {
      unawaited(_nfc.stopReader());
    }
    _lockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final stored = await widget.vault.hasPin;
      final left = await widget.vault.lockRemaining();
      final count = await widget.vault.failureCount();
      final available = await widget.gate.biometrics();
      final nfcSet = await widget.vault.hasNfcKey;
      final nfcSt = await _nfc.getStatus();
      if (!mounted) return;
      setState(() {
        hasPin = stored;
        lockLeft = left;
        failures = count;
        biometrics = available;
        hasNfcConfigured = nfcSet;
        nfcHwAvailable = nfcSt.available;
        nfcHwEnabled = nfcSt.enabled;
        pinStatus = stored == false
            ? 'CRIE SEU PIN (4-8 DÍGITOS)'
            : left > Duration.zero
                ? 'BLOQUEIO TEMPORÁRIO'
                : 'AGUARDANDO AUTENTICAÇÃO';
      });
      _startLockTimer();
      final pendingUid = await _nfc.consumePendingUnlockUid();
      if (!mounted) return;
      if (stored == true && nfcSet && pendingUid != null) {
        await _handleNfcTag(pendingUid);
        if (!mounted || widget.gate.isAuthenticated) return;
      }
      if (stored == true && nfcSet && nfcSt.available && nfcSt.enabled) {
        await _startNfcListening();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        hasPin = false;
        pinStatus = 'ERRO DE COFRE';
        error = 'Armazenamento seguro indisponível: $e';
      });
    }
  }

  Future<void> _startNfcListening() async {
    if (_nfcReaderStarted) return;
    _nfcReaderStarted = true;
    await _nfc.startReader();
    await _nfcSub?.cancel();
    _nfcSub = _nfc.tagStream.listen(_handleNfcTag);
  }

  Future<void> _handleNfcTag(String uidHex) async {
    if (blocked || isSetup || !hasNfcConfigured) return;
    HapticFeedback.selectionClick();
    setState(() {
      busy = true;
      error = null;
      pinStatus = 'VERIFICANDO CHAVE NFC...';
    });
    try {
      final ok = await widget.gate.authenticateNfc(
        uidHex,
        widget.vault.verifyNfcTag,
      );
      if (ok) await widget.vault.resetFailures();
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        setState(() {
          busy = false;
          pinStatus = 'NÍVEL 2 • NFC LIBERADO';
        });
      } else {
        HapticFeedback.heavyImpact();
        await _refreshLock();
        if (!mounted) return;
        setState(() {
          busy = false;
          pinStatus = lockLeft > Duration.zero ? 'BLOQUEIO ATIVO' : 'CHAVE NFC RECUSADA';
          error = 'Tag NFC não autorizada.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        pinStatus = 'ERRO NFC';
        error = 'Falha ao validar NFC: $e';
      });
    }
  }

  void _startLockTimer() {
    _lockTimer?.cancel();
    if (lockLeft <= Duration.zero) return;
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final left = await widget.vault.lockRemaining();
      if (!mounted) return;
      setState(() {
        lockLeft = left;
        if (left <= Duration.zero) {
          error = null;
          pinStatus = 'AGUARDANDO PIN';
        }
      });
      if (left <= Duration.zero) _lockTimer?.cancel();
    });
  }

  Future<void> _refreshLock() async {
    final left = await widget.vault.lockRemaining();
    final count = await widget.vault.failureCount();
    if (!mounted) return;
    setState(() {
      lockLeft = left;
      failures = count;
    });
    _startLockTimer();
  }

  bool get isSetup => hasPin == false;
  bool get blocked => busy || lockLeft > Duration.zero;

  Future<void> _submit() async {
    if (blocked) return;
    if (isSetup && firstEntry == null) {
      if (pin.length < 4) {
        setState(() {
          pinStatus = 'PIN CURTO';
          error = 'Use de 4 a 8 dígitos';
        });
        return;
      }
      setState(() {
        firstEntry = pin;
        pin = '';
        error = null;
        pinStatus = 'REPITA O PIN';
      });
      return;
    }
    if (pin.length < 4) {
      setState(() {
        pinStatus = 'PIN CURTO';
        error = 'Use de 4 a 8 dígitos';
      });
      return;
    }
    if (isSetup) {
      if (pin != firstEntry) {
        HapticFeedback.heavyImpact();
        setState(() {
          firstEntry = null;
          pin = '';
          pinStatus = 'DIVERGÊNCIA DE PIN';
          error = 'Os PINs não coincidem. Tente de novo.';
        });
        return;
      }
      setState(() {
        busy = true;
        pinStatus = 'GRAVANDO COFRE PBKDF2...';
      });
      try {
        await widget.vault.setPin(pin);
        final ok = await widget.gate.authenticatePin(pin, widget.vault.verify);
        if (!mounted) return;
        setState(() {
          busy = false;
          pinStatus = ok ? 'PORTÃO LIBERADO' : 'FALHA NO COFRE';
          if (!ok) error = 'Não foi possível salvar o PIN';
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          busy = false;
          pinStatus = 'FALHA NO COFRE';
          error = 'Erro ao gravar PIN: $e';
        });
      }
      return;
    }

    setState(() {
      busy = true;
      pinStatus = 'AUTENTICANDO AUTHGATE...';
    });
    try {
      final mode = await widget.vault.verifyWithDuress(pin);
      if (!mounted) return;
      if (mode == PinAuthMode.duress) {
        try {
          await ConversationHistory.instance.clear();
        } catch (_) {}
        HapticFeedback.mediumImpact();
        if (!mounted) return;
        setState(() {
          busy = false;
          pin = '';
          pinStatus = 'PORTÃO LIBERADO';
        });
        widget.gate.grantDuress();
        return;
      }
      final ok = mode == PinAuthMode.normal &&
          await widget.gate.authenticatePin(pin, (_) async => true);
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        await _refreshLock();
        if (!mounted) return;
        setState(() {
          busy = false;
          pin = '';
          pinStatus =
              lockLeft > Duration.zero ? 'BLOQUEIO ATIVO' : 'PIN RECUSADO';
          error = 'PIN inválido';
        });
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        busy = false;
        pinStatus = 'PORTÃO LIBERADO';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        pinStatus = 'ERRO DE AUTENTICAÇÃO';
        error = 'Falha ao verificar PIN: $e';
      });
    }
  }

  Future<void> _biometric() async {
    if (busy || isSetup) return;
    HapticFeedback.selectionClick();
    setState(() {
      busy = true;
      error = null;
      pinStatus = 'ESCANEANDO BIOMETRIA...';
    });
    try {
      final ok = await widget.gate.authenticateBiometric();
      if (ok) await widget.vault.resetFailures();
      if (!mounted) return;
      setState(() {
        busy = false;
        if (ok) {
          pinStatus = 'BIOMETRIA APROVADA';
        } else {
          pinStatus = 'FALHA BIOMÉTRICA';
          error =
              'Sensor indisponível, cancelado ou bloqueado pelo sistema. Use o PIN.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        busy = false;
        pinStatus = 'FALHA BIOMÉTRICA';
        error = 'Sensor indisponível no momento. Use o PIN.';
      });
    }
  }

  void _handleDigit(String digit) {
    if (blocked) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    if (pin.length < 8) {
      setState(() {
        pin += digit;
        error = null;
        pinStatus = isSetup
            ? (firstEntry == null ? 'DIGITANDO NOVO PIN' : 'CONFIRMANDO PIN')
            : 'RECEBENDO PIN...';
      });
    }
  }

  void _handleBackspace() {
    if (blocked || pin.isEmpty) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
    setState(() {
      pin = pin.substring(0, pin.length - 1);
      error = null;
      if (pin.isEmpty) {
        pinStatus = isSetup
            ? (firstEntry == null
                ? 'CRIE SEU PIN (4-8 DÍGITOS)'
                : 'REPITA O PIN')
            : 'AGUARDANDO PIN';
      }
    });
  }

  void _handleClear() {
    if (blocked) return;
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
    setState(() {
      if (isSetup && pin.isEmpty && firstEntry != null) {
        firstEntry = null;
      }
      pin = '';
      error = null;
      pinStatus = isSetup
          ? (firstEntry == null ? 'CRIE SEU PIN (4-8 DÍGITOS)' : 'REPITA O PIN')
          : 'AGUARDANDO PIN';
    });
  }

  String get _biometricLabel {
    if (biometrics.contains(BiometricType.face)) {
      return 'Reconhecimento Facial';
    }
    if (biometrics.contains(BiometricType.fingerprint)) {
      return 'Impressão Digital';
    }
    if (biometrics.contains(BiometricType.iris)) return 'Scanner de Íris';
    return 'Face Unlock + Digital';
  }

  IconData get _biometricIcon => biometrics.contains(BiometricType.face)
      ? Icons.face_retouching_natural
      : Icons.fingerprint;

  static String _formatWait(Duration wait) {
    final seconds = wait.inSeconds;
    if (seconds < 60) return '${seconds}s';
    return '${wait.inMinutes}m${(seconds % 60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final accent = UltronTheme.accentOf(context);
    if (hasPin == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF080808),
        body: Center(
          child: CircularProgressIndicator(color: accent),
        ),
      );
    }

    final slotCount = max(4, pin.length);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Telemetry & AuthGate Header
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'GALAXY A34 5G',
                              style: TextStyle(
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              '• BLOQUEADO',
                              style: TextStyle(
                                color: _rose,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Icon(Icons.wifi, size: 11, color: accent),
                            const SizedBox(width: 3),
                            const Text(
                              '5G',
                              style: TextStyle(
                                color: Color(0xFF9A9AA3),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.battery_full,
                              size: 11,
                              color: Color(0xFF9A9AA3),
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'SECURE',
                              style: TextStyle(
                                color: Color(0xFF9A9AA3),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.only(bottom: 8),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.lock_outline, size: 13, color: accent),
                            const SizedBox(width: 6),
                            Text(
                              'AUTHGATE v1.19',
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          isSetup ? 'MODO: SETUP' : 'ISOLAMENTO: 127.0.0.1',
                          style: const TextStyle(
                            color: Color(0xFF9A9AA3),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Biometric Reticle + PIN Display
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: (!isSetup && !busy) ? _biometric : null,
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF111114),
                          border: Border.all(
                            color: busy
                                ? accent
                                : const Color(0xFF222228),
                            width: 1.5,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF1A1A20),
                                ),
                              ),
                            ),
                            Icon(
                              isSetup
                                  ? Icons.lock_outline_rounded
                                  : (busy
                                      ? Icons.face_retouching_natural
                                      : _biometricIcon),
                              size: 36,
                              color: busy ? accent : const Color(0xFFEEEEEE),
                            ),
                            if (busy)
                              Container(
                                width: 72,
                                height: 2,
                                color: accent,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isSetup
                          ? (firstEntry == null
                              ? 'CRIE SEU PIN DE OPERADOR'
                              : 'CONFIRME SEU PIN DE OPERADOR')
                          : '${_biometricLabel.toUpperCase()} + COFRE PIN',
                      style: const TextStyle(
                        color: _rose,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isSetup
                          ? 'USE DE 4 A 8 DÍGITOS E TOQUE EM ENTRAR'
                          : 'PIN (BASE) • NFC (2º ESTÁGIO) • ${_biometricLabel.toUpperCase()} (TOTAL)',
                      style: const TextStyle(
                        color: Color(0xFF9A9AA3),
                        fontSize: 9.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!isSetup && hasNfcConfigured) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: nfcHwAvailable && !nfcHwEnabled
                            ? () => _nfc.openNfcSettings()
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _surface.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: nfcHwEnabled
                                  ? const Color(0xFF9A9AA3)
                                  : Colors.white24,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.nfc,
                                size: 13,
                                color: nfcHwEnabled
                                    ? const Color(0xFF9A9AA3)
                                    : Colors.white54,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                nfcHwEnabled
                                    ? 'NFC PRONTO: ENCOSTE SUA TAG NO VERSO'
                                    : (nfcHwAvailable
                                        ? 'NFC DESLIGADO (TOQUE P/ ATIVAR)'
                                        : 'HARDWARE NFC INDISPONÍVEL'),
                                style: TextStyle(
                                  color: nfcHwEnabled
                                      ? const Color(0xFF9A9AA3)
                                      : Colors.white60,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // PIN Status & Slot Display
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'STATUS:',
                            style: TextStyle(
                              color: Color(0xFF9A9AA3),
                              fontSize: 10,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                lockLeft > Duration.zero
                                    ? 'AGUARDE ${_formatWait(lockLeft)}'
                                    : pinStatus,
                                style: TextStyle(
                                  color: lockLeft > Duration.zero
                                      ? UltronColors.crimson
                                      : accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (pin.isNotEmpty && !blocked) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _handleBackspace,
                                  borderRadius: BorderRadius.circular(4),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Icon(
                                      Icons.backspace_outlined,
                                      size: 13,
                                      color: _rose,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 6,
                        children: List.generate(slotCount, (idx) {
                          final filled = idx < pin.length;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: 32,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: filled
                                  ? const Color(0xFF18181D)
                                  : const Color(0xFF111114),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: filled ? accent : _border,
                              ),
                            ),
                            child: Text(
                              filled ? '●' : '·',
                              style: TextStyle(
                                color: filled
                                    ? const Color(0xFFEEEEEE)
                                    : const Color(0xFF686872),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    if (error != null || lockLeft > Duration.zero) ...[
                      const SizedBox(height: 8),
                      Text(
                        lockLeft > Duration.zero
                            ? 'Muitas tentativas. Aguarde ${_formatWait(lockLeft)}'
                            : error!,
                        style: const TextStyle(
                          color: _rose,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),

              // Virtual Keypad 3x4
              Column(
                children: [
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.15,
                    children: [
                      for (var num = 1; num <= 9; num++)
                        _KeypadButton(
                          label: num.toString(),
                          onTap: blocked ? null : () => _handleDigit('$num'),
                        ),
                      _KeypadButton(
                        label: isSetup && pin.isEmpty && firstEntry != null
                            ? 'VOLTAR'
                            : 'LIMPAR',
                        textColor: const Color(0xFF9A9AA3),
                        fontSize: 11,
                        onTap: blocked ? null : _handleClear,
                      ),
                      _KeypadButton(
                        label: '0',
                        onTap: blocked ? null : () => _handleDigit('0'),
                      ),
                      _KeypadButton(
                        label: 'ENTRAR ✓',
                        backgroundColor: const Color(0xFF18181D),
                        borderColor: const Color(0xFF18181D),
                        textColor: accent,
                        fontSize: 11,
                        onTap: blocked ? null : _submit,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(top: 8),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: _border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'PBKDF2-SHA256 • FALHAS: $failures',
                          style: const TextStyle(
                            color: Color(0xFF9A9AA3),
                            fontSize: 10,
                          ),
                        ),
                        const Text(
                          'FAIL-CLOSED ATIVO',
                          style: TextStyle(
                            color: Color(0xFF9A9AA3),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.backgroundColor = const Color(0xFF18181D),
    this.borderColor = const Color(0xFF222228),
    this.textColor = const Color(0xFFEEEEEE),
    this.fontSize = 15,
  });

  final String label;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: const Color(0xFF18181D),
          highlightColor: const Color(0xFF18181D),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null ? const Color(0xFF686872) : textColor,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
}
