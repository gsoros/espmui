import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
//import 'package:flutter/painting.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:intl/intl.dart';

import 'espm.dart';
import 'espcc.dart';
import 'ble_constants.dart';
import 'ble.dart';
import 'ble_characteristic.dart';
import 'preferences.dart';
import 'api.dart';

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
  StreamSubscription<PeripheralConnectionState>? _stateSubscription;
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
    dev.log("Device.fromSaved($savedDevice)");
    var chunks = savedDevice.split(";");
    if (chunks.length != 3) return null;
    var manager = await BLE().manager;
    Peripheral peripheral = manager.createUnsafePeripheral(chunks[2]);
    Device device;
    if ("ESPM" == chunks[0])
      device = ESPM(peripheral);
    else if ("ESPCC" == chunks[0])
      device = ESPCC(peripheral);
    else if ("PowerMeter" == chunks[0])
      device = PowerMeter(peripheral);
    else if ("HeartRateMonitor" == chunks[0])
      device = HeartRateMonitor(peripheral);
    else
      return null;
    device.name = chunks[1];
    return device;
  }

  void init() async {
    autoConnect.value = await isSaved();
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;
    if (_stateSubscription == null && peripheral != null) {
      _stateSubscription = peripheral!
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
        onError: (e) => bleError(debugTag, "_stateSubscription", e),
      );
    }
    if (_stateChangeSubscription == null)
      _stateChangeSubscription = stateStream.listen(
        (state) async {
          if (state == connectedState)
            await onConnected();
          else if (state == disconnectedState) await onDisconnected();
        },
        onError: (e) => bleError(debugTag, "_stateChangeSubscription", e),
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
    await _stateSubscription?.cancel();
    _stateSubscription = null;
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
    //debugLog("_onDisconnected()");
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    //streamSendIfNotClosed(stateController, newState);
    if (autoConnect.value && !await connected) {
      await Future.delayed(Duration(seconds: 15)).then((_) async {
        if (autoConnect.value && !await connected) {
          //debugLog("Autoconnect calling connect()");
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
      debugLog("connect() Adapter is off, not connecting");
      streamSendIfNotClosed(_stateController, disconnectedState);
      return;
    }
    if (null == peripheral) {
      debugLog("connect() Peripheral is null)");
      return;
    }
    if (_connectionInitiated) {
      debugLog("connect() Connection already initiated");
      return;
    }
    //debugLog("connect() Connecting to $name(${peripheral!.identifier})");
    _connectionInitiated = true;
    await peripheral!
        .connect(
      isAutoConnect: true,
      refreshGatt: true,
      timeout: Duration(seconds: 20),
    )
        .catchError(
      (e) async {
        bleError(debugTag, "peripheral.connect()", e);
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
    debugLog('_subscribeCharacteristics start');
    if (!await discovered()) return;
    await characteristics.forEachListItem((_, item) async {
      if (item.subscribeOnConnect) {
        if (null == item.characteristic) return;
        debugLog('_subscribeCharacteristics ${item.characteristic?.charUUID} start');
        await item.characteristic?.subscribe();
        debugLog('_subscribeCharacteristics ${item.characteristic?.charUUID} end');
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
    streamSendIfNotClosed(_stateController, lastConnectionState);
    if (value && !(await connected)) connect();
  }

  Future<void> updatePreferences() async {
    if (null == peripheral) return;
    List<String> devices = (await Preferences().getDevices()).value;
    debugLog('updatePreferences savedDevices before: $devices');
    String item = runtimeType.toString() + ';' + (name?.replaceAll(RegExp(r';'), '') ?? '') + ';' + peripheral!.identifier;
    debugLog('updatePreferences item: $item');
    if (autoConnect.value)
      devices.add(item);
    else
      devices.removeWhere((item) => item.endsWith(peripheral!.identifier));
    Preferences().setDevices(devices);
    debugLog('updatePreferences savedDevices after: $devices');
  }

  Future<bool> isSaved() async {
    if (null == peripheral) return false;
    var devices = (await Preferences().getDevices()).value;
    return devices.any((item) => item.endsWith(peripheral!.identifier));
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
    } else
      return this;
    return device;
  }
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
