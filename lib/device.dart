import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math';
//import 'dart:collection';

import 'package:flutter/foundation.dart';
//import 'package:flutter/painting.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
//import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'espm.dart';
import 'espcc.dart';
import 'homeauto.dart';
import 'ble_constants.dart';
import 'ble.dart';
import 'ble_characteristic.dart';
import 'preferences.dart';
import 'api.dart';
import "device_widgets.dart";
import "notifications.dart";

import 'util.dart';
import 'debug.dart';

/*
Device: Battery
  ├─ PowerMeter: Power(, Cadence)
  │   └─ ESPM: Api, Wifi, WeightScale, Hall, Temp
  ├─ ESPCC: Api, Wifi, Peers, Rec
  ├─ Homeauto: Api, Wifi, Peers
  ├─ HeartrateMonitor: Heartrate
  ├─ TODO CadenceSensor: Cadence
  └─ TODO SpeedSensor: Speed
*/

class Device with Debug {
  /// whether the device should be remembered
  final remember = ValueNotifier<bool>(false);

  /// whether the device should be kept connected
  final autoConnect = ValueNotifier<bool>(false);

  /// whether the log should be saved
  final saveLog = ValueNotifier<bool>(false);

  /// list of characteristics
  CharacteristicList characteristics = CharacteristicList();

  /// Signal strength in dBm at the time of the last scan
  int lastScanRssi = 0;

  /// the received mtu size, if requested
  int? mtu;

  /// the device identifier, MAC on Adroid
  String id;

  /// the name of the device
  String name;

  BatteryCharacteristic? get battery => characteristic("battery") as BatteryCharacteristic?;

  bool _subscribed = false;
  bool _discovered = false;
  bool _connectionInitiated = false;

  // Connection state
  DeviceConnectionState? lastConnectionState;
  final stateController = StreamController<DeviceConnectionState>.broadcast();
  Stream<DeviceConnectionState> get stateStream => stateController.stream;
  StreamSubscription<DeviceConnectionState>? stateSubscription;
  StreamSubscription<ConnectionStateUpdate>? _stateUpdateSubscription;

  bool get connected => lastConnectionState == DeviceConnectionState.connected;

  /// Streams which can be selected on the tiles
  Map<String, DeviceTileStream> tileStreams = {};

  /// Actions which can be initiated by tapping on the tiles
  Map<String, DeviceTileAction> tileActions = {};

  StreamSubscription<int>? _batteryLevelSubscription;
  ExtendedBool isCharging = ExtendedBool.eUnknown;

  int get defaultMtu => 23;
  int get largeMtu => 512;

  Device(this.id, this.name) {
    logD("construct");
    characteristics.addAll({
      'battery': CharacteristicListItem(BatteryCharacteristic(this)),
    });
    tileStreams.addAll({
      "battery": DeviceTileStream(
        label: "Battery",
        stream: battery?.defaultStream.map<Widget>((value) => Text(value.toString())),
        initialData: () => Text(battery?.lastValueToString() ?? ' '),
        units: "%",
        history: battery?.histories['charge'],
      ),
    });
    init();
  }

  static Device fromScanResult(DiscoveredDevice scanResult) {
    var uuids = scanResult.serviceUuids;
    if (uuids.isEmpty) {
      dev.log('[Device] fromScanResult: no serviceUuids in scanResult');
      return Device(scanResult.id, scanResult.name);
    }
    dev.log('[Device] fromScanResult uuids: $uuids');
    if (uuids.contains(Uuid.parse(BleConstants.ESPM_API_SERVICE_UUID))) {
      return ESPM(scanResult.id, scanResult.name);
    }
    if (uuids.contains(Uuid.parse(BleConstants.ESPCC_API_SERVICE_UUID))) {
      return ESPCC(scanResult.id, scanResult.name);
    }
    if (uuids.contains(Uuid.parse(BleConstants.HOMEAUTO_API_SERVICE_UUID))) {
      return HomeAuto(scanResult.id, scanResult.name);
    }
    if (uuids.contains(Uuid.parse(BleConstants.CYCLING_POWER_SERVICE_UUID))) {
      return PowerMeter(scanResult.id, scanResult.name);
    }
    if (uuids.contains(Uuid.parse(BleConstants.HEART_RATE_SERVICE_UUID))) {
      return HeartRateMonitor(scanResult.id, scanResult.name);
    }
    dev.log('[Device] fromScanResult no uuid match');
    return Device(scanResult.id, scanResult.name);
  }

