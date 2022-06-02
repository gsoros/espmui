import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
//import 'package:flutter/painting.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble_constants.dart';
import 'ble.dart';
import 'ble_characteristic.dart';
import 'preferences.dart';
import 'api.dart';
import 'espcc_syncer.dart';
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
  var _characteristics = CharacteristicList();

  /// Signal strength in dBm at the time of the last scan
  int lastScanRssi = 0;

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
      _characteristics.addAll({
        'battery': CharacteristicListItem(BatteryCharacteristic(peripheral!)),
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
            await _onConnected();
          else if (state == disconnectedState) await _onDisconnected();
        },
        onError: (e) => bleError(debugTag, "_stateChangeSubscription", e),
      );
  }

  Future<void> dispose() async {
    debugLog("$name dispose");
    await disconnect();
    await _stateController.close();
    _characteristics.forEachCharacteristic((_, char) async {
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

  Future<void> _onConnected() async {
    await discoverCharacteristics();
    await _subscribeCharacteristics();
  }

  Future<void> _onDisconnected() async {
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
    await _characteristics.forEachListItem((_, item) async {
      if (item.subscribeOnConnect) {
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
    await _characteristics.forEachListItem((_, item) async {
      await item.characteristic?.unsubscribe();
    });
  }

  Future<void> _deinitCharacteristics() async {
    _discovered = false;
    _subscribed = false;
    await _characteristics.forEachListItem((_, item) async {
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
    return _characteristics.get(name);
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

  Future<Type> _correctType() async {
    return runtimeType;
  }

  Future<bool> isCorrectType() async {
    return runtimeType == await _correctType();
  }

  Future<Device> copyToCorrectType() async {
    return this;
  }
}

class PowerMeter extends Device {
  PowerCharacteristic? get power => characteristic("power") as PowerCharacteristic?;

  PowerMeter(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'power': CharacteristicListItem(PowerCharacteristic(peripheral)),
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
  Future<Type> _correctType() async {
    Type t = runtimeType;
    debugLog("_correctType peripheral: $peripheral");
    if (null == peripheral || !await discovered()) return t;
    debugLog("_correctType 2");
    (await peripheral!.services()).forEach((s) {
      if (s.uuid == BleConstants.ESPM_API_SERVICE_UUID) {
        debugLog("_correctType() ESPM detected");
        t = ESPM;
        return;
      }
    });
    return t;
  }

  Future<Device> copyToCorrectType() async {
    if (null == peripheral) return this;
    Type t = await _correctType();
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

class ESPM extends PowerMeter {
  late Api api;
  final weightServiceMode = ValueNotifier<int>(-1);
  final hallEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  final settings = AlwaysNotifier<ESPMSettings>(ESPMSettings());
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());
  //ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;
  StreamSubscription<ApiMessage>? _apiSubsciption;

  WeightScaleCharacteristic? get weightScaleChar => characteristic("weightScale") as WeightScaleCharacteristic?;
  HallCharacteristic? get hallChar => characteristic("hall") as HallCharacteristic?;

  ESPM(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'api': CharacteristicListItem(
        ApiCharacteristic(
          peripheral,
          serviceUUID: BleConstants.ESPM_API_SERVICE_UUID,
        ),
      ),
      'weightScale': CharacteristicListItem(
        WeightScaleCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
      'hall': CharacteristicListItem(
        HallCharacteristic(peripheral),
        subscribeOnConnect: false,
      ),
    });
    api = Api(this);
    api.commands = {1: "config"};
    // listen to api message done events
    _apiSubsciption = api.messageDoneStream.listen((message) => _onApiDone(message));
    tileStreams.addAll({
      "scale": DeviceTileStream(
        label: "Weight Scale",
        stream: weightScaleChar?.defaultStream.map<String>((value) {
          String s = value.toStringAsFixed(2);
          if (s.length > 6) s = s.substring(0, 6);
          if (s == "-0.00") s = "0.00";
          return s;
        }),
        initialData: weightScaleChar?.lastValue.toString,
        units: "kg",
        history: weightScaleChar?.histories['measurement'],
      ),
    });
    tileActions.addAll({
      "tare": DeviceTileAction(
        label: "Tare",
        action: () async {
          var resultCode = await api.requestResultCode("tare=0");
          snackbar("Tare " + (resultCode == ApiResult.success ? "success" : "failed"));
        },
      ),
    });
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(ApiMessage message) async {
    //debugLog("onApiDone parsing message: $message");
    if (message.resultCode != ApiResult.success) return;
    //debugLog("onApiDone parsing successful message: $message");
    // switch does not work with non-constant case :(

    // hostName
    if (api.commandCode("hostName") == message.commandCode) {
      name = message.valueAsString;
    }
    // weightServiceMode
    else if (api.commandCode("weightService") == message.commandCode) {
      weightServiceMode.value = message.valueAsInt ?? -1;
      if (0 < weightServiceMode.value)
        await weightScaleChar?.subscribe();
      else
        await weightScaleChar?.unsubscribe();
    }
    // hallEnabled
    else if (api.commandCode("hallChar") == message.commandCode) {
      hallEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await hallChar?.subscribe();
      else
        await hallChar?.unsubscribe();
    }
    // wifi
    else if (api.commandCode("wifi") == message.commandCode) {
      wifiSettings.value.enabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApEnabled
    else if (api.commandCode("wifiApEnabled") == message.commandCode) {
      wifiSettings.value.apEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiApSSID
    else if (api.commandCode("wifiApSSID") == message.commandCode) {
      wifiSettings.value.apSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiApPassword
    else if (api.commandCode("wifiApPassword") == message.commandCode) {
      wifiSettings.value.apPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaEnabled
    else if (api.commandCode("wifiStaEnabled") == message.commandCode) {
      wifiSettings.value.staEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
    }
    // wifiStaSSID
    else if (api.commandCode("wifiStaSSID") == message.commandCode) {
      wifiSettings.value.staSSID = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // wifiStaPassword
    else if (api.commandCode("wifiStaPassword") == message.commandCode) {
      wifiSettings.value.staPassword = message.valueAsString;
      wifiSettings.notifyListeners();
    }
    // crankLength
    else if (api.commandCode("crankLength") == message.commandCode) {
      settings.value.cranklength = message.valueAsDouble;
      settings.notifyListeners();
    }
    // reverseStrain
    else if (api.commandCode("reverseStrain") == message.commandCode) {
      settings.value.reverseStrain = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      settings.notifyListeners();
    }
    // doublePower
    else if (api.commandCode("doublePower") == message.commandCode) {
      settings.value.doublePower = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      settings.notifyListeners();
    }
    // sleepDelay
    else if (api.commandCode("sleepDelay") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.sleepDelay = (message.valueAsInt! / 1000 / 60).round();
        settings.notifyListeners();
      }
    }
    // motionDetectionMethod
    else if (api.commandCode("motionDetectionMethod") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.motionDetectionMethod = message.valueAsInt!;
        settings.notifyListeners();
      }
    }
    // strainThreshold
    else if (api.commandCode("strainThreshold") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.strainThreshold = message.valueAsInt!;
        settings.notifyListeners();
      }
    } // strainThresLow
    else if (api.commandCode("strainThresLow") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.strainThresLow = message.valueAsInt!;
        settings.notifyListeners();
      }
    }
    // negativeTorqueMethod
    else if (api.commandCode("negativeTorqueMethod") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.negativeTorqueMethod = message.valueAsInt!;
        settings.notifyListeners();
      }
    }
    // autoTare
    else if (api.commandCode("autoTare") == message.commandCode) {
      settings.value.autoTare = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      settings.notifyListeners();
    }
    // autoTareDelayMs
    else if (api.commandCode("autoTareDelayMs") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.autoTareDelayMs = message.valueAsInt!;
        settings.notifyListeners();
      }
    }
    // autoTareRangG
    else if (api.commandCode("autoTareRangeG") == message.commandCode) {
      if (message.valueAsInt != null) {
        settings.value.autoTareRangeG = message.valueAsInt!;
        settings.notifyListeners();
      }
    }
    // config
    else if (api.commandCode("config") == message.commandCode) {
      debugLog("_onApiDone got config: ${message.valueAsString}");
      if (message.valueAsString != null) {
        message.valueAsString!.split(';').forEach((chunk) {
          var pair = chunk.split('=');
          if (2 != pair.length) return;
          var message = ApiMessage(api, pair.first);
          message.commandCode = int.tryParse(pair.first);
          if (null == message.commandCode) return;
          message.resultCode = ApiResult.success;
          message.value = pair.last;
          debugLog('_onApiDone config calling _onApiDone(${message.commandCode})');
          _onApiDone(message);
        });
      }
    }
  }

  Future<void> dispose() async {
    debugLog("$name dispose");
    _apiSubsciption?.cancel();
    super.dispose();
  }

  Future<void> _onConnected() async {
    debugLog("_onConnected()");
    if (null == peripheral) return;
    // api char can use values longer than 20 bytes
    await BLE().requestMtu(peripheral!, 512);
    await super._onConnected();
    _requestInit();
  }

  Future<void> _onDisconnected() async {
    //debugLog("_onDisconnected()");
    await super._onDisconnected();
    _resetInit();
  }

  /// request initial values, returned values are discarded
  /// because the message.done subscription will handle them
  void _requestInit() async {
    debugLog("Requesting init start");
    if (!await ready()) return;
    debugLog("Requesting init ready to go");
    weightServiceMode.value = -1;
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
      "weightService=2",
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
    weightServiceMode.value = -1;
    wifiSettings.value = WifiSettings();
    settings.value = ESPMSettings();
  }

  Future<Type> _correctType() async {
    return ESPM;
  }

  Future<Device> copyToCorrectType() async {
    return this;
  }
}

class ESPCC extends Device {
  late Api api;
  late ESPCCSyncer syncer;
  final settings = AlwaysNotifier<ESPCCSettings>(ESPCCSettings());
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());
  final files = AlwaysNotifier<ESPCCFileList>(ESPCCFileList());
  //ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;
  StreamSubscription<ApiMessage>? _apiSubsciption;

  ESPCC(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'api': CharacteristicListItem(
        ApiCharacteristic(
          peripheral,
          serviceUUID: BleConstants.ESPCC_API_SERVICE_UUID,
        ),
      ),
    });
    api = Api(this);
    syncer = ESPCCSyncer(this);
    // listen to api message done events
    _apiSubsciption = api.messageDoneStream.listen((message) => _onApiDone(message));
  }

  void _onApiDone(ApiMessage message) async {
    //debugLog("onApiDone parsing message: $message");

    //////////////////////////////////////////////////// init
    if ("init" == message.commandStr) {
      if (null == message.value) {
        debugLog("init value null");
        return;
      }
      List<String> tokens = message.value!.split(";");
      tokens.forEach((token) {
        int? code;
        String? command;
        String? value;
        List<String> parts = token.split("=");
        if (parts.length == 1) {
          //debugLog("parts.length == 1; $parts");
          value = null;
        } else
          value = parts[1];
        List<String> c = parts[0].split(":");
        if (c.length != 2) {
          //debugLog("c.length != 2; $c");
          return;
        }
        code = int.tryParse(c[0]);
        command = c[1];
        //debugLog("_onApiDone init: $code:$command=$value");

        if (null == code) {
          debugLog("code is null");
        } else if (api.commands.containsKey(code)) {
          //debugLog("command code already exists: $code");
        } else if (api.commands.containsValue(command)) {
          debugLog("command already exists: $command");
        } else {
          api.commands.addAll({code: command});
        }

        if (null == value) {
          //debugLog("value is null");
          //} else if (value.length < 1) {
          //  //debugLog("value is empty");
        } else {
          // generate (fake) message and call ourself
          ApiMessage m = ApiMessage(api, command);
          m.commandCode = code;
          m.commandStr = command;
          m.value = value;
          m.isDone = true;
          _onApiDone(m);
        }
      });
      return;
    }

    //////////////////////////////////////////////////// hostname
    if ("hostname" == message.commandStr) {
      name = message.valueAsString;
      return;
    }

    //////////////////////////////////////////////////// build
    if ("build" == message.commandStr) {
      return;
    }

    //////////////////////////////////////////////////// touchThres
    if ("touchThres" == message.commandStr) {
      String? v = message.valueAsString;
      if (null == v) return;
      List<String> pairs = v.split(",");
      Map<int, int> values = {};
      pairs.forEach((pair) {
        List<String> parts = pair.split(":");
        if (parts.length != 2) return;
        int? index = int.tryParse(parts[0]);
        if (null == index) return;
        if (index < 0) return;
        int? value = int.tryParse(parts[1]);
        if (null == value) return;
        if (value < 0 || 100 < value) return;
        values[index] = value;
      });
      debugLog("new touchThres=$values");
      settings.value.touchThres = values;
      settings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// peers
    if ("peers" == message.commandStr) {
      String? v = message.valueAsString;
      if (null == v) return;
      List<String> tokens = v.split("|");
      List<String> values = [];
      tokens.forEach((token) {
        if (token.length < 1) return;
        values.add(token);
      });
      debugLog("new peers=$values");
      settings.value.peers = values;
      settings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifi
    if ("wifi" == message.commandStr) {
      wifiSettings.value.enabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiAp
    if ("wifiAp" == message.commandStr) {
      wifiSettings.value.apEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiApSSID
    if ("wifiApSSID" == message.commandStr) {
      wifiSettings.value.apSSID = message.valueAsString;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiApPassword
    if ("wifiApPassword" == message.commandStr) {
      wifiSettings.value.apPassword = message.valueAsString;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiSta
    if ("wifiSta" == message.commandStr) {
      wifiSettings.value.staEnabled = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiStaSSID
    if ("wifiStaSSID" == message.commandStr) {
      wifiSettings.value.staSSID = message.valueAsString;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// wifiStaPassword
    if ("wifiStaPassword" == message.commandStr) {
      wifiSettings.value.staPassword = message.valueAsString;
      wifiSettings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// battery
    if ("battery" == message.commandStr) {
      return;
    }

    //////////////////////////////////////////////////// rec
    if ("rec" == message.commandStr) {
      String? val = message.valueAsString;
      //debugLog("_onApiDone() rec: received val=$val");
      if (null == val) return;
      if ("files:" == val.substring(0, min(6, val.length))) {
        List<String> names = val.substring(6).split(";");
        debugLog("_onApiDone() rec: received names=$names");
        names.forEach((name) async {
          if (16 < name.length) {
            debugLog("_onApiDone() rec:name too long: $name");
            return;
          }
          ESPCCFile f = files.value.files.firstWhere(
            (file) => file.name == name,
            orElse: () {
              var file = syncer.getFromQueue(name: name);
              if (file == null) file = ESPCCFile(name, this, remoteExists: ExtendedBool.True);
              files.value.files.add(file);
              files.notifyListeners();
              return file;
            },
          );
          if (f.remoteSize < 0) {
            api.requestResultCode("rec=info:${f.name}", expectValue: "info:${f.name}");
            await Future.delayed(Duration(seconds: 1));
          }
        });
        for (ESPCCFile f in files.value.files) {
          if (f.localExists == ExtendedBool.Unknown) {
            await f.updateLocalStatus();
            files.notifyListeners();
          }
        }
      } else if ("info:" == val.substring(0, min(5, val.length))) {
        List<String> tokens = val.substring(5).split(";");
        debugLog("got info: $tokens");
        var f = ESPCCFile(tokens[0], this, remoteExists: ExtendedBool.True);
        if (8 <= f.name.length) {
          tokens.removeAt(0);
          tokens.forEach((token) {
            if ("size:" == token.substring(0, 5)) {
              int? s = int.tryParse(token.substring(5));
              if (s != null && 0 <= s) f.remoteSize = s;
            } else if ("distance:" == token.substring(0, 9)) {
              double? s = double.tryParse(token.substring(9));
              if (s != null && 0 <= s) f.distance = s.round();
            } else if ("altGain:" == token.substring(0, 8)) {
              int? s = int.tryParse(token.substring(8));
              if (s != null && 0 <= s) f.altGain = s;
            }
          });
          files.value.files.firstWhere(
            (file) => file.name == f.name,
            orElse: () {
              files.value.files.add(f);
              return f;
            },
          ).update(
            //name: f.name,
            remoteSize: f.remoteSize,
            distance: f.distance,
            altGain: f.altGain,
            //remoteExists: f.remoteExists,
          );
          files.notifyListeners();
        }
      }
      //debugLog("files.length=${files.value.files.length}");
      return;
    }

    //////////////////////////////////////////////////// scan
    if ("scan" == message.commandStr) {
      int? timeout = message.valueAsInt;
      debugLog("_onApiDone() scan: received scan=$timeout");
      settings.value.scanning = null != timeout && 0 < timeout;
      settings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// scanResult
    if ("scanResult" == message.commandStr) {
      String? result = message.valueAsString;
      debugLog("_onApiDone() scanResult: received $result");
      if (null == result) return;
      if (settings.value.scanResults.contains(result)) return;
      settings.value.scanResults.add(result);
      settings.notifyListeners();
      return;
    }

    //////////////////////////////////////////////////// touchRead
    if ("touchRead" == message.commandStr) {
      // reply format: padIndex:currentValue[,padIndex:currentValue...]
      String? result = message.valueAsString;
      if (null == result) return;
      List<String> tokens = result.split(",");
      tokens.forEach((token) {
        List<String> pair = token.split(":");
        if (pair.length != 2) return;
        int? k = int.tryParse(pair[0]);
        int? v = int.tryParse(pair[1]);
        if (null == k || null == v) return;
        settings.value.touchRead.update(k, (_) => v, ifAbsent: () => v);
      });
      debugLog("touchRead: ${settings.value.touchRead}");
      settings.notifyListeners();
      return;
    }

    //snackbar("${message.info} ${message.command}");
    debugLog("unhandled api response: $message");
  }

  Future<void> dispose() async {
    debugLog("$name dispose");
    _apiSubsciption?.cancel();
    super.dispose();
  }

  Future<void> _onConnected() async {
    debugLog("_onConnected()");
    if (null == peripheral) return;
    // api char can use values longer than 20 bytes
    await BLE().requestMtu(peripheral!, 512);
    await super._onConnected();
    _requestInit();
  }

  Future<void> _onDisconnected() async {
    await super._onDisconnected();
    settings.value = ESPCCSettings();
    settings.notifyListeners();
    wifiSettings.value = WifiSettings();
    wifiSettings.notifyListeners();
    files.value = ESPCCFileList();
    files.notifyListeners();
  }

  /// request initial values, returned value is discarded
  /// because the message.done subscription will handle it
  void _requestInit() async {
    debugLog("Requesting init start");
    if (!await ready()) return;
    //await characteristic("api")?.write("init");

    await api.request<String>(
      "init",
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    //await Future.delayed(Duration(milliseconds: 250));
  }
}

class HeartRateMonitor extends Device {
  HeartRateCharacteristic? get heartRate => characteristic("heartRate") as HeartRateCharacteristic?;

  HeartRateMonitor(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'heartRate': CharacteristicListItem(HeartRateCharacteristic(peripheral)),
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

  final motionDetectionMethods = {
    0: "Hall effect sensor",
    1: "MPU",
    2: "Strain gauge",
  };

  final negativeTorqueMethods = {
    0: "Keep",
    1: "Zero",
    2: "Discard",
    3: "Absolute value",
  };

  static final weightMeasurementCharModes = {
    0: "Off",
    1: "On",
    2: "On When Not Pedalling",
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

class ESPCCSettings {
  List<String> peers = [];
  Map<int, int> touchThres = {};
  bool scanning = false;
  List<String> scanResults = [];
  Map<int, int> touchRead = {};
  bool otaMode = false;

  @override
  bool operator ==(other) {
    return (other is ESPCCSettings) && other.peers == peers && other.touchThres == touchThres;
  }

  @override
  int get hashCode => peers.hashCode ^ touchThres.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "peers: $peers, "
        "touchThres: $touchThres"
        ")";
  }
}

class ESPCCFile with Debug {
  ESPCC device;
  String name;
  int remoteSize;
  int localSize;
  int distance;
  int altGain;
  ExtendedBool remoteExists;
  ExtendedBool localExists;

  /// flag for syncer queue
  bool cancelDownload = false;

  ESPCCFile(this.name, this.device,
      {this.remoteSize = -1,
      this.localSize = -1,
      this.distance = -1,
      this.altGain = -1,
      this.remoteExists = ExtendedBool.Unknown,
      this.localExists = ExtendedBool.Unknown});

  Future<void> updateLocalStatus() async {
    String? p = await path;
    if (null == p) return;
    final file = File(p);
    if (await file.exists()) {
      //debugLog("updateLocalStatus() local file $p exists");
      localExists = ExtendedBool.True;
      localSize = await file.length();
    } else {
      debugLog("updateLocalStatus() local file $p does not exist");
      localExists = ExtendedBool.False;
      localSize = -1;
    }
  }

  Future<String?> get path async {
    if (name.length < 1) return null;
    String? path = Platform.isAndroid ? await Path().external : await Path().documents;
    if (null == path) return null;
    String deviceName = "unnamedDevice";
    if (device.name != null && 0 < device.name!.length) deviceName = device.name!;
    return "$path/${Path().sanitize(deviceName)}/rec/${Path().sanitize(name)}";
  }

  Future<File?> getLocal() async {
    String? p = await path;
    if (null == p) return null;
    return File(p);
  }

  void update({
    String? name,
    ESPCC? device,
    int? remoteSize,
    int? localSize,
    int? distance,
    int? altGain,
    ExtendedBool? remoteExists,
    ExtendedBool? localExists,
  }) {
    if (null != name) this.name = name;
    if (null != device) this.device = device;
    if (null != remoteSize) this.remoteSize = remoteSize;
    if (null != localSize) this.localSize = localSize;
    if (null != distance) this.distance = distance;
    if (null != altGain) this.altGain = altGain;
    if (null != remoteExists) this.remoteExists = remoteExists;
    if (null != localExists) this.localExists = localExists;
  }

  @override
  bool operator ==(other) {
    return (other is ESPCCFile) &&
        other.device == device &&
        other.name == name &&
        other.remoteSize == remoteSize &&
        //other.localSize == localSize &&
        other.distance == distance &&
        other.altGain == altGain &&
        other.remoteExists == remoteExists &&
        other.localExists == localExists;
  }

  @override
  int get hashCode =>
      device.hashCode ^
      name.hashCode ^
      remoteSize.hashCode ^
      localSize.hashCode ^
      distance.hashCode ^
      altGain.hashCode ^
      remoteExists.hashCode ^
      localExists.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "name: $name, "
        "device: ${device.name}, "
        "remoteSize: $remoteSize, "
        "localSize: $localSize, "
        "distance: $distance, "
        "altGain: $altGain, "
        "remote: $remoteExists, "
        "local: $localExists "
        ")";
  }
}

class ESPCCFileList {
  List<ESPCCFile> files = [];

  bool has(String name) {
    bool exists = false;
    for (ESPCCFile f in files) {
      if (f.name == name) {
        exists = true;
        break;
      }
    }
    return exists;
  }

  @override
  bool operator ==(other) {
    return (other is ESPCCFileList) && other.files == files;
  }

  @override
  int get hashCode => files.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "files: $files"
        ")";
  }
}

class WifiSettings {
  var enabled = ExtendedBool.Unknown;
  var apEnabled = ExtendedBool.Unknown;
  String? apSSID;
  String? apPassword;
  var staEnabled = ExtendedBool.Unknown;
  String? staSSID;
  String? staPassword;

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
