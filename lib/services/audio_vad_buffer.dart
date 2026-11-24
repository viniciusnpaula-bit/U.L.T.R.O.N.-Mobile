import 'dart:math' as math;
import 'dart:typed_data';

/// Computes energy and spectral metrics over little-endian 16-bit PCM frames.
class PcmEnergy {
  PcmEnergy._();

  /// Returns the root-mean-square amplitude in int16 units (`0.0..32768.0`).
  static double rmsInt16(Uint8List pcm) {
    final usableBytes = pcm.length & ~1;
    if (usableBytes == 0) return 0.0;
    final sampleCount = usableBytes ~/ 2;
    final data = ByteData.sublistView(pcm, 0, usableBytes);
    double sumSquares = 0;
    for (var i = 0; i < usableBytes; i += 2) {
      final sample = data.getInt16(i, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / sampleCount);
  }

  /// Returns DC-offset-removed RMS amplitude in int16 units (`0.0..32768.0`).
  /// Prevents hardware microphone DC bias from falsely triggering Auto-VAD.
  static double dcRemovedRmsInt16(Uint8List pcm) {
    final usableBytes = pcm.length & ~1;
    if (usableBytes == 0) return 0.0;
    final sampleCount = usableBytes ~/ 2;
    final data = ByteData.sublistView(pcm, 0, usableBytes);
    double sum = 0;
    for (var i = 0; i < usableBytes; i += 2) {
      sum += data.getInt16(i, Endian.little).toDouble();
    }
    final mean = sum / sampleCount;
    double sumSquares = 0;
    for (var i = 0; i < usableBytes; i += 2) {
      final centered = data.getInt16(i, Endian.little).toDouble() - mean;
      sumSquares += centered * centered;
    }
    return math.sqrt(sumSquares / sampleCount);
  }

  /// Computes zero-crossing rate in `[0.0, 1.0]` after removing DC offset.
  static double zeroCrossingRate(Uint8List pcm) {
    final usableBytes = pcm.length & ~1;
    final sampleCount = usableBytes ~/ 2;
    if (sampleCount < 2) return 0.0;
    final data = ByteData.sublistView(pcm, 0, usableBytes);
    double sum = 0;
    for (var i = 0; i < usableBytes; i += 2) {
      sum += data.getInt16(i, Endian.little).toDouble();
    }
    final mean = sum / sampleCount;
    var crossings = 0;
    var prevPos = (data.getInt16(0, Endian.little).toDouble() - mean) >= 0;
    for (var i = 2; i < usableBytes; i += 2) {
      final curPos = (data.getInt16(i, Endian.little).toDouble() - mean) >= 0;
      if (curPos != prevPos) {
        crossings++;
        prevPos = curPos;
      }
    }
    return crossings / (sampleCount - 1);
  }

  /// Converte RMS (0..32768) para escala logarítmica dBFS limitada em `[-60.0, 0.0]`.
  static double dbfsFromRms(double rms) {
    if (rms <= 0.0) return -60.0;
    final norm = (rms / 32768.0).clamp(1e-6, 1.0);
    final db = 20.0 * (math.log(norm) / math.ln10);
    return db.clamp(-60.0, 0.0);
  }

  /// Mede o piso de ruído ambiente em dBFS a partir de um bloco PCM16 mono.
  static double noiseFloorDb(Uint8List pcm) => dbfsFromRms(rmsInt16(pcm));
}

/// Perfis calibrados de Auto-VAD adaptativo para diferentes ambientes acústicos.
enum VadProfile {
  quiet(
    id: 'quiet',
    label: 'Silencioso',
    description: 'Alta sensibilidade para quartos ou escritórios calmos',
    minSpeechThreshold: 85.0,
    startSnrRatio: 1.9,
    continueSnrRatio: 1.35,
    noiseMarginRms: 45.0,
    minSpeechDuration: Duration(milliseconds: 80),
    minUtteranceDuration: Duration(milliseconds: 200),
    defaultHangover: Duration(milliseconds: 750),
  ),
  balanced(
    id: 'balanced',
    label: 'Balanceado',
    description: 'Adapta ao ruído ambiente com pausas naturais',
    minSpeechThreshold: 140.0,
    startSnrRatio: 2.35,
    continueSnrRatio: 1.50,
    noiseMarginRms: 85.0,
    minSpeechDuration: Duration(milliseconds: 100),
    minUtteranceDuration: Duration(milliseconds: 240),
    defaultHangover: Duration(milliseconds: 850),
  ),
  noisy(
    id: 'noisy',
    label: 'Ruidoso',
    description: 'Filtra ventilador, TV, trânsito e ruído constante',
    minSpeechThreshold: 260.0,
    startSnrRatio: 2.85,
    continueSnrRatio: 1.75,
    noiseMarginRms: 150.0,
    minSpeechDuration: Duration(milliseconds: 140),
    minUtteranceDuration: Duration(milliseconds: 280),
    defaultHangover: Duration(milliseconds: 700),
  );

