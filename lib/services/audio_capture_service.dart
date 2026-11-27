import 'package:flutter/services.dart';

class AudioEffectsReport {
  const AudioEffectsReport({
    this.aecEnabled = false,
    this.nsEnabled = false,
    this.agcEnabled = false,
    this.sampleRate = 16000,
    this.routedDeviceName,
    this.routedDeviceType,
  });

  final bool aecEnabled;
  final bool nsEnabled;
  final bool agcEnabled;
  final int sampleRate;
  final String? routedDeviceName;
  final int? routedDeviceType;

  factory AudioEffectsReport.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const AudioEffectsReport();
    return AudioEffectsReport(
      aecEnabled: map['aecEnabled'] == true,
      nsEnabled: map['nsEnabled'] == true,
      agcEnabled: map['agcEnabled'] == true,
      sampleRate: (map['sampleRate'] as num?)?.toInt() ?? 16000,
      routedDeviceName: (map['routedDeviceName'] as String?)?.trim(),
      routedDeviceType: (map['routedDeviceType'] as num?)?.toInt(),
    );
  }
}

class AudioInputDevice {
  const AudioInputDevice({
    required this.id,
    required this.type,
    required this.category,
    required this.name,
    required this.typeLabel,
    this.address = '',
    this.isBluetooth = false,
    this.isBuiltIn = false,
    this.isWiredOrUsb = false,
    this.isSelected = false,
  });

  final int id;
  final int type;
  final String category;
  final String name;
  final String typeLabel;
  final String address;
  final bool isBluetooth;
  final bool isBuiltIn;
  final bool isWiredOrUsb;
  final bool isSelected;

  bool get isAuto => id == -1 && type == -1;

  factory AudioInputDevice.auto({bool selected = true}) => AudioInputDevice(
        id: -1,
        type: -1,
        category: 'auto',
        name: 'Automático (Padrão do Android)',
        typeLabel: 'Roteamento padrão',
        isSelected: selected,
      );

  factory AudioInputDevice.fromMap(Map<Object?, Object?> map) =>
      AudioInputDevice(
        id: (map['id'] as num?)?.toInt() ?? -1,
        type: (map['type'] as num?)?.toInt() ?? -1,
        category: (map['category'] as String? ?? 'other').trim(),
        name: (map['name'] as String? ?? 'Microfone').trim(),
        typeLabel: (map['typeLabel'] as String? ?? '').trim(),
        address: (map['address'] as String? ?? '').trim(),
        isBluetooth: map['isBluetooth'] == true,
        isBuiltIn: map['isBuiltIn'] == true,
        isWiredOrUsb: map['isWiredOrUsb'] == true,
        isSelected: map['isSelected'] == true,
      );
}

class AudioInputSelection {
  const AudioInputSelection({
    this.id = -1,
    this.type = -1,
    this.name = 'Automático (Padrão do Android)',
    this.isAuto = true,
  });

  final int id;
  final int type;
  final String name;
  final bool isAuto;

  factory AudioInputSelection.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const AudioInputSelection();
    final id = (map['id'] as num?)?.toInt() ?? -1;
    final type = (map['type'] as num?)?.toInt() ?? -1;
    final name = (map['name'] as String? ?? '').trim();
    return AudioInputSelection(
      id: id,
      type: type,
      name: name.isEmpty ? 'Automático (Padrão do Android)' : name,
      isAuto: map['isAuto'] == true || (id == -1 && type == -1),
    );
  }
}

abstract interface class AudioInputRouterService {
  Future<List<AudioInputDevice>> listInputDevices();
  Future<AudioInputSelection> getPreferredInputDevice();
  Future<bool> setPreferredInputDevice(AudioInputDevice device);
  Future<bool> hasBluetoothPermission();
  Future<bool> requestBluetoothPermission();
}

class MethodChannelAudioInputRouterService implements AudioInputRouterService {
  MethodChannelAudioInputRouterService({MethodChannel? methodChannel})
      : _methodChannel = methodChannel ??
            const MethodChannel('com.viniciusnpaula.ultron_mobile/audio_capture');

  final MethodChannel _methodChannel;

  @override
  Future<List<AudioInputDevice>> listInputDevices() async {
    final list =
        await _methodChannel.invokeListMethod<Object?>('listInputDevices');
    if (list == null || list.isEmpty) {
      return [AudioInputDevice.auto()];
    }
    return list
        .whereType<Map<Object?, Object?>>()
        .map(AudioInputDevice.fromMap)
        .toList();
  }

  @override
  Future<AudioInputSelection> getPreferredInputDevice() async {
    final raw = await _methodChannel.invokeMapMethod<Object?, Object?>(
      'getPreferredInputDevice',
    );
    return AudioInputSelection.fromMap(raw);
  }

  @override
  Future<bool> setPreferredInputDevice(AudioInputDevice device) async {
    final ok = await _methodChannel.invokeMethod<bool>(
      'setPreferredInputDevice',
      <String, Object?>{
        'id': device.id,
        'type': device.type,
        'name': device.name,
      },
    );
    return ok ?? false;
  }

  @override
  Future<bool> hasBluetoothPermission() async {
    final ok =
        await _methodChannel.invokeMethod<bool>('hasBluetoothPermission');
    return ok ?? true;
  }

  @override
  Future<bool> requestBluetoothPermission() async {
    final ok =
        await _methodChannel.invokeMethod<bool>('requestBluetoothPermission');
    return ok ?? true;
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