  static Future<Device?> fromSaved(String savedDevice) async {
    var chunks = savedDevice.split(";");
    if (chunks.length < 3) return null;
    String address = chunks.removeAt(0);
    String type = "";
    String name = "";
    bool autoConnect = false;
    bool saveLog = false;
    for (var chunk in chunks) {
      String key = "type=";
      if (chunk.startsWith(key)) type = chunk.substring(key.length);
      key = "name=";
      if (chunk.startsWith(key)) name = chunk.substring(key.length);
      key = "autoConnect=";
      if (chunk.startsWith(key)) autoConnect = chunk.substring(key.length) == "true";
      key = "saveLog=";
      if (chunk.startsWith(key)) saveLog = chunk.substring(key.length) == "true";
    }
    dev.log(
        "Device.fromSaved($savedDevice): address: $address, type: $type, name: $name, autoConnect: ${autoConnect ? "true" : "false"}, saveLog: ${saveLog ? "true" : "false"}");
    Device device;
    if ("ESPM" == type) {
      device = ESPM(address, name);
    } else if ("ESPCC" == type) {
      device = ESPCC(address, name);
    } else if ("HomeAuto" == type) {
      device = HomeAuto(address, name);
    } else if ("PowerMeter" == type) {
      device = PowerMeter(address, name);
    } else if ("HeartRateMonitor" == type) {
      device = HeartRateMonitor(address, name);
    } else {
      return null;
    }
    device.autoConnect.value = autoConnect;
    device.remember.value = true;
    device.saveLog.value = saveLog;
    return device;
  }

  void init() async {
    String? saved = await getSaved();
    if (null != saved) {
      remember.value = true;
      autoConnect.value = saved.contains("autoConnect=true");
      saveLog.value = saved.contains("saveLog=true");
    }

    stateSubscription ??= stateStream.listen(
      (state) async {
        logD("$name _stateSubscription state: $state");
        lastConnectionState = state;
        if (state == DeviceConnectionState.connected) {
          await onConnected();
        } else if (state == DeviceConnectionState.disconnected) {
          await onDisconnected();
        }
      },
      onError: (e) => bleError(debugTag, "$name _stateSubscription", e),
    );
    _batteryLevelSubscription ??= battery?.defaultStream.listen(
      (level) {
        logD("$name _batteryLevelSubscription level: $level%, charging: $isCharging");
        if (isCharging.asBool) notifyCharging();
      },
      onError: (e) => logD("$debugTag _batteryLevelSubscription $e"),
    );
  }

  Future<void> dispose() async {
    logD("$name dispose");
    await disconnect();
    await stateController.close();
    characteristics.forEachCharacteristic((_, char) async {
      await char?.unsubscribe();
      await char?.dispose();
    });
    await stateSubscription?.cancel();
    stateSubscription = null;
    await _stateUpdateSubscription?.cancel();
    _stateUpdateSubscription = null;
    await _batteryLevelSubscription?.cancel();
    _batteryLevelSubscription = null;
  }

  Future<bool> ready() async {
    if (!await discovered()) return false;
    if (!await subscribed()) return false;
    return true;
  }

