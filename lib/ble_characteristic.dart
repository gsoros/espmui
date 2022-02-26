import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:mutex/mutex.dart';

import 'util.dart';
import 'ble.dart';
import 'ble_constants.dart';

abstract class BleCharacteristic<T> {
  Peripheral _peripheral;
  final serviceUUID = "";
  final characteristicUUID = "";
  //CharacteristicWithValue? _characteristic;
  Characteristic? _characteristic;
  Stream<Uint8List>? _rawStream;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<T>.broadcast();
  T? lastValue;
  final _exclusiveAccess = Mutex();
  late final String tag;

  Stream<T> get stream => _controller.stream;

  BleCharacteristic(this._peripheral) {
    lastValue = fromUint8List(Uint8List.fromList([]));
    print("$runtimeType construct " + _peripheral.identifier);
    tag = runtimeType.toString();
  }

  T fromUint8List(Uint8List list);
  Uint8List toUint8List(T value);

  /// Reads value from characteristic and sets [lastValue]
  Future<T?> read() async {
    await _init();
    if (null == _characteristic) {
      bleError(tag, "read() characteristic is null");
      return fromUint8List(Uint8List.fromList([]));
    }
    if (!_characteristic!.isReadable) {
      bleError(tag, "read() characteristic not readable");
      return fromUint8List(Uint8List.fromList([]));
    }
    await _exclusiveAccess.protect(() async {
      var value = await _characteristic?.read().catchError((e) {
        bleError(tag, "read()", e);
        return Uint8List.fromList([]);
      });
      if (value != null) lastValue = fromUint8List(value);
    });
    return lastValue;
  }

  Future<void> write(
    T value, {
    bool withResponse = false,
    String? transactionId,
  }) async {
    await _init();
    if (_characteristic == null) {
      bleError(tag, "write() characteristic is null");
      return Future.value(null);
    }
    if (!_characteristic!.isWritableWithoutResponse && !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writable");
      return Future.value(null);
    }
    if (withResponse && !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writableWithResponse");
      return Future.value(null);
    }
    //print("$runtimeType write($value)");
    await _exclusiveAccess.protect(() async {
      if (null == _characteristic) return;
      _characteristic!
          .write(
        toUint8List(value),
        withResponse,
        transactionId: transactionId,
      )
          .catchError((e) {
        bleError(tag, "write($value)", e);
      });
    });
  }

  Future<void> subscribe() async {
    print("$runtimeType subscribe()");
    if (_subscription != null) {
      bleError(tag, "already subscribed");
      return;
    }
    await _init();
    if (_characteristic == null) {
      bleError(tag, "subscribe() characteristic is null");
      return;
    }
    if (!(_characteristic?.isIndicatable ?? false) && !(_characteristic?.isNotifiable ?? false)) {
      bleError(tag, "characteristic neither indicatable nor notifiable");
      return;
    }
    _rawStream = _characteristic?.monitor().handleError((e) {
      bleError(tag, "_rawStream", e);
    }); //.asBroadcastStream();
    if (_rawStream == null) {
      bleError(tag, "subscribe() _rawStream is null");
      return;
    }
    await _exclusiveAccess.protect(() async {
      _subscription = _rawStream?.listen(
        (value) async {
          lastValue = await onNotify(fromUint8List(value));
          //print("$runtimeType $lastValue");
          streamSendIfNotClosed(_controller, lastValue);
        },
        onError: (e) => bleError(tag, "subscription", e),
      );
    });
    await read();
    print("$runtimeType subscribe() initial value: $lastValue");
    streamSendIfNotClosed(_controller, lastValue);
  }

