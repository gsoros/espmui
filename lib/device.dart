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

  Map<String, BleCharacteristic> characteristics = {};

  String get name => peripheral.name;
  String get identifier => peripheral.identifier;

  Device(this.peripheral, {this.rssi, this.lastSeen}) {
    print("[Device] construct");
    characteristics = {
      "battery": BatteryCharacteristic(peripheral),
      "power": PowerCharacteristic(peripheral),
      "api": ApiCharacteristic(peripheral),
    };
  }

  void dispose() async {
    print("$tag $name dispose");
    disconnect();
    await connectionStateStreamController.close();
    characteristics.forEach((k, char) {
      char.dispose();
    });
  }

  Future<void> connect() async {
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
        if (state == PeripheralConnectionState.connected)
          subscribeCharacteristics();
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
    } else {
      print("$tag Not connecting to $name, already connected");
      if (connectionStateStreamController.isClosed)
        print("$tag _connectionStateSubscription stream is closed");
      else {
        connectionStateStreamController.sink
            .add(PeripheralConnectionState.connected);
        subscribeCharacteristics();
      }
    }
    return Future.value(null);
  }

  void subscribeCharacteristics() async {
    try {
      await peripheral.discoverAllServicesAndCharacteristics();
      characteristics.forEach((k, char) {
        char.subscribe();
      });
    } catch (e) {
      print("$tag subscribeCharacteristics error: ${e.toString()}");
    }
  }

  void unsubscribeCharacteristics() {
    characteristics.forEach((k, char) {
      char.unsubscribe();
    });
  }

  void disconnect() async {
    print("$tag disconnect() $name");
    try {
      unsubscribeCharacteristics();
      await peripheral.disconnectOrCancelConnection();
      if (connectionStateSubscription != null)
        await connectionStateSubscription.cancel().catchError((e) {
          print("$tag disconnect() catchE: ${e.toString()}");
        });
    } catch (e) {
      print("$tag disconnect() Error: ${e.toString()}");
    }
  }

  BleCharacteristic characteristic(String id) {
    if (!characteristics.containsKey(id)) {
      print("$tag characteristic $id not found");
      return null;
    }
    return characteristics[id];
  }
}
