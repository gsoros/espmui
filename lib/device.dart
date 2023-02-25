import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
//import 'package:flutter/painting.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'espm.dart';
import 'espcc.dart';
import 'ble_constants.dart';
import 'ble.dart';
import 'ble_characteristic.dart';
import 'preferences.dart';
import 'api.dart';
import "device_widgets.dart";

import 'util.dart';
import 'debug.dart';

/*
Device: Battery
  ├─ PowerMeter: Power(, Cadence)
  │    └─ ESPM: Api, WeightScale, Hall
  ├─ ESPCC: Api
  ├─ HeartrateMonitor: Heartrate
  ├─ TODO CadenceSensor: Cadence
  └─ TODO SpeedSensor: Speed
*/

class Device with Debug {
  Peripheral? peripheral;

  /// whether the device should be remembered
  final remember = ValueNotifier<bool>(false);

  /// whether the device should be kept connected
  final autoConnect = ValueNotifier<bool>(false);

  /// list of characteristics
  CharacteristicList characteristics = CharacteristicList();

  /// Signal strength in dBm at the time of the last scan
  int lastScanRssi = 0;

  /// the received mtu size, if requested
  int? mtu;

  String? get name => peripheral?.name;
  set name(String? name) => peripheral?.name = name;
  String get identifier => peripheral?.identifier ?? "";
  BatteryCharacteristic? get battery => characteristic("battery") as BatteryCharacteristic?;

  Future<bool> get connected async {
    if (null == peripheral) return false;
    return await peripheral!.isConnected().catchError((e) {
      bleError(debugTag, "could not get connection state", e);
    });
  }

  bool _subscribed = false;
  bool _discovered = false;
  bool _connectionInitiated = false;

  // Connection state
  PeripheralConnectionState lastConnectionState = PeripheralConnectionState.disconnected;
  final _stateController = StreamController<PeripheralConnectionState>.broadcast();
  Stream<PeripheralConnectionState> get stateStream => _stateController.stream;
  StreamSubscription<PeripheralConnectionState>? stateSubscription;
  StreamSubscription<PeripheralConnectionState>? _stateChangeSubscription;

  /// Streams which can be selected on the tiles
  Map<String, DeviceTileStream> tileStreams = {};

  /// Actions which can be initiated by tapping on the tiles
  Map<String, DeviceTileAction> tileActions = {};

  Device(this.peripheral) {
    debugLog("construct");
    if (null != peripheral)
      characteristics.addAll({
        'battery': CharacteristicListItem(BatteryCharacteristic(this)),
      });
    tileStreams.addAll({
      "battery": DeviceTileStream(
        label: "Battery",
        stream: battery?.defaultStream.map<String>((value) => "$value"),
        initialData: battery?.lastValue.toString,
        units: "%",
        history: battery?.histories['charge'],
      ),
    });
    init();
  }

  static Device fromScanResult(ScanResult scanResult) {
    var uuids = scanResult.advertisementData.serviceUuids ?? [];
    if (0 == uuids.length) {
      dev.log('[Device] fromScanResult: no serviceUuids in scanResult.advertisementData');
      return Device(scanResult.peripheral);
    }
    dev.log('[Device] fromScanResult uuids: $uuids');
    if (uuids.contains(BleConstants.ESPM_API_SERVICE_UUID)) {
      return ESPM(scanResult.peripheral);
    }
    if (uuids.contains(BleConstants.ESPCC_API_SERVICE_UUID)) {
      return ESPCC(scanResult.peripheral);
    }
    if (uuids.contains(BleConstants.CYCLING_POWER_SERVICE_UUID)) {
      return PowerMeter(scanResult.peripheral);
    }
    if (uuids.contains(BleConstants.HEART_RATE_SERVICE_UUID)) {
      return HeartRateMonitor(scanResult.peripheral);
    }
    return Device(scanResult.peripheral);
  }

