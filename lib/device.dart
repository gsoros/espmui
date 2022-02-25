import 'dart:async';
import 'dart:developer' as dev;

import 'package:espmui/ble_constants.dart';
import 'package:espmui/preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble.dart';
import 'ble_characteristic.dart';
import 'espm_api.dart';
import 'util.dart';

/*
Device: Battery
  ├─ PowerMeter: Power(, Cadence)
  │    └─ ESPM: Api, WeightScale, Hall
  ├─ HeartrateMonitor: Heartrate
  ├─ TODO CadenceSensor: Cadence
  └─ TODO SpeedSensor: Speed
*/

class Device {
  final String tag = '[Device]';
  Peripheral peripheral;
  int rssi = 0;
  int lastSeen = 0;
  bool shouldConnect = false;
  final autoConnect = ValueNotifier<bool>(false);
  var _characteristics = CharacteristicList();

  String? get name => peripheral.name;
  set name(String? name) => peripheral.name = name;
  String get identifier => peripheral.identifier;
  BatteryCharacteristic? get battery => characteristic("battery") as BatteryCharacteristic?;

  Future<bool> get connected => peripheral.isConnected().catchError((e) {
        bleError(tag, "could not get connection state", e);
      });

  bool _subscribed = false;
  bool _discovered = false;

  // Connection state stream controller
  final _stateController = StreamController<PeripheralConnectionState>.broadcast();

  // Connection state stream
  Stream<PeripheralConnectionState> get stateStream => _stateController.stream;

  // Connection state subscription
  StreamSubscription<PeripheralConnectionState>? _stateSubscription;

  Device(this.peripheral, {this.rssi = 0, this.lastSeen = 0}) {
    _characteristics.addAll({
      'battery': CharacteristicListItem(BatteryCharacteristic(peripheral)),
    });
    init();
  }

  void init() async {
    autoConnect.value = await isSaved();
  }

  Future<void> dispose() async {
    print("$tag $name dispose");
    await disconnect();
    await _stateController.close();
    _characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
      await char?.dispose();
    });
    await _stateSubscription?.cancel();
    _stateSubscription = null;
  }

  Future<bool> ready() async {
    if (!await discovered()) return false;
    if (!await subscribed()) return false;
    return true;
  }

  Future<bool> discovered() async {
    if (!await connected) return false;
    var stopwatch = Stopwatch();
    while (!_discovered) {
      await Future.delayed(Duration(milliseconds: 500));
      if (3000 < stopwatch.elapsedMilliseconds) return false;
    }
    return true;
  }

  Future<bool> subscribed() async {
    if (!await connected) return false;
    var stopwatch = Stopwatch();
    while (!_subscribed) {
      await Future.delayed(Duration(milliseconds: 500));
      if (3000 < stopwatch.elapsedMilliseconds) return false;
    }
    return true;
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
    });
  }

  Future<void> _onDisconnected() async {
    print("$tag _onDisconnected()");
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    //streamSendIfNotClosed(stateController, newState);
    if (shouldConnect) {
      await Future.delayed(Duration(milliseconds: 1000)).then((_) async {
        print("$tag Autoconnect calling connect()");
        await connect();
      });
    }
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
      //_requestInit();
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
    _discovered = true;
  }

  Future<void> _subscribeCharacteristics() async {
    dev.log('$tag _subscribeCharacteristics start');
    if (!await discovered()) return;
    await _characteristics.forEachListItem((_, item) async {
      if (item.subscribeOnConnect) {
        dev.log('$tag _subscribeCharacteristics ${item.characteristic?.characteristicUUID} start');
        await item.characteristic?.subscribe();
        dev.log('$tag _subscribeCharacteristics ${item.characteristic?.characteristicUUID} end');
      }
    });
    _subscribed = true;
    dev.log('$tag _subscribeCharacteristics end');
  }

  Future<void> _unsubscribeCharacteristics() async {
    _characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
      _subscribed = false;
    });
  }

  void _deinitCharacteristics() {
    _characteristics.forEachCharacteristic((_, char) {
      char?.deinit();
    });
    _discovered = false;
    _subscribed = false;
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
      _discovered = false;
    });
  }

  BleCharacteristic? characteristic(String name) {
    return _characteristics.get(name);
  }

  void setAutoConnect(bool value) async {
    autoConnect.value = value;
    updatePreferences();
  }

  void updatePreferences() async {
    List<String> devices = (await Preferences().getDevices()).value;
    dev.log('$tag updatePreferences savedDevices before: $devices');
    String item = (name?.replaceAll(RegExp(r';'), '') ?? '') + ';' + peripheral.identifier;
    dev.log('$tag updatePreferences item: $item');
    if (autoConnect.value)
      devices.add(item);
    else
      devices.removeWhere((item) => item.endsWith(peripheral.identifier));
    Preferences().setDevices(devices);
    dev.log('$tag updatePreferences savedDevices after: $devices');
  }

  Future<bool> isSaved() async {
    var devices = (await Preferences().getDevices()).value;
    return devices.any((item) => item.endsWith(peripheral.identifier));
  }
}