  const VadProfile({
    required this.id,
    required this.label,
    required this.description,
    required this.minSpeechThreshold,
    required this.startSnrRatio,
    required this.continueSnrRatio,
    required this.noiseMarginRms,
    required this.minSpeechDuration,
    required this.minUtteranceDuration,
    required this.defaultHangover,
  });

  final String id;
  final String label;
  final String description;
  final double minSpeechThreshold;
  final double startSnrRatio;
  final double continueSnrRatio;
  final double noiseMarginRms;
  final Duration minSpeechDuration;
  final Duration minUtteranceDuration;
  final Duration defaultHangover;

  static VadProfile fromId(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    for (final p in VadProfile.values) {
      if (p.id == normalized) return p;
    }
    return VadProfile.balanced;
  }
}

/// Snapshot imutável de diagnóstico acústico em campo.
class AcousticDiagnosticsSnapshot {
  const AcousticDiagnosticsSnapshot({
    required this.ambientNoiseDb,
    required this.preRollMs,
    required this.avgSttLatencyMs,
    required this.sttSampleCount,
    required this.kwsTriggers,
    required this.kwsFalsePositives,
  });

  final double ambientNoiseDb;
  final int preRollMs;
  final int avgSttLatencyMs;
  final int sttSampleCount;
  final int kwsTriggers;
  final int kwsFalsePositives;

  double get falsePositiveRate => kwsTriggers <= 0
      ? 0.0
      : (kwsFalsePositives / kwsTriggers).clamp(0.0, 1.0);
}

/// Rastreador local de métricas acústicas (AudioRecord / Auto-VAD / Whisper / KWS).
class AcousticDiagnosticsTracker {
  AcousticDiagnosticsTracker({this.preRollMs = 500});

  static final AcousticDiagnosticsTracker instance =
      AcousticDiagnosticsTracker();

  final int preRollMs;
  double _ambientNoiseDb = -52.0;
  int _totalSttLatencyMs = 0;
  int _sttSamples = 0;
  int _kwsTriggers = 0;
  int _kwsFalsePositives = 0;

  void recordPcmNoiseFrame(Uint8List pcm) {
    _ambientNoiseDb = PcmEnergy.noiseFloorDb(pcm);
  }

  void recordNoiseFloorDb(double db) {
    _ambientNoiseDb = db.clamp(-60.0, 0.0);
  }

  void recordSttLatency(int elapsedMs) {
    if (elapsedMs < 0) return;
    _totalSttLatencyMs += elapsedMs;
    _sttSamples++;
  }

  void recordKwsTrigger({bool falsePositive = false}) {
    _kwsTriggers++;
    if (falsePositive) _kwsFalsePositives++;
  }

  void reset() {
    _ambientNoiseDb = -52.0;
    _totalSttLatencyMs = 0;
    _sttSamples = 0;
    _kwsTriggers = 0;
    _kwsFalsePositives = 0;
  }

  AcousticDiagnosticsSnapshot snapshot() => AcousticDiagnosticsSnapshot(
        ambientNoiseDb: _ambientNoiseDb,
        preRollMs: preRollMs,
        avgSttLatencyMs:
            _sttSamples == 0 ? 0 : (_totalSttLatencyMs / _sttSamples).round(),
        sttSampleCount: _sttSamples,
        kwsTriggers: _kwsTriggers,
        kwsFalsePositives: _kwsFalsePositives,
      );
}

/// Fixed-capacity circular byte buffer for pre-speech audio lookback.
class PreSpeechRingBuffer {
  PreSpeechRingBuffer({this.capacityBytes = 12800})
      : assert(capacityBytes >= 0),
        _buffer = Uint8List(capacityBytes);

  final int capacityBytes;
  final Uint8List _buffer;
  int _head = 0;
  int _length = 0;

  int get length => _length;

  /// Appends [frame], overwriting the oldest bytes if capacity is exceeded.
  void push(Uint8List frame) {
    if (capacityBytes == 0 || frame.isEmpty) return;

    if (frame.length >= capacityBytes) {
      final offset = frame.length - capacityBytes;
      _buffer.setRange(0, capacityBytes, frame, offset);
      _head = 0;
      _length = capacityBytes;
      return;
    }

    final available = capacityBytes - _length;
    if (frame.length > available) {
      final drop = frame.length - available;
      _head = (_head + drop) % capacityBytes;
      _length -= drop;
    }

    final tail = (_head + _length) % capacityBytes;
    final firstChunk = math.min(frame.length, capacityBytes - tail);
    _buffer.setRange(tail, tail + firstChunk, frame, 0);
    final remaining = frame.length - firstChunk;
    if (remaining > 0) {
      _buffer.setRange(0, remaining, frame, firstChunk);
    }
    _length += frame.length;
  }