  static Future<Device?> fromSaved(String savedDevice) async {
    var chunks = savedDevice.split(";");
    if (chunks.length < 3) return null;
    String address = chunks.removeAt(0);
    String type = "";
    String name = "";
    bool autoConnect = false;
    chunks.forEach((chunk) {
      String key = "type=";
      if (chunk.startsWith(key)) type = chunk.substring(key.length);
      key = "name=";
      if (chunk.startsWith(key)) name = chunk.substring(key.length);
      key = "autoConnect=";
      if (chunk.startsWith(key)) autoConnect = chunk.substring(key.length) == "true";
    });
    dev.log("Device.fromSaved($savedDevice): address: $address, type: $type, name: $name, autoConnect: " + (autoConnect ? "true" : "false"));
    var manager = await BLE().manager;
    Peripheral peripheral = manager.createUnsafePeripheral(address);
    Device device;
    if ("ESPM" == type)
      device = ESPM(peripheral);
    else if ("ESPCC" == type)
      device = ESPCC(peripheral);
    else if ("PowerMeter" == type)
      device = PowerMeter(peripheral);
    else if ("HeartRateMonitor" == type)
      device = HeartRateMonitor(peripheral);
    else
      return null;
    device.name = name;
    device.autoConnect.value = autoConnect;
    device.remember.value = true;
    return device;
  }

  void init() async {
    String? saved = await getSaved();
    if (null != saved) {
      remember.value = true;
      autoConnect.value = saved.contains("autoConnect=true");
    }
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;
    if (stateSubscription == null && peripheral != null) {
      stateSubscription = peripheral!
          .observeConnectionState(
        emitCurrentValue: true,
        completeOnDisconnect: false,
      )
          .listen(
        (state) async {
          //debugLog("new connection state: $state");
          lastConnectionState = state;
          /*
          if (state == connectedState)
            await _onConnected();
          else if (state == disconnectedState) await _onDisconnected();
          */
          streamSendIfNotClosed(_stateController, state);
        },
        onError: (e) => bleError(debugTag, "$name _stateSubscription", e),
      );
    }
    if (_stateChangeSubscription == null)
      _stateChangeSubscription = stateStream.listen(
        (state) async {
          debugLog("$name _stateChangeSubscription state: $state");
          if (state == connectedState)
            await onConnected();
          else if (state == disconnectedState) await onDisconnected();
        },
        onError: (e) => bleError(debugTag, "$name _stateChangeSubscription", e),
      );
  }

