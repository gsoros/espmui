// @dart=2.9
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'util.dart';

abstract class BleCharacteristic<T> {
  final String tag = "[Characteristic]";
  Peripheral _peripheral;
  String serviceUUID;
  String characteristicUUID;
  CharacteristicWithValue _characteristic;
  Stream<Uint8List> _rawStream;
  StreamSubscription<Uint8List> _subscription;
  StreamController<T> _controller = StreamController<T>.broadcast();
  T lastValue;

  Stream get stream => _controller.stream;

  BleCharacteristic(this._peripheral) {
    lastValue = fromUint8List(Uint8List.fromList([]));
    if (_peripheral == null) {
      bleError(tag, "construct: peripheral is null");
      return;
    }
    print("$tag construct " + _peripheral.identifier);
  }

  T fromUint8List(Uint8List list);
  Uint8List toUint8List(T value);

  // read value from characteristic and set lastValue
  Future<T> read() async {
    if (!_characteristic.isReadable) {
      bleError(tag, "read() characteristic not readable");
      return fromUint8List(Uint8List.fromList([]));
    }
    lastValue = fromUint8List(await _characteristic.read().catchError((e) {
      bleError(tag, "read()", e);
      return Uint8List.fromList([]);
    }));
    return lastValue;
  }

  Future<void> write(
    T value, {
    bool withResponse = false,
    String transactionId,
  }) {
    if (!_characteristic.isWritableWithoutResponse &&
        !_characteristic.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writable");
      return null;
    }
    if (withResponse && !_characteristic.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writableWithResponse");
      return null;
    }
    return _characteristic.write(
      toUint8List(value),
      withResponse,
      transactionId: transactionId,
    );
  }

  void subscribe() async {
    print("$tag subscribe()");
    if (_peripheral == null) {
      bleError(tag, "subscribe() peripheral is null");
      return;
    }
    _characteristic = await _peripheral
        .readCharacteristic(serviceUUID, characteristicUUID)
        .catchError((e) {
      bleError(tag, "readCharacteristic()", e);
      return Future.value(null);
    });
    if (_characteristic == null) {
      bleError(tag, "characteristic is null");
      return;
    }
    await read();
    print("$tag subscribe() initial value: $lastValue");
    streamSendIfNotClosed(_controller, lastValue);
    if (!_characteristic.isIndicatable && !_characteristic.isNotifiable) {
      bleError(tag, "characteristic neither indicatable nor notifiable");
      return;
    }
    _rawStream = _characteristic
        .monitor()
        .handleError((e) => bleError(tag, "_rawStream", e))
        .asBroadcastStream();
    _subscription = _rawStream.listen(
      (value) async {
        lastValue = await onNotify(fromUint8List(value));
        print("$tag " + lastValue.toString());
        streamSendIfNotClosed(_controller, lastValue);
      },
      onError: (e) => bleError(tag, "subscription", e),
    );
  }

  Future<T> onNotify(T value) {
    return Future.value(value);
  }

  void unsubscribe() async {
    if (_subscription != null) await _subscription.cancel();
  }

  void dispose() async {
    unsubscribe();
    await _controller.close();
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

  PowerCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  Uint8List fromUint8List(Uint8List list) => list;

  @override
  Uint8List toUint8List(Uint8List value) {
    return value;
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
    }
    return list;
  }

  @override
  Future<String> onNotify(String value) {
    // read full value as the notification is limited to 20 bytes
    return read();
  }
}