  /// Returns all buffered bytes in FIFO order and resets the buffer.
  Uint8List drain() {
    if (_length == 0) return Uint8List(0);
    final result = Uint8List(_length);
    final firstChunk = math.min(_length, capacityBytes - _head);
    result.setRange(0, firstChunk, _buffer, _head);
    final remaining = _length - firstChunk;
    if (remaining > 0) {
      result.setRange(firstChunk, _length, _buffer, 0);
    }
    clear();
    return result;
  }

  void clear() {
    _head = 0;
    _length = 0;
  }
}

/// Segments continuous PCM16 mono frames into speech utterances.
///
/// Supports both deterministic fixed-threshold mode (default for unit tests)
/// and [VadSegmenter.adaptive] mode with DC-offset removal, asymmetric ambient
/// noise-floor tracking, dual-threshold hysteresis, speech onset debouncing,
/// and minimum utterance validation.
class VadSegmenter {
  VadSegmenter({
    this.sampleRate = 16000,
    double speechThreshold = 50.0,
    this.preSpeechDuration = const Duration(milliseconds: 400),
    Duration silenceHangover = const Duration(milliseconds: 700),
    this.maxTurnDuration = const Duration(seconds: 15),
    this.adaptiveNoiseFloor = false,
    double startSnrRatio = 2.35,
    double continueSnrRatio = 1.50,
    double noiseMarginRms = 85.0,
    Duration minSpeechDuration = Duration.zero,
    Duration minUtteranceDuration = Duration.zero,
    VadProfile profile = VadProfile.balanced,
  })  : _speechThreshold = speechThreshold,
        _silenceHangover = silenceHangover,
        _startSnrRatio = startSnrRatio,
        _continueSnrRatio = continueSnrRatio,
        _noiseMarginRms = noiseMarginRms,
        _minSpeechDuration = minSpeechDuration,
        _minUtteranceDuration = minUtteranceDuration,
        _profile = profile,
        _preSpeech = PreSpeechRingBuffer(
          capacityBytes: _durationToEvenBytes(sampleRate, preSpeechDuration),
        ),
        _hangoverBytes = _durationToEvenBytes(sampleRate, silenceHangover),
        _maxTurnBytes = _durationToEvenBytes(sampleRate, maxTurnDuration),
        _minSpeechBytes = _durationToEvenBytes(sampleRate, minSpeechDuration),
        _minUtteranceBytes =
            _durationToEvenBytes(sampleRate, minUtteranceDuration);

  /// Factory tuned for real-world Android microphone capture with adaptive
  /// ambient noise tracking, hysteresis, and click/bump onset filtering.
  factory VadSegmenter.adaptive({
    int sampleRate = 16000,
    VadProfile profile = VadProfile.balanced,
    Duration? silenceHangover,
    Duration preSpeechDuration = const Duration(milliseconds: 500),
    Duration maxTurnDuration = const Duration(seconds: 18),
  }) {
    return VadSegmenter(
      sampleRate: sampleRate,
      speechThreshold: profile.minSpeechThreshold,
      preSpeechDuration: preSpeechDuration,
      silenceHangover: silenceHangover ?? profile.defaultHangover,
      maxTurnDuration: maxTurnDuration,
      adaptiveNoiseFloor: true,
      startSnrRatio: profile.startSnrRatio,
      continueSnrRatio: profile.continueSnrRatio,
      noiseMarginRms: profile.noiseMarginRms,
      minSpeechDuration: profile.minSpeechDuration,
      minUtteranceDuration: profile.minUtteranceDuration,
      profile: profile,
    );
  }

  static const double _minNoiseFloorRms = 18.0;
  static const double _maxNoiseFloorRms = 2400.0;

  final int sampleRate;
  final Duration preSpeechDuration;
  final Duration maxTurnDuration;
  final bool adaptiveNoiseFloor;

  double _speechThreshold;
  Duration _silenceHangover;
  double _startSnrRatio;
  double _continueSnrRatio;
  double _noiseMarginRms;
  Duration _minSpeechDuration;
  Duration _minUtteranceDuration;
  VadProfile _profile;

