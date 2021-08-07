// @dart=2.9
import 'dart:typed_data';

//import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

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
      print("$tag construct error: peripheral is null");
      return;
    }
    print("$tag construct " + _peripheral.identifier);
  }

  T fromUint8List(Uint8List list);

  void subscribe() async {
    print("$tag subscribe()");
    if (_peripheral == null) {
      print("$tag subscribe() error: peripheral is null");
      return;
    }
    _characteristic =
        await _peripheral.readCharacteristic(serviceUUID, characteristicUUID);
    lastValue = fromUint8List(await _characteristic.read());
    print("$tag Initial value: ${lastValue.toString()}");
    _rawStream = _characteristic.monitor().asBroadcastStream();
    _subscription = _rawStream.listen(
      (value) {
        print("$tag " + value.toString());
        lastValue = fromUint8List(value);
        if (_controller.isClosed)
          print("$tag Error: stream is closed");
        else
          _controller.sink.add(lastValue);
      },
      onError: (e) {
        print("$tag subscription error: ${e.toString()}");
      },
    );
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
  final String serviceUUID = "0000180F-0000-1000-8000-00805F9B34FB";
  final String characteristicUUID = "00002A19-0000-1000-8000-00805F9B34FB";

  BatteryCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  final String tag = "[PowerCharacteristic]";
  final String serviceUUID = "00001818-0000-1000-8000-00805F9B34FB";
  final String characteristicUUID = "00002A63-0000-1000-8000-00805F9B34FB";

  PowerCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  Uint8List fromUint8List(Uint8List list) => list;
}

class ApiCharacteristic extends BleCharacteristic<String> {
  final String tag = "[ApiCharacteristic]";
  final String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final String characteristicUUID = "da34811a-03c0-4efe-a266-ed014e181b65";

  ApiCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);
}