  Future<bool> discovered() async {
    if (!connected) return false;
    var stopwatch = Stopwatch();
    while (!_discovered) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (3000 < stopwatch.elapsedMilliseconds) return false;
    }
    return true;
  }

  Future<bool> subscribed() async {
    if (!connected) return false;
    var stopwatch = Stopwatch();
    while (!_subscribed) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (3000 < stopwatch.elapsedMilliseconds) return false;
    }
    return true;
  }

  Future<void> onConnected() async {
    await discover();
    await subscribeCharacteristics();
  }

  Future<void> onDisconnected() async {
    String tag = name;
    // if (await connected) {
    //   logD("but $name is connected");
    //   return;
    // }
    await _unsubscribeCharacteristics();
    _deinitCharacteristics();
    _discovered = false;

    //streamSendIfNotClosed(stateController, newState);

    isCharging = ExtendedBool.eUnknown;
    Notifications().cancel(id.hashCode);

    logD("$tag autoConnect.value: ${autoConnect.value}");
    if (autoConnect.value && !connected) {
      await Future.delayed(const Duration(seconds: 15)).then((_) async {
        if (autoConnect.value && !connected) {
          logD("$tag calling connect()");
          await connect();
        }
      });
    }
  }

  Future<void> connect() async {
    if (connected) {
      logD("Not connecting to $name, already connected");
      //streamSendIfNotClosed(stateController, connectedState);
      //await discoverCharacteristics();
      //await _subscribeCharacteristics();
      //_requestInit();
      return;
    }
    if (await BLE().currentStatus() != BleStatus.ready) {
      logD("$name connect() Adapter is not ready, not connecting");
      //streamSendIfNotClosed(stateController, disconnectedState);
      return;
    }
    if (_connectionInitiated) {
      logD("$name connect() Connection already initiated");
      return;
    }
    //logD("connect() Connecting to $name(${peripheral!.identifier})");
    _connectionInitiated = true;
    _stateUpdateSubscription = (await BLE().manager)
/* 
        .connectToAdvertisingDevice(
      id: id,
      withServices: [],
      prescanDuration: const Duration(seconds: 5),
      connectionTimeout: const Duration(seconds: 2),
    )
*/
        .connectToDevice(
      id: id,
      servicesWithCharacteristicsToDiscover: null,
      connectionTimeout: const Duration(seconds: 2),
    )
        .listen(
      (stateUpdate) async {
        logD("connection state update: $stateUpdate");
        if (stateUpdate.failure != null) {
          logD("Failure: ${stateUpdate.failure}");
        }
        streamSendIfNotClosed(stateController, stateUpdate.connectionState);
      },
      onError: (Object e, StackTrace t) => bleError(debugTag, "$name _stateSubscription $t", e),
    );
    //logD("peripheral.connect() returned");
    _connectionInitiated = false;
  }

  Future<void> discover() async {
    String subject = "$debugTag discoverCharacteristics()";
    //logD("$subject conn=${await connected}");
    if (!connected) {
      logD("$name not connected, $lastConnectionState");
      //return;
    }
    if (_discovered) {
      logD("$name already discovered");
      return;
    }
    //logD("$subject discoverAllServicesAndCharacteristics() start");
    var manager = await BLE().manager;
    await manager
        .discoverAllServices(id) // TODO isn't discovery done automatically in connectToBlaBla?
        .catchError((e) {
      bleError(debugTag, "discoverAllServices()", e);
    });
    var services = await manager.getDiscoveredServices(id).catchError((e) {
      bleError(debugTag, "getDiscoveredServices()", e);
      return List<Service>.empty();
    });
    //logD("$subject getDiscoveredServices() end");
    Map<Uuid, List<Uuid>> uuidMap = {};
    for (var s in services) {
      List<Uuid> charList = [];
      for (var c in s.characteristics) {
        characteristics.byUuid(c.service.id, c.id)?.characteristic = c;
        charList.add(c.id);
      }
      uuidMap.addAll({s.id: charList});
    }
    logD("$subject end services: $uuidMap");
    _discovered = true;
  }

  Future<FlutterReactiveBle> get manager async => await BLE().manager;

  /// FlutterReactiveBle services
  Future<List<Service>> get frbServices async {
    if (!await discovered()) {
      logD("$name not discovered");
      return List<Service>.empty();
    }
    return await (await manager).getDiscoveredServices(id).catchError((e) {
      bleError(debugTag, "getDiscoveredServices()", e);
      return List<Service>.empty();
    });
  }

  /// FlutterReactiveBle service
  Future<Service?> frbService(Uuid uuid) async {
    Service? s;
    for (var e in (await frbServices)) {
      if (e.id == uuid) {
        s = e;
        continue;
      }
    }
    return s;
  }

  /// FlutterReactiveBle characteristics
  Future<List<Characteristic>> frbCharacteristics(Uuid serviceUuid) async => (await frbService(serviceUuid))?.characteristics ?? List<Characteristic>.empty();

  /// FlutterReactiveBle characteristic
  Future<Characteristic?> frbCharacteristic(Uuid serviceUuid, Uuid characteristicUuid) async {
    Characteristic? c;
    (await frbService(serviceUuid))?.characteristics.forEach((e) {
      if (e.id == characteristicUuid) {
        c = e;
        return;
      }
    });
    return c;
  }

  Future<void> subscribeCharacteristics() async {
    logD('$name subscribeCharacteristics start');
    if (!await discovered()) return;
    await characteristics.forEachListItem((name, item) async {
      if (item.subscribeOnConnect) {
        if (null == item.characteristic) return;
        logD('_subscribeCharacteristics $name ${item.characteristic?.charUUID} start');
        await item.characteristic?.subscribe();
        logD('_subscribeCharacteristics $name ${item.characteristic?.charUUID} end');
      }
    });
    _subscribed = true;
    logD('subscribeCharacteristics end');
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
    logD("disconnect() $name");
    if (!connected) {
      logD("not connected, $lastConnectionState");
      //return;
    }
    streamSendIfNotClosed(stateController, DeviceConnectionState.disconnecting);
    // Disconnecting the device is achieved by cancelling the stream subscription
    await _stateUpdateSubscription?.cancel();
    streamSendIfNotClosed(stateController, DeviceConnectionState.disconnected);
  }

  BleCharacteristic? characteristic(String name) {
    return characteristics.get(name);
  }

  void setAutoConnect(bool value) async {
    autoConnect.value = value;
    await updatePreferences();
    // resend last connection state to trigger connect button update
    // streamSendIfNotClosed(_stateController, lastConnectionState);
    if (value && !connected) connect();
  }

  void setRemember(bool value) async {
    remember.value = value;
    await updatePreferences();
  }

  void setSaveLog(bool value) async {
    if (!saveLog.value && value) {
      characteristics.get("apiLog")?.subscribe();
    } else if (saveLog.value && !value) {
      characteristics.get("apiLog")?.unsubscribe();
    }
    saveLog.value = value;
    await updatePreferences();
  }

  Future<void> updatePreferences() async {
    List<String> devices = (await Preferences().getDevices()).value;
    logD('updatePreferences savedDevices before: $devices');
    devices.removeWhere((item) => item.startsWith(id));
    if (remember.value) {
      String item =
          "$id;name=${name.replaceAll(RegExp(r';'), '')};type=$runtimeType;autoConnect=${autoConnect.value ? "true" : "false"};saveLog=${saveLog.value ? "true" : "false"}";
      logD('updatePreferences item: $item');
      devices.add(item);
    }
    Preferences().setDevices(devices);
    logD('updatePreferences savedDevices after: $devices');
  }

  Future<String?> getSaved() async {
    var devices = (await Preferences().getDevices()).value;
    String item = devices.firstWhere((item) => item.startsWith(id), orElse: () => "");
    return "" == item ? null : item;
  }

  Future<int?> requestMtu(int mtu) => BLE().requestMtu(this, mtu);

  Future<Type> correctType() async {
    return runtimeType;
  }

  Future<bool> isCorrectType() async {
    return runtimeType == await correctType();
  }

  Future<Device> copyToCorrectType() async {
    return this;
  }

  IconData get iconData => const DeviceIcon(null).data();

  void notifyCharging() {
    bool charging = isCharging.asBool;
    String status = charging ? "charging" : "charge end";
    int progress = battery?.lastValue ?? -1;
    bool showProgress = progress != -1;

    Notifications().cancel(id.hashCode);

    logD("$name notifyCharging() battery charging: $charging");

    Notifications().notify(
      name.isNotEmpty ? name : "unknown device",
      status,
      id: id.hashCode,
      channelId: status,
      playSound: !charging,
      enableVibration: !charging,
      showProgress: showProgress,
      progress: progress,
      maxProgress: 100,
      ongoing: charging,
      onlyAlertOnce: true,
    );
  }

  void onCommandAdded(String command) {}
}

