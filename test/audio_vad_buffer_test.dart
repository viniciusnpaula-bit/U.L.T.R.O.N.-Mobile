import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultron_mobile/services/audio_vad_buffer.dart';

Uint8List _pcmFrame(int samples, int amplitude) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final value = i.isEven ? amplitude : -amplitude;
    data.setInt16(i * 2, value, Endian.little);
  }
  return bytes;
}

Uint8List _sineFrame(int samples, double amplitude, {int sampleRate = 16000}) {
  final bytes = Uint8List(samples * 2);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < samples; i++) {
    final sample = (amplitude * math.sin(2 * math.pi * 440 * i / sampleRate))
        .round()
        .clamp(-32768, 32767);
    data.setInt16(i * 2, sample, Endian.little);
  }
  return bytes;
}

void main() {
  test('PcmEnergy.rmsInt16 returns 0 for empty/silent and exact RMS for square/sine waves', () {
    expect(PcmEnergy.rmsInt16(Uint8List(0)), 0.0);
    expect(PcmEnergy.rmsInt16(Uint8List(640)), 0.0);

    final square = _pcmFrame(320, 1000);
    expect(PcmEnergy.rmsInt16(square), closeTo(1000.0, 0.001));

    final sine = _sineFrame(1600, 1000.0);
    expect(PcmEnergy.rmsInt16(sine), closeTo(1000.0 / math.sqrt(2), 1.0));
  });

  test('PreSpeechRingBuffer caps capacity and preserves FIFO order on drain', () {
    final ring = PreSpeechRingBuffer(capacityBytes: 8);
    ring.push(Uint8List.fromList([1, 2, 3, 4]));
    ring.push(Uint8List.fromList([5, 6, 7, 8]));
    ring.push(Uint8List.fromList([9, 10]));

    expect(ring.length, 8);
    expect(ring.drain(), Uint8List.fromList([3, 4, 5, 6, 7, 8, 9, 10]));
    expect(ring.length, 0);
    expect(ring.drain(), isEmpty);

    ring.push(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
    expect(ring.drain(), Uint8List.fromList([4, 5, 6, 7, 8, 9, 10, 11]));
  });

  test('VadSegmenter stays silent on noise and emits pre-speech + speech through hangover', () async {
    final vad = VadSegmenter(
      sampleRate: 16000,
      speechThreshold: 50.0,
      preSpeechDuration: const Duration(milliseconds: 40),
      silenceHangover: const Duration(milliseconds: 40),
      maxTurnDuration: const Duration(milliseconds: 200),
    );

    final silence = Uint8List(640); // 20ms @ 16kHz
    final pre1 = _pcmFrame(320, 10);
    final pre2 = _pcmFrame(320, 20);
    final speech = _pcmFrame(320, 500);

    final emitted = <Uint8List>[];
    for (var i = 0; i < 10; i++) {
      await for (final seg in vad.processFrame(silence)) {
        emitted.add(seg);
      }
    }
    expect(emitted, isEmpty);

    await for (final seg in vad.processFrame(pre1)) {
      emitted.add(seg);
    }
    await for (final seg in vad.processFrame(pre2)) {
      emitted.add(seg);
    }
    await for (final seg in vad.processFrame(speech)) {
      emitted.add(seg);
    }
    expect(emitted, isEmpty);

    await for (final seg in vad.processFrame(silence)) {
      emitted.add(seg);
    }
    expect(emitted, isEmpty);

    await for (final seg in vad.processFrame(silence)) {
      emitted.add(seg);
    }
    expect(emitted, hasLength(1));
    // 2 pre-speech frames (40ms = 1280B) + 1 speech (640B) + 2 hangover (1280B)
    expect(emitted.single.length, 3200);
    expect(emitted.single.sublist(0, 640), pre1);
    expect(emitted.single.sublist(640, 1280), pre2);
    expect(emitted.single.sublist(1280, 1920), speech);
  });

  test('VadSegmenter splits segments at maxTurnDuration', () async {
    final vad = VadSegmenter(
      sampleRate: 16000,
      speechThreshold: 50.0,
      preSpeechDuration: const Duration(milliseconds: 20),
      silenceHangover: const Duration(milliseconds: 100),
      maxTurnDuration: const Duration(milliseconds: 60),
    );
    final speech = _pcmFrame(320, 400); // 20ms = 640B
    final emitted = <Uint8List>[];
    for (var i = 0; i < 3; i++) {
      await for (final seg in vad.processFrame(speech)) {
        emitted.add(seg);
      }
    }
    expect(emitted, hasLength(1));
    expect(emitted.single.length, 1920);
  });

  test('WavEncoder.pcm16MonoToWav builds valid 44-byte RIFF/WAVE header and payload', () {
    final pcm = _pcmFrame(4, 1234);
    final wav = WavEncoder.pcm16MonoToWav(pcm, sampleRate: 16000);
    expect(wav.length, 44 + pcm.length);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');

    final header = ByteData.sublistView(wav);
    expect(header.getUint32(4, Endian.little), 36 + pcm.length);
    expect(header.getUint32(16, Endian.little), 16);
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(32, Endian.little), 2);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), pcm.length);
    expect(wav.sublist(44), pcm);
  });
}