  final PreSpeechRingBuffer _preSpeech;
  int _hangoverBytes;
  final int _maxTurnBytes;
  int _minSpeechBytes;
  int _minUtteranceBytes;
  final BytesBuilder _speechBuilder = BytesBuilder(copy: false);
  final BytesBuilder _onsetBuilder = BytesBuilder(copy: false);

  bool _inSpeech = false;
  int _silenceBytes = 0;
  int _activeSpeechBytes = 0;
  double _noiseFloorRms = 45.0;
  int _noiseSamples = 0;
  double _lastFrameRms = 0.0;

  double get speechThreshold => _speechThreshold;
  Duration get silenceHangover => _silenceHangover;
  VadProfile get profile => _profile;
  bool get isInSpeech => _inSpeech;
  double get noiseFloorRms => _noiseFloorRms;
  double get noiseFloorDb => PcmEnergy.dbfsFromRms(_noiseFloorRms);
  double get lastFrameRms => _lastFrameRms;
  double get lastFrameDb => PcmEnergy.dbfsFromRms(_lastFrameRms);

  /// Current effective RMS threshold required to start speech detection.
  double get effectiveStartThreshold {
    if (!adaptiveNoiseFloor) return _speechThreshold;
    return math.max(
      _speechThreshold,
      _noiseFloorRms * _startSnrRatio + _noiseMarginRms,
    );
  }

  /// Current effective RMS threshold (lower hysteresis bound) to keep speech active.
  double get effectiveContinueThreshold {
    if (!adaptiveNoiseFloor) return _speechThreshold;
    return math.max(
      _speechThreshold * 0.68,
      _noiseFloorRms * _continueSnrRatio + _noiseMarginRms * 0.42,
    );
  }

  double get effectiveStartThresholdDb =>
      PcmEnergy.dbfsFromRms(effectiveStartThreshold);

  /// Updates Auto-VAD sensitivity profile and optional hangover live without restart.
  void applyProfile(VadProfile nextProfile, {Duration? silenceHangover}) {
    _profile = nextProfile;
    _speechThreshold = nextProfile.minSpeechThreshold;
    _startSnrRatio = nextProfile.startSnrRatio;
    _continueSnrRatio = nextProfile.continueSnrRatio;
    _noiseMarginRms = nextProfile.noiseMarginRms;
    _minSpeechDuration = nextProfile.minSpeechDuration;
    _minUtteranceDuration = nextProfile.minUtteranceDuration;
    _silenceHangover = silenceHangover ?? nextProfile.defaultHangover;
    _hangoverBytes = _durationToEvenBytes(sampleRate, _silenceHangover);
    _minSpeechBytes = _durationToEvenBytes(sampleRate, _minSpeechDuration);
    _minUtteranceBytes =
        _durationToEvenBytes(sampleRate, _minUtteranceDuration);
  }

  static int _durationToEvenBytes(int sampleRate, Duration duration) {
    final raw = (sampleRate * 2 * duration.inMicroseconds) ~/ 1000000;
    return raw & ~1;
  }

  void _updateNoiseFloor(double rms) {
    if (!adaptiveNoiseFloor) return;
    final clamped = rms.clamp(_minNoiseFloorRms, _maxNoiseFloorRms);
    if (_noiseSamples == 0) {
      _noiseFloorRms = clamped;
      _noiseSamples = 1;
      return;
    }
    if (_noiseSamples < 10) {
      // Fast lock-on during initial 200ms after opening microphone.
      _noiseFloorRms = _noiseFloorRms * 0.65 + clamped * 0.35;
      _noiseSamples++;
      return;
    }
    // Asymmetric EMA: track quieter room fast, absorb steady rising noise slowly.
    final alpha = clamped < _noiseFloorRms ? 0.16 : 0.035;
    _noiseFloorRms =
        (_noiseFloorRms * (1.0 - alpha) + clamped * alpha).clamp(
      _minNoiseFloorRms,
      _maxNoiseFloorRms,
    );
  }

