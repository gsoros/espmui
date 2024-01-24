import 'dart:async';
//import 'dart:html';
//import 'dart:io';
//import 'dart:math';
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:sprintf/sprintf.dart';
//import 'package:listenable_stream/listenable_stream.dart';
import 'package:intl/intl.dart';
//mport 'package:mutex/mutex.dart';
import 'package:page_transition/page_transition.dart';

import 'device.dart';
import 'api.dart';
//import 'ble.dart';
import 'ble_characteristic.dart';
import 'ble_constants.dart';
import 'device_widgets.dart';
import 'device_route.dart';

import 'util.dart';
import 'debug.dart';

class HomeAuto extends Device with DeviceWithApi, DeviceWithWifi, DeviceWithPeers {
  late final AlwaysNotifier<HomeAutoSettings> settings;
  //Stream<HomeAutoSettings>? _settingsStream;

  final switchesTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get switchesTileStream => switchesTileStreamController.stream;
  final voltageTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get voltageTileStream => voltageTileStreamController.stream;
  final currentTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get currentTileStream => currentTileStreamController.stream;
  final powerTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get powerTileStream => powerTileStreamController.stream;
  final cellsTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get cellsTileStream => cellsTileStreamController.stream;

  @override
  int get defaultMtu => 512;

  @override
  int get largeMtu => 512;

  HomeAuto(Peripheral peripheral) : super(peripheral) {
    settings = AlwaysNotifier<HomeAutoSettings>(
      HomeAutoSettings(
        switchesTileStreamController,
        voltageTileStreamController,
        currentTileStreamController,
        powerTileStreamController,
        cellsTileStreamController,
      ),
    );

    deviceWithApiConstruct(
      characteristic: HomeAutoApiCharacteristic(this),
      handler: handleApiMessageSuccess,
      serviceUuid: BleConstants.HOMEAUTO_API_SERVICE_UUID,
    );

    tileStreams.addAll({
      'switches': DeviceTileStream(
        label: 'Switches',
        stream: switchesTileStream,
        initialData: () => settings.value.switches.asTile,
      ),
      'voltage': DeviceTileStream(
        label: 'Voltage',
        units: 'V',
        stream: voltageTileStream,
        initialData: () => settings.value.bms.voltageTile,
        history: settings.value.bms.voltageHistory,
      ),
      'current': DeviceTileStream(
        label: 'Current',
        units: 'A',
        stream: currentTileStream,
        initialData: () => settings.value.bms.currentTile,
        history: settings.value.bms.currentHistory,
      ),
      'power': DeviceTileStream(
        label: 'Power',
        units: 'W',
        stream: powerTileStream,
        initialData: () => settings.value.bms.powerTile,
        history: settings.value.bms.powerHistory,
      ),
      'cells': DeviceTileStream(
        label: 'Cells',
        stream: cellsTileStream,
        initialData: () => settings.value.bms.cellsTile,
      ),
    });
    tileActions.addAll({
      "switchesSettings": DeviceTileAction(
        label: "Open Switches Settings",
        device: this,
        action: (context, device) {
          if (null == device) return;
          Navigator.push(
            context,
            PageTransition(
              type: PageTransitionType.rightToLeft,
              child: DeviceRoute(device, focus: 'switches', open: ['settings', 'switches']),
            ),
          );
        },
      ),
    });
  }

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //String tag = "handleApiMessageSuccess";
    //logD("$tag $message");

    if (await wifiHandleApiMessageSuccess(message)) return true;
    if (await peerHandleApiMessageSuccess(message)) return true;

    if (await settings.value.handleApiMessageSuccess(message)) {
      settings.notifyListeners();
      return true;
    }

