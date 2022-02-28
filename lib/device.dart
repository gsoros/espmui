import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble_constants.dart';
import 'ble.dart';
import 'ble_characteristic.dart';
import 'preferences.dart';
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

class Device with DebugHelper {
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
  Map<String, TileStream> tileStreams = {};

  Device(this.peripheral) {
    dev.log("$debugTag construct");
    if (null != peripheral)
      _characteristics.addAll({
        'battery': CharacteristicListItem(BatteryCharacteristic(peripheral!)),
      });
    tileStreams.addAll({
      "battery": TileStream(
        label: "Battery",
        stream: battery?.stream.map<String>((value) => "$value"),
        initialData: battery?.lastValue.toString,
        units: "%",
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
    if (uuids.contains(BleConstants.CYCLING_POWER_SERVICE_UUID)) {
      return PowerMeter(scanResult.peripheral);
    }
    if (uuids.contains(BleConstants.HEART_RATE_SERVICE_UUID)) {
      return HeartRateMonitor(scanResult.peripheral);
    }
    return Device(scanResult.peripheral);
  }

  static Device? fromSaved(String savedDevice) {
    var chunks = savedDevice.split(";");
    if (chunks.length != 3) return null;
    Peripheral peripheral = BleManager().createUnsafePeripheral(chunks[2]);
    var device;
    if ("ESPM" == chunks[0])
      device = ESPM(peripheral);
    else if ("PowerMeter" == chunks[0])
      device = PowerMeter(peripheral);
    else if ("HeartRateMonitor" == chunks[0])
      device = HeartRateMonitor(peripheral);
    else
      return null;
    device.name = chunks[1];
    dev.log("Device.fromSaved($savedDevice): $device");
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
          print("$runtimeType new connection state: $state");
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
    print("$runtimeType $name dispose");
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
    print("$debugTag _onDisconnected()");
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    //streamSendIfNotClosed(stateController, newState);
    if (autoConnect.value && !await connected) {
      await Future.delayed(Duration(seconds: 15)).then((_) async {
        if (autoConnect.value && !await connected) {
          print("$debugTag Autoconnect calling connect()");
          await connect();
        }
      });
    }
  }

  Future<void> connect() async {
    final connectedState = PeripheralConnectionState.connected;
    final disconnectedState = PeripheralConnectionState.disconnected;

    if (await connected) {
      print("$runtimeType Not connecting to $name, already connected");
      streamSendIfNotClosed(_stateController, connectedState);
      //await discoverCharacteristics();
      //await _subscribeCharacteristics();
      //_requestInit();
      return;
    }
    if (await BLE().currentState() != BluetoothState.POWERED_ON) {
      print("$debugTag connect() Adapter is off, not connecting");
      streamSendIfNotClosed(_stateController, disconnectedState);
      return;
    }
    if (null == peripheral) {
      print("$debugTag connect() Peripheral is null)");
      return;
    }
    if (_connectionInitiated) {
      print("$debugTag connect() Connection already initiated");
      return;
    }
    print("$debugTag connect() Connecting to $name(${peripheral!.identifier})");
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
    print("$debugTag peripheral.connect() returned");
    _connectionInitiated = false;
  }

  Future<void> discoverCharacteristics() async {
    String subject = "$debugTag discoverCharacteristics()";
    //print("$subject conn=${await connected}");
    if (!await connected) return;
    if (null == peripheral) return;
    //print("$subject discoverAllServicesAndCharacteristics() start");
    await peripheral!.discoverAllServicesAndCharacteristics().catchError((e) {
      bleError(debugTag, "discoverAllServicesAndCharacteristics()", e);
    });
    //print("$subject discoverAllServicesAndCharacteristics() end");
    //print("$subject services() start");
    var services = await peripheral!.services().catchError((e) {
      bleError(debugTag, "services()", e);
      return <Service>[];
    });
    //print("$subject services() end");
    var serviceUuids = <String>[];
    services.forEach((s) {
      serviceUuids.add(s.uuid);
    });
    print("$subject end services: $serviceUuids");
    _discovered = true;
  }

  Future<void> _subscribeCharacteristics() async {
    dev.log('$runtimeType _subscribeCharacteristics start');
    if (!await discovered()) return;
    await _characteristics.forEachListItem((_, item) async {
      if (item.subscribeOnConnect) {
        dev.log('$runtimeType _subscribeCharacteristics ${item.characteristic?.characteristicUUID} start');
        await item.characteristic?.subscribe();
        dev.log('$runtimeType _subscribeCharacteristics ${item.characteristic?.characteristicUUID} end');
      }
    });
    _subscribed = true;
    dev.log('$runtimeType _subscribeCharacteristics end');
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
    print("$runtimeType disconnect() $name");
    if (null == peripheral) return;
    if (!await peripheral!.isConnected()) {
      dev.log("$debugTag disconnect(): not connected, but proceeding anyway");
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
    dev.log('$runtimeType updatePreferences savedDevices before: $devices');
    String item = runtimeType.toString() + ';' + (name?.replaceAll(RegExp(r';'), '') ?? '') + ';' + peripheral!.identifier;
    dev.log('$runtimeType updatePreferences item: $item');
    if (autoConnect.value)
      devices.add(item);
    else
      devices.removeWhere((item) => item.endsWith(peripheral!.identifier));
    Preferences().setDevices(devices);
    dev.log('$runtimeType updatePreferences savedDevices after: $devices');
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
      "power": TileStream(
        label: "Power",
        stream: power?.powerStream.map<String>((value) => "$value"),
        initialData: power?.lastPower.toString,
        units: "W",
      ),
    });
    tileStreams.addAll({
      "cadence": TileStream(
        label: "Cadence",
        stream: power?.cadenceStream.map<String>((value) => "$value"),
        initialData: power?.lastCadence.toString,
        units: "rpm",
      ),
    });
  }

  /// Hack: the 128-bit api service uuid is sometimes not detected from the
  /// advertisement packet, only after discovery
  Future<Type> _correctType() async {
    Type t = runtimeType;
    dev.log("$debugTag _correctType peripheral: $peripheral");
    if (null == peripheral || !await discovered()) return t;
    dev.log("$debugTag _correctType 2");
    (await peripheral!.services()).forEach((s) {
      if (s.uuid == BleConstants.ESPM_API_SERVICE_UUID) {
        dev.log("$debugTag _correctType() ESPM detected");
        t = ESPM;
        return;
      }
    });
    return t;
  }

  Future<Device> copyToCorrectType() async {
    if (null == peripheral) return this;
    Type t = await _correctType();
    dev.log("$debugTag copyToCorrectType $t");
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
    tileStreams.addAll({
      "scale": TileStream(
        label: "Weight Scale",
        stream: weightScale?.stream.map<String>((value) {
          String s = value.toStringAsFixed(2);
          if (s.length > 6) s = s.substring(0, 6);
          if (s == "-0.00") s = "0.00";
          return s;
        }),
        initialData: weightScale?.lastValue.toString,
        units: "kg",
      ),
    });
  }

  /// Processes "done" messages sent by the API
  void _onApiDone(EspmApiMessage message) async {
    //print("$runtimeType onApiDone parsing message: $message");
    if (message.resultCode != EspmApiResult.success.index) return;
    //print("$runtimeType onApiDone parsing successful message: $message");
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
      dev.log('$runtimeType _onApiDone got config');
      if (message.valueAsString != null) {
        message.valueAsString!.split(';').forEach((chunk) {
          var pair = chunk.split('=');
          if (2 != pair.length) return;
          var message = EspmApiMessage(pair.first);
          message.commandCode = int.tryParse(pair.first);
          if (null == message.commandCode) return;
          message.resultCode = EspmApiResult.success.index;
          message.value = pair.last;
          dev.log('$runtimeType _onApiDone config calling _onApiDone(${message.commandCode})');
          _onApiDone(message);
        });
      }
    }
  }

  Future<void> dispose() async {
    print("$runtimeType $name dispose");
    _apiSubsciption?.cancel();
    super.dispose();
  }

  Future<void> _onConnected() async {
    print("$debugTag _onConnected()");
    if (null == peripheral) return;
    // api char can use values longer than 20 bytes
    await BLE().requestMtu(peripheral!, 512);
    await super._onConnected();
    _requestInit();
  }

  Future<void> _onDisconnected() async {
    print("$runtimeType _onDisconnected()");
    await super._onDisconnected();
    _resetInit();
  }

  /// request initial values, returned values are discarded
  /// because the message.done subscription will handle them
  void _requestInit() async {
    print("$runtimeType Requesting init start");
    if (!await ready()) return;
    print("$runtimeType Requesting init ready to go");
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

  Future<Type> _correctType() async {
    return ESPM;
  }

  Future<Device> copyToCorrectType() async {
    return this;
  }
}

class HeartRateMonitor extends Device {
  HeartRateCharacteristic? get heartRate => characteristic("heartRate") as HeartRateCharacteristic?;

  HeartRateMonitor(Peripheral peripheral) : super(peripheral) {
    _characteristics.addAll({
      'heartRate': CharacteristicListItem(HeartRateCharacteristic(peripheral)),
    });
    tileStreams.addAll({
      "heartRate": TileStream(
        label: "Heart Rate",
        stream: heartRate?.stream.map<String>((value) => "$value"),
        initialData: heartRate?.lastValue.toString,
        units: "bpm",
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

class TileStream {
  String label;
  Stream<String>? stream;
  String Function()? initialData;
  String units;

  TileStream({
    required this.label,
    required this.stream,
    required this.initialData,
    required this.units,
  });
}