class PowerMeter extends Device {
  final String tag = '[PowerMeter]';
  PowerCharacteristic? get power => characteristic("power") as PowerCharacteristic?;

  PowerMeter(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'power': CharacteristicListItem(PowerCharacteristic(peripheral)),
    });
  }
}

class ESPM extends PowerMeter {
  final String tag = '[ESPM]';
  late EspmApi api;
  final weightServiceEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  final hallEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  final deviceSettings = AlwaysNotifier<ESPMSettings>(ESPMSettings());
  final wifiSettings = AlwaysNotifier<ESPMWifiSettings>(ESPMWifiSettings());

  ApiCharacteristic? get apiCharacteristic => characteristic("api") as ApiCharacteristic?;
  WeightScaleCharacteristic? get weightScale => characteristic("weightScale") as WeightScaleCharacteristic?;
  HallCharacteristic? get hall => characteristic("hall") as HallCharacteristic?;
  StreamSubscription<EspmApiMessage>? _apiSubsciption;

  ESPM(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'api': CharacteristicListItem(ApiCharacteristic(peripheral)),
      'weightScale': CharacteristicListItem(
        WeightScaleCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
      'hall': CharacteristicListItem(
        HallCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
    });
    api = EspmApi(this);
    // listen to api message done events
    _apiSubsciption = api.messageDoneStream.listen((message) => _onApiDone(message));
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(EspmApiMessage message) async {
    //print("$tag onApiDone parsing message: $message");
    if (message.resultCode != EspmApiResult.success.index) return;
    //print("$tag onApiDone parsing successful message: $message");
    // switch does not work with non-constant case :(

    // hostName
    if (EspmApiCommand.hostName.index == message.commandCode) {
      name = message.valueAsString;
    }
    // weightServiceEnabled
    else if (EspmApiCommand.weightService.index == message.commandCode) {
      weightServiceEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await weightScale?.subscribe();
      else
        await weightScale?.unsubscribe();
    }
    // hallEnabled
    else if (EspmApiCommand.hallChar.index == message.commandCode) {
      hallEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await hall?.subscribe();
      else
        await hall?.unsubscribe();
    }
    // wifi
    else if (EspmApiCommand.wifi.index == message.commandCode) {
      wifiSettings.value.enabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApEnabled
    else if (EspmApiCommand.wifiApEnabled.index == message.commandCode) {
      wifiSettings.value.apEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApSSID
    else if (EspmApiCommand.wifiApSSID.index == message.commandCode) {
      wifiSettings.value.apSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiApPassword
    else if (EspmApiCommand.wifiApPassword.index == message.commandCode) {
      wifiSettings.value.apPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaEnabled
    else if (EspmApiCommand.wifiStaEnabled.index == message.commandCode) {
      wifiSettings.value.staEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiStaSSID
    else if (EspmApiCommand.wifiStaSSID.index == message.commandCode) {
      wifiSettings.value.staSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaPassword
    else if (EspmApiCommand.wifiStaPassword.index == message.commandCode) {
      wifiSettings.value.staPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // crankLength
    else if (EspmApiCommand.crankLength.index == message.commandCode) {
      deviceSettings.value.cranklength = message.valueAsDouble;
      deviceSettings.notifyListeners();
    }
    // reverseStrain
    else if (EspmApiCommand.reverseStrain.index == message.commandCode) {
      deviceSettings.value.reverseStrain = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      deviceSettings.notifyListeners();
    }
    // doublePower
    else if (EspmApiCommand.doublePower.index == message.commandCode) {
      deviceSettings.value.doublePower = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      deviceSettings.notifyListeners();
    }
    // sleepDelay
    else if (EspmApiCommand.sleepDelay.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.sleepDelay = (message.valueAsInt! / 1000 / 60).round();
        deviceSettings.notifyListeners();
      }
    }
    // motionDetectionMethod
    else if (EspmApiCommand.motionDetectionMethod.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.motionDetectionMethod = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    }
    // strainThreshold
    else if (EspmApiCommand.strainThreshold.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.strainThreshold = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    } // strainThresLow
    else if (EspmApiCommand.strainThresLow.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.strainThresLow = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    }
    // negativeTorqueMethod
    else if (EspmApiCommand.negativeTorqueMethod.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.negativeTorqueMethod = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    }
    // autoTare
    else if (EspmApiCommand.autoTare.index == message.commandCode) {
      deviceSettings.value.autoTare = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      deviceSettings.notifyListeners();
    }
    // autoTareDelayMs
    else if (EspmApiCommand.autoTareDelayMs.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.autoTareDelayMs = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    }
    // autoTareRangG
    else if (EspmApiCommand.autoTareRangeG.index == message.commandCode) {
      if (message.valueAsInt != null) {
        deviceSettings.value.autoTareRangeG = message.valueAsInt!;
        deviceSettings.notifyListeners();
      }
    }
    // config
    else if (EspmApiCommand.config.index == message.commandCode) {
      dev.log('$tag _onApiDone got config');
      if (message.valueAsString != null) {
        message.valueAsString!.split(';').forEach((chunk) {
          var pair = chunk.split('=');
          if (2 != pair.length) return;
          var message = EspmApiMessage(pair.first);
          message.commandCode = int.tryParse(pair.first);
          if (null == message.commandCode) return;
          message.resultCode = EspmApiResult.success.index;
          message.value = pair.last;
          dev.log('$tag _onApiDone config calling _onApiDone(${message.commandCode})');
          _onApiDone(message);
        });
      }
    }
  }

  Future<void> dispose() async {
    print("$tag $name dispose");
    _apiSubsciption?.cancel();
    super.dispose();
  }

  Future<void> _onConnected() async {
    print("$tag _onConnected()");
    await super._onConnected();
    _requestInit();
  }

  Future<void> _onDisconnected() async {
    print("$tag _onDisconnected()");
    await super._onDisconnected();
    _resetInit();
  }

  /// request initial values, returned values are discarded
  /// because the message.done subscription will handle them
  void _requestInit() async {
    print("$tag Requesting init start");
    if (!await ready()) return;
    print("$tag Requesting init ready to go");
    weightServiceEnabled.value = ExtendedBool.Waiting;
    [
      /*
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
      "motionDetectionMethod",
      "strainThreshold",
      "strainThresLow",
      "negativeTorqueMethod",
      "autoTare",
      "autoTareDelayMs",
      "autoTareRangeG",
      */
      "config",
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
    wifiSettings.value = ESPMWifiSettings();
    deviceSettings.value = ESPMSettings();
  }
}

class HeartRateMonitor extends Device {
  final String tag = '[HeartRateMonitor]';
  HeartRateCharacteristic? get heartRate => characteristic("heartRate") as HeartRateCharacteristic?;

  HeartRateMonitor(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'heartRate': CharacteristicListItem(HeartRateCharacteristic(peripheral)),
    });
  }
}

Device createDevice(ScanResult scanResult) {
  if (null == scanResult.advertisementData.serviceUuids) {
    dev.log('[createDevice] no serviceUuids in scanResult.advertisementData');
    return Device(scanResult.peripheral);
  }
  dev.log('[createDevice] uuids: ${scanResult.advertisementData.serviceUuids}');
  if (scanResult.advertisementData.serviceUuids!.contains(BleConstants.ESPM_API_SERVICE_UUID)) {
    return ESPM(scanResult.peripheral);
  }
  if (scanResult.advertisementData.serviceUuids!.contains(BleConstants.CYCLING_POWER_SERVICE_UUID)) {
    return PowerMeter(scanResult.peripheral);
  }
  if (scanResult.advertisementData.serviceUuids!.contains(BleConstants.HEART_RATE_SERVICE_UUID)) {
    return HeartRateMonitor(scanResult.peripheral);
  }
  return Device(scanResult.peripheral);
}

class ScanResultList {
  final String tag = "[ScanResultList]";
  Map<String, ScanResult> _items = {};

  ScanResultList() {
    print("$tag construct");
  }

  bool containsIdentifier(String identifier) {
    return _items.containsKey(identifier);
  }

  /// Adds or updates an item from a [ScanResult]
  ///
  /// If an item with the same identifier already exists, updates the item,
  /// otherwise adds new item.
  /// Returns the new or updated [ScanResult] or null on error.
  ScanResult? addOrUpdate(ScanResult scanResult) {
    final subject = scanResult.peripheral.name.toString() + " rssi=" + scanResult.rssi.toString();
    _items.update(
      scanResult.peripheral.identifier,
      (existing) {
        print("$tag updating $subject");
        existing = scanResult;
        return existing;
      },
      ifAbsent: () {
        print("$tag adding $subject");
        return scanResult;
      },
    );
    return _items[scanResult.peripheral.identifier];
  }

  ScanResult? byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _items[identifier];
    return null;
  }

  Future<void> dispose() async {
    print("$tag dispose");
    //_items.forEach((_, scanResult) => scanResult.dispose());
    _items.clear();
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  void forEach(void Function(String, ScanResult) f) => _items.forEach(f);
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

  Future<void> forEachListItem(Future<void> Function(String, CharacteristicListItem) f) async {
    for (MapEntry e in _items.entries) await f(e.key, e.value);
  }
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

class ESPMSettings {
  double? cranklength;
  var reverseStrain = ExtendedBool.Unknown;
  var doublePower = ExtendedBool.Unknown;
  int? sleepDelay;
  int? motionDetectionMethod;
  int? strainThreshold;
  int? strainThresLow;
  int? negativeTorqueMethod;
  var autoTare = ExtendedBool.Unknown;
  int? autoTareDelayMs;
  int? autoTareRangeG;

  final validMotionDetectionMethods = {
    0: "Hall effect sensor",
    1: "MPU",
    2: "Strain gauge",
  };

  final validNegativeTorqueMethods = {
    0: "Keep",
    1: "Zero",
    2: "Discard",
    3: "Absolute value",
  };

  @override
  bool operator ==(other) {
    return (other is ESPMSettings) &&
        other.cranklength == cranklength &&
        other.reverseStrain == reverseStrain &&
        other.doublePower == doublePower &&
        other.sleepDelay == sleepDelay &&
        other.motionDetectionMethod == motionDetectionMethod &&
        other.strainThreshold == strainThreshold &&
        other.strainThresLow == strainThresLow &&
        other.negativeTorqueMethod == negativeTorqueMethod &&
        other.autoTare == autoTare &&
        other.autoTareDelayMs == autoTareDelayMs &&
        other.autoTareRangeG == autoTareRangeG;
  }

  @override
  int get hashCode =>
      cranklength.hashCode ^
      reverseStrain.hashCode ^
      doublePower.hashCode ^
      sleepDelay.hashCode ^
      motionDetectionMethod.hashCode ^
      strainThreshold.hashCode ^
      strainThresLow.hashCode ^
      negativeTorqueMethod.hashCode ^
      autoTare.hashCode ^
      autoTareDelayMs.hashCode ^
      autoTareDelayMs.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "crankLength: $cranklength, "
        "reverseStrain: $reverseStrain, "
        "doublePower: $doublePower, "
        "sleepDelay: $sleepDelay, "
        "motionDetectionMethod: $motionDetectionMethod, "
        "strainThreshold: $strainThreshold, "
        "strainThresLow: $strainThresLow, "
        "negativeTorqueMethod: $negativeTorqueMethod, "
        "autoTare: $autoTare, "
        "autoTareDelayMs: $autoTareDelayMs, "
        "autoTareRangeG: $autoTareRangeG)";
  }
}

class ESPMWifiSettings {
  var enabled = ExtendedBool.Unknown;
  var apEnabled = ExtendedBool.Unknown;
  String? apSSID;
  String? apPassword;
  var staEnabled = ExtendedBool.Unknown;
  String? staSSID;
  String? staPassword;

  @override
  bool operator ==(other) {
    return (other is ESPMWifiSettings) &&
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