mixin DeviceWithApi on Device {
  late Api api;
  StreamSubscription<ApiMessage>? apiSubsciption;
  ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;

  void deviceWithApiConstruct({
    required ApiCharacteristic characteristic,
    required Future<bool> Function(ApiMessage message) handler,
    required String serviceUuid,
  }) {
    characteristics.addAll({
      'api': CharacteristicListItem(
        characteristic,
      ),
      'apiLog': CharacteristicListItem(
        ApiLogCharacteristic(this, serviceUuid),
        subscribeOnConnect: saveLog.value,
      )
    });

    api = Api(this, queueDelayMs: 50);
    apiSubsciption = api.messageSuccessStream.listen((m) => handler(m));
  }

  Future<void> apiOnDisconnected() async {
    api.reset();
  }

  Future<void> apiDispose() async {
    logD("$name dispose");
    apiSubsciption?.cancel();
  }
}

mixin DeviceWithWifi on Device {
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());

  /// returns true if the message does not need any further handling
  Future<bool> wifiHandleApiMessageSuccess(ApiMessage message) async {
    if (await wifiSettings.value.handleApiMessageSuccess(message)) {
      wifiSettings.notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> wifiOnDisconnected() async {
    logD("$name onDisconnected()");
    wifiSettings.value = WifiSettings();
    wifiSettings.notifyListeners();
  }

  Future<void> wifiDispose() async {
    logD("$name dispose");
  }
}

mixin DeviceWithPeers on Device {
  final peerSettings = AlwaysNotifier<PeerSettings>(PeerSettings());

  /// returns true if the message does not need any further handling
  Future<bool> peerHandleApiMessageSuccess(ApiMessage message) async {
    if (await peerSettings.value.handleApiMessageSuccess(message)) {
      peerSettings.notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> peerOnDisconnected() async {
    logD("$name onDisconnected()");
    peerSettings.value = PeerSettings();
    peerSettings.notifyListeners();
  }

  Future<void> peerDispose() async {
    logD("$name dispose");
  }
}

class PowerMeter extends Device {
  PowerCharacteristic? get power => characteristic("power") as PowerCharacteristic?;

  PowerMeter(super.id, super.name) {
    characteristics.addAll({
      'power': CharacteristicListItem(PowerCharacteristic(this)),
    });
    tileStreams.addAll({
      "power": DeviceTileStream(
        label: "Power",
        stream: power?.powerStream.map<Widget>((value) => Text(value.toString())),
        initialData: () => Text(power?.lastPower.toString() ?? ' '),
        units: "W",
        history: power?.histories['power'],
      ),
    });
    tileStreams.addAll({
      "cadence": DeviceTileStream(
        label: "Cadence",
        stream: power?.cadenceStream.map<Widget>((value) => Text(value.toString())),
        initialData: () => Text(power?.lastCadence.toString() ?? ' '),
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
    if (!await discovered()) return t;
    logD("_correctType 2");
    for (var s in (await frbServices)) {
      if (s.id == Uuid.parse(BleConstants.ESPM_API_SERVICE_UUID)) {
        logD("correctType() ESPM detected");
        t = ESPM;
        continue;
      }
    }
    return t;
  }

  @override
  Future<Device> copyToCorrectType() async {
    Type t = await correctType();
    logD("copyToCorrectType $t");
    Device device = this;
    if (ESPM == t) {
      device = ESPM(id, name);
      device.autoConnect.value = autoConnect.value;
      device.remember.value = remember.value;
    } else {
      return this;
    }
    return device;
  }

  @override
  IconData get iconData => const DeviceIcon("PM").data();
}

class HeartRateMonitor extends Device {
  HeartRateCharacteristic? get heartRate => characteristic("heartRate") as HeartRateCharacteristic?;

  HeartRateMonitor(super.id, super.name) {
    characteristics.addAll({
      'heartRate': CharacteristicListItem(HeartRateCharacteristic(this)),
    });
    tileStreams.addAll({
      "heartRate": DeviceTileStream(
        label: "Heart Rate",
        stream: heartRate?.defaultStream.map<Widget>((value) => Text(value.toString())),
        initialData: () => Text(heartRate?.lastValueToString() ?? ' '),
        units: "bpm",
        history: heartRate?.histories['measurement'],
      ),
    });
  }

  @override
  IconData get iconData => const DeviceIcon("HRM").data();
}

class WifiSettings with Debug {
  var enabled = ExtendedBool.eUnknown;
  var apEnabled = ExtendedBool.eUnknown;
  String? apSSID;
  String? apPassword;
  var staEnabled = ExtendedBool.eUnknown;
  String? staSSID;
  String? staPassword;

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //logD("handleApiDoneMessage $message");

    //////////////////////////////////////////////////// wifi
    if ("w" == message.commandStr) {
      enabled = message.valueAsBool == true ? ExtendedBool.eTrue : ExtendedBool.eFalse;
      return true;
    }

    //////////////////////////////////////////////////// wifiAp
    if ("wa" == message.commandStr) {
      apEnabled = message.valueAsBool == true ? ExtendedBool.eTrue : ExtendedBool.eFalse;
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
      staEnabled = message.valueAsBool == true ? ExtendedBool.eTrue : ExtendedBool.eFalse;
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

  @override
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

class PeerSettings with Debug {
  List<String> peers = [];
  List<String> scanResults = [];
  bool scanning = false;
  Map<String, TextEditingController> peerPasskeyEditingControllers = {};

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "PeerSettings.handleApiMessageSuccess";
    //logD("$tag $message");

    if ('peers' != message.commandStr) return false;

    String valueS = message.valueAsString ?? '';
    logD('$tag value: $valueS');

    // no arg: list of peers
    if (!valueS.startsWith("scan:") &&
        !valueS.startsWith("scanResult:") &&
        !valueS.startsWith("add:") &&
        !valueS.startsWith("delete:") &&
        !valueS.startsWith("disable:") &&
        !valueS.startsWith("enable:")) {
      List<String> tokens = valueS.split("|");
      List<String> values = [];
      for (var token in tokens) {
        if (token.isEmpty) continue;
        values.add(token);
      }
      logD("$tag peers=$values");
      peers = values;
      return true;
    }
    if (valueS.startsWith("scan:")) {
      int? timeout = int.tryParse(valueS.substring("scan:".length));
      logD("$tag peers=scan:$timeout");
      scanning = null != timeout && 0 < timeout;
      return true;
    }
    if (valueS.startsWith("scanResult:")) {
      String result = valueS.substring("scanResult:".length);
      logD("$tag scanResult: received $result");
      if (result.isEmpty) return false;
      if (scanResults.contains(result)) return false;
      scanResults.add(result);
      return true;
    }
    if (valueS.startsWith('add:')) {
      logD('$tag add not implemented (value: $valueS)');
      return true;
    }
    if (valueS.startsWith('delete:')) {
      logD('$tag delete not implemented (value: $valueS)');
      return true;
    }
    if (valueS.startsWith('enable:')) {
      logD('$tag enable not implemented (value: $valueS)');
      return true;
    }
    if (valueS.startsWith('disable:')) {
      logD('$tag disable not implemented (value: $valueS)');
      return true;
    }

    return false;
  }

  @override
  bool operator ==(other) {
    return (other is PeerSettings) && other.peers == peers;
  }

  @override
  int get hashCode => peers.hashCode;

  @override
  String toString() {
    return "${describeIdentity(this)} (peers: $peers)";
  }

  TextEditingController? getController({String? peer, String? initialValue}) {
    if (null == peer || peer.isEmpty) return null;
    if (null == peerPasskeyEditingControllers[peer]) peerPasskeyEditingControllers[peer] = TextEditingController(text: initialValue);
    return peerPasskeyEditingControllers[peer];
  }

  void dispose() {
    peerPasskeyEditingControllers.forEach((_, value) {
      value.dispose();
    });
  }
}

class DeviceTileStream {
  String? label;
  Stream<Widget>? stream;
  Widget Function()? initialData;
  String? units;
  History? history;

  DeviceTileStream({
    required this.label,
    required this.stream,
    required this.initialData,
    this.units,
    this.history,
  });
}

class DeviceTileAction {
  Device? device;
  String label;
  Function(BuildContext context, Device? device) action;

  DeviceTileAction({
    required this.label,
    required this.action,
    this.device,
  });

  void call(BuildContext context) {
    action(context, device);
  }
}

class History<T> with Debug {
  final _data = <int, T>{};
  final int maxEntries;

  /// <0: no limit
  final int maxAge;

  final bool absolute;

  /// The oldest entries will be deleted when either
  /// - the number of entries exceeds [maxEntries]
  /// - or the age of the entry in seconds is greater than [maxAge].
  History({this.maxEntries = 3600, this.maxAge = -1, this.absolute = false});

  /// Append a value to the history.
  /// - [timestamp]: milliseconds since Epoch
  void append(T value, {int? timestamp}) {
    timestamp ??= uts();
    //logD("append timestamp: $timestamp value: $value length: ${_data.length}");
    if (absolute) {
      if (value.runtimeType == int) value = int.tryParse(value.toString())?.abs() as T;
      if (value.runtimeType == double) value = double.tryParse(value.toString())?.abs() as T;
    }
    _data[timestamp] = value;
    // Prune on every ~100 appends
    if (.99 < Random().nextDouble()) {
      if (.5 < Random().nextDouble()) {
        while (maxEntries < _data.length) {
          _data.remove(_data.entries.first.key);
        }
      } else if (0 <= maxAge) {
        _data.removeWhere((time, _) => time < uts() - maxAge * 1000);
      }
    }
  }

  /// [timestamp] is milliseconds since the Epoch
  Map<int, T> since({required int timestamp}) {
    Map<int, T> filtered = Map.of(_data);
    filtered.removeWhere((time, _) => time < timestamp);
    //logD("since  timestamp: $timestamp data: ${_data.length} filtered: ${filtered.length}");
    return filtered;
  }

  /// [timestamp] is milliseconds since the Epoch
  Widget graph({required int timestamp, Color? color}) {
    Map<int, T> filtered = since(timestamp: timestamp);
    if (filtered.isEmpty) return const Empty();
    var data = Map<int, num>.from(filtered);
    double? min;
    double? max;
    data.forEach((_, val) {
      if (null == min || val < min!) min = val.toDouble();
      if (null == max || max! < val) max = val.toDouble();
    });
    //logD("min: $min max: $max");
    if (null == min || null == max) return const Empty();
    var widgets = <Widget>[];
    Color outColor = color ?? Colors.red;
    data.forEach((time, value) {
      var height = map(value.toDouble(), min!, max!, 0, 1000);
      widgets.add(Container(
        width: 50,
        height: (0 < height) ? height : 1,
        color: outColor, //.withOpacity((0 < height) ? .5 : 0),
        margin: const EdgeInsets.all(1),
      ));
    });
    if (widgets.isEmpty) return const Empty();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: widgets,
    );
  }
}