    logD("unhandled: $message");
    return false;
  }

  Future<void> dispose() async {
    logD("$name dispose");
    switchesTileStreamController.close();
    voltageTileStreamController.close();
    currentTileStreamController.close();
    powerTileStreamController.close();
    cellsTileStreamController.close();
    await apiDispose();
    await wifiDispose();
    await peerDispose();
    super.dispose();
  }

  Future<void> onConnected() async {
    logD("_onConnected()");
    // api char can use values longer than 20 bytes
    await requestMtu(512);
    logD("calling super.onConnected()");
    await super.onConnected();
    logD("calling _requestInit()");
    _requestInit();
  }

  Future<void> onDisconnected() async {
    logD("$name onDisconnected()");
    await settings.value.onDisconnected();
    settings.notifyListeners();
    await apiOnDisconnected();
    await wifiOnDisconnected();
    await peerOnDisconnected();
    await super.onDisconnected();
  }

  /// request initial values, returned value is discarded
  /// because the message.done subscription will handle it
  void _requestInit() async {
    logD('Requesting init');
    if (!await ready()) return;
    //await characteristic("api")?.write("init");

    await api.request<String>(
      'init',
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    /*
    await Future.delayed(Duration(seconds: 2));
    await api.request<String>(
      "ep=dump",
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    await Future.delayed(Duration(seconds: 2));
    await api.request<String>(
      "ci=delay:2000",
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    */
  }

  @override
  IconData get iconData => DeviceIcon('HomeAuto').data();

  @override
  void onCommandAdded(String command) {
    if ('switch' == command) api.sendCommand('switch=all');
    if ('ep' == command) api.sendCommand('ep=dump');
    if ('ci' == command) api.sendCommand('ci=delay:2000');
  }
}

class HomeAutoSettings with Debug {
  bool otaMode = false;
  final switches = HomeAutoSwitches();
  final epever = EpeverSettings();
  final bms = Bms();
  StreamController<Widget> switchesTileStreamController;
  StreamController<Widget> voltageTileStreamController;
  StreamController<Widget> currentTileStreamController;
  StreamController<Widget> powerTileStreamController;
  StreamController<Widget> cellsTileStreamController;

  HomeAutoSettings(
    this.switchesTileStreamController,
    this.voltageTileStreamController,
    this.currentTileStreamController,
    this.powerTileStreamController,
    this.cellsTileStreamController,
  ) {
    logD('construct');
  }

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //String tag = "";
    //logD("$tag $message");
    //String? valueS = message.valueAsString;

    if ("system" == message.commandStr) {
      if ("ota" == message.valueAsString) {
        otaMode = true;
        return true;
      }
      return false;
    }

    if ("switch" == message.command) {
      logD("parsing switch=${message.valueAsString}");
      List<String>? sws = message.valueAsString?.split('|');
      sws?.forEach((s) {
        List<String> parts = s.split(':');
        if (2 != parts.length) return;
        List<String> tokens = parts[1].split(',');
        if (8 != tokens.length) {
          logE("invalid switch: $s");
          return;
        }
        var sw = HomeAutoSwitch(
          mode: HomeAutoSwitchMode.fromString(tokens[0]),
          state: HomeAutoSwitchState.fromString(tokens[1]),
          bvOn: double.tryParse(tokens[2]),
          bvOff: double.tryParse(tokens[3]),
          socOn: int.tryParse(tokens[4]),
          socOff: int.tryParse(tokens[5]),
          cvmOn: double.tryParse(tokens[6]),
          cvmOff: double.tryParse(tokens[7]),
        );
        switches.set(parts[0], sw);
        switchesTileStreamController.sink.add(switches.asTile);
      });
      return true;
    }

    if ("ep" == message.command) {
      logD("parsing ep=${message.arg}");
      List<String>? tokens = message.valueAsString?.split(',');
      tokens?.forEach((s) {
        List<String> kv = s.split(':');
        if (2 != kv.length) return;
        logD('ep: ' + kv[0] + ' = ' + kv[1]);
        epever.set(kv[0], kv[1]);
      });
      return true;
    }

    if ('ci' == message.command) {
      if (message.value?.startsWith('delay:') ?? false) {
        logD('received delay reply: ${message.valueAsString}');
        return true;
      }
      //logD("parsing ci=${message.valueAsString}");
      //name,voltage,current,balanceCurrent[,cellVoltage1,cellVoltage2,...,cellVoltageN]
      List<String> values = message.valueAsString?.split(',') ?? [];
      if ((values.length) < 4) {
        logE("not enough values in ${message.valueAsString}");
        return false;
      }
      bms.updatedAt = uts();
      bms.name = values[0];
      bms.voltage = double.tryParse(values[1]) ?? 0.0;
      bms.current = double.tryParse(values[2]) ?? 0.0;
      bms.balanceCurrent = double.tryParse(values[3]) ?? 0.0;
      List<double> cells = [];
      for (int i = 4; i < values.length; i++) cells.add((double.tryParse(values[i]) ?? 0.0) / 1000);
      bms.cellVoltage = cells;
      voltageTileStreamController.sink.add(bms.voltageTile);
      currentTileStreamController.sink.add(bms.currentTile);
      powerTileStreamController.sink.add(bms.powerTile);
      cellsTileStreamController.sink.add(bms.cellsTile);
      bms.voltageHistory.append(bms.voltage);
      bms.currentHistory.append(bms.current);
      bms.powerHistory.append((bms.voltage * bms.current).round());
      return true;
    }

