import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble_characteristic.dart';
import 'util.dart';
import 'ble.dart';
import 'api.dart';

class Device {
  final String tag = "[Device]";
  Peripheral peripheral;
  int rssi = 0;
  double lastSeen = 0;
  late Api api;
  bool shouldConnect = false;

  /// Connection state
  final stateController =
      StreamController<PeripheralConnectionState>.broadcast();
  Stream<PeripheralConnectionState> get stateStream => stateController.stream;
  StreamSubscription<PeripheralConnectionState>? stateSubscription;

  Map<String, BleCharacteristic> characteristics = {};

  String? get name => peripheral.name;
  set name(String? name) => peripheral.name = name;
  String get identifier => peripheral.identifier;
  BatteryCharacteristic get battery =>
      characteristic("battery") as BatteryCharacteristic;
  PowerCharacteristic get power =>
      characteristic("power") as PowerCharacteristic;
  ApiCharacteristic get apiCharacteristic =>
      characteristic("api") as ApiCharacteristic;
  ApiStrainCharacteristic get apiStrain =>
      characteristic("apiStrain") as ApiStrainCharacteristic;

  Future<bool> get connected => peripheral.isConnected().catchError((e) {
        bleError(tag, "could not get connection state", e);
      });

  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0}) {
    print("[Device] construct");
    characteristics = {
      "battery": BatteryCharacteristic(peripheral),
      "power": PowerCharacteristic(peripheral),
      "api": ApiCharacteristic(peripheral),
      "apiStrain": ApiStrainCharacteristic(peripheral),
    };
    api = Api(this);
  }

  void dispose() async {
    print("$tag $name dispose");
    disconnect();
    await stateController.close();
    characteristics.forEach((_, char) {
      char.dispose();
    });
    if (stateSubscription != null)
      await stateSubscription
          ?.cancel()
          .catchError((e) => bleError(tag, "connStateSub.cancel()", e));
    stateSubscription = null;
  }

  Future<void> connect() async {
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;
    if (stateSubscription == null) {
      stateSubscription = peripheral
          .observeConnectionState(
        emitCurrentValue: true,
        completeOnDisconnect: false,
      )
          //.asBroadcastStream()
          .listen(
        (newState) async {
          if (newState == connectedState) {
            //print("$tag _connectionStateSubscription delaying connected state");
            //await Future.delayed(Duration(milliseconds: 500));
          }
          print("$tag state connected=${await connected} newState: $newState");
          if (newState == connectedState) {
            print("$tag newState is connected");
            // api char can use values longer than 20 bytes
            peripheral.requestMtu(512).catchError((e) {
              bleError(tag, "requestMtu()", e);
              return 0;
            });
            //print("$tag got MTU=$mtu");
            await discoverCharacteristics().then((_) {
              subscribeCharacteristics();
            }, onError: (e) {
              bleError(tag, "discoverCharacteristics", e);
            });
            //streamSendIfNotClosed(stateController, newState);
          } else if (newState == disconnectedState) {
            print("$tag newState is disconnected");
            unsubscribeCharacteristics();
            //deinitCharacteristics();
            //streamSendIfNotClosed(stateController, newState);
            if (shouldConnect)
              await Future.delayed(Duration(milliseconds: 1000)).then((_) {
                print("$tag Autoconnect calling connect()");
                connect();
              });
          }
          streamSendIfNotClosed(stateController, newState);
        },
        onError: (e) => bleError(tag, "connectionStateSubscription", e),
      );
    }
    if (!await connected) {
      print("$tag Connecting to $name");
      await peripheral
          .connect(
        isAutoConnect: true,
        refreshGatt: true,
      )
          .catchError(
        (e) async {
          bleError(tag, "peripheral.connect()", e);
          if (e is BleError) {
            BleError be = e;
            if (be.errorCode.value == BleErrorCode.deviceAlreadyConnected) {
              bool savedShouldConnect = shouldConnect;
              shouldConnect = false;
              await disconnect();
              await Future.delayed(Duration(milliseconds: 3000)).then((_) {
                shouldConnect = savedShouldConnect;
                connect();
              });
              //streamSendIfNotClosed(stateController, connectedState);
            }
          }
        },
      );
    } else {
      print("$tag Not connecting to $name, already connected");
      //state = connectedState;
      //streamSendIfNotClosed(stateController, connectedState);
      await discoverCharacteristics();
      await subscribeCharacteristics();
    }
  }

  Future<void> discoverCharacteristics() async {
    print("$tag discoverCharacteristics() start conn=${await connected}");
    if (!await connected) return;
    print("$tag discoverCharacteristics()");
    await peripheral.discoverAllServicesAndCharacteristics().catchError((e) {
      bleError(tag, "discoverCharacteristics()", e);
    });
    print("$tag discoverCharacteristics() end conn=${await connected}");
  }

  Future<void> subscribeCharacteristics() async {
    if (!await connected) return;
    characteristics.forEach((_, char) async {
      await char.subscribe();
    });
  }

  Future<void> unsubscribeCharacteristics() async {
    characteristics.forEach((_, char) async {
      await char.unsubscribe();
    });
  }

  void deinitCharacteristics() {
    characteristics.forEach((_, char) {
      char.deinit();
    });
  }

  Future<void> disconnect() async {
    print("$tag disconnect() $name");
    if (!await peripheral.isConnected()) {
      bleError(tag, "disconnect(): not connected, but proceeding anyway");
      //return;
    }
    await unsubscribeCharacteristics();
    await peripheral.disconnectOrCancelConnection().catchError((e) {
      bleError(tag, "peripheral.discBlaBla()", e);
      if (e is BleError) {
        BleError be = e;
        // 205
        if (be.errorCode.value == BleErrorCode.deviceNotConnected) {
          //streamSendIfNotClosed(
          //stateController, PeripheralConnectionState.disconnected);
        }
      }
    });
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