  Future<void> dispose() async {
    debugLog("$name dispose");
    await disconnect();
    await _stateController.close();
    characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
      await char?.dispose();
    });
    await stateSubscription?.cancel();
    stateSubscription = null;
    await _stateChangeSubscription?.cancel();
    _stateChangeSubscription = null;
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

  Future<void> onConnected() async {
    await discoverCharacteristics();
    await _subscribeCharacteristics();
  }

  Future<void> onDisconnected() async {
    debugLog("$name onDisconnected()");
    // if (await connected) {
    //   debugLog("but $name is connected");
    //   return;
    // }
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    //streamSendIfNotClosed(stateController, newState);
    if (autoConnect.value && !await connected) {
      await Future.delayed(Duration(seconds: 15)).then((_) async {
        if (autoConnect.value && !await connected) {
          debugLog("$name onDisconnected() calling connect()");
          await connect();
        }
      });
    }
  }

  Future<void> connect() async {
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;

    if (await connected) {
      debugLog("Not connecting to $name, already connected");
      streamSendIfNotClosed(_stateController, connectedState);
      //await discoverCharacteristics();
      //await _subscribeCharacteristics();
      //_requestInit();
      return;
    }
    if (await BLE().currentState() != BluetoothState.POWERED_ON) {
      debugLog("$name connect() Adapter is off, not connecting");
      streamSendIfNotClosed(_stateController, disconnectedState);
      return;
    }
    if (null == peripheral) {
      debugLog("$name connect() Peripheral is null)");
      return;
    }
    if (_connectionInitiated) {
      debugLog("$name connect() Connection already initiated");
      return;
    }
    //debugLog("connect() Connecting to $name(${peripheral!.identifier})");
    _connectionInitiated = true;
    await peripheral!
        .connect(
      isAutoConnect: true,
      refreshGatt: true,
      timeout: Duration(seconds: 20),
      //requestMtu: 512,
    )
        .catchError(
      (e) async {
        bleError(debugTag, "$name peripheral.connect()", e);
        if (e is BleError) {
          BleError be = e;
          if (be.errorCode.value == BleErrorCode.deviceAlreadyConnected) {
            await disconnect();
            await Future.delayed(Duration(seconds: 3));
            connect();
            //dev.log("$runtimeType $name already connected, sending message to stateController");
            //streamSendIfNotClosed(_stateController, connectedState);
          }
        }
      },
    );
    //debugLog("peripheral.connect() returned");
    _connectionInitiated = false;
  }

  Future<void> discoverCharacteristics() async {
    String subject = "$debugTag discoverCharacteristics()";
    //debugLog("$subject conn=${await connected}");
    if (!await connected) return;
    if (null == peripheral) return;
    //debugLog("$subject discoverAllServicesAndCharacteristics() start");
    await peripheral!.discoverAllServicesAndCharacteristics().catchError((e) {
      bleError(debugTag, "discoverAllServicesAndCharacteristics()", e);
    });
    //debugLog("$subject discoverAllServicesAndCharacteristics() end");
    //debugLog("$subject services() start");
    var services = await peripheral!.services().catchError((e) {
      bleError(debugTag, "services()", e);
      return <Service>[];
    });
    //debugLog("$subject services() end");
    var serviceUuids = <String>[];
    services.forEach((s) {
      serviceUuids.add(s.uuid);
    });
    debugLog("$subject end services: $serviceUuids");
    _discovered = true;
  }

  Future<void> _subscribeCharacteristics() async {
    debugLog('$name _subscribeCharacteristics start');
    if (!await discovered()) return;
    await characteristics.forEachListItem((name, item) async {
      if (item.subscribeOnConnect) {
        if (null == item.characteristic) return;
        debugLog('_subscribeCharacteristics $name ${item.characteristic?.charUUID} start');
        await item.characteristic?.subscribe();
        debugLog('_subscribeCharacteristics $name ${item.characteristic?.charUUID} end');
      }
    });
    _subscribed = true;
    debugLog('_subscribeCharacteristics end');
  }

  Future<void> _unsubscribeCharacteristics() async {
    _subscribed = false;
    await characteristics.forEachListItem((_, item) async {
      await item.characteristic?.unsubscribe();
    });
  }

  Future<void> _deinitCharacteristics() async {
    _discovered = false;
    _subscribed = false;
    await characteristics.forEachListItem((_, item) async {
      await item.characteristic?.deinit();
    });
  }

  Future<void> disconnect() async {
    debugLog("disconnect() $name");
    if (null == peripheral) return;
    if (!await peripheral!.isConnected()) {
      debugLog("disconnect(): not connected, but proceeding anyway");
      //return;
    }
    //await _unsubscribeCharacteristics();
    await peripheral!.disconnectOrCancelConnection().catchError((e) {
      bleError(debugTag, "peripheral.disconnectOrCancelConnection()", e);
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
    return characteristics.get(name);
  }

  void setAutoConnect(bool value) async {
    autoConnect.value = value;
    await updatePreferences();
    // resend last connection state to trigger connect button update
    // streamSendIfNotClosed(_stateController, lastConnectionState);
    if (value && !(await connected)) connect();
  }

  void setRemember(bool value) async {
    remember.value = value;
    await updatePreferences();
  }

  Future<void> updatePreferences() async {
    if (null == peripheral) return;
    List<String> devices = (await Preferences().getDevices()).value;
    debugLog('updatePreferences savedDevices before: $devices');
    devices.removeWhere((item) => item.startsWith(peripheral!.identifier));
    if (remember.value) {
      String item = peripheral!.identifier +
          ";name=" +
          (name?.replaceAll(RegExp(r';'), '') ?? '') +
          ";type=" +
          runtimeType.toString() +
          ";autoConnect=" +
          (autoConnect.value ? "true" : "false");
      debugLog('updatePreferences item: $item');
      devices.add(item);
    }
    Preferences().setDevices(devices);
    debugLog('updatePreferences savedDevices after: $devices');
  }

  Future<String?> getSaved() async {
    if (null == peripheral) return null;
    var devices = (await Preferences().getDevices()).value;
    String item = devices.firstWhere((item) => item.startsWith(peripheral!.identifier), orElse: () => "");
    return "" == item ? null : item;
  }

  Future<Type> correctType() async {
    return runtimeType;
  }

  Future<bool> isCorrectType() async {
    return runtimeType == await correctType();
  }

  Future<Device> copyToCorrectType() async {
    return this;
  }

  IconData get iconData => DeviceIcon(null).data();
}

class PowerMeter extends Device {
  PowerCharacteristic? get power => characteristic("power") as PowerCharacteristic?;

  PowerMeter(Peripheral peripheral) : super(peripheral) {
    characteristics.addAll({
      'power': CharacteristicListItem(PowerCharacteristic(this)),
    });
    tileStreams.addAll({
      "power": DeviceTileStream(
        label: "Power",
        stream: power?.powerStream.map<String>((value) => "$value"),
        initialData: power?.lastPower.toString,
        units: "W",
        history: power?.histories['power'],
      ),
    });
    tileStreams.addAll({
      "cadence": DeviceTileStream(
        label: "Cadence",
        stream: power?.cadenceStream.map<String>((value) => "$value"),
        initialData: power?.lastCadence.toString,
        units: "rpm",
        history: power?.histories['cadence'],
      ),
    });
  }

  /// Hack: the 128-bit api service uuid is sometimes not detected from the
  /// advertisement packet, only after discovery
  @override
  Future<Type> correctType() async {
    Type t = runtimeType;
    debugLog("correctType peripheral: $peripheral");
    if (null == peripheral || !await discovered()) return t;
    debugLog("_correctType 2");
    (await peripheral!.services()).forEach((s) {
      if (s.uuid == BleConstants.ESPM_API_SERVICE_UUID) {
        debugLog("correctType() ESPM detected");
        t = ESPM;
        return;
      }
    });
    return t;
  }

  @override
  Future<Device> copyToCorrectType() async {
    if (null == peripheral) return this;
    Type t = await correctType();
    debugLog("copyToCorrectType $t");
    Device device = this;
    if (ESPM == t) {
      device = ESPM(peripheral!);
      device.name = name;
      device.autoConnect.value = autoConnect.value;
      device.remember.value = remember.value;
    } else
      return this;
    return device;
  }

  @override
  IconData get iconData => DeviceIcon("PM").data();
}

class HeartRateMonitor extends Device {
  HeartRateCharacteristic? get heartRate => characteristic("heartRate") as HeartRateCharacteristic?;

  HeartRateMonitor(Peripheral peripheral) : super(peripheral) {
    characteristics.addAll({
      'heartRate': CharacteristicListItem(HeartRateCharacteristic(this)),
    });
    tileStreams.addAll({
      "heartRate": DeviceTileStream(
        label: "Heart Rate",
        stream: heartRate?.defaultStream.map<String>((value) => "$value"),
        initialData: heartRate?.lastValue.toString,
        units: "bpm",
        history: heartRate?.histories['measurement'],
      ),
    });
  }

  @override
  IconData get iconData => DeviceIcon("HRM").data();
}

class WifiSettings with Debug {
  var enabled = ExtendedBool.Unknown;
  var apEnabled = ExtendedBool.Unknown;
  String? apSSID;
  String? apPassword;
  var staEnabled = ExtendedBool.Unknown;
  String? staSSID;
  String? staPassword;

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //debugLog("handleApiDoneMessage $message");

    //////////////////////////////////////////////////// wifi
    if ("w" == message.commandStr) {
      enabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }

    //////////////////////////////////////////////////// wifiAp
    if ("wa" == message.commandStr) {
      apEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }

    //////////////////////////////////////////////////// wifiApSSID
    if ("was" == message.commandStr) {
      apSSID = message.valueAsString;
      return true;
    }

    //////////////////////////////////////////////////// wifiApPassword
    if ("wap" == message.commandStr) {
      apPassword = message.valueAsString;
      return true;
    }

    //////////////////////////////////////////////////// wifiSta
    if ("ws" == message.commandStr) {
      staEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }

    //////////////////////////////////////////////////// wifiStaSSID
    if ("wss" == message.commandStr) {
      staSSID = message.valueAsString;
      return true;
    }

    //////////////////////////////////////////////////// wifiStaPassword
    if ("wsp" == message.commandStr) {
      staPassword = message.valueAsString;
      return true;
    }
    return false;
  }

  @override
  bool operator ==(other) {
    return (other is WifiSettings) &&
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

class DeviceTileStream {
  String label;
  Stream<String>? stream;
  String Function()? initialData;
  String units;
  CharacteristicHistory? history;

  DeviceTileStream({
    required this.label,
    required this.stream,
    required this.initialData,
    required this.units,
    this.history,
  });
}

class DeviceTileAction {
  String label;
  Function action;

  DeviceTileAction({
    required this.label,
    required this.action,
  });

  void call() {
    action();
  }
}