    return false;
  }

  Future<void> onDisconnected() async {
    otaMode = false;
    await switches.onDisconnected();
    await epever.onDisconnected();
    await bms.onDisconnected();
  }

  @override
  bool operator ==(other) {
    return (other is HomeAutoSettings) && other.otaMode == otaMode && other.switches == switches && other.bms == bms;
  }

  @override
  int get hashCode => otaMode.hashCode ^ switches.hashCode ^ bms.hashCode;

  String toString() {
    return "${describeIdentity(this)} (otaMode: $otaMode, switches: $switches, bms: $bms)";
  }
}

class EpeverSetting<T> {
  String arg;
  String name;
  Type type;
  T? _value;
  late TextEditingController controller;

  EpeverSetting(this.arg, this.name, this.type, [T? value]) {
    controller = TextEditingController(text: '');
    this.value = value;
  }

  set value(T? updated) {
    _value = updated;
    controller.value = TextEditingValue(text: (null == updated) ? '' : updated.toString());
  }

  T? get value => _value;

  String get unit {
    switch (arg) {
      case 'cs':
        return 'in series';
      case 'typ':
        return '0: USER, 1: SLA, 2: GEL, 3: FLD';
      case 'cap':
        return 'Ah';
      case 'tc':
        return 'mV/℃/2V';
      case 'eqd':
      case 'bd':
        return 'minutes';
      default:
    }
    return 'V';
  }

  @override
  String toString() => "$name: $type($value)";

  Future<void> onDisconnected() async {
    value = null;
  }
}

class EpeverSettings with Debug {
  Map<String, EpeverSetting> values = {};

  EpeverSettings() {
    add<int>('cs', 'Number of cells');
    add<int>('typ', 'Battery type');
    add<int>('cap', 'Capacity');
    add<double>('tc', 'Temp coeff.');
    add<double>('cl', 'Charging limit');
    add<double>('hvd', 'High voltage disconnect');
    add<double>('ovr', 'Overvoltage reconnect');
    add<double>('eqv', 'Eq voltage');
    add<double>('bv', 'Boost voltage');
    add<double>('fv', 'Float voltage');
    add<double>('brv', 'Boost reconnect voltage');
    add<double>('lvr', 'Low voltage reconnect');
    add<double>('uvr', 'Undervoltage recover');
    add<double>('uvw', 'Undervoltage warning');
    add<double>('lvd', 'Low voltage disconnect');
    add<double>('dl', 'Discharge limit');
    add<int>('eqd', 'Eq duration');
    add<int>('bd', 'Boost duration');
  }

  void add<T>(String arg, String name) {
    values[arg] = EpeverSetting<T>(arg, name, T);
  }

  EpeverSetting? get(String arg) => values[arg];

  void set(String arg, String value) {
    if (null == values[arg]) {
      logD("$arg not found");
      return;
    }
    if (int == values[arg]!.type) {
      values[arg]!.value = int.tryParse(value);
    } else if (double == values[arg]!.type) {
      values[arg]!.value = double.tryParse(value);
    } else {
      logE("unhandled type: ${values[arg]!.type}");
    }
    logD("$arg: ${values[arg]}");
  }

  Future<void> onDisconnected() async {
    values.forEach((arg, s) async {
      await s.onDisconnected();
    });
  }
}

class HomeAutoSwitch with Debug {
  HomeAutoSwitchMode? mode;
  HomeAutoSwitchState? state;
  double? bvOn;
  double? bvOff;
  int? socOn;
  int? socOff;
  double? cvmOn;
  double? cvmOff;

  HomeAutoSwitch({
    this.mode,
    this.state,
    this.bvOn,
    this.bvOff,
    this.socOn,
    this.socOff,
    this.cvmOn,
    this.cvmOff,
  });

  Widget stateIcon({double? size}) => Icon(
        size: size,
        Icons.circle,
        color: state == HomeAutoSwitchStates.byId(0)
            ? Colors.red
            : state == HomeAutoSwitchStates.byId(1)
                ? Colors.green
                : Colors.grey,
      );

