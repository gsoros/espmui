import 'dart:async';
// import 'dart:html';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:mutex/mutex.dart';

import 'device.dart';
import 'api.dart';
//import 'ble.dart';
import 'ble_characteristic.dart';

import 'util.dart';
import 'debug.dart';

class ESPM extends PowerMeter {
  late Api api;
  final weightServiceMode = ValueNotifier<int>(ESPMWeightServiceMode.UNKNOWN);
  final hallEnabled = ValueNotifier<ExtendedBool>(ExtendedBool.Unknown);
  late final AlwaysNotifier<ESPMSettings> settings;
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());
  //ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;
  StreamSubscription<ApiMessage>? _apiSubsciption;

  WeightScaleCharacteristic? get weightScaleChar => characteristic("weightScale") as WeightScaleCharacteristic?;
  HallCharacteristic? get hallChar => characteristic("hall") as HallCharacteristic?;
  TemperatureCharacteristic? get tempChar => characteristic("temp") as TemperatureCharacteristic?;

  ESPM(Peripheral peripheral) : super(peripheral) {
    settings = AlwaysNotifier<ESPMSettings>(ESPMSettings(this));
    characteristics.addAll({
      'api': CharacteristicListItem(
        EspmApiCharacteristic(this),
      ),
      'weightScale': CharacteristicListItem(
        WeightScaleCharacteristic(this),
        subscribeOnConnect: false,
      ),
      'hall': CharacteristicListItem(
        HallCharacteristic(this),
        subscribeOnConnect: false,
      ),
      'temp': CharacteristicListItem(
        TemperatureCharacteristic(this),
        subscribeOnConnect: true,
      ),
    });
    api = Api(this);
    //api.commands = {1: "config"};
    // listen to api message done events
    _apiSubsciption = api.messageSuccessStream.listen((m) => handleApiMessageSuccess(m));
    tileStreams.addAll({
      "scale": DeviceTileStream(
        label: "Weight Scale",
        stream: weightScaleChar?.defaultStream.map<String>((value) {
          String s = value.toStringAsFixed(2);
          if (s.length > 6) s = s.substring(0, 6);
          if (s == "-0.00") s = "0.00";
          return s;
        }),
        initialData: weightScaleChar?.lastValueToString,
        units: "kg",
        history: weightScaleChar?.histories['measurement'],
      ),
    });
    tileStreams.addAll({
      "temp": DeviceTileStream(
        label: "Temperature",
        stream: tempChar?.defaultStream.map<String>((value) {
          String s = value.toStringAsFixed(1);
          if (s.length > 6) s = s.substring(0, 6);
          return s;
        }),
        initialData: tempChar?.lastValueToString,
        units: "˚C",
        history: tempChar?.histories['measurement'],
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

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    //debugLog("handleApiDoneMessage $message");

    if (await wifiSettings.value.handleApiMessageSuccess(message)) {
      wifiSettings.notifyListeners();
      return true;
    }

    if (await settings.value.handleApiMessageSuccess(message)) {
      settings.notifyListeners();
      return true;
    }

    if ("wse" == message.commandStr) {
      weightServiceMode.value = message.valueAsInt ?? ESPMWeightServiceMode.UNKNOWN;
      if (ESPMWeightServiceMode.OFF < weightServiceMode.value)
        await weightScaleChar?.subscribe();
      else
        await weightScaleChar?.unsubscribe();
      return true;
    }
    if ("hc" == message.commandStr) {
      hallEnabled.value = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      if (message.valueAsBool ?? false)
        await hallChar?.subscribe();
      else
        await hallChar?.unsubscribe();
      return true;
    }

    return false;
  }

  Future<void> dispose() async {
    debugLog("$name dispose");
    _apiSubsciption?.cancel();
    super.dispose();
  }

  Future<void> onConnected() async {
    debugLog("_onConnected()");
    await requestMtu(defaultMtu);
    await super.onConnected();
    _requestInit();
  }

  Future<void> onDisconnected() async {
    //debugLog("_onDisconnected()");
    _resetInit();
    await super.onDisconnected();
  }

  /// request initial values, returned values are discarded
  /// because the message.done subscription will handle them
  void _requestInit() async {
    //debugLog("Requesting init start");
    if (!await ready()) return;
    await requestMtu(largeMtu);
    //debugLog("Requesting init ready to go");
    weightServiceMode.value = ESPMWeightServiceMode.UNKNOWN;
    [
      "init",
      //"wse=${ESPMWeightServiceMode.WHEN_NO_CRANK}",
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
    weightServiceMode.value = ESPMWeightServiceMode.UNKNOWN;
    wifiSettings.value = WifiSettings();
    wifiSettings.notifyListeners();
    settings.value = ESPMSettings(this, tc: settings.value.tc); // preserve collected values
    //debugLog("_resetInit tc.isCollecting: ${settings.value.tc.isCollecting}");
    settings.notifyListeners();
    api.reset();
  }

  @override
  Future<Type> correctType() async {
    return ESPM;
  }

  @override
  Future<Device> copyToCorrectType() async {
    return this;
  }

  @override
  Future<void> subscribeCharacteristics() async {
    await super.subscribeCharacteristics();
    if (null == tempChar || !tempChar!.isSubscribed) {
      int len = tileStreams.length;
      tileStreams.removeWhere((key, _) => key == "temp");
      if (len <= tileStreams.length) debugLog("ESPM subscribeCharacteristics failed to remove temperature tilestream, tileStreams: $tileStreams");
    }
  }
}

class ESPMSettings with Debug {
  ESPM device;

  ESPMSettings(this.device, {TemperatureControlSettings? tc}) {
    if (null != tc && tc.device == device)
      this.tc = tc;
    else
      this.tc = TemperatureControlSettings(device);
  }

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
  bool otaMode = false;
  late TemperatureControlSettings tc;

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

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "handleApiMessageSuccess";
    //debugLog("$tag $message");

    if ("cl" == message.commandStr) {
      cranklength = message.valueAsDouble;
      return true;
    }
    if ("rs" == message.commandStr) {
      reverseStrain = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }
    if ("dp" == message.commandStr) {
      doublePower = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }
    if ("sd" == message.commandStr) {
      if (message.valueAsInt != null) sleepDelay = (message.valueAsInt! / 1000 / 60).round();
      return true;
    }
    if ("mdm" == message.commandStr) {
      if (message.valueAsInt != null) motionDetectionMethod = message.valueAsInt!;
      return true;
    }
    if ("st" == message.commandStr) {
      if (message.valueAsInt != null) strainThreshold = message.valueAsInt!;
      return true;
    }
    if ("stl" == message.commandStr) {
      if (message.valueAsInt != null) strainThresLow = message.valueAsInt!;
      return true;
    }
    if ("ntm" == message.commandStr) {
      if (message.valueAsInt != null) negativeTorqueMethod = message.valueAsInt!;
      return true;
    }
    if ("at" == message.commandStr) {
      autoTare = message.valueAsBool == true ? ExtendedBool.True : ExtendedBool.False;
      return true;
    }
    if ("atd" == message.commandStr) {
      if (message.valueAsInt != null) autoTareDelayMs = message.valueAsInt!;
      return true;
    }
    if ("atr" == message.commandStr) {
      if (message.valueAsInt != null) autoTareRangeG = message.valueAsInt!;
      return true;
    }
    if ("system" == message.commandStr) {
      if ("ota" == message.valueAsString) {
        otaMode = true;
        return true;
      }
      return false;
    }
    if ("tc" == message.commandStr) {
      debugLog("$tag tc message: $message");
      return tc.handleApiMessage(message);
    }

    return false;
  }

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
        other.autoTareRangeG == autoTareRangeG &&
        other.tc == tc;
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
      autoTareDelayMs.hashCode ^
      tc.hashCode;

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
        "autoTareRangeG: $autoTareRangeG, "
        "tc: $tc)";
  }
}

class ESPMWeightServiceMode {
  static const int UNKNOWN = -1;

  /// weight scale measurement characteristic updates disabled
  static const int OFF = 0;

  /// weight scale measurement characteristic updates ensabled
  static const int ON = 1;

  /// weight scale measurement characteristic updates enabled while there are no crank events
  static const int WHEN_NO_CRANK = 2;
}

class TemperatureControlSettings with Debug {
  ESPM device;

  TemperatureControlSettings(this.device);

  ExtendedBool _enabled = ExtendedBool.Unknown;
  ExtendedBool get enabled => _enabled;
  set enabled(ExtendedBool value) {
    _enabled = value;
    setUpdated();
  }

  /// table size
  int get size => _values.length;
  set size(int newSize) {
    if (newSize < size) {
      debugLog("size $size: removeRange(${newSize - 1}, ${size - 1})");
      _values.removeRange(newSize - 1, size - 1);
      debugLog("size $size");
      setUpdated();
    } else if (size < newSize) {
      debugLog("size $size: adding ${newSize - size} elements");
      _values.addAll(List<int>.filled(newSize - size, 0));
      debugLog("size $size");
      setUpdated();
    }
  }

  int? _keyOffset;
  int? get keyOffset => _keyOffset;
  set keyOffset(int? value) {
    _keyOffset = value;
    setUpdated();
  }

  double? _keyResolution;
  double? get keyResolution => _keyResolution;
  set keyResolution(double? value) {
    _keyResolution = value;
    setUpdated();
  }

  double? _valueResolution;
  double? get valueResolution => _valueResolution;
  set valueResolution(double? value) {
    _valueResolution = value;
    setUpdated();
  }

  var _values = <int>[];
  List<int> get values => _values;
  set values(List<int> newValues) {
    if (size != newValues.length) size = newValues.length;
    _values = newValues;
    setUpdated();
  }

  int? getValueAt(int key) {
    if (size - 1 < key) return null;
    return values[key];
  }

  bool setValueAt(int key, int value) {
    if (size < key + 1) size = key + 1;
    _values[key] = value;
    setUpdated();
    return true;
  }

  int _lastUpdate = 0;
  int get lastUpdate => _lastUpdate;
  setUpdated() {
    _lastUpdate = uts();
    device.settings.notifyListeners();
  }

  /// INT8_MIN
  static const int valueAllowedMin = -128;

  /// INT8_MAX
  static const int valueAllowedMax = 127;

  /// lowest value in the table
  int get valuesMin => _values.fold(0, min);

  /// highest value in the table
  int get valuesMax => _values.fold(0, max);

  double keyToTemperature(int key) => ((_keyOffset ?? 0) + key * (_keyResolution ?? 0)).toDouble();
  double valueToWeight(int value) => value * (_valueResolution ?? 1);

  bool isReading = false;
  Future<bool> readFromDevice() async {
    String tag = "readFromDevice";
    bool success = true;
    bool done = false;
    int? rc;
    isReading = true;
    status("Requesting MTU");
    int mtu = await device.requestMtu(device.largeMtu) ?? device.defaultMtu;
    if (mtu < 200) {
      debugLog("$tag mtu: $mtu");
      status("could not get MTU");
    }
    status("Reading settings");
    var mutex = Mutex();
    <String, Map<String, String?>>{
      "tc": {
        "expect": "enabled:",
        "msg": "checking if tc is enabled",
      },
      "tc=table": {
        "expect": "table;",
        "msg": "reading table settings",
      },
      //"invalidCommand": {"expect": "impossibleReply", "msg": "debug triggering failure",},
      "tc=valuesFrom:0": {
        "expect": "valuesFrom:0;",
        "msg": "reading table values",
      },
      "0": {
        "mtu": "${device.defaultMtu}",
        "msg": "restoring MTU",
      },
      "1": {"msg": "done reading from device"},
    }.forEach((command, params) async {
      await mutex.protect(() async {
        if (done) {
          isReading = false;
          return;
        }
        status(params["msg"]?.capitalize());
        if (1 < command.length) {
          rc = await device.api.requestResultCode(command, expectValue: params["expect"]);
          if (ApiResult.success != rc) {
            status("Failed ${params["msg"]}");
            debugLog("readFromDevice $command fail, rc: $rc");
            success = false;
            done = true;
          }
          await Future.delayed(Duration(milliseconds: 300));
          return;
        }
        if (params.containsKey("mtu")) {
          device.requestMtu(int.tryParse(params["mtu"] ?? "") ?? device.defaultMtu);
        }
        isReading = false;
        done = true;
        debugLog("readFromDevice success: $success");
        status(success ? "" : null);
      });
    });
    return null ==
            await Future.doWhile(() async {
              debugLog("readFromDevice waiting");
              await Future.delayed(Duration(milliseconds: 300));
              return !done;
            })
        ? success
        : false;
  }

  bool isWriting = false;
  Future<bool> writeToDevice() async {
    String tag = "writeToDevice";
    bool result = true;
    bool done = false;
    int? rc;
    isWriting = true;

    var sugg = Map.fromEntries(suggested.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    if (sugg.length != size || size < 1) {
      status("Error: suggested table size is ${sugg.length}, saved size is $size");
      isWriting = false;
      return false;
    }
    status("Requesting MTU");
    int mtu = await device.requestMtu(device.largeMtu) ?? device.defaultMtu;
    if (mtu < 200) {
      debugLog("$tag mtu: $mtu");
      status("could not get MTU");
      isWriting = false;
      return false;
    }
    int commandMaxLen = mtu - 10;
    status("Writing TC");

    int newKeyOffset = sugg.entries.first.key.toInt();
    double newKeyResolution = (sugg.entries.last.key.toInt() - sugg.entries.first.key.toInt()).abs() / size;
    var suggValues = sugg.values.toList(growable: false);
    double newValueResolution = max(suggValues.max.abs(), suggValues.min.abs()) / (valueAllowedMax - 1);
    // debugLog("newValueResolution: $newValueResolution, suggValues.min: ${suggValues.min}, suggValues.max: ${suggValues.max}");

    var tasks = <String, Map<String, String?>>{
      "tc=table;size:$size;"
          "keyOffset:$newKeyOffset;"
          "keyRes:${newKeyResolution.toStringAsFixed(4)};"
          "valueRes:${newValueResolution.toStringAsFixed(4)};": {
        "expect": "table;size:$size;",
        "msg": "writing table settings",
      },
    };

    String command = "", expect = "";
    int i = 0, page = 0;
    sugg.forEach((temp, weight) {
      if (!result) return;
      if ("" == command) {
        command = "tc=valuesFrom:$i;set:";
        expect = "valuesFrom:$i;";
        page++;
      }
      int value = weight ~/ newValueResolution;
      if (value < valueAllowedMin || valueAllowedMax < value) {
        result = false;
        debugLog("$tag value out of range: $value, weight: $weight, newValueResolution: $newValueResolution");
        status("Error writing table, value $value out of range");
        return;
      }
      command += value.toString();
      if (i < size - 1) command += ",";
      if (i == size - 1 || commandMaxLen - 3 <= command.length) {
        tasks.addAll({
          command: {
            "expect": expect,
            "msg": "writing table, page $page",
          }
        });
        command = "";
      }
      if (i == size - 1) return;
      i++;
    });

    if (!result) {
      isWriting = false;
      return result;
    }

    tasks.addAll({
      "0": {
        "mtu": "${device.defaultMtu}",
        "msg": "restoring MTU",
      }
    });

    tasks.addAll({
      "1": {"msg": "done writing to device"}
    });

    var mutex = Mutex();
    tasks.forEach((command, params) async {
      await mutex.protect(() async {
        if (done) {
          isWriting = false;
          return;
        }
        status(params["msg"]?.capitalize());
        if (1 < command.length) {
          //debugLog("$tag not sending (len: ${command.length}) $command");
          //rc = ApiResult.success;
          rc = await device.api.requestResultCode(command, expectValue: params["expect"]);
          if (ApiResult.success != rc) {
            status("Failed ${params["msg"]}");
            debugLog("$tag $command fail, rc: $rc");
            result = false;
            done = true;
          }
          await Future.delayed(Duration(milliseconds: 300));
          return;
        }
        if (params.containsKey("mtu")) {
          device.requestMtu(int.tryParse(params["mtu"] ?? "") ?? 23);
        }
        isWriting = false;
        done = true;
        debugLog("$tag success: $result");
        status(result ? "" : null);
      });
    });
    return null ==
            await Future.doWhile(() async {
              debugLog("$tag waiting");
              await Future.delayed(Duration(milliseconds: 300));
              return !done;
            })
        ? result
        : false;
  }

  bool handleApiMessage(ApiMessage m) {
    String tag = "handleApiMessage";
    debugLog("$tag");
    if (null == m.value) {
      debugLog("$tag m.value is null");
      return true;
    }
    if (m.value == "enabled:0") {
      enabled = ExtendedBool.False;
      return true;
    }
    if (m.value == "enabled:1") {
      enabled = ExtendedBool.True;
      return true;
    }
    if (m.value!.contains("table;")) {
      return handleApiTableParams(m);
    }
    if (m.value!.contains("valuesFrom:")) {
      return handleApiTableValues(m);
    }
    debugLog("$tag invalid message: ${m.value}");
    return true;
  }

  bool handleApiTableParams(ApiMessage m) {
    String tag = "handleApiTableParams";
    debugLog("$tag");
    if (null == m.value || m.value!.indexOf("table;") < 0) return true;
    if (m.hasParamValue("size:")) size = int.tryParse(m.getParamValue("size:") ?? "") ?? 0;
    if (m.hasParamValue("keyOffset:")) keyOffset = int.tryParse(m.getParamValue("keyOffset:") ?? "");
    if (m.hasParamValue("keyRes:")) keyResolution = double.tryParse(m.getParamValue("keyRes:") ?? "");
    if (m.hasParamValue("valueRes:")) valueResolution = double.tryParse(m.getParamValue("valueRes:") ?? "");
    return true;
  }

  bool handleApiTableValues(ApiMessage m) {
    String tag = "handleApiTableValues";
    debugLog("$tag");
    if (null == m.value || m.value!.indexOf("valuesFrom:") < 0) {
      debugLog("$tag invalid message");
      return true;
    }
    int? startKey = int.tryParse(m.getParamValue("valuesFrom:") ?? "");
    if (null == startKey) {
      debugLog("$tag could not get start key");
      return true;
    }
    int key = startKey;
    String v = m.value!;
    int semi = v.indexOf(";", v.indexOf("valuesFrom:"));
    if (semi < 0) {
      debugLog("$tag could not get first semi");
      return true;
    }
    v = v.substring(semi + 1);

    int updated = 0;
    v.split(",").forEach((nStr) {
      if (size <= key) {
        debugLog("$tag key: $key but size: $size");
        return;
      }
      //int? oldValue = getValueAt(key);
      if (setValueAt(key, int.tryParse(nStr) ?? 0)) updated++;
      //debugLog("$tag $key: $oldValue -> ${getValueAt(key)})");
      key++;
    });
    debugLog("$tag $updated values updated, size: $size");

    if (key < size) {
      String exp = "=valuesFrom:$key;";
      debugLog("$tag requesting tc$exp");
      device.api.requestResultCode("tc$exp", expectValue: exp);
    }

    return true;
  }

  List<List<double>> collected = [[]];

  void addCollected(double temperature, double weight) {
    weight = (weight * 100).round() / 100; //reduce to 2 decimals
    double? updateTemp, updateWeight;
    if (0 < collected.length && 0 < collected.last.length) {
      if (collected.last[0] == temperature) {
        updateWeight = (collected.last[1] + weight) / 2;
      } else if (collected.last[1] == weight) {
        updateTemp = (collected.last[0] + temperature) / 2;
      }
    }
    if (null != updateTemp || null != updateWeight) {
      collected.last = [updateTemp ?? temperature, updateWeight ?? weight];
      debugLog("addCollected($temperature, $weight) last value updated");
    } else {
      collected.add([temperature, weight]);
      debugLog("addCollected($temperature, $weight)");
    }
    status("Collecting: ${collected.length}");
  }

  double? get collectedMinTemp {
    double? d;
    collected.forEach((e) {
      if ((0 < e.length) && (null == d || e[0] < d!)) d = e[0];
    });
    return d;
  }

  double? get collectedMaxTemp {
    double? d;
    collected.forEach((e) {
      if ((0 < e.length) && (null == d || d! < e[0])) d = e[0];
    });
    return d;
  }

  bool isCollecting = false;

  void startCollecting() {
    //if (isCollecting) return;
    isCollecting = true;
    status("Collecting: ${collected.length}");
    // Future.doWhile(() async {
    //   status("Collecting: ${collected.length}");
    //   await Future.delayed(Duration(seconds: 1));
    //   return isCollecting;
    // });
  }

  void stopCollecting() {
    isCollecting = false;
    status("");
  }

  Map<double, double> get suggested {
    String tag = "suggested";
    Map<double, double> sugg = {};
    if (size < 1) return sugg;
    double? collMin = collectedMinTemp;
    double? collMax = collectedMaxTemp;
    if (null == collMin || null == collMax) return sugg;
    //double start = min(keyToTemperature(0), collMin);
    //double end = max(collMax, keyToTemperature(size - 1));
    double start = collMin;
    double end = collMax;
    double step = (end - start) / size;
    //debugLog("$tag start: $start, end: $end, step: $step");
    if (step <= 0) {
      debugLog("$tag invalid step: $step");
      return sugg;
    }

    Map<double, List<double>> crosses = {};
    var collLen = collected.length;
    List<double> prev, next;
    double weightToAdd;
    for (double current = start; current <= end; current += step) {
      for (int i = 0; i < collLen - 1; i++) {
        prev = collected[i];
        next = collected[i + 1];
        if (prev.length < 2 || next.length < 2) continue;
        if ((prev[0] <= current && current < next[0]) || (next[0] <= current && current < prev[0])) {
          double tempDiff = current - min(prev[0], next[0]);
          //debugLog("$tag prev[0]: ${prev[0]}, tempDiff: $tempDiff");
          if (0 == tempDiff) {
            weightToAdd = (prev[1] + next[1]) / 2;
            //debugLog("$tag tempDiff is 0");
          } else {
            double tempDist = (next[0] - prev[0]).abs();
            double weightDist = (next[1] - prev[1]).abs();
            weightToAdd = prev[1] + weightDist * (tempDiff / tempDist);
            //debugLog("$tag tempDiff: $tempDiff, tempDist: $tempDist, weightDist: $weightDist");
            //if (weightDist != 0)
            //debugLog("$tag at ${prev[0]}˚C weightDist: ${weightDist}kg, next[1]: ${next[1]}, prev[1]: ${prev[1]}, weightToAdd: $weightToAdd");
          }
          if (crosses.containsKey(current))
            crosses[current]?.add(weightToAdd);
          else
            crosses.addAll({
              current: [weightToAdd]
            });
        }
      }
    }

    // String crossStr = "";
    // crosses.forEach((temp, weights) {
    //   crossStr += "${temp.toStringAsFixed(2)}: ${weights.average.toStringAsFixed(2)} (${weights.length}), ";
    // });
    // debugLog("$tag crosses: $crossStr");

    crosses.forEach((temp, weights) {
      sugg.addAll({temp: weights.average});
    });

    // String suggStr = "";
    // sugg.forEach((temp, weight) {
    //   suggStr += "${temp.toStringAsFixed(2)}: ${weight.toStringAsFixed(2)}, ";
    // });
    // debugLog("$tag sugg: $suggStr");

    return sugg;
  }

  String statusMessage = "";
  void status(String? message) {
    // workaround for "setState() or markNeedsBuild() called during build"
    Future.delayed(Duration.zero, () {
      if (null != message) statusMessage = message;
      setUpdated();
      //debugLog("status $statusMessage");
    });
  }

  @override
  bool operator ==(other) {
    //debugLog("comparing $this to $other");
    return (other is TemperatureControlSettings) &&
        other.device == device &&
        other.enabled == enabled &&
        other.size == size &&
        other.keyOffset == keyOffset &&
        other.keyResolution == keyResolution &&
        other.valueResolution == valueResolution &&
        other.values == values &&
        other.statusMessage == statusMessage;
  }

  @override
  int get hashCode =>
      device.hashCode ^
      enabled.hashCode ^
      size.hashCode ^
      keyOffset.hashCode ^
      keyResolution.hashCode ^
      valueResolution.hashCode ^
      values.hashCode ^
      statusMessage.hashCode;
}
