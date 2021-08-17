import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble_characteristic.dart';
import 'util.dart';
import 'ble.dart';
import 'api.dart';

class Device {
  final String tag = "[Device]";
  Peripheral peripheral;
  int rssi = 0;
  int lastSeen = 0;
  late Api api;
  bool shouldConnect = false;

  final weightServiceEnabled =
      ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);

  /// Connection state
  final stateController =
      StreamController<PeripheralConnectionState>.broadcast();
  Stream<PeripheralConnectionState> get stateStream => stateController.stream;
  StreamSubscription<PeripheralConnectionState>? _stateSubscription;

  /// API done messages
  StreamSubscription<ApiMessage>? _apiSubsciption;

  Map<String, BleCharacteristic> _characteristics = {};

  String? get name => peripheral.name;
  set name(String? name) => peripheral.name = name;
  String get identifier => peripheral.identifier;
  BatteryCharacteristic get battery =>
      characteristic("battery") as BatteryCharacteristic;
  PowerCharacteristic get power =>
      characteristic("power") as PowerCharacteristic;
  ApiCharacteristic get apiCharacteristic =>
      characteristic("api") as ApiCharacteristic;
  WeightScaleCharacteristic get weightScale =>
      characteristic("weightScale") as WeightScaleCharacteristic;

  Future<bool> get connected => peripheral.isConnected().catchError((e) {
        bleError(tag, "could not get connection state", e);
      });

  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0}) {
    print("[Device] construct");
    _characteristics = {
      "battery": BatteryCharacteristic(peripheral),
      "power": PowerCharacteristic(peripheral),
      "api": ApiCharacteristic(peripheral),
      "weightScale": WeightScaleCharacteristic(peripheral),
    };
    api = Api(this);

    /// listen to api message done events
    _apiSubsciption =
        api.messageDoneStream.listen((message) => _onApiDone(message));
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(ApiMessage message) {
    // print("$tag onApiDone: $message");
    if (message.resultCode != ApiResult.success.index) return;

    // switch does not work with non-consant case :(

    // hostName
    if (ApiCommand.hostName.index == message.commandCode) {
      name = message.valueAsString;
      print("$tag onApiDone hostName updated to $name");
    }
    // weightServiceEnabled
    else if (ApiCommand.weightService.index == message.commandCode) {
      weightServiceEnabled.value =
          message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      print(
          "$tag onApiDone weightServiceEnabled updated to ${weightServiceEnabled.value}");
    }
  }

  void dispose() async {
    print("$tag $name dispose");
    disconnect();
    await stateController.close();
    _characteristics.forEach((_, char) {
      char.dispose();
    });
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    _apiSubsciption?.cancel();
  }

  Future<void> _onConnected() async {
    print("$tag _onConnected()");
    // api char can use values longer than 20 bytes
    peripheral.requestMtu(512).catchError((e) {
      bleError(tag, "requestMtu()", e);
      return 0;
    }).then((mtu) async {
      print("$tag got MTU=$mtu");
      await discoverCharacteristics();
      await _subscribeCharacteristics();
      _requestInit();
    });
  }

  Future<void> _onDisconnected() async {
    print("$tag _onDisconnected()");
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    //streamSendIfNotClosed(stateController, newState);
    if (shouldConnect) {
      await Future.delayed(Duration(milliseconds: 1000)).then((_) {
        print("$tag Autoconnect calling connect()");
        connect();
      });
    }
    _resetInit();
  }

  Future<void> connect() async {
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;
    if (_stateSubscription == null) {
      _stateSubscription = peripheral
          .observeConnectionState(
        emitCurrentValue: true,
        completeOnDisconnect: false,
      )
          .listen(
        (newState) async {
          print("$tag state connected=${await connected} newState: $newState");
          if (newState == connectedState)
            await _onConnected();
          else if (newState == disconnectedState) await _onDisconnected();
          streamSendIfNotClosed(stateController, newState);
        },
        onError: (e) => bleError(tag, "connectionStateSubscription", e),
      );
    }
    if (!await connected) {
      if (await BLE().currentState() != BluetoothState.POWERED_ON) {
        print("$tag connect() Adapter is off, not connecting");
      } else {
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
                await Future.delayed(Duration(milliseconds: 3000));
                shouldConnect = savedShouldConnect;
                connect();

                //streamSendIfNotClosed(stateController, connectedState);
              }
            }
          },
        );
      }
    } else {
      print("$tag Not connecting to $name, already connected");
      //state = connectedState;
      //streamSendIfNotClosed(stateController, connectedState);
      await discoverCharacteristics();
      await _subscribeCharacteristics();
      _requestInit();
    }
  }

  /// request initial values, returned values are discarded
  /// because the message.done subscription will handle them
  void _requestInit() async {
    if (!await connected) return;
    weightServiceEnabled.value = ExtendedBool.Waiting;
    print("$tag Requesting init");
    [
      "hostName",
      "secureApi",
      "weightService",
    ].forEach((key) async {
      await api.request<String>(
        key,
        minDelayMs: 10000,
        maxAttempts: 3,
      );
      await Future.delayed(Duration(milliseconds: 150));
    });
  }

  void _resetInit() {
    weightServiceEnabled.value = ExtendedBool.Unknown;
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

  Future<void> _subscribeCharacteristics() async {
    if (!await connected) return;
    _characteristics.forEach((_, char) async {
      await char.subscribe();
    });
  }

  Future<void> _unsubscribeCharacteristics() async {
    _characteristics.forEach((_, char) async {
      await char.unsubscribe();
    });
  }

  void _deinitCharacteristics() {
    _characteristics.forEach((_, char) {
      char.deinit();
    });
  }

  Future<void> disconnect() async {
    print("$tag disconnect() $name");
    if (!await peripheral.isConnected()) {
      bleError(tag, "disconnect(): not connected, but proceeding anyway");
      //return;
    }
    await _unsubscribeCharacteristics();
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
    if (!_characteristics.containsKey(id)) {
      bleError(tag, "characteristic $id not found");
      return null;
    }
    return _characteristics[id];
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
    final now = uts();
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