  dynamic onValue() {
    if (HomeAutoSwitchModes.byName('bv') == mode) return bvOn;
    if (HomeAutoSwitchModes.byName('soc') == mode) return socOn;
    if (HomeAutoSwitchModes.byName('cvm') == mode) return cvmOn;
  }

  dynamic offValue() {
    if (HomeAutoSwitchModes.byName('bv') == mode) return bvOff;
    if (HomeAutoSwitchModes.byName('soc') == mode) return socOff;
    if (HomeAutoSwitchModes.byName('cvm') == mode) return cvmOff;
  }

  @override
  bool operator ==(other) {
    return (other is HomeAutoSwitch) &&
        other.mode == mode &&
        other.state == state &&
        other.bvOn == bvOn &&
        other.bvOff == bvOff &&
        other.socOn == socOn &&
        other.socOff == socOff &&
        other.cvmOn == cvmOn &&
        other.cvmOff == cvmOff;
  }

  @override
  int get hashCode => mode.hashCode ^ state.hashCode ^ bvOn.hashCode ^ bvOff.hashCode ^ socOn.hashCode ^ socOff.hashCode ^ cvmOn.hashCode ^ cvmOff.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "mode: ${mode?.name ?? 'unknown'}, "
        "state: ${state?.label.toLowerCase() ?? 'unknown'}, "
        "bvOn: $bvOn, "
        "bvOff: $bvOff, "
        "socOn: $socOn, "
        "socOff: $socOff, "
        "cvmOn: $cvmOn, "
        "cvmOff: $cvmOff"
        ")";
  }

  Future<void> onDisconnected() async {
    mode = null;
    state = null;
    bvOn = null;
    bvOff = null;
    socOn = null;
    socOff = null;
    cvmOn = null;
    cvmOff = null;
  }
}

class HomeAutoSwitches with Debug {
  Map<String, HomeAutoSwitch> values = {};
  var modes = HomeAutoSwitchModes();
  var states = HomeAutoSwitchStates();

  HomeAutoSwitches() {
    logD("construct");
  }

  void set(String name, HomeAutoSwitch value) {
    logD("set $name $value");
    if (values.containsKey(name))
      values[name] = value;
    else
      values.addAll({name: value});
  }

  Widget get asTile {
    List<Widget> widgets = [];
    values.forEach((name, sw) {
      widgets.add(Flexible(
          child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(flex: 2, child: sw.stateIcon(size: 100)),
          Flexible(flex: 8, child: Text(" $name: ${sw.mode?.name}")),
        ],
      )));
    });
    if (widgets.length < 1) return Empty();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );

    /*
    String ret = '';
    values.forEach((name, sw) {
      ret += "$name: ${sw.mode?.name}\r\n";
    });
    return Text(ret);
    */
  }

  String toString() {
    String sws = '';
    values.forEach((key, value) {
      if (0 < sws.length) sws += ', ';
      sws += "$key ($value)";
    });
    return "${describeIdentity(this)} ($sws)";
  }

  Future<void> onDisconnected() async {
    values.forEach((name, sw) async {
      await sw.onDisconnected();
    });
  }
}

class HomeAutoSwitchMode {
  String name;
  String label;
  String? unit;
  HomeAutoSwitchMode(this.name, this.label, {this.unit});

  @override
  bool operator ==(other) {
    if (other is HomeAutoSwitchMode) return other.name == name && other.label == label && other.unit == unit;
    if (other is String) return other == name;
    return false;
  }

  @override
  int get hashCode => name.hashCode ^ label.hashCode ^ unit.hashCode;

  static HomeAutoSwitchMode? fromString(String name) => HomeAutoSwitchModes.byName(name);

  String toString() => "${describeIdentity(this)} $name: $label";
}

class HomeAutoSwitchModes {
  static final Map<String, HomeAutoSwitchMode> values = {
    'off': HomeAutoSwitchMode('off', 'Off'),
    'on': HomeAutoSwitchMode('on', 'On'),
    'bv': HomeAutoSwitchMode('bv', 'Battery voltage', unit: 'V'),
    'soc': HomeAutoSwitchMode('soc', 'State of charge', unit: '%'),
    'cvm': HomeAutoSwitchMode('cvm', 'Highest cell voltage', unit: 'Vpc'),
  };

