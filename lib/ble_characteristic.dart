import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:espmui/scanner.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'util.dart';
import 'ble.dart';

abstract class BleCharacteristic<T> {
  final String tag = "[Characteristic]";
  Peripheral _peripheral;
  String serviceUUID = "";
  String characteristicUUID = "";
  CharacteristicWithValue? _characteristic;
  Stream<Uint8List>? _rawStream;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<T>.broadcast();
  T? lastValue;

  Stream<T> get stream => _controller.stream;

  BleCharacteristic(this._peripheral) {
    lastValue = fromUint8List(Uint8List.fromList([]));
    print("$tag construct " + _peripheral.identifier);
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
    lastValue = fromUint8List(await _characteristic!.read().catchError((e) {
      bleError(tag, "read()", e);
      return Uint8List.fromList([]);
    }));
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
    if (!_characteristic!.isWritableWithoutResponse &&
        !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writable");
      return Future.value(null);
    }
    if (withResponse && !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writableWithResponse");
      return Future.value(null);
    }
    //print("$tag write($value)");
    return _characteristic!
        .write(
      toUint8List(value),
      withResponse,
      transactionId: transactionId,
    )
        .catchError((e) {
      bleError(tag, "write($value)", e);
    });
  }

  Future<void> subscribe() async {
    print("$tag subscribe()");
    if (_subscription != null) {
      bleError(tag, "already subscribed");
      return;
    }
    await _init();
    if (_characteristic == null) {
      bleError(tag, "subscribe() characteristic is null");
      return;
    }
    await read();
    print("$tag subscribe() initial value: $lastValue");
    streamSendIfNotClosed(_controller, lastValue);
    if (!_characteristic!.isIndicatable && !_characteristic!.isNotifiable) {
      bleError(tag, "characteristic neither indicatable nor notifiable");
      return;
    }
    _rawStream = _characteristic!.monitor().handleError((e) {
      bleError(tag, "_rawStream", e);
    }).asBroadcastStream();
    if (_rawStream == null) {
      bleError(tag, "subscribe() _rawStream is null");
      return;
    }
    _subscription = _rawStream!.listen(
      (value) async {
        lastValue = await onNotify(fromUint8List(value));
        //print("$tag $lastValue");
        streamSendIfNotClosed(_controller, lastValue);
      },
      onError: (e) => bleError(tag, "subscription", e),
    );
  }

  Future<void> unsubscribe() async {
    if (_subscription == null) return;
    print("$tag unsubscribe");
    await _init();
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _init() async {
    if (_characteristic != null) return; // already init'd
    bool connected = await Scanner().selected?.connected ?? false;
    print("$tag _init()");
    if (!connected) {
      bleError(tag, "_init() peripheral not connected");
      return Future.value(null);
    }
    /*
    _characteristic = await _peripheral.readCharacteristic(serviceUUID, characteristicUUID).catchError((e) {
      bleError(tag, "readCharacteristic()", e);
      return Future.value(null);
    });
    */
    try {
      _characteristic =
          await _peripheral.readCharacteristic(serviceUUID, characteristicUUID);
    } catch (e) {
      bleError(tag, "readCharacteristic()", e);
      _characteristic = null;
      //  print("$tag readCharacteristic() serviceUUID: $serviceUUID, characteristicUUID: $characteristicUUID, $e");
    }
  }

  void deinit() {
    print("$tag deinit()");
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
  final String tag = "[BatteryCharacteristic]";
  final String serviceUUID = "0000180f-0000-1000-8000-00805f9b34fb";
  final String characteristicUUID = "00002a19-0000-1000-8000-00805f9b34fb";

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
  final String tag = "[PowerCharacteristic]";
  final String serviceUUID = "00001818-0000-1000-8000-00805f9b34fb";
  final String characteristicUUID = "00002a63-0000-1000-8000-00805f9b34fb";

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
    /// [flags: 2][power: 2][revolutions: 2][last crank event: 2]
    /// Flags: 0b0000000000100000;  // Crank rev data present
    /// crank event time unit: 1/1024s, rolls over
    int power = value.buffer.asByteData().getUint16(2, Endian.little);
    lastPower = power;
    streamSendIfNotClosed(_powerController, power);

    int newRevolutions = value.buffer.asByteData().getUint16(4, Endian.little);
    int newCrankEvent = value.buffer.asByteData().getUint16(6, Endian.little);
    double dTime = 0.0;
    if (lastCrankEvent > 0) {
      dTime = (newCrankEvent -
              ((newCrankEvent < lastCrankEvent)
                  ? (lastCrankEvent - 65535)
                  : lastCrankEvent)) /
          1.024 /
          60000; // 1 minute
    }

    int cadence = 0;
    int dRev = 0;
    if (revolutions > 0 && dTime > 0) {
      dRev = newRevolutions -
          ((newRevolutions < revolutions)
              ? (revolutions - 65535)
              : revolutions);
      cadence = (dRev / dTime).round();
    }

    int now = DateTime.now().millisecondsSinceEpoch;
    if (lastCrankEventTime < now - 2000) cadence = 0;
    if (lastCrankEvent != newCrankEvent) {
      lastCrankEvent = newCrankEvent;
      lastCrankEventTime = now;
    }

    if (lastCadence != cadence && cadence > 0 ||
        (lastCrankEventTime < now - 2000))
      streamSendIfNotClosed(_cadenceController, cadence);
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
  final String tag = "[ApiCharacteristic]";
  final String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final String characteristicUUID = "da34811a-03c0-4efe-a266-ed014e181b65";

  ApiCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    Uint8List list = Uint8List.fromList([]);
    try {
      list = ascii.encode(value);
    } catch (e) {
      print("$tag error: failed to ascii encode '$value': $e");
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

class ApiStrainCharacteristic extends BleCharacteristic<double> {
  final String tag = "[ApiStrainCharacteristic]";
  final String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final String characteristicUUID = "1d7fd29e-86bc-4640-86b5-00fa3462b480";

  ApiStrainCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  double fromUint8List(Uint8List list) => list.isNotEmpty
      ? list.buffer.asByteData().getFloat32(0, Endian.little)
      : 0.0;

  @override
  Uint8List toUint8List(double value) =>
      Uint8List(4)..buffer.asByteData().setFloat32(0, value, Endian.little);
}
