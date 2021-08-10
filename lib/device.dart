import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble_characteristic.dart';
import 'util.dart';
import 'ble.dart';

class Device {
  final String tag = "[Device]";
  Peripheral peripheral;
  int rssi = 0;
  double lastSeen = 0;

  /// Connection state
  var state = PeripheralConnectionState.disconnected;
  final stateController =
      StreamController<PeripheralConnectionState>.broadcast();
  Stream<PeripheralConnectionState> get stateStream => stateController.stream;
  StreamSubscription<PeripheralConnectionState>? stateSubscription;

  Map<String, BleCharacteristic> characteristics = {};

  String? get name => peripheral.name;
  set name(String? name) => peripheral.name = name;
  String get identifier => peripheral.identifier;

  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0}) {
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
    await stateController.close();
    characteristics.forEach((_, char) {
      char.dispose();
    });
  }

  Future<void> connect() async {
    final connectedState = PeripheralConnectionState.connected;
    stateSubscription = peripheral
        .observeConnectionState(
      emitCurrentValue: false,
      completeOnDisconnect: true,
    )
        //.asBroadcastStream()
        .listen(
      (newState) async {
        state = newState;
        print("$tag _connectionStateSubscription $name $newState");
        streamSendIfNotClosed(stateController, newState);
        if (newState == connectedState) {
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
      print("$tag Connecting to $name");
      await peripheral
          .connect(
            refreshGatt: true,
          )
          .catchError(
            (e) => bleError(tag, "peripheral.connect()", e),
          );
    } else {
      print("$tag Not connecting to $name, already connected");
      state = connectedState;
      streamSendIfNotClosed(
        stateController,
        connectedState,
      );
      subscribeCharacteristics();
    }
  }

  void subscribeCharacteristics() async {
    await peripheral
        .discoverAllServicesAndCharacteristics()
        .catchError((e) => bleError(tag, "discoverBlaBla()", e));
    characteristics.forEach((_, char) {
      char.subscribe();
    });
  }

  void unsubscribeCharacteristics() {
    characteristics.forEach((_, char) {
      char.unsubscribe();
    });
  }

  Future<void> disconnect() async {
    print("$tag disconnect() $name");
    if (!await peripheral.isConnected()) {
      bleError(tag, "disconnect(): not connected, but proceeding anyway");
      //return;
    }
    unsubscribeCharacteristics();
    await peripheral
        .disconnectOrCancelConnection()
        .catchError((e) => bleError(tag, "peripheral.discBlaBla()", e));
    if (stateSubscription != null)
      await stateSubscription
          ?.cancel()
          .catchError((e) => bleError(tag, "connStateSub.cancel()", e));
  }

  BleCharacteristic? characteristic(String id) {
    if (!characteristics.containsKey(id)) {
      bleError(tag, "characteristic $id not found");
      return null;
    }
    return characteristics[id];
  }
}

class DeviceList {
  final String tag = "[DeviceList]";
  Map<String, Device> _devices = {};

  DeviceList() {
    print("$tag construct");
  }

  bool containsIdentifier(String identifier) {
    return _devices.containsKey(identifier);
  }

  /// Adds or updates a device from a [ScanResult]
  ///
  /// If a device with the same identifier already exists, updates name, rssi
  /// and lastSeen, otherwise adds new device.
  /// Returns the new or updated device or null on error.
  Device? addOrUpdate(ScanResult scanResult) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000;
    final subject = scanResult.peripheral.name.toString() +
        " rssi=" +
        scanResult.rssi.toString();
    _devices.update(
      scanResult.peripheral.identifier,
      (existing) {
        print("$tag updating $subject");
        existing.name = scanResult.peripheral.name;
        existing.rssi = scanResult.rssi;
        existing.lastSeen = now;
        return existing;
      },
      ifAbsent: () {
        print("$tag adding $subject");
        return Device(
          scanResult.peripheral,
          rssi: scanResult.rssi,
          lastSeen: now,
        );
      },
    );
    return _devices[scanResult.peripheral.identifier];
  }

  Device? byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _devices[identifier];
    return null;
  }

  void dispose() {
    print("$tag dispose");
    _devices.forEach((_, device) => device.dispose());
    _devices.clear();
  }

  int get length => _devices.length;
  bool get isEmpty => _devices.isEmpty;
  void forEach(void Function(String, Device) f) => _devices.forEach(f);
}
