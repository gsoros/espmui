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

  /// Connection state stream controller
  final _stateController =
      StreamController<PeripheralConnectionState>.broadcast();

  /// Connection state stream
  Stream<PeripheralConnectionState> get stateStream => _stateController.stream;

  /// Connection state subscription
  StreamSubscription<PeripheralConnectionState>? _stateSubscription;

  /// API done messages
  StreamSubscription<ApiMessage>? _apiSubsciption;

  //Map<String, BleCharacteristic> _characteristics = {};
  var _characteristics = CharacteristicList();

  String? get name => peripheral.name;
  set name(String? name) => peripheral.name = name;
  String get identifier => peripheral.identifier;
  BatteryCharacteristic? get battery =>
      characteristic("battery") as BatteryCharacteristic?;
  PowerCharacteristic? get power =>
      characteristic("power") as PowerCharacteristic?;
  ApiCharacteristic? get apiCharacteristic =>
      characteristic("api") as ApiCharacteristic?;
  WeightScaleCharacteristic? get weightScale =>
      characteristic("weightScale") as WeightScaleCharacteristic?;

  Future<bool> get connected => peripheral.isConnected().catchError((e) {
        bleError(tag, "could not get connection state", e);
      });

  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0}) {
    print("[Device] construct");
    _characteristics.addAll({
      "battery": CharacteristicListItem(BatteryCharacteristic(peripheral)),
      "power": CharacteristicListItem(PowerCharacteristic(peripheral)),
      "api": CharacteristicListItem(ApiCharacteristic(peripheral)),
      "weightScale": CharacteristicListItem(
        WeightScaleCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
    });
    api = Api(this);

    /// listen to api message done events
    _apiSubsciption =
        api.messageDoneStream.listen((message) => _onApiDone(message));
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(ApiMessage message) async {
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
      if (message.valueAsBool ?? false)
        await weightScale?.subscribe();
      else
        await weightScale?.unsubscribe();
    }
  }

  void dispose() async {
    print("$tag $name dispose");
    disconnect();
    await _stateController.close();
    _characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
      await char?.dispose();
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
          streamSendIfNotClosed(_stateController, newState);
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
      "wifi",
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
    _characteristics.forEachListItem((_, item) async {
      if (item.subscribeOnConnect) await item.characteristic?.subscribe();
    });
  }

  Future<void> _unsubscribeCharacteristics() async {
    _characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
    });
  }

  void _deinitCharacteristics() {
    _characteristics.forEachCharacteristic((_, char) {
      char?.deinit();
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

  BleCharacteristic? characteristic(String name) {
    return _characteristics.get(name);
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

class CharacteristicList {
  final String tag = "[CharacteristicList]";
  Map<String, CharacteristicListItem> _items = {};

  BleCharacteristic? get(String name) {
    return _items.containsKey(name) ? _items[name]!.characteristic : null;
  }

  void set(String name, CharacteristicListItem item) => _items[name] = item;

  void addAll(Map<String, CharacteristicListItem> items) =>
      _items.addAll(items);

  void dispose() {
    print("$tag dispose");
    _items.forEach((_, item) => item.dispose());
    _items.clear();
  }

  void forEachCharacteristic(void Function(String, BleCharacteristic?) f) =>
      _items.forEach((String name, CharacteristicListItem item) =>
          f(name, item.characteristic));

  void forEachListItem(void Function(String, CharacteristicListItem) f) =>
      _items.forEach(f);
}

class CharacteristicListItem {
  bool subscribeOnConnect;
  BleCharacteristic? characteristic;

  CharacteristicListItem(
    this.characteristic, {
    this.subscribeOnConnect = true,
  });

  void dispose() {
    characteristic?.dispose();
  }
}