  static HomeAutoSwitchMode? byName(String name) => values[name];
}

class HomeAutoSwitchState {
  int id;
  String label;

  HomeAutoSwitchState(this.id, this.label);

  @override
  bool operator ==(other) {
    if (other is HomeAutoSwitchState) return other.id == id && other.label == label;
    if (other is int) return other == id;
    return false;
  }

  @override
  int get hashCode => id.hashCode ^ label.hashCode;

  static HomeAutoSwitchState? fromString(String label) => HomeAutoSwitchStates.fromLabel(label);

  String toString() => "${describeIdentity(this)} $label ($id)";
}

class HomeAutoSwitchStates {
  static final Map<int, HomeAutoSwitchState> values = {
    0: HomeAutoSwitchState(0, 'Off'),
    1: HomeAutoSwitchState(1, 'On'),
  };

  static HomeAutoSwitchState? byId(int id) => values[id];

  static HomeAutoSwitchState? fromIdString(String id) => values[int.tryParse(id)];

  static HomeAutoSwitchState? fromLabel(String s) {
    var matches = values.values.where((hass) => hass.label.toLowerCase() == s.toLowerCase());
    if (matches.length == 1) return matches.first;
    return null;
  }
}

class Bms {
  String name = '';
  int updatedAt = 0;
  double voltage = 0.0;
  double current = 0.0;
  double balanceCurrent = 0.0;
  List<double> cellVoltage = [];
  final voltageHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final currentHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final powerHistory = History<int>(maxEntries: 3600, maxAge: 3600);

  Future<void> onDisconnected() async {
    updatedAt = 0;
    voltage = 0;
    current = 0.0;
    cellVoltage = [];
  }

  Widget get voltageTile {
    return Text(voltage.toStringAsFixed(3));
  }

  Widget get currentTile {
    return Text(current.toStringAsFixed(3));
  }

  Widget get powerTile {
    return Text((voltage * current).round().toString());
  }

  Widget get cellsTile {
    var voltages = cellVoltage;
    //var voltages = <double>[3.382, 3.383, 3.386, 3.381, 3.384, 3.382, 3.383, 3.381]; // balanced
    //var voltages = <double>[3.383, 3.272, 3.172, 3.272, 3.372, 3.212, 3.222, 3.151]; // unbalanced
    if (voltages.length < 1) return Text('');
    var sorted = List<double>.from(voltages);
    sorted.sort();
    var min = sorted.first;
    var max = sorted.last;
    var delta = max - min;
    if (delta < 0.0001) delta = 0.0001;
    const double minBarHeight = 5.0;
    const double maxBarHeight = 35.0;
    double factor = 1 / delta * (maxBarHeight - minBarHeight);
    List<Widget> bars = [];
    voltages.forEach((v) {
      Color color = v == max
          ? const Color.fromARGB(255, 2, 124, 6)
          : v == min
              ? const Color.fromARGB(255, 255, 0, 0)
              : const Color.fromARGB(255, 43, 55, 95);
      bars.add(Container(
        width: 10,
        height: (v - min) * factor + minBarHeight,
        color: color,
        margin: const EdgeInsets.only(left: 2),
      ));
    });
    const small = TextStyle(fontSize: 4, color: Color.fromARGB(192, 255, 255, 255));
    const smallActive = TextStyle(fontSize: 4, color: Color.fromARGB(255, 255, 208, 0));
    const warning = TextStyle(fontSize: 10, color: Color.fromARGB(255, 26, 209, 255));
    const important = TextStyle(fontSize: 32, color: Color.fromARGB(255, 255, 132, 132));
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text("Max: ${max.toStringAsFixed(3)}V", style: small),
            SizedBox(height: 35, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: bars)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                0.01 < balanceCurrent
                    ? Text(
                        "Balance: ${(balanceCurrent * 1000).round().toString().padLeft(3, '0')}mA    ",
                        style: smallActive,
                      )
                    : Empty(),
                Text("Min: ${min.toStringAsFixed(3)}V", style: small),
              ],
            ),
          ],
        ),
        Row(
          children: [
            Text('±', style: small),
            Text(
              "${(delta * 1000).round()}",
              style: 0.025 <= delta
                  ? important
                  : 0.01 < delta
                      ? warning
                      : small,
            ),
            Text('mV', style: small),
          ],
        ),
      ],
    );
  }
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
