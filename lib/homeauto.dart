import 'dart:async';
//import 'dart:io';
//import 'dart:math';
// import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:sprintf/sprintf.dart';
//import 'package:listenable_stream/listenable_stream.dart';
import 'package:intl/intl.dart';
//mport 'package:mutex/mutex.dart';

import 'device.dart';
import 'api.dart';
//import 'ble.dart';
import 'ble_characteristic.dart';
import 'ble_constants.dart';
import 'device_widgets.dart';

import 'util.dart';
import 'debug.dart';

class HomeAuto extends Device {
  late Api api;
  final settings = AlwaysNotifier<HomeAutoSettings>(HomeAutoSettings());
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());
  //ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;
  StreamSubscription<ApiMessage>? _apiSubsciption;
  //Stream<HomeAutoSettings>? _settingsStream;
  Map<String, HomeAutoSwitch> switches = {};
  StreamSubscription<Map<String, HomeAutoSwitch>>? _switchesSubsciption;
  Stream<Map<String, HomeAutoSwitch>>? _switchesStream;

  @override
  int get defaultMtu => 512;

  @override
  int get largeMtu => 512;

  HomeAuto(Peripheral peripheral) : super(peripheral) {
    characteristics.addAll({
      'api': CharacteristicListItem(
        HomeAutoApiCharacteristic(this),
      ),
    });
    characteristics.addAll({
      'apiLog': CharacteristicListItem(
        ApiLogCharacteristic(this, BleConstants.HOMEAUTO_API_SERVICE_UUID),
        subscribeOnConnect: saveLog.value,
      ),
    });
    api = Api(this, queueDelayMs: 50);
    _apiSubsciption = api.messageSuccessStream.listen((m) => handleApiMessageSuccess(m));
    //_settingsStream = settings.toValueStream().asBroadcastStream();
  }

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //String tag = "";
    //logD("$tag $message");

    if (await wifiSettings.value.handleApiMessageSuccess(message)) {
      wifiSettings.notifyListeners();
      return true;
    }

    if (await settings.value.handleApiMessageSuccess(message)) {
      settings.notifyListeners();
      return true;
    }

    if ("switch" == message.command) {
      logD("todo parse and stream switch=${message.valueAsString}");
      return true;
    }

    //snackbar("${message.info} ${message.command}");
    logD("unhandled api response: $message");

    return false;
  }

  Future<void> dispose() async {
    logD("$name dispose");
    _apiSubsciption?.cancel();
    _switchesSubsciption?.cancel();
    super.dispose();
  }

  Future<void> onConnected() async {
    logD("_onConnected()");
    // api char can use values longer than 20 bytes
    await requestMtu(512);
    await super.onConnected();
    _requestInit();
  }

  Future<void> onDisconnected() async {
    logD("$name onDisconnected()");
    // if (await connected) {
    //   logD("but $name is connected");
    //   return;
    // }

    settings.value = HomeAutoSettings();
    settings.notifyListeners();
    wifiSettings.value = WifiSettings();
    wifiSettings.notifyListeners();
    api.reset();
    await super.onDisconnected();
  }

  /// request initial values, returned value is discarded
  /// because the message.done subscription will handle it
  void _requestInit() async {
    logD("Requesting init start");
    if (!await ready()) return;
    //await characteristic("api")?.write("init");

    await api.request<String>(
      "init",
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    //await Future.delayed(Duration(milliseconds: 250));
  }

  @override
  IconData get iconData => DeviceIcon("HomeAuto").data();
}

class HomeAutoSettings with Debug {
  List<String> peers = [];
  List<String> scanResults = [];
  bool scanning = false;
  bool otaMode = false;
  Map<String, TextEditingController> peerPasskeyEditingControllers = {};

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "";
    //logD("$tag $message");
    String? valueS = message.valueAsString;

    if ("peers" == message.commandStr &&
        valueS != null &&
        !valueS.startsWith("scan:") &&
        !valueS.startsWith("scanResult:") &&
        !valueS.startsWith("add:") &&
        !valueS.startsWith("delete:")) {
      String? v = message.valueAsString;
      if (null == v) return false;
      List<String> tokens = v.split("|");
      List<String> values = [];
      tokens.forEach((token) {
        if (token.length < 1) return;
        values.add(token);
      });
      logD("$tag peers=$values");
      peers = values;
      return true;
    }

