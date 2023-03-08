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
  final settings = AlwaysNotifier<ESPMSettings>(ESPMSettings());
  final wifiSettings = AlwaysNotifier<WifiSettings>(WifiSettings());
  //ApiCharacteristic? get apiChar => characteristic("api") as ApiCharacteristic?;
  StreamSubscription<ApiMessage>? _apiSubsciption;

  WeightScaleCharacteristic? get weightScaleChar => characteristic("weightScale") as WeightScaleCharacteristic?;
  HallCharacteristic? get hallChar => characteristic("hall") as HallCharacteristic?;
  TemperatureCharacteristic? get tempChar => characteristic("temp") as TemperatureCharacteristic?;

  ESPM(Peripheral peripheral) : super(peripheral) {
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
    settings.value = ESPMSettings();
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
    //debugLog("handleApiMessageSuccess $message");

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

class ESPMWeightServiceMode {
  static const int UNKNOWN = -1;

  /// weight scale measurement characteristic updates disabled
  static const int OFF = 0;

  /// weight scale measurement characteristic updates ensabled
  static const int ON = 1;

  /// weight scale measurement characteristic updates enabled while there are no crank events
  static const int WHEN_NO_CRANK = 2;
}
