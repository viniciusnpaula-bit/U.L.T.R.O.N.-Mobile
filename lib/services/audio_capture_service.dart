import 'package:flutter/services.dart';

class AudioEffectsReport {
  const AudioEffectsReport({
    this.aecEnabled = false,
    this.nsEnabled = false,
    this.agcEnabled = false,
    this.sampleRate = 16000,
  });

  final bool aecEnabled;
  final bool nsEnabled;
  final bool agcEnabled;
  final int sampleRate;

  factory AudioEffectsReport.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const AudioEffectsReport();
    return AudioEffectsReport(
      aecEnabled: map['aecEnabled'] == true,
      nsEnabled: map['nsEnabled'] == true,
      agcEnabled: map['agcEnabled'] == true,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 16000,
    );
  }
}

abstract interface class AudioCaptureSource {
  Stream<Uint8List> get frames;
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<AudioEffectsReport> start({int sampleRate = 16000});
  Future<void> stop();
}

/// Platform-channel implementation backed by Android `AudioRecord` with
/// hardware AEC, NoiseSuppressor, and AutomaticGainControl when supported.
class MethodChannelAudioCaptureSource implements AudioCaptureSource {
  MethodChannelAudioCaptureSource({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/audio_capture'),
        _eventChannel = eventChannel ??
            const EventChannel(
              'com.viniciusnpaula.ultron_mobile/audio_capture_frames',
            );

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<Uint8List>? _frames;

  @override
  Stream<Uint8List> get frames => _frames ??= _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Uint8List)
      .cast<Uint8List>();

  @override
  Future<bool> hasPermission() async {
    final granted = await _methodChannel.invokeMethod<bool>('hasPermission');
    return granted ?? false;
  }

  @override
  Future<bool> requestPermission() async {
    final granted = await _methodChannel.invokeMethod<bool>('requestPermission');
    return granted ?? false;
  }

  @override
  Future<AudioEffectsReport> start({int sampleRate = 16000}) async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'start',
      <String, Object?>{'sampleRate': sampleRate},
    );
    return AudioEffectsReport.fromMap(raw);
  }

  @override
  Future<void> stop() => _methodChannel.invokeMethod<void>('stop');
}
