// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

class Device {
  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0});
  Peripheral peripheral;
  int rssi;
  double lastSeen;
  PeripheralConnectionState connectionState;
  StreamSubscription<PeripheralConnectionState> _connectionStateSubscription;

  void dispose() {
    print("Device dispose");
    disconnect();
  }

  void connect() async {
    _connectionStateSubscription = peripheral
        .observeConnectionState(
      emitCurrentValue: true,
      completeOnDisconnect: false,
    )
        .listen((state) {
      print("Peripheral ${peripheral.identifier}: $connectionState");
      connectionState = state;
    });
    if (!await peripheral.isConnected()) {
      print("Connecting to ${peripheral.name}");
      try {
        await peripheral.connect();
      } catch (e) {
        print("Connect error: ${e.toString()}");
      }
    } else
      print("Not connecting to ${peripheral.name}, already connected");
    await peripheral.discoverAllServicesAndCharacteristics();
    try {
      CharacteristicWithValue battChar = await peripheral.readCharacteristic(
          "0000180F-0000-1000-8000-00805F9B34FB",
          "00002A19-0000-1000-8000-00805F9B34FB");
      print(battChar.value.toString());
    } catch (e) {
      print("Error ${e.toString()}");
    }
  }

  void disconnect() async {
    await peripheral.disconnectOrCancelConnection();
    await _connectionStateSubscription.cancel();
    connectionState = null;
  }

  Widget screen() {
    return Text(peripheral.name);
  }
}