  /// Processes one PCM16 mono frame and yields any completed speech segment.
  Stream<Uint8List> processFrame(Uint8List frame) async* {
    if (frame.isEmpty) return;
    final rms = adaptiveNoiseFloor
        ? PcmEnergy.dcRemovedRmsInt16(frame)
        : PcmEnergy.rmsInt16(frame);
    _lastFrameRms = rms;

    if (!_inSpeech) {
      // Reject sub-30Hz pure handling thumps when adaptive mode is enabled.
      final zcrOk = !adaptiveNoiseFloor ||
          PcmEnergy.zeroCrossingRate(frame) >= 0.004;
      final isSpeechCandidate = zcrOk && rms >= effectiveStartThreshold;

      if (!isSpeechCandidate) {
        if (_onsetBuilder.isNotEmpty) {
          // Transient click/tap failed onset confirmation; fold back into pre-roll.
          _preSpeech.push(_onsetBuilder.takeBytes());
        }
        _updateNoiseFloor(rms);
        _preSpeech.push(frame);
        return;
      }

      if (_minSpeechBytes > 0) {
        _onsetBuilder.add(frame);
        if (_onsetBuilder.length < _minSpeechBytes) {
          return;
        }
      }

      _inSpeech = true;
      _silenceBytes = 0;
      _activeSpeechBytes = 0;
      final prefix = _preSpeech.drain();
      if (prefix.isNotEmpty) {
        _speechBuilder.add(prefix);
      }
      if (_onsetBuilder.isNotEmpty) {
        final onset = _onsetBuilder.takeBytes();
        _speechBuilder.add(onset);
        _activeSpeechBytes += onset.length;
      } else {
        _speechBuilder.add(frame);
        _activeSpeechBytes += frame.length;
      }
      if (_maxTurnBytes > 0 && _speechBuilder.length >= _maxTurnBytes) {
        final seg = _takeSegmentIfValid();
        if (seg != null) yield seg;
      }
      return;
    }

    // Already inside speech: use lower hysteresis bound to avoid chopping soft endings.
    final isStillSpeech = rms >= effectiveContinueThreshold;
    _speechBuilder.add(frame);
    if (isStillSpeech) {
      _silenceBytes = 0;
      _activeSpeechBytes += frame.length;
    } else {
      _silenceBytes += frame.length;
      if (adaptiveNoiseFloor && rms < _noiseFloorRms * 1.25) {
        _updateNoiseFloor(rms);
      }
    }

    // Slightly tighten hangover on long utterances (> 4s of active speech) for snappier turn end.
    final fourSecBytes = sampleRate * 2 * 4;
    final targetHangover = (adaptiveNoiseFloor &&
            _activeSpeechBytes >= fourSecBytes &&
            _hangoverBytes > 0)
        ? (_hangoverBytes * 0.80).round()
        : _hangoverBytes;

    if ((_maxTurnBytes > 0 && _speechBuilder.length >= _maxTurnBytes) ||
        _silenceBytes >= targetHangover) {
      final seg = _takeSegmentIfValid();
      if (seg != null) yield seg;
    }
  }

  /// Flushes any in-progress utterance (for example when Push-to-Talk releases).
  Uint8List? flush() {
    if (!_inSpeech && _speechBuilder.isEmpty) return null;
    return _takeSegmentIfValid(ignoreMinDuration: true);
  }

  void reset({bool preserveNoiseFloor = false}) {
    _inSpeech = false;
    _silenceBytes = 0;
    _activeSpeechBytes = 0;
    _speechBuilder.clear();
    _onsetBuilder.clear();
    _preSpeech.clear();
    if (!preserveNoiseFloor) {
      _noiseFloorRms = 45.0;
      _noiseSamples = 0;
      _lastFrameRms = 0.0;
    }
  }

  Uint8List? _takeSegmentIfValid({bool ignoreMinDuration = false}) {
    final activeBytes = _activeSpeechBytes;
    final segment = _speechBuilder.takeBytes();
    _inSpeech = false;
    _silenceBytes = 0;
    _activeSpeechBytes = 0;
    _onsetBuilder.clear();
    _preSpeech.clear();
    if (!ignoreMinDuration &&
        _minUtteranceBytes > 0 &&
        activeBytes < _minUtteranceBytes) {
      return null;
    }
    return segment;
  }
}

/// Wraps raw mono PCM16 bytes into an in-memory RIFF/WAVE container.
class WavEncoder {
  WavEncoder._();

  static Uint8List pcm16MonoToWav(Uint8List pcm, {int sampleRate = 16000}) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    const blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcm.length;

    final wav = Uint8List(44 + dataSize);
    final header = ByteData.sublistView(wav, 0, 44);

    // RIFF header
    wav.setRange(0, 4, const [0x52, 0x49, 0x46, 0x46]); // RIFF
    header.setUint32(4, 36 + dataSize, Endian.little);
    wav.setRange(8, 12, const [0x57, 0x41, 0x56, 0x45]); // WAVE

    // fmt subchunk
    wav.setRange(12, 16, const [0x66, 0x6D, 0x74, 0x20]); // "fmt "
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    wav.setRange(36, 40, const [0x64, 0x61, 0x74, 0x61]); // data
    header.setUint32(40, dataSize, Endian.little);
    wav.setRange(44, 44 + dataSize, pcm);
    return wav;
  }
}