    if ("peers" == message.commandStr && message.valueAsString != null && message.valueAsString!.startsWith("scanResult:")) {
      String result = message.valueAsString!.substring("scanResult:".length);
      logD("$tag scanResult: received $result");
      if (0 == result.length) return false;
      if (scanResults.contains(result)) return false;
      scanResults.add(result);
      return true;
    }

    if ("peers" == message.commandStr && message.valueAsString != null && message.valueAsString!.startsWith("scan:")) {
      int? timeout = int.tryParse(message.valueAsString!.substring("scan:".length));
      logD("$tag peers=scan:$timeout");
      scanning = null != timeout && 0 < timeout;
      return true;
    }

    if ("system" == message.commandStr) {
      if ("ota" == message.valueAsString) {
        otaMode = true;
        return true;
      }
      return false;
    }

    return false;
  }

  @override
  bool operator ==(other) {
    return (other is HomeAutoSettings) && other.peers == peers && other.scanning == scanning && other.otaMode == otaMode;
  }

  @override
  int get hashCode => peers.hashCode ^ scanning.hashCode ^ otaMode.hashCode;
  String toString() {
    return "${describeIdentity(this)} ("
        "peers: $peers, "
        "scanning: $scanning, "
        "otaMode: $otaMode, "
        ")";
  }

  TextEditingController? getController({String? peer, String? initialValue}) {
    if (null == peer || peer.length <= 0) return null;
    if (null == peerPasskeyEditingControllers[peer]) peerPasskeyEditingControllers[peer] = TextEditingController(text: initialValue);
    return peerPasskeyEditingControllers[peer];
  }

  void dispose() {
    peerPasskeyEditingControllers.forEach((_, value) {
      value.dispose();
    });
  }
}

class HomeAutoSwitch {
  int? mode;
  int? state;
  double? voltageOn;
  double? voltageOff;
  int? socOn;
  int? socOff;
}

class HomeAutoSwitchMode {
  static const int Off = 0;
  static const int On = 1;
  static const int Voltage = 2;
  static const int Soc = 3;
}

class HomeAutoSwitchState {
  static const int Off = 0;
  static const int On = 1;
}

/*
  Epever:
    struct __attribute__((packed)) DataPoint {
        ulong time = 0;          //
        uint16_t pv_volt = 0;    // length: 2; unit: V * 100
        uint16_t pv_amp = 0;     // length: 2; unit: A * 100
        uint32_t pv_watt = 0;    // length: 4; unit: W * 100
        uint16_t batt_volt = 0;  // length: 2; unit: V * 100
        uint16_t batt_amp = 0;   // length: 2; unit: A * 100
        uint16_t load_amp = 0;   // length: 2; unit: A * 100
        uint32_t load_watt = 0;  // length: 4; unit: W * 100
    };

  JkBms:
    struct CellInfo {
        ulong lastUpdate = 0;

        struct Cell {
            float voltage = 0.0f;
            float resistance = 0.0f;
        } cells[32];

        float cellVoltageMin = 0.0f;
        float cellVoltageMax = 0.0f;
        float cellVoltageAvg = 0.0f;
        float cellVoltageDelta = 0.0f;
        uint8_t cellVoltageMinId = 0;
        uint8_t cellVoltageMaxId = 0;

        float temp0 = 0.0f;
        float temp1 = 0.0f;
        float temp2 = 0.0f;

        float voltage = 0.0f;
        float chargeCurrent = 0.0f;
        float power = 0.0f;
        float powerCharge = 0.0f;
        float powerDischarge = 0.0f;

        float balanceCurrent = 0.0f;

        uint8_t soc = 0;
        float capacityRemaining = 0.0f;
        float capacityNominal = 0.0f;
        uint32_t cycleCount = 0;
        float capacityCycle = 0.0f;
        uint32_t totalRuntime = 0;

        bool chargingEnabled = false;
        bool dischargingEnabled = false;

        char errors[512] = "";
    } 

*/
class HomeAutoDataPoint with Debug {
  static const String _tag = "HomeAutoDataPoint";
  static const Endian _endian = Endian.little;

