import 'dart:math' as math;
import 'dart:typed_data';

/// Computes energy metrics over little-endian 16-bit PCM frames.
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

/// Segments continuous PCM16 mono frames into speech utterances using RMS VAD.
class VadSegmenter {
  VadSegmenter({
    this.sampleRate = 16000,
    this.speechThreshold = 50.0,
    this.preSpeechDuration = const Duration(milliseconds: 400),
    this.silenceHangover = const Duration(milliseconds: 700),
    this.maxTurnDuration = const Duration(seconds: 15),
  })  : _preSpeech = PreSpeechRingBuffer(
          capacityBytes: _durationToEvenBytes(sampleRate, preSpeechDuration),
        ),
        _hangoverBytes = _durationToEvenBytes(sampleRate, silenceHangover),
        _maxTurnBytes = _durationToEvenBytes(sampleRate, maxTurnDuration);

  final int sampleRate;
  final double speechThreshold;
  final Duration preSpeechDuration;
  final Duration silenceHangover;
  final Duration maxTurnDuration;

  final PreSpeechRingBuffer _preSpeech;
  final int _hangoverBytes;
  final int _maxTurnBytes;
  final BytesBuilder _speechBuilder = BytesBuilder(copy: false);

  bool _inSpeech = false;
  int _silenceBytes = 0;

  bool get isInSpeech => _inSpeech;

  static int _durationToEvenBytes(int sampleRate, Duration duration) {
    final raw = (sampleRate * 2 * duration.inMicroseconds) ~/ 1000000;
    return raw & ~1;
  }

  /// Processes one PCM16 mono frame and yields any completed speech segment.
  Stream<Uint8List> processFrame(Uint8List frame) async* {
    if (frame.isEmpty) return;
    final rms = PcmEnergy.rmsInt16(frame);
    final isSpeech = rms >= speechThreshold;

    if (!_inSpeech) {
      if (!isSpeech) {
        _preSpeech.push(frame);
        return;
      }
      _inSpeech = true;
      _silenceBytes = 0;
      final prefix = _preSpeech.drain();
      if (prefix.isNotEmpty) {
        _speechBuilder.add(prefix);
      }
      _speechBuilder.add(frame);
      if (_maxTurnBytes > 0 && _speechBuilder.length >= _maxTurnBytes) {
        yield _takeSegment();
      }
      return;
    }

    _speechBuilder.add(frame);
    if (isSpeech) {
      _silenceBytes = 0;
    } else {
      _silenceBytes += frame.length;
    }

    if ((_maxTurnBytes > 0 && _speechBuilder.length >= _maxTurnBytes) ||
        _silenceBytes >= _hangoverBytes) {
      yield _takeSegment();
    }
  }

  /// Flushes any in-progress utterance (for example when Push-to-Talk releases).
  Uint8List? flush() {
    if (!_inSpeech && _speechBuilder.isEmpty) return null;
    return _takeSegment();
  }

  void reset() {
    _inSpeech = false;
    _silenceBytes = 0;
    _speechBuilder.clear();
    _preSpeech.clear();
  }

  Uint8List _takeSegment() {
    final segment = _speechBuilder.takeBytes();
    _inSpeech = false;
    _silenceBytes = 0;
    _preSpeech.clear();
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
