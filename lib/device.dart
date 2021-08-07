// @dart=2.9

import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'bleCharacteristic.dart';

class Device {
  final String tag = "[Device]";
  Peripheral peripheral;
  int rssi = 0;
  double lastSeen = 0;

  // connectionState
  PeripheralConnectionState connectionState =
      PeripheralConnectionState.disconnected;
  final StreamController<PeripheralConnectionState>
      connectionStateStreamController =
      StreamController<PeripheralConnectionState>.broadcast();
  StreamSubscription<PeripheralConnectionState> connectionStateSubscription;

  BatteryCharacteristic battery;
  PowerCharacteristic power;
  ApiCharacteristic api;

  String get name => peripheral.name;
  String get identifier => peripheral.identifier;

  Device(this.peripheral, {this.rssi, this.lastSeen}) {
    print("[Device] construct");
    battery = BatteryCharacteristic(peripheral);
    power = PowerCharacteristic(peripheral);
    api = ApiCharacteristic(peripheral);
  }

  void dispose() async {
    print("$tag $name dispose");
    disconnect();
    await connectionStateStreamController.close();
    battery.dispose();
    power.dispose();
    api.dispose();
  }

  void connect() async {
    connectionStateSubscription = peripheral
        .observeConnectionState(
      emitCurrentValue: false,
      completeOnDisconnect: true,
    )
        //.asBroadcastStream()
        .listen(
      (state) {
        connectionState = state;
        print("$tag _connectionStateSubscription $name $state");
        if (connectionStateStreamController.isClosed)
          print("$tag _connectionStateSubscription stream is closed");
        else
          connectionStateStreamController.sink.add(state);
      },
    );
    if (!await peripheral.isConnected()) {
      print("$tag Connecting to ${peripheral.name}");
      try {
        await peripheral.connect().catchError(
          (e) {
            print("$tag peripheral.connect() catchE: ${e.toString()}");
          },
        );
      } catch (e) {
        print("$tag peripheral.connect() error: ${e.toString()}");
      }
    } else
      print("$tag Not connecting to $name, already connected");
    try {
      await peripheral.discoverAllServicesAndCharacteristics();
      battery.subscribe();
      power.subscribe();
      api.subscribe();
    } catch (e) {
      print("$tag Error: ${e.toString()}");
    }
  }

  void disconnect() async {
    print("$tag disconnect() $name");
    try {
      await peripheral.disconnectOrCancelConnection();
      battery.unsubscribe();
      power.unsubscribe();
      if (connectionStateSubscription != null)
        await connectionStateSubscription.cancel().catchError((e) {
          print("$tag disconnect() catchE: ${e.toString()}");
        });
    } catch (e) {
      print("$tag disconnect() Error: ${e.toString()}");
    }
  }
}