  var _flags = Uint8List(1);
  var _time = Uint8List(4);
  var _lat = Uint8List(8);
  var _lon = Uint8List(8);
  var _alt = Uint8List(2);
  var _power = Uint8List(2);
  var _cadence = Uint8List(1);
  var _heartrate = Uint8List(1);
  var _temperature = Uint8List(2);

  bool fromList(Uint8List bytes) {
    String tag = "$_tag";
    if (bytes.length < sizeInBytes) {
      logD("$tag incorrect length: ${bytes.length}, need at least $sizeInBytes");
      return false;
    }
    //logD("$tag $bytes");
    int cursor = 0;
    _flags = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    _time = bytes.sublist(cursor, cursor + 4);
    cursor += 4;
    if (locationFlag) _lat = bytes.sublist(cursor, cursor + 8);
    cursor += 8;
    if (locationFlag) _lon = bytes.sublist(cursor, cursor + 8);
    cursor += 8;
    if (altitudeFlag) _alt = bytes.sublist(cursor, cursor + 2);
    cursor += 2;
    if (powerFlag) _power = bytes.sublist(cursor, cursor + 2);
    cursor += 2;
    if (cadenceFlag) _cadence = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    if (heartrateFlag) _heartrate = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    if (temperatureFlag) _temperature = bytes.sublist(cursor, cursor + 2);
    return true;
  }

  bool from(HomeAutoDataPoint p) {
    _flags = Uint8List.fromList(p.flagsList);
    _time = Uint8List.fromList(p.timeList);
    _lat = Uint8List.fromList(p.latList);
    _lon = Uint8List.fromList(p.lonList);
    _alt = Uint8List.fromList(p.altList);
    _power = Uint8List.fromList(p.powerList);
    _cadence = Uint8List.fromList(p.cadenceList);
    _heartrate = Uint8List.fromList(p.heartrateList);
    _temperature = Uint8List.fromList(p.temperatureList);
    return true;
  }

  /// 2022-01-01 00:00:00 < time < 2122-01-01 00:00:00
  bool get hasTime {
    int t = time;
    return 1640995200 < t && t < 4796668800;
  }

  bool get locationFlag => 0 < _flags[0] & HomeAutoDataPointFlags.location;
  bool get hasLocation {
    if (!locationFlag) return false;
    double d = lat;
    if (d < 0 || 90 < d) return false;
    d = lon;
    if (d < 0 || 180 < d) return false;
    return true;
  }

  bool get altitudeFlag => 0 < _flags[0] & HomeAutoDataPointFlags.altitude;
  set altitudeFlag(bool b) => _flags[0] |= b ? HomeAutoDataPointFlags.altitude : ~HomeAutoDataPointFlags.altitude;
  bool get hasAltitude {
    if (!altitudeFlag) return false;
    int i = alt;
    return (-500 < i && i < 10000);
  }

  bool get powerFlag => 0 < _flags[0] & HomeAutoDataPointFlags.power;
  set powerFlag(bool b) => _flags[0] |= b ? HomeAutoDataPointFlags.power : ~HomeAutoDataPointFlags.power;
  bool get hasPower {
    if (!powerFlag) return false;
    int i = power;
    return (0 <= i && i < 3000);
  }

  bool get cadenceFlag => 0 < _flags[0] & HomeAutoDataPointFlags.cadence;
  set cadenceFlag(bool b) => _flags[0] |= b ? HomeAutoDataPointFlags.cadence : ~HomeAutoDataPointFlags.cadence;
  bool get hasCadence {
    if (!cadenceFlag) return false;
    int i = cadence;
    return (0 <= i && i < 200);
  }