  Future<void> unsubscribe() async {
    await _init();
    if (_subscription == null) return;
    print("$runtimeType unsubscribe");
    streamSendIfNotClosed(_controller, fromUint8List(Uint8List.fromList([])));
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _init() async {
    if (_characteristic != null) return; // already init'd
    bool connected = await _peripheral.isConnected();
    if (!connected) {
      bleError(tag, "_init() peripheral not connected");
      return Future.value(null);
    }
    try {
      //_characteristic = await _peripheral.readCharacteristic(serviceUUID, characteristicUUID);
      var chars = await _peripheral.characteristics(serviceUUID);
      _characteristic = chars.firstWhere((char) => char.uuid == characteristicUUID);
    } catch (e) {
      bleError(tag, "_init() readCharacteristic()", e);
      _characteristic = null;
      //  print("$runtimeType readCharacteristic() serviceUUID: $serviceUUID, characteristicUUID: $characteristicUUID, $e");
    }
  }

  Future<void> deinit() async {
    print("$runtimeType deinit()");
    _characteristic = null;
  }

  Future<T?> onNotify(T value) {
    return Future.value(value);
  }

  Future<void> dispose() async {
    await unsubscribe();
    await _controller.close();
    deinit();
  }
}

class BatteryCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.BATTERY_SERVICE_UUID;
  final characteristicUUID = BleConstants.BATTERY_LEVEL_CHAR_UUID;

  BatteryCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;

  @override
  Uint8List toUint8List(int value) {
    if (value < 0)
      bleError(tag, "toUint8List() negative value");
    else if (255 < value) bleError(tag, "toUint8List() $value clipped");
    return Uint8List.fromList([value]);
  }
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  final serviceUUID = BleConstants.CYCLING_POWER_SERVICE_UUID;
  final characteristicUUID = BleConstants.CYCLING_POWER_MEASUREMENT_CHAR_UUID;

  int revolutions = 0;
  int lastCrankEvent = 0;
  int lastCrankEventTime = 0;
  int lastPower = 0;
  int lastCadence = 0;

  final _powerController = StreamController<int>.broadcast();
  Stream<int> get powerStream => _powerController.stream;
  final _cadenceController = StreamController<int>.broadcast();
  Stream<int> get cadenceStream => _cadenceController.stream;

  PowerCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  Uint8List fromUint8List(Uint8List list) => list;

  @override
  Uint8List toUint8List(Uint8List value) => value;

  @override
  Future<Uint8List?> onNotify(Uint8List value) {
    /// Format: little-endian
    /// Bytes: [flags: 2][power: 2][revolutions: 2][last crank event: 2]
    /// Flags: 0b0000000000100000;  // Crank rev data present
    /// crank event time unit: 1/1024s, rolls over
    int power = value.buffer.asByteData().getUint16(2, Endian.little);
    lastPower = power;
    streamSendIfNotClosed(_powerController, power);

    int newRevolutions = value.buffer.asByteData().getUint16(4, Endian.little);
    int newCrankEvent = value.buffer.asByteData().getUint16(6, Endian.little);
    double dTime = 0.0;
    if (lastCrankEvent > 0) {
      dTime = (newCrankEvent - ((newCrankEvent < lastCrankEvent) ? (lastCrankEvent - 65535) : lastCrankEvent)) / 1.024 / 60000; // 1 minute
    }

    int cadence = 0;
    int dRev = 0;
    if (revolutions > 0 && dTime > 0) {
      dRev = newRevolutions - ((newRevolutions < revolutions) ? (revolutions - 65535) : revolutions);
      cadence = (dRev / dTime).round();
    }

    int now = DateTime.now().millisecondsSinceEpoch;
    if (lastCrankEventTime < now - 2000) cadence = 0;
    if (lastCrankEvent != newCrankEvent) {
      lastCrankEvent = newCrankEvent;
      lastCrankEventTime = now;
    }

    if (lastCadence != cadence && cadence > 0 || (lastCrankEventTime < now - 2000)) streamSendIfNotClosed(_cadenceController, cadence);
    lastCadence = cadence;
    revolutions = newRevolutions;

    return super.onNotify(value);
  }

  @override
  Future<void> dispose() {
    _powerController.close();
    _cadenceController.close();
    return Future.value(null);
  }
}

