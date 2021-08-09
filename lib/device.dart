// @dart=2.9

import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'bleCharacteristic.dart';
import 'util.dart';

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
    PeripheralConnectionState connectedState =
        PeripheralConnectionState.connected;
    connectionStateSubscription = peripheral
        .observeConnectionState(
      emitCurrentValue: false,
      completeOnDisconnect: true,
    )
        //.asBroadcastStream()
        .listen(
      (state) async {
        connectionState = state;
        print("$tag _connectionStateSubscription $name $state");
        streamSendIfNotClosed(connectionStateStreamController, state);
        if (state == connectedState) {
          // api char can use values longer than 20 bytes
          int mtu = await peripheral.requestMtu(512).catchError((e) {
            bleError(tag, "requestMtu()", e);
          });
          print("$tag got MTU=$mtu");
          subscribeCharacteristics();
        }
      },
      onError: (e) => bleError(tag, "connectionStateSubscription", e),
    );
    if (!await peripheral.isConnected()) {
      print("$tag Connecting to ${peripheral.name}");
      await peripheral
          .connect(
            refreshGatt: true,
          )
          .catchError(
            (e) => bleError(tag, "peripheral.connect()", e),
          );
    } else {
      print("$tag Not connecting to $name, already connected");
      connectionState = connectedState;
      streamSendIfNotClosed(
        connectionStateStreamController,
        connectedState,
      );
      subscribeCharacteristics();
    }
    return Future.value(null);
  }

  void subscribeCharacteristics() async {
    await peripheral
        .discoverAllServicesAndCharacteristics()
        .catchError((e) => bleError(tag, "discoverBlaBla()", e));
    characteristics.forEach((k, char) {
      char.subscribe();
    });
  }

  void unsubscribeCharacteristics() {
    characteristics.forEach((k, char) {
      char.unsubscribe();
    });
  }

  void disconnect() async {
    print("$tag disconnect() $name");
    if (!await peripheral.isConnected()) {
      bleError(tag, "disconnect(): not connected, but proceeding anyway");
      //return;
    }
    unsubscribeCharacteristics();
    await peripheral
        .disconnectOrCancelConnection()
        .catchError((e) => bleError(tag, "peripheral.discBlaBla()", e));
    if (connectionStateSubscription != null)
      await connectionStateSubscription
          .cancel()
          .catchError((e) => bleError(tag, "connStateSub.cancel()", e));
  }

  BleCharacteristic characteristic(String id) {
    if (!characteristics.containsKey(id)) {
      bleError(tag, "characteristic $id not found");
      return null;
    }
    return characteristics[id];
  }
}
