import 'dart:async';
//import 'dart:html';
//import 'dart:io';
//import 'dart:math';
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
//import 'package:sprintf/sprintf.dart';
//import 'package:listenable_stream/listenable_stream.dart';
// import 'package:intl/intl.dart';
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

  final bmsStatus = AlwaysNotifier<BmsStatus>(BmsStatus());
  final epeverStatus = AlwaysNotifier<EpeverStatus>(EpeverStatus());

  final switchesTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get switchesTileStream => switchesTileStreamController.stream;
  final bmsVoltageTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get bmsVoltageTileStream => bmsVoltageTileStreamController.stream;
  final bmsCurrentTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get bmsCurrentTileStream => bmsCurrentTileStreamController.stream;
  final bmsPowerTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get bmsPowerTileStream => bmsPowerTileStreamController.stream;
  final bmsCellsTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get bmsCellsTileStream => bmsCellsTileStreamController.stream;
  final epeverInVoltageTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get epeverInVoltageTileStream => epeverInVoltageTileStreamController.stream;
  final epeverOutVoltageTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get epeverOutVoltageTileStream => epeverOutVoltageTileStreamController.stream;
  final epeverOutCurrentTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get epeverOutCurrentTileStream => epeverOutCurrentTileStreamController.stream;
  final epeverOutPowerTileStreamController = StreamController<Widget>.broadcast();
  Stream<Widget> get epeverOutPowerTileStream => epeverOutPowerTileStreamController.stream;

  @override
  int get defaultMtu => 512;

  @override
  int get largeMtu => 512;

  HomeAuto(super.id, super.name) {
    settings = AlwaysNotifier<HomeAutoSettings>(
      HomeAutoSettings(
        switchesTileStreamController,
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
      'bmsVoltage': DeviceTileStream(
        label: 'BMS Voltage',
        units: 'V',
        stream: bmsVoltageTileStream,
        initialData: () => bmsStatus.value.voltageTile,
        history: bmsStatus.value.voltageHistory,
      ),
      'bmsCurrent': DeviceTileStream(
        label: 'BMS Current',
        units: 'A',
        stream: bmsCurrentTileStream,
        initialData: () => bmsStatus.value.currentTile,
        history: bmsStatus.value.currentHistory,
      ),
      'bmsPpower': DeviceTileStream(
        label: 'BMS Power',
        units: 'W',
        stream: bmsPowerTileStream,
        initialData: () => bmsStatus.value.powerTile,
        history: bmsStatus.value.powerHistory,
      ),
      'bmsCells': DeviceTileStream(
        label: 'BMS Cells',
        stream: bmsCellsTileStream,
        initialData: () => bmsStatus.value.cellsTile,
      ),
      'epeverInVoltage': DeviceTileStream(
        label: 'Charger Voltage In',
        units: 'V',
        stream: epeverInVoltageTileStream,
        initialData: () => epeverStatus.value.inVoltageTile,
        history: epeverStatus.value.inVoltageHistory,
      ),
      'epeverOutVoltage': DeviceTileStream(
        label: 'Charger Voltage Out',
        units: 'V',
        stream: epeverOutVoltageTileStream,
        initialData: () => epeverStatus.value.outVoltageTile,
        history: epeverStatus.value.outVoltageHistory,
      ),
      'epeverOutCurrent': DeviceTileStream(
        label: 'Charger Current Out',
        units: 'A',
        stream: epeverOutCurrentTileStream,
        initialData: () => epeverStatus.value.outCurrentTile,
        history: epeverStatus.value.outCurrentHistory,
      ),
      'epeverOutPower': DeviceTileStream(
        label: 'Charger Power Out',
        units: 'W',
        stream: epeverOutPowerTileStream,
        initialData: () => epeverStatus.value.outPowerTile,
        history: epeverStatus.value.outPowerHistory,
      ),
    });
    tileActions.addAll({
      'switchesSettings': DeviceTileAction(
        label: 'Open Switches Settings',
        device: this,
        action: (context, device) {
          if (null == device) return;
          Navigator.push(
            context,
            PageTransition(
              type: PageTransitionType.rightToLeft,
              child: DeviceRoute(device, focus: 'switches', open: const ['settings', 'switches']),
            ),
          );
        },
      ),
      'epeverSettings': DeviceTileAction(
        label: 'Open Charger Settings',
        device: this,
        action: (context, device) {
          if (null == device) return;
          Navigator.push(
            context,
            PageTransition(
              type: PageTransitionType.rightToLeft,
              child: DeviceRoute(device, focus: 'charger', open: const ['settings', 'charger']),
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

    if ('ci' == message.command) {
      if (message.value?.startsWith('delay:') ?? false) {
        logD('received ci delay reply: ${message.valueAsString}');
        return true;
      }
      //logD("parsing ci=${message.valueAsString}");
      //name,voltage,current,balanceCurrent[,cellVoltage1,cellVoltage2,...,cellVoltageN]
      List<String> values = message.valueAsString?.split(',') ?? [];
      if ((values.length) < 4) {
        logE("not enough values in ${message.valueAsString}");
        return false;
      }
      BmsStatus bms = bmsStatus.value;
      bms.updatedAt = uts();
      bms.name = values[0];
      bms.voltage = double.tryParse(values[1]) ?? 0.0;
      bms.current = double.tryParse(values[2]) ?? 0.0;
      bms.balanceCurrent = double.tryParse(values[3]) ?? 0.0;
      List<double> cells = [];
      for (int i = 4; i < values.length; i++) {
        cells.add((double.tryParse(values[i]) ?? 0.0) / 1000);
      }
      bms.cellVoltage = cells;
      bmsVoltageTileStreamController.sink.add(bms.voltageTile);
      bmsCurrentTileStreamController.sink.add(bms.currentTile);
      bmsPowerTileStreamController.sink.add(bms.powerTile);
      bmsCellsTileStreamController.sink.add(bms.cellsTile);
      if (null != bms.voltage) bms.voltageHistory.append(bms.voltage!);
      if (null != bms.current) bms.currentHistory.append(bms.current!);
      if (null != bms.voltage && null != bms.current) bms.powerHistory.append((bms.voltage! * bms.current!).round());
      return true;
    }

    if ('eps' == message.command) {
      if (message.value?.startsWith('delay:') ?? false) {
        logD('received eps delay reply: ${message.valueAsString}');
        return true;
      }
      //logD("parsing eps=${message.valueAsString}");
      List<String>? tokens = message.valueAsString?.split(',');
      if (tokens?.length != 3) {
        logD("wrong number of tokens in $message");
        return false;
      }
      var ev = epeverStatus.value;
      ev.updatedAt = uts();
      ev.inVoltage = double.tryParse(tokens?[0] ?? '');
      epeverInVoltageTileStreamController.sink.add(ev.inVoltageTile);
      if (null != ev.inVoltage) ev.inVoltageHistory.append(ev.inVoltage!);
      ev.outVoltage = double.tryParse(tokens?[1] ?? '');
      epeverOutVoltageTileStreamController.sink.add(ev.outVoltageTile);
      if (null != ev.outVoltage) ev.outVoltageHistory.append(ev.outVoltage!);
      ev.outCurrent = double.tryParse(tokens?[2] ?? '');
      epeverOutCurrentTileStreamController.sink.add(ev.outCurrentTile);
      if (null != ev.outCurrent) ev.outCurrentHistory.append(ev.outCurrent!);
      epeverOutPowerTileStreamController.sink.add(ev.outPowerTile);
      if (null != ev.outPower) ev.outPowerHistory.append(ev.outPower!);
      return true;
    }

    logD("unhandled: $message");
    return false;
  }

  @override
  Future<void> dispose() async {
    logD("$name dispose");
    switchesTileStreamController.close();
    bmsVoltageTileStreamController.close();
    bmsCurrentTileStreamController.close();
    bmsPowerTileStreamController.close();
    bmsCellsTileStreamController.close();
    epeverInVoltageTileStreamController.close();
    epeverOutVoltageTileStreamController.close();
    epeverOutCurrentTileStreamController.close();
    epeverOutPowerTileStreamController.close();
    await apiDispose();
    await wifiDispose();
    await peerDispose();
    super.dispose();
  }

  @override
  Future<void> onConnected() async {
    logD("_onConnected()");
    // api char can use values longer than 20 bytes
    await requestMtu(512);
    logD("calling super.onConnected()");
    await super.onConnected();
    logD("calling _requestInit()");
    _requestInit();
  }

  @override
  Future<void> onDisconnected() async {
    logD("$name onDisconnected()");
    await settings.value.onDisconnected();
    settings.notifyListeners();
    await apiOnDisconnected();
    await wifiOnDisconnected();
    await peerOnDisconnected();
    await bmsStatus.value.onDisconnected();
    await epeverStatus.value.onDisconnected();
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
  IconData get iconData => const DeviceIcon('HomeAuto').data();

  @override
  Future<void> onCommandAdded(String command) async {
    if ('switch' == command) {
      await Future.delayed(const Duration(seconds: 1), () {
        api.sendCommand('switch=all');
      });
    }
    if ('ep' == command) {
      await Future.delayed(const Duration(seconds: 2), () {
        api.sendCommand('ep=dump');
      });
    }
    if ('ci' == command) {
      await Future.delayed(const Duration(seconds: 3), () {
        api.sendCommand('ci=delay:1973');
      });
    }
    if ('eps' == command) {
      await Future.delayed(const Duration(seconds: 4), () {
        api.sendCommand('eps=delay:2124');
      });
    }
    if ('acv' == command) {
      await Future.delayed(const Duration(seconds: 5), () {
        api.sendCommand('acv=dump');
      });
    }
  }
}

class HomeAutoSettings with Debug {
  bool otaMode = false;
  final switches = HomeAutoSwitches();
  final epever = EpeverSettings();
  final acv = AutoChargingVoltage();
  StreamController<Widget> switchesTileStreamController;

  HomeAutoSettings(
    this.switchesTileStreamController,
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
      logD("parsing ep=${message.valueAsString}");
      List<String>? tokens = message.valueAsString?.split(',');
      tokens?.forEach((s) {
        List<String> kv = s.split(':');
        if (2 != kv.length) return;
        //logD('ep: ' + kv[0] + ' = ' + kv[1]);
        epever.set(kv[0], kv[1]);
      });
      return true;
    }

    if (await acv.handleApiMessageSuccess(message)) return true;

    return false;
  }

  Future<void> onDisconnected() async {
    otaMode = false;
    await switches.onDisconnected();
    await epever.onDisconnected();
    await acv.onDisconnected();
  }

  @override
  bool operator ==(other) {
    return (other is HomeAutoSettings) && other.otaMode == otaMode && other.switches == switches && other.epever == epever && other.acv == acv;
  }

  @override
  int get hashCode => otaMode.hashCode ^ switches.hashCode ^ epever.hashCode ^ acv.hashCode;

  @override
  String toString() {
    return "${describeIdentity(this)} (otaMode: $otaMode, switches: $switches, epever: $epever, acv: $acv)";
  }
}

class AutoChargingVoltage with Debug {
  bool? enabled;
  double? min;
  double? max;
  double? trigger;
  double? release;

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    if ('acv' != message.commandStr) return false;
    if (message.value?.length == 1) {
      enabled = message.valueAsBool;
      return true;
    }
    logD('parsing ${message.value}');
    var parts = message.value?.split(',') ?? <String>[];
    if (5 == parts.length) {
      enabled = int.tryParse(parts[0]) == 1;
      min = double.tryParse(parts[1]);
      max = double.tryParse(parts[2]);
      trigger = double.tryParse(parts[3]);
      release = double.tryParse(parts[4]);
      logD(toString());
      return true;
    }
    if (10 == parts.length) {
      for (var part in parts) {
        var pair = part.split(':');
        if (pair.length != 2) continue;
        switch (pair[0]) {
          case 'enabled':
            enabled = int.tryParse(pair[1]) == 1;
            break;
          case 'min':
            min = double.tryParse(pair[1]);
            break;
          case 'max':
            max = double.tryParse(pair[1]);
            break;
          case 'trigger':
            trigger = double.tryParse(pair[1]);
            break;
          case 'release':
            release = double.tryParse(pair[1]);
            break;
          default:
            logD('unhandled ${pair[0]}: ${pair[1]}');
        }
      }
      logD(toString());
      return true;
    }
    return false;
  }

  Future<void> onDisconnected() async {
    enabled = null;
    min = null;
    max = null;
    trigger = null;
    release = null;
  }

  @override
  bool operator ==(other) {
    return (other is AutoChargingVoltage) &&
        other.enabled == enabled &&
        other.min == min &&
        other.max == max &&
        other.trigger == trigger &&
        other.release == release;
  }

  @override
  int get hashCode => enabled.hashCode ^ min.hashCode ^ max.hashCode ^ trigger.hashCode ^ release.hashCode;

  @override
  String toString() => '[enabled: $enabled, min: $min, max: $max, trigger: $trigger, release: $release]';
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
  String toString() => "$value ($name) ($type)";

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

  dynamic get onValue {
    if (HomeAutoSwitchModes.byName('bv') == mode) return bvOn;
    if (HomeAutoSwitchModes.byName('soc') == mode) return socOn;
    if (HomeAutoSwitchModes.byName('cvm') == mode) return cvmOn;
  }

  dynamic get offValue {
    if (HomeAutoSwitchModes.byName('bv') == mode) return bvOff;
    if (HomeAutoSwitchModes.byName('soc') == mode) return socOff;
    if (HomeAutoSwitchModes.byName('cvm') == mode) return cvmOff;
  }

  dynamic get nextTriggerValue {
    if (HomeAutoSwitchStates.fromLabel('On') == state) return offValue;
    if (HomeAutoSwitchStates.fromLabel('Off') == state) return onValue;
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

  @override
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
    if (values.containsKey(name)) {
      values[name] = value;
    } else {
      values.addAll({name: value});
    }
  }

  Widget get asTile {
    List<Widget> widgets = [];
    values.forEach((name, sw) {
      String trigger = '';
      var triggerValue = sw.nextTriggerValue;
      if (null != triggerValue) trigger = ": $triggerValue${sw.mode?.unit ?? ''}";
      widgets.add(Flexible(
          child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(flex: 2, child: sw.stateIcon(size: 100)),
          Flexible(flex: 8, child: Text(" $name$trigger")),
        ],
      )));
    });
    if (widgets.isEmpty) return const Empty();
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

  @override
  String toString() {
    String sws = '';
    values.forEach((key, value) {
      if (sws.isNotEmpty) sws += ', ';
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

  @override
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

  @override
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

class BmsStatus {
  String? name;
  int? updatedAt;
  double? voltage;
  double? current;
  double? balanceCurrent;
  List<double> cellVoltage = [];
  final voltageHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final currentHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final powerHistory = History<int>(maxEntries: 3600, maxAge: 3600);

  Future<void> onDisconnected() async {
    voltage = null;
    current = null;
    balanceCurrent = null;
    cellVoltage = [];
  }

  Widget get voltageTile {
    return Text(voltage?.toStringAsFixed(3) ?? '');
  }

  Widget get currentTile {
    return Text(current?.toStringAsFixed(3) ?? '');
  }

  Widget get powerTile {
    return Text((null == voltage || null == current) ? '' : (voltage! * current!).round().toString());
  }

  Widget get cellsTile {
    var voltages = cellVoltage;
    //var voltages = <double>[3.382, 3.383, 3.386, 3.381, 3.384, 3.382, 3.383, 3.381]; // balanced
    //var voltages = <double>[3.383, 3.272, 3.172, 3.272, 3.372, 3.212, 3.222, 3.151]; // unbalanced
    if (voltages.isEmpty) return const Text('');
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
    for (var v in voltages) {
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
    }
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
                0.01 < (balanceCurrent ?? 0.0)
                    ? Text(
                        "Balance: ${((balanceCurrent ?? 0.0) * 1000).round().toString().padLeft(3, '0')}mA    ",
                        style: smallActive,
                      )
                    : const Empty(),
                Text("Min: ${min.toStringAsFixed(3)}V", style: small),
              ],
            ),
          ],
        ),
        Row(
          children: [
            const Text('±', style: small),
            Text(
              "${(delta * 1000).round()}",
              style: 0.025 <= delta
                  ? important
                  : 0.01 < delta
                      ? warning
                      : small,
            ),
            const Text('mV', style: small),
          ],
        ),
      ],
    );
  }
}

class EpeverStatus {
  int? updatedAt;
  double? inVoltage;
  double? outVoltage;
  double? outCurrent;
  int? get outPower => (null == outVoltage || null == outCurrent) ? null : (outVoltage! * outCurrent!).round();
  final inVoltageHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final outVoltageHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final outCurrentHistory = History<double>(maxEntries: 3600, maxAge: 3600);
  final outPowerHistory = History<int>(maxEntries: 3600, maxAge: 3600);

  Future<void> onDisconnected() async {
    inVoltage = null;
    outVoltage = null;
    outCurrent = null;
  }

  Widget get inVoltageTile {
    return Text(inVoltage?.toStringAsFixed(2) ?? '');
  }

  Widget get outVoltageTile {
    return Text(outVoltage?.toStringAsFixed(2) ?? '');
  }

  Widget get outCurrentTile {
    return Text(outCurrent?.toStringAsFixed(2) ?? '');
  }

  Widget get outPowerTile {
    return Text((outPower ?? '').toString());
  }
}