class ApiCharacteristic extends BleCharacteristic<String> {
  final serviceUUID = BleConstants.ESPM_API_SERVICE_UUID;
  final characteristicUUID = BleConstants.ESPM_API_CHAR_UUID;

  ApiCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    Uint8List list = Uint8List.fromList([]);
    try {
      list = ascii.encode(value);
    } catch (e) {
      print("$runtimeType error: failed to ascii encode '$value': $e");
      List<int> valid = [];
      for (int code in value.codeUnits) if (code < 256) valid.add(code);
      list = Uint8List.fromList(valid);
    }
    return list;
  }

  @override
  Future<String?> onNotify(String value) {
    if (value.length < 20) return Future.value(value);
    // read full value as the notification is limited to 20 bytes
    return read();
  }
}

class WeightScaleCharacteristic extends BleCharacteristic<double> {
  final serviceUUID = BleConstants.WEIGHT_SCALE_SERVICE_UUID;
  final characteristicUUID = BleConstants.WEIGHT_MEASUREMENT_CHAR_UUID;

  WeightScaleCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  double fromUint8List(Uint8List list) {
    /// Format: little-endian
    /// Bytes: [flags: 1][weight: 2]
    return list.isNotEmpty ? list.buffer.asByteData().getInt16(1, Endian.little) / 200 : 0.0;
  }

  @override
  Uint8List toUint8List(double value) => Uint8List(3)..buffer.asByteData().setInt16(1, (value * 200).round(), Endian.little);
}

class HallCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.ESPM_API_SERVICE_UUID;
  final characteristicUUID = BleConstants.ESPM_HALL_CHAR_UUID;

  HallCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) {
    /// Format: little-endian
    return list.isNotEmpty ? list.buffer.asByteData().getInt16(0, Endian.little) : 0;
  }

  @override
  Uint8List toUint8List(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, (value).round(), Endian.little);
}

class HeartRateCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.HEART_RATE_SERVICE_UUID;
  final characteristicUUID = BleConstants.HEART_RATE_MEASUREMENT_CHAR_UUID;

  HeartRateCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) {
    /// Format: little-endian
    /// Bytes: [Flags: 1][Heart rate: 1 or 2, depending on bit 0 of the Flags field]
    if (list.isEmpty) return 0;
    int byteCount = list.last & 0 == 0 ? 1 : 2;
    var byteData = list.buffer.asByteData();
    int heartRate = 0;
    if (byteData.lengthInBytes < byteCount + 1) {
      dev.log('$runtimeType fromUint8List() not enough bytes in $list');
      return heartRate;
    }
    if (byteCount == 1)
      heartRate = byteData.getUint8(1);
    else if (byteCount == 2) heartRate = byteData.getUint16(1, Endian.little);
    dev.log('$runtimeType got list: $list byteCount: $byteCount hr: $heartRate');
    return heartRate;
  }

  @override
  Uint8List toUint8List(int value) => Uint8List(2); // we are not writing
}

class CharacteristicList {
  Map<String, CharacteristicListItem> _items = {};

  BleCharacteristic? get(String name) {
    return _items.containsKey(name) ? _items[name]!.characteristic : null;
  }

  void set(String name, CharacteristicListItem item) => _items[name] = item;

  void addAll(Map<String, CharacteristicListItem> items) => _items.addAll(items);

  void dispose() {
    print("$runtimeType dispose");
    _items.forEach((_, item) => item.dispose());
    _items.clear();
  }

  void forEachCharacteristic(void Function(String, BleCharacteristic?) f) =>
      _items.forEach((String name, CharacteristicListItem item) => f(name, item.characteristic));

  Future<void> forEachListItem(Future<void> Function(String, CharacteristicListItem) f) async {
    for (MapEntry e in _items.entries) await f(e.key, e.value);
  }
}

class CharacteristicListItem {
  bool subscribeOnConnect;
  BleCharacteristic? characteristic;

  CharacteristicListItem(
    this.characteristic, {
    this.subscribeOnConnect = true,
  });

  void dispose() {
    characteristic?.dispose();
  }
}
