// @dart=2.9
import 'dart:typed_data';

//import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

abstract class Char {
  final String tag = "[Char]";
  Peripheral peripheral;
  String serviceUUID;
  String charUUID;
  CharacteristicWithValue characteristic;
  Stream<Uint8List> stream;
  StreamSubscription<Uint8List> subscription;
  StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast();
  Uint8List currentValue = Uint8List.fromList([]);

  Char(this.peripheral) {
    if (peripheral == null) {
      print("$tag construct error: peripheral is null");
      return;
    }
    print("$tag construct " + peripheral.identifier);
  }

  void subscribe() async {
    print("$tag subscribe()");
    if (peripheral == null) {
      print("$tag subscribe() error: peripheral is null");
      return;
    }
    characteristic = await peripheral.readCharacteristic(serviceUUID, charUUID);
    currentValue = await characteristic.read();
    stream = characteristic.monitor().asBroadcastStream();
    subscription = stream.listen(
      (value) {
        print("$tag " + value.toString());
        currentValue = value;
        if (controller.isClosed)
          print("$tag Error: stream is closed");
        else
          controller.sink.add(value);
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

class BatteryChar extends Char {
  final String tag = "[BatteryChar]";
  String serviceUUID = "0000180F-0000-1000-8000-00805F9B34FB";
  String charUUID = "00002A19-0000-1000-8000-00805F9B34FB";

  BatteryChar(Peripheral peripheral) : super(peripheral);
}

class PowerChar extends Char {
  final String tag = "[PowerChar]";
  String serviceUUID = "00001818-0000-1000-8000-00805F9B34FB";
  String charUUID = "00002A63-0000-1000-8000-00805F9B34FB";

  PowerChar(Peripheral peripheral) : super(peripheral);
}
