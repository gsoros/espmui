import 'dart:async';
//import 'dart:developer' as dev;
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'package:espmui/util.dart';
//import 'package:flutter/material.dart';
//import 'package:mutex/mutex.dart';

import 'api.dart';
import 'espm.dart';
//import 'util.dart';
//import 'device_widgets.dart';
import 'debug.dart';

class TC with Debug {
  ESPM espm;

  TC(this.espm);

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
      logD("size $size: removeRange(${newSize - 1}, ${size - 1})");
      _values.removeRange(newSize - 1, size - 1);
      logD("size $size");
      setUpdated();
    } else if (size < newSize) {
      logD("size $size: adding ${newSize - size} elements");
      _values.addAll(List<int>.filled(newSize - size, 0));
      logD("size $size");
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
    if (size - 1 < key || key < 0) return null;
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
    espm.settings.notifyListeners();
  }

  /// INT8_MIN
  static const int valueAllowedMin = -128;

  /// INT8_MAX
  static const int valueAllowedMax = 127;

  /// lowest value in the table
  int get valuesMin => _values.fold(0, min);

  /// highest value in the table
  int get valuesMax => _values.fold(0, max);

  int? get firstNonNullKey {
    int i = _values.indexWhere((v) => v != 0);
    return i == -1 ? null : i;
  }

  int? get lastNonNullKey {
    int i = _values.lastIndexWhere((v) => v != 0);
    return i == -1 ? null : i;
  }

  double keyToTemperature(int key) => ((_keyOffset ?? 0) + key * (_keyResolution ?? 0)).toDouble();

  int? temperatureToKey(double temp) {
    // index = (temp - offset) / resolution
    if (null == keyResolution || keyResolution! <= 0.0) return null;
    return (temp - (keyOffset ?? 0)) ~/ keyResolution!;
  }

  double valueToWeight(int value) => value * (_valueResolution ?? 1);

  bool _isReading = false;
  bool get isReading => _isReading;
  set isReading(bool value) {
    _isReading = value;
    espm.settings.notifyListeners();
    status((value ? "Starting" : "Stopped") + " reading");
  }

  Future<bool> readFromDevice() async {
    String tag = "";
    bool success = true;
    int? rc;
    isReading = true;
    status("Requesting MTU");
    int mtu = await espm.requestMtu(espm.largeMtu) ?? espm.defaultMtu;
    if (mtu < 200) {
      logD("$tag mtu: $mtu");
      status("could not get MTU");
    }
    status("Reading settings");
    var tasks = <Map<String, String?>>[
      {
        "command": "tc",
        "expect": "enabled:",
        "msg": "checking if tc is enabled",
      },
      {
        "command": "tc=table",
        "expect": "table;",
        "msg": "reading table settings",
      },
      {
        "command": "tc=valuesFrom:0",
        "expect": "valuesFrom:0;",
        "msg": "reading table values",
      },
      {
        "mtu": "${espm.defaultMtu}",
        "msg": "restoring MTU",
      },
      {
        "msg": "done reading from device",
      },
    ];
    for (var task in tasks) {
      var msg = task["msg"];
      if (null != msg) status(msg.capitalize());
      if (!await espm.connected) {
        status("Device disconnected");
        success = false;
        break;
      }
      var command = task["command"];
      var expect = task["expect"];
      if (null != command && 0 < command.length) {
        rc = await espm.api.requestResultCode(command, expectValue: expect);
        if (ApiResult.success != rc) {
          status("Failed $msg");
          logD("readFromDevice $command fail, rc: $rc");
          success = false;
          break;
        }
        await Future.delayed(Duration(milliseconds: 300));
      }
      if (task.containsKey("mtu")) {
        await espm.requestMtu(int.tryParse(task["mtu"] ?? "") ?? espm.defaultMtu);
      }
    }
    isReading = false;
    if (success) status("");
    return success;
  }

  bool _isWriting = false;
  bool get isWriting => _isWriting;
  set isWriting(bool value) {
    _isWriting = value;
    espm.settings.notifyListeners();
    status((value ? "Starting" : "Stopped") + " writing");
  }

  Future<bool> writeToDevice() async {
    String tag = "";
    bool success = true;
    int? rc;
    if (suggested.length < 2) {
      status("Nothing to write");
      return false;
    }
    var sugg = Map.fromEntries(suggested.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
    if (sugg.length != size || size < 1) {
      status("Error: suggested table size is ${sugg.length}, saved size is $size");
      return false;
    }
    isWriting = true;

    status("Requesting MTU");
    int mtu = await espm.requestMtu(espm.largeMtu) ?? espm.defaultMtu;
    if (mtu < 200) {
      logD("$tag mtu: $mtu");
      status("could not get MTU");
    }
    int commandMaxLen = min(mtu - 3, 220); // ATOLL_API_MSG_ARG_LENGTH = 239
    status("Writing TC");
    int newKeyOffset = sugg.entries.first.key.toInt();
    double newKeyResolution = (sugg.entries.last.key.toInt() - sugg.entries.first.key.toInt()).abs() / size;
    var suggValues = sugg.values.toList(growable: false);
    double newValueResolution = max(suggValues.max.abs(), suggValues.min.abs()) / (valueAllowedMax - 1);
    // logD("newValueResolution: $newValueResolution, suggValues.min: ${suggValues.min}, suggValues.max: ${suggValues.max}");

    var tasks = <Map<String, String?>>[
      {
        "command": "tc=table;size:$size;"
            "keyOffset:$newKeyOffset;"
            "keyRes:${newKeyResolution.toStringAsFixed(4)};"
            "valueRes:${newValueResolution.toStringAsFixed(4)};",
        "expect": "table;size:$size;",
        "msg": "writing table settings",
      },
    ];

    String command = "", expect = "";
    int i = 0, page = 0;
    sugg.forEach((temp, weight) {
      if (!success) return;
      if ("" == command) {
        command = "tc=valuesFrom:$i;set:";
        expect = "valuesFrom:$i;";
        page++;
      }
      int value = weight ~/ newValueResolution;
      if (value < valueAllowedMin || valueAllowedMax < value) {
        success = false;
        logD("$tag value out of range: $value, weight: $weight, newValueResolution: $newValueResolution");
        status("Error writing table, value $value out of range");
        return;
      }
      command += value.toString();
      if (i < size - 1) command += ",";
      if (i == size - 1 || commandMaxLen - 3 <= command.length) {
        tasks.addAll([
          {
            "command": command,
            "expect": expect,
            "msg": "writing table, page $page",
          },
        ]);
        command = "";
      }
      if (i == size - 1) return;
      i++;
    });

    if (!success) {
      isWriting = false;
      return success;
    }

    tasks.addAll([
      {
        "mtu": "${espm.defaultMtu}",
        "msg": "restoring MTU",
      },
      {
        "msg": "done writing to device",
      },
    ]);

    for (var task in tasks) {
      var msg = task["msg"];
      if (null != msg) status(msg.capitalize());
      if (!await espm.connected) {
        status("Device disconnected");
        success = false;
        break;
      }
      var command = task["command"];
      var expect = task["expect"];
      if (null != command && 0 < command.length) {
        rc = await espm.api.requestResultCode(command, expectValue: expect);
        if (ApiResult.success != rc) {
          status("Failed $msg");
          logD("writeToDevice $command fail, rc: $rc");
          success = false;
          break;
        }
        await Future.delayed(Duration(milliseconds: 300));
      }
      if (task.containsKey("mtu")) {
        await espm.requestMtu(int.tryParse(task["mtu"] ?? "") ?? espm.defaultMtu);
      }
    }
    isWriting = false;
    if (success) status("");
    return success;
  }

  bool handleApiMessage(ApiMessage m) {
    String tag = "";
    logD("$tag");
    if (null == m.value) {
      logD("$tag m.value is null");
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
    logD("$tag invalid message: ${m.value}");
    return true;
  }

  bool handleApiTableParams(ApiMessage m) {
    String tag = "";
    logD("$tag");
    if (null == m.value || m.value!.indexOf("table;") < 0) return true;
    if (m.hasParamValue("size:")) size = int.tryParse(m.getParamValue("size:") ?? "") ?? 0;
    if (m.hasParamValue("keyOffset:")) keyOffset = int.tryParse(m.getParamValue("keyOffset:") ?? "");
    if (m.hasParamValue("keyRes:")) keyResolution = double.tryParse(m.getParamValue("keyRes:") ?? "");
    if (m.hasParamValue("valueRes:")) valueResolution = double.tryParse(m.getParamValue("valueRes:") ?? "");
    return true;
  }

  bool handleApiTableValues(ApiMessage m) {
    String tag = "";
    logD("$tag");
    if (null == m.value || m.value!.indexOf("valuesFrom:") < 0) {
      logD("$tag invalid message");
      return true;
    }
    int? startKey = int.tryParse(m.getParamValue("valuesFrom:") ?? "");
    if (null == startKey) {
      logD("$tag could not get start key");
      return true;
    }
    int key = startKey;
    String v = m.value!;
    int semi = v.indexOf(";", v.indexOf("valuesFrom:"));
    if (semi < 0) {
      logD("$tag could not get first semi");
      return true;
    }
    v = v.substring(semi + 1);

    int updated = 0;
    v.split(",").forEach((nStr) {
      if (size <= key) {
        logD("$tag key: $key but size: $size");
        return;
      }
      //int? oldValue = getValueAt(key);
      if (setValueAt(key, int.tryParse(nStr) ?? 0)) updated++;
      //logD("$tag $key: $oldValue -> ${getValueAt(key)})");
      key++;
    });
    logD("$tag $updated values updated, size: $size");

    if (key < size) {
      String exp = "=valuesFrom:$key;";
      logD("$tag requesting tc$exp");
      espm.api.requestResultCode("tc$exp", expectValue: exp);
    }
    if (0 < updated) notify();
    return true;
  }

  List<List<double>> collected = List.empty(growable: true);

  void addCollected(double temperature, double weight) {
    weight = (weight * 100).round() / 100; //reduce to 2 decimals
    double? updateTemp, updateWeight;
    if (0 < collected.length && 1 < collected.last.length) {
      if (collected.last[0] == temperature && collected.last[1] != weight) {
        logD("updated weight: ${collected.last[1]} -> $weight");
        updateWeight = (collected.last[1] + weight) / 2;
      } else if (collected.last[1] == weight && collected.last[0] != temperature) {
        logD("updated temperature: ${collected.last[0]} -> $temperature");
        updateTemp = (collected.last[0] + temperature) / 2;
      }
    }
    if (null != updateTemp || null != updateWeight) {
      collected.last = [updateTemp ?? temperature, updateWeight ?? weight];
      // logD("addCollected($temperature, $weight) last value updated");
    } else {
      collected.add([temperature, weight]);
      logD("addCollected($temperature, $weight)");
      status("Collecting: ${collected.length}");
    }
    notify();
  }

  void notify() {
    espm.settings.notifyListeners();
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

  bool _isCollecting = false;
  bool get isCollecting => _isCollecting;
  set isCollecting(bool value) {
    _isCollecting = value;
    espm.settings.notifyListeners();
    status((value ? "Starting" : "Stopped") + " collecting");
  }

  ExtendedBool prevEnabled = ExtendedBool.Unknown;
  void startCollecting() async {
    if (isCollecting) return;
    isCollecting = true;
    prevEnabled = enabled;
    status("Disabling TC");
    int? rc = await espm.api.requestResultCode("tc=enabled:0", expectValue: "enabled:0");
    if (rc != ApiResult.success) {
      isCollecting = false;
      logE("rc: $rc");
      status("Failed to disable TC");
      return;
    }
    status("Sending tare");
    rc = await espm.api.requestResultCode("tare=0");
    if (rc != ApiResult.success) {
      isCollecting = false;
      logE("rc: $rc");
      status("Tare failed");
      return;
    }
    status("Collecting...");
    // Future.doWhile(() async {
    //   status("Collecting: ${collected.length}");
    //   await Future.delayed(Duration(seconds: 1));
    //   return isCollecting;
    // });
  }

  void stopCollecting() async {
    isCollecting = false;
    if (prevEnabled.asBool) {
      status("Re-enabling TC");
      int? rc = await espm.api.requestResultCode("tc=enabled:1", expectValue: "enabled:1");
      if (rc != ApiResult.success) {
        logE("rc: $rc");
        status("Failed to enable TC");
        return;
      }
    }
    status("");
  }

  Map<double, double> get suggested {
    String tag = "";
    Map<double, double> result = {};
    if (size < 1) return result;
    var firstNN = firstNonNullKey;
    var lastNN = lastNonNullKey;
    double? savedMin = null == firstNN ? null : keyToTemperature(firstNN);
    double? savedMax = null == lastNN ? null : keyToTemperature(lastNN);
    double? collMin = collectedMinTemp;
    double? collMax = collectedMaxTemp;
    if (null == savedMin && null == collMin) return result;
    if (null == savedMax && null == collMax) return result;

    double start = min(savedMin ?? collMin!, collMin ?? savedMin!);
    double end = max(savedMax ?? collMax!, collMax ?? savedMax!);
    double step = (end - start) / size;
    //logD("$tag start: $start, end: $end, step: $step");
    if (step <= 0) {
      logE("$tag invalid step: $step");
      return result;
    }

    Map<double, List<double>> crosses = {};
    var collLen = collected.length;
    List<double> prev, next;
    double weightToAdd;
    int numSteps = 0;
    for (double current = start; current <= end; current += step) {
      if (size <= numSteps) {
        //logD("size: $size <= numSteps: $numSteps but current: $current, step: $step, end: $end");
        break;
      }
      numSteps++;
      for (int i = 0; i < collLen - 1; i++) {
        prev = collected[i];
        next = collected[i + 1];
        if (prev.length < 2 || next.length < 2) continue;
        if ((prev[0] <= current && current < next[0]) || (next[0] <= current && current < prev[0])) {
          double tempDiff = current - min(prev[0], next[0]);
          //logD("$tag prev[0]: ${prev[0]}, tempDiff: $tempDiff");
          if (0 == tempDiff) {
            weightToAdd = (prev[1] + next[1]) / 2;
            //logD("$tag tempDiff is 0");
          } else {
            double tempDist = (next[0] - prev[0]).abs();
            double weightDist = (next[1] - prev[1]).abs();
            weightToAdd = prev[1] + weightDist * (tempDiff / tempDist);
            //logD("$tag tempDiff: $tempDiff, tempDist: $tempDist, weightDist: $weightDist");
            //if (weightDist != 0)
            //logD("$tag at ${prev[0]}˚C weightDist: ${weightDist}kg, next[1]: ${next[1]}, prev[1]: ${prev[1]}, weightToAdd: $weightToAdd");
          }
          if (crosses.containsKey(current))
            crosses[current]?.add(weightToAdd);
          else
            crosses.addAll({
              current: [weightToAdd]
            });
        }
        if (!crosses.containsKey(current)) {
          var key = temperatureToKey(current);
          if (null != key) {
            var savedWeight = getValueAt(key);
            if (null != savedWeight)
              crosses.addAll({
                current: [valueToWeight(savedWeight)]
              });
          }
        }
      }
    }

    // String crossStr = "";
    // crosses.forEach((temp, weights) {
    //   crossStr += "${temp.toStringAsFixed(2)}: ${weights.average.toStringAsFixed(2)} (${weights.length}), ";
    // });
    // logD("$tag crosses: $crossStr");

    crosses.forEach((temp, weights) {
      result.addAll({temp: weights.average});
    });

    // String suggStr = "";
    // sugg.forEach((temp, weight) {
    //   suggStr += "${temp.toStringAsFixed(2)}: ${weight.toStringAsFixed(2)}, ";
    // });
    // logD("$tag sugg: $suggStr");

    return result;
  }

  var statusMessage = ValueNotifier<String>("");
  void status(String message) {
    //logD(message);
    statusMessage.value = message;
  }

  @override
  bool operator ==(other) {
    logD("comparing $this to $other");
    return (other is TC) &&
        other.espm == espm &&
        other.enabled == enabled &&
        other.size == size &&
        other.keyOffset == keyOffset &&
        other.keyResolution == keyResolution &&
        other.valueResolution == valueResolution &&
        other.values == values;
  }

  @override
  int get hashCode =>
      espm.hashCode ^ enabled.hashCode ^ size.hashCode ^ keyOffset.hashCode ^ keyResolution.hashCode ^ valueResolution.hashCode ^ values.hashCode;
}
