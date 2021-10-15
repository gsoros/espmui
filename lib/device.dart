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

  final weightServiceEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  final hallEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  final deviceSettings = PropertyValueNotifier<DeviceSettings>(DeviceSettings());
  final wifiSettings = PropertyValueNotifier<DeviceWifiSettings>(DeviceWifiSettings());

  /// Connection state stream controller
  final _stateController = StreamController<PeripheralConnectionState>.broadcast();

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
  BatteryCharacteristic? get battery => characteristic("battery") as BatteryCharacteristic?;
  PowerCharacteristic? get power => characteristic("power") as PowerCharacteristic?;
  ApiCharacteristic? get apiCharacteristic => characteristic("api") as ApiCharacteristic?;
  WeightScaleCharacteristic? get weightScale => characteristic("weightScale") as WeightScaleCharacteristic?;
  HallCharacteristic? get hall => characteristic("hall") as HallCharacteristic?;

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
      "hall": CharacteristicListItem(
        HallCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
    });
    api = Api(this);

    /// listen to api message done events
    _apiSubsciption = api.messageDoneStream.listen((message) => _onApiDone(message));
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(ApiMessage message) async {
    if (message.resultCode != ApiResult.success.index) return;
    //print("$tag onApiDone parsing successful message: $message");
    // switch does not work with non-consant case :(

    // hostName
    if (ApiCommand.hostName.index == message.commandCode) {
      name = message.valueAsString;
    }
    // weightServiceEnabled
    else if (ApiCommand.weightService.index == message.commandCode) {
      weightServiceEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await weightScale?.subscribe();
      else
        await weightScale?.unsubscribe();
    }
    // hallEnabled
    else if (ApiCommand.hallChar.index == message.commandCode) {
      hallEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await hall?.subscribe();
      else
        await hall?.unsubscribe();
    }
    // wifi
    else if (ApiCommand.wifi.index == message.commandCode) {
      wifiSettings.value.enabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApEnabled
    else if (ApiCommand.wifiApEnabled.index == message.commandCode) {
      wifiSettings.value.apEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApSSID
    else if (ApiCommand.wifiApSSID.index == message.commandCode) {
      wifiSettings.value.apSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiApPassword
    else if (ApiCommand.wifiApPassword.index == message.commandCode) {
      wifiSettings.value.apPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaEnabled
    else if (ApiCommand.wifiStaEnabled.index == message.commandCode) {
      wifiSettings.value.staEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiStaSSID
    else if (ApiCommand.wifiStaSSID.index == message.commandCode) {
      wifiSettings.value.staSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaPassword
    else if (ApiCommand.wifiStaPassword.index == message.commandCode) {
      wifiSettings.value.staPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // crankLength
    else if (ApiCommand.crankLength.index == message.commandCode) {
      deviceSettings.value.cranklength = message.valueAsDouble;
      deviceSettings.notifyListeners();
    }
    // reverseStrain
    else if (ApiCommand.reverseStrain.index == message.commandCode) {
      deviceSettings.value.reverseStrain = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      deviceSettings.notifyListeners();
    }
    // doublePower
    else if (ApiCommand.doublePower.index == message.commandCode) {
      deviceSettings.value.doublePower = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      deviceSettings.notifyListeners();
    }
    // sleepDelay
    else if (ApiCommand.sleepDelay.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.sleepDelay = (message.valueAsInt! / 1000 / 60).round();
        deviceSettings.notifyListeners();
      }
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
        emitCurrentValue: false,
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
      "weightService",
      "hallChar",
      "hostName",
      "wifi",
      "wifiApEnabled",
      "wifiApSSID",
      "wifiApPassword",
      "wifiStaEnabled",
      "wifiStaSSID",
      "wifiStaPassword",
      "secureApi",
      "crankLength",
      "reverseStrain",
      "doublePower",
      "sleepDelay",
    ].forEach((key) async {
      await api.request<String>(
        key,
        minDelayMs: 10000,
        maxAttempts: 3,
      );
      await Future.delayed(Duration(milliseconds: 250));
    });
  }

  void _resetInit() {
    weightServiceEnabled.value = ExtendedBool.Unknown;
    wifiSettings.value = DeviceWifiSettings();
    wifiSettings.notifyListeners();
    deviceSettings.value = DeviceSettings();
    deviceSettings.notifyListeners();
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
    final subject = scanResult.peripheral.name.toString() + " rssi=" + scanResult.rssi.toString();
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

  void addAll(Map<String, CharacteristicListItem> items) => _items.addAll(items);

  void dispose() {
    print("$tag dispose");
    _items.forEach((_, item) => item.dispose());
    _items.clear();
  }

  void forEachCharacteristic(void Function(String, BleCharacteristic?) f) =>
      _items.forEach((String name, CharacteristicListItem item) => f(name, item.characteristic));

  void forEachListItem(void Function(String, CharacteristicListItem) f) => _items.forEach(f);
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

class DeviceSettings {
  double? cranklength;
  var reverseStrain = ExtendedBool.Unknown;
  var doublePower = ExtendedBool.Unknown;
  int? sleepDelay;
  int motionDetectionMethod = 0;

  final validMotionDetectionMethods = {
    0: "Hall effect sensor",
    1: "MPU",
    2: "Strain gauge",
  };

  @override
  bool operator ==(other) {
    return (other is DeviceSettings) &&
        other.cranklength == cranklength &&
        other.reverseStrain == reverseStrain &&
        other.doublePower == doublePower &&
        other.sleepDelay == sleepDelay &&
        other.motionDetectionMethod == motionDetectionMethod;
  }

  @override
  int get hashCode => cranklength.hashCode ^ reverseStrain.hashCode ^ doublePower.hashCode ^ sleepDelay.hashCode ^ motionDetectionMethod.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "crankLength: $cranklength, "
        "reverseStrain: $reverseStrain, "
        "doublePower: $doublePower, "
        "sleepDelay: $sleepDelay, "
        "motionDetectionMethod: $motionDetectionMethod)";
  }
}

class DeviceWifiSettings {
  var enabled = ExtendedBool.Unknown;
  var apEnabled = ExtendedBool.Unknown;
  String? apSSID;
  String? apPassword;
  var staEnabled = ExtendedBool.Unknown;
  String? staSSID;
  String? staPassword;

  @override
  bool operator ==(other) {
    return (other is DeviceWifiSettings) &&
        other.enabled == enabled &&
        other.apEnabled == apEnabled &&
        other.apSSID == apSSID &&
        other.apPassword == apPassword &&
        other.staEnabled == staEnabled &&
        other.staSSID == staSSID &&
        other.staPassword == staPassword;
  }

  @override
  int get hashCode =>
      enabled.hashCode ^ apEnabled.hashCode ^ apSSID.hashCode ^ apPassword.hashCode ^ staEnabled.hashCode ^ staSSID.hashCode ^ staPassword.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "enabled: $enabled, "
        "apEnabled: $apEnabled, "
        "apSSID: $apSSID, "
        "apPassword: $apPassword, "
        "staEnabled: $staEnabled, "
        "staSSID: $staSSID, "
        "staPassword: $staPassword)";
  }
}
