import 'dart:async';
// import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'device.dart';
import 'api.dart';
import 'ble.dart';
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
        initialData: weightScaleChar?.lastValue.toString,
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
        initialData: tempChar?.lastValue.toString,
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
    // api char can use values longer than 20 bytes
    await BLE().requestMtu(this, 512);
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
    debugLog("Requesting init start");
    if (!await ready()) return;
    debugLog("Requesting init ready to go");
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
    settings.value = ESPMSettings(this);
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

  ESPMSettings(this.device) {
    tc = TemperatureControlSettings(device);
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

  int? get size => _values?.length;
  set size(int? newSize) {
    if (newSize != size) {
      _initValues(size: newSize);
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

  List<int?>? _values;
  List<int?>? get values => _values;
  set values(List<int?>? newValues) {
    if ((size ?? 0) != (newValues?.length ?? 0)) size = newValues?.length ?? 0;
    _values = newValues;
    setUpdated();
  }

  int? getValueAt(int key) {
    if ((size ?? 1) - 1 < key) return null;
    if ((values?.length ?? 1) - 1 < key) return null;
    return values?[key];
  }

  bool setValueAt(int key, int? value) {
    if (null == size || size! < key - 1) return false;
    if (null == _values) _initValues();
    _values![key] = value;
    setUpdated();
    return true;
  }

  void _initValues({int? size}) {
    _values = List<int?>.filled(size ?? 0, null);
  }

  int _lastUpdate = 0;
  int get lastUpdate => _lastUpdate;
  setUpdated() {
    _lastUpdate = uts();
    device.settings.notifyListeners();
  }

  static const int valueUnset = -128; // INT8_MIN
  static const int valueMin = -127; // INT8_MIN + 1
  static const int valueMax = 128; // INT8_MAX

  double keyToTemperature(int key) => ((_keyOffset ?? 0) + key * (_keyResolution ?? 0)).toDouble();
  double valueToMass(int value) => value == valueUnset ? 0 : value * (_valueResolution ?? 1);

  Future<bool> readFromDevice() async {
    bool success = true;
    int? rc;
    status("Requesting MTU", type: TCSST.reading);
    await device.requestMtu(512);
    status("Reading settings");
    <String, String>{
      "tc": "getting enabled",
      "tc=table": "reading table settings",
      "tc=valuesFrom:0": "reading table values",
    }.forEach((command, msg) async {
      status(msg.capitalize());
      rc = await device.api.requestResultCode(command);
      if (ApiResult.success != rc) {
        status("Failed $msg");
        debugLog("readFromDevice $command fail, rc: $rc");
        success = false;
      }
    });
    status(success ? "" : null, type: TCSST.idle);
    return success;
  }

  bool handleApiMessage(ApiMessage m) {
    String tag = "handleApiMessage";
    debugLog("$tag");
    if (null == m.value) {
      debugLog("$tag m.value is null");
      return true;
    }
    if (m.value == "0") {
      enabled = ExtendedBool.False;
      return true;
    }
    if (m.value == "1") {
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
    if (m.hasParamValue("size:")) size = int.tryParse(m.getParamValue("size:") ?? "");
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
      if ((size ?? 0) <= key) return;
      //int? oldValue = getValueAt(key);
      if (setValueAt(key, int.tryParse(nStr) ?? valueUnset)) updated++;
      //debugLog("$tag $key: $oldValue -> ${getValueAt(key)})");
      key++;
    });
    debugLog("$tag $updated values updated, size: $size");

    if (key < (size ?? 0)) {
      debugLog("$tag requesting tc=valuesFrom:$key");
      device.api.requestResultCode("tc=valuesFrom:$key");
    }

    return true;
  }

  int? get valuesMin {
    int? i;
    _values?.forEach((v) {
      if (null == i || null == v || v < i!) i = v;
    });
    return i;
  }

  int? get valuesMax {
    int? i;
    _values?.forEach((v) {
      if (null == i || null == v || i! < v) i = v;
    });
    return i;
  }

  TCSST statusType = TCSST.idle;
  String statusMessage = "";
  void status(String? message, {TCSST? type}) {
    if (null != message) statusMessage = message;
    if (null != type) statusType = type;
    device.settings.notifyListeners();
    debugLog("status $statusMessage $statusType");
  }

  @override
  bool operator ==(other) {
    debugLog("comparing $this to $other");
    return (other is TemperatureControlSettings) &&
        other.device == device &&
        other.enabled == enabled &&
        other.size == size &&
        other.keyOffset == keyOffset &&
        other.keyResolution == keyResolution &&
        other.valueResolution == valueResolution &&
        other.values == values &&
        other.statusType == statusType &&
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
      statusMessage.hashCode ^
      statusType.hashCode;
}

enum TemperatureControlSettingsStatusType {
  idle,
  reading,
  collecting,
  writing,
}

typedef TCSST = TemperatureControlSettingsStatusType;
