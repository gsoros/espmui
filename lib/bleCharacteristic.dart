// @dart=2.9
import 'dart:typed_data';

//import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

abstract class BleCharacteristic<T> {
  final String tag = "[Characteristic]";
  Peripheral peripheral;
  String serviceUUID;
  String characteristicUUID;
  CharacteristicWithValue characteristic;
  Stream<Uint8List> rawStream;
  StreamSubscription<Uint8List> subscription;
  StreamController<T> controller = StreamController<T>.broadcast();
  T currentValue;

  BleCharacteristic(this.peripheral) {
    currentValue = fromUint8List(Uint8List.fromList([]));
    if (peripheral == null) {
      print("$tag construct error: peripheral is null");
      return;
    }
    print("$tag construct " + peripheral.identifier);
  }

  T fromUint8List(Uint8List list);

  void subscribe() async {
    print("$tag subscribe()");
    if (peripheral == null) {
      print("$tag subscribe() error: peripheral is null");
      return;
    }
    characteristic =
        await peripheral.readCharacteristic(serviceUUID, characteristicUUID);
    currentValue = fromUint8List(await characteristic.read());
    print("$tag Initial value: ${currentValue.toString()}");
    rawStream = characteristic.monitor().asBroadcastStream();
    subscription = rawStream.listen(
      (value) {
        print("$tag " + value.toString());
        currentValue = fromUint8List(value);
        if (controller.isClosed)
          print("$tag Error: stream is closed");
        else
          controller.sink.add(currentValue);
      },
      onError: (e) {
        print("$tag subscription error: ${e.toString()}");
      },
    );
  }

  void unsubscribe() async {
    if (subscription != null) await subscription.cancel();
  }

  void dispose() async {
    unsubscribe();
    await controller.close();
  }
}

class BatteryCharacteristic extends BleCharacteristic<int> {
  final String tag = "[BatteryCharacteristic]";
  String serviceUUID = "0000180F-0000-1000-8000-00805F9B34FB";
  String characteristicUUID = "00002A19-0000-1000-8000-00805F9B34FB";

  BatteryCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  final String tag = "[PowerCharacteristic]";
  String serviceUUID = "00001818-0000-1000-8000-00805F9B34FB";
  String characteristicUUID = "00002A63-0000-1000-8000-00805F9B34FB";

  PowerCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  Uint8List fromUint8List(Uint8List list) => list;
}

class ApiCharacteristic extends BleCharacteristic<String> {
  final String tag = "[ApiCharacteristic]";
  String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  String characteristicUUID = "da34811a-03c0-4efe-a266-ed014e181b65";

  ApiCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  String fromUint8List(Uint8List list) {
    return String.fromCharCodes(list);
  }
}