  bool get heartrateFlag => 0 < _flags[0] & HomeAutoDataPointFlags.heartrate;
  set heartrateFlag(bool b) => _flags[0] |= b ? HomeAutoDataPointFlags.heartrate : ~HomeAutoDataPointFlags.heartrate;
  bool get hasHeartrate {
    //String tag = "$_tag";
    //logD("$tag flags: ${_flags[0]}");
    if (!heartrateFlag) return false;
    int i = heartrate;
    //logD("$tag heartrate: $i");
    return (30 <= i && i < 230);
  }

  bool get temperatureFlag => 0 < _flags[0] & HomeAutoDataPointFlags.temperature;
  set temperatureFlag(bool b) => _flags[0] |= b ? HomeAutoDataPointFlags.temperature : ~HomeAutoDataPointFlags.temperature;
  bool get hasTemperature {
    if (!temperatureFlag) return false;
    double f = temperature;
    return (-50 <= f && f < 70);
  }

  bool get hasLap => 0 < _flags[0] & HomeAutoDataPointFlags.lap;

  int get flags => _flags.buffer.asByteData().getUint8(0);
  Uint8List get flagsList => _flags;
  int get time => _time.buffer.asByteData().getInt32(0, _endian);
  Uint8List get timeList => _time;
  double get lat => _lat.buffer.asByteData().getFloat64(0, _endian);
  Uint8List get latList => _lat;
  set lat(double f) => _lat.buffer.asByteData().setFloat64(0, f, _endian);
  double get lon => _lon.buffer.asByteData().getFloat64(0, _endian);
  Uint8List get lonList => _lon;
  set lon(double f) => _lon.buffer.asByteData().setFloat64(0, f, _endian);
  int get alt => _alt.buffer.asByteData().getInt16(0, _endian);
  Uint8List get altList => _alt;
  set alt(int i) => _alt.buffer.asByteData().setInt16(0, i, _endian);
  int get power => _power.buffer.asByteData().getUint16(0, _endian);
  Uint8List get powerList => _power;
  set power(int i) => _power.buffer.asByteData().setUint16(0, i, _endian);
  int get cadence => _cadence.buffer.asByteData().getUint8(0);
  Uint8List get cadenceList => _cadence;
  set cadence(int i) => _cadence.buffer.asByteData().setUint8(0, i);
  int get heartrate => _heartrate.buffer.asByteData().getUint8(0);
  Uint8List get heartrateList => _heartrate;
  set heartrate(int i) => _heartrate.buffer.asByteData().setUint8(0, i);
  double get temperature => _temperature.buffer.asByteData().getInt16(0, _endian) / 100;
  Uint8List get temperatureList => _temperature;
  set temperature(double f) => _temperature.buffer.asByteData().setInt16(0, (f * 100).toInt(), _endian);

  /// example: 2022-03-25T12:58:13Z
  String get timeAsIso8601 => DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true));

  /// example: 2022-03-25T12:58:13.000Z
  //String get timeAsIso8601 => DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true).toIso8601String();

  String get debug => "flags: ${_flags.toList()}, time: ${_time.toList()}, ";

  /*
  set flags(int v) {
    if (v < 0 || 255 < v) {
      logD("$_tag set flags out of range: $v");
      return;
    }
    _flags.buffer.asByteData().setUint8(0, v);
  }
  set time(int v) {
    if (v < -2147483648 || 2147483647 < v) {
      logD("$_tag set time out of range: $v");
      return;
    }
    _time.buffer.asByteData().setInt32(0, v, _endian);
  }
  ...
  */

  int get sizeInBytes =>
      _flags.length + //
      _time.length +
      _lat.length +
      _lon.length +
      _alt.length +
      _power.length +
      _cadence.length +
      _heartrate.length +
      _temperature.length;
}

/*
    struct Flags {
        const byte location = 1;
        const byte altitude = 2;
        const byte power = 4;
        const byte cadence = 8;
        const byte heartrate = 16;
        const byte temperature = 32;  
        const byte lap = 64;          // unused
    } const Flags;
*/
class HomeAutoDataPointFlags {
  static const int location = 1;
  static const int altitude = 2;
  static const int power = 4;
  static const int cadence = 8;
  static const int heartrate = 16;
  static const int temperature = 32;
  static const int lap = 64;
}
