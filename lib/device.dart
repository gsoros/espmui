import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'bleCharacteristic.dart';
import 'util.dart';
import 'ble.dart';

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
  StreamSubscription<PeripheralConnectionState>? connectionStateSubscription;

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
    if (connectionStateSubscription != null)
      await connectionStateSubscription
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

  /// If a device with the same identifier already exists, updates name, rssi
  /// and lastSeen, otherwise adds new device.
  /// Returns the new or updated device or null on error.
  Device? addOrUpdate(ScanResult scanResult) {
    double now = DateTime.now().millisecondsSinceEpoch / 1000;
    String subject = scanResult.peripheral.name.toString() +
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
    return byIdentifier(scanResult.peripheral.identifier);
  }

  Device? byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _devices[identifier];
    return null;
  }

  void dispose() {
    print("$tag dispose");
    Device? device = _devices.remove(_devices.keys.first);
    while (null != device) {
      device.dispose();
      device = _devices.remove(_devices.keys.first);
    }
  }

  int get length => _devices.length;
  bool get isEmpty => _devices.isEmpty;
  void forEach(void Function(String, Device) f) => _devices.forEach(f);
}
