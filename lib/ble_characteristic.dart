// ignore_for_file: overridden_fields

import 'dart:convert';

import 'dart:typed_data';
import 'dart:async';

import 'dart:io';

import 'package:espmui/api.dart';
//import 'package:flutter/material.dart';

import 'package:espmui/debug.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
//import 'package:mutex/mutex.dart';

import 'util.dart' as util;
import 'ble.dart';
import 'ble_constants.dart';
import 'device.dart';
import 'espm.dart';
import 'espcc.dart';
import 'homeauto.dart';

abstract class BleCharacteristic<T> with Debug {
  Device device;
  final serviceUUID = "";
  final charUUID = "";
  Stream<List<int>>? _rawStream;
  StreamSubscription<List<int>>? _subscription;
  final _controller = StreamController<T>.broadcast();
  T? lastValue;
  List<int>? lastRawValue;

  // The reactive_ble char object
  Characteristic? _characteristic;
  set characteristic(Characteristic? c) => _characteristic = c;

  QualifiedCharacteristic get qualifiedCharacteristic => QualifiedCharacteristic(
        characteristicId: Uuid.parse(charUUID),
        serviceId: Uuid.parse(serviceUUID),
        deviceId: device.id,
      );

  /// whether to send [beforeUnsubscribeValue] before unsubscribing
  bool sendBeforeUnsubscribe = false;

  /// the value to send to listeners before unsubscribing
  T? beforeUnsubscribeValue;

  /// mutex shared with BLE
  final _exclusiveAccess = BLE().mutex;

  /// Histories associated with the streams
  Map<String, History> histories = {};

  Stream<T> get defaultStream => _controller.stream;

  BleCharacteristic(this.device) {
    logD("construct ${device.id}");
    //lastValue = fromUint8List(Uint8List.fromList([]));
  }

  T fromUint8List(Uint8List list);
  Uint8List toUint8List(T value);

  /// Reads value from characteristic and sets [lastValue]
  Future<T?> read() async {
    var value = await readAsUint8List();
    if (value != null) {
      lastValue = fromUint8List(value);
      return lastValue;
    }
    return null;
  }

  /// Reads raw value from characteristic and sets [lastRawValue]
  Future<Uint8List?> readAsUint8List() async {
    await _init();
    String tag = "";
    if (null == _characteristic) {
      bleError(debugTag, "$tag characteristic is null");
      return null;
    }
    if (!_characteristic!.isReadable) {
      bleError(debugTag, "$tag characteristic not readable");
      return null;
    }
    Uint8List? value;
    bool error = false;
    await _exclusiveAccess.protect(() async {
      List<int> vals = await _characteristic?.read().catchError((e) {
            bleError(debugTag, tag, e);
            error = true;
            return Uint8List.fromList([]);
          }) ??
          [];
      value = Uint8List.fromList(vals);
    });
    if (null != value && !error) {
      lastRawValue = value;
      return value;
    }
    return null;
  }

  Future<void> write(
    T value, {
    bool withResponse = false,
    Characteristic? char,
  }) async {
    await _init();
    char ??= _characteristic;
    if (char == null) {
      bleError(debugTag, "write() characteristic is null");
      return Future.value(null);
    }
    if (!char.isWritableWithoutResponse && !char.isWritableWithResponse) {
      bleError(debugTag, "write() characteristic not writable");
      return Future.value(null);
    }
    if (withResponse && !char.isWritableWithResponse) {
      bleError(debugTag, "write() characteristic not writableWithResponse");
      return Future.value(null);
    }
    //logD("write($value)");
    await _exclusiveAccess.protect(() async {
      if (null == char) return;
      char
          .write(
        toUint8List(value),
        withResponse: withResponse,
      )
          .catchError((e) {
        bleError(debugTag, "write($value)", e);
      });
    });
  }

  Future<void> subscribe() async {
    logD("subscribe()");
    if (isSubscribed) {
      bleError(debugTag, "already subscribed");
      return;
    }
    await _init();

    if (_characteristic == null) {
      bleError(debugTag, "subscribe() characteristic is null");
      return;
    }
    if (!(_characteristic?.isIndicatable ?? false) && !(_characteristic?.isNotifiable ?? false)) {
      bleError(debugTag, "characteristic neither indicatable nor notifiable");
      return;
    }
    _rawStream = _characteristic?.subscribe().handleError((e) {
      bleError(debugTag, "_rawStream", e);
    }); //.asBroadcastStream();
    if (_rawStream == null) {
      bleError(debugTag, "subscribe() _rawStream is null");
      return;
    }
    await _exclusiveAccess.protect(() async {
      _subscription = _rawStream?.listen(
        (value) async {
          lastRawValue = value;
          lastValue = await onNotify(fromUint8List(Uint8List.fromList(value)));
          //logD("$lastValue");
          util.streamSendIfNotClosed(_controller, lastValue);
          _appendToHistory();
        },
        onError: (e) => bleError(debugTag, "subscription", e),
      );
    });
    await read();
    _appendToHistory();
    logD("subscribe() initial value: $lastValue");
    util.streamSendIfNotClosed(_controller, lastValue);
  }

  bool get isSubscribed => _subscription != null;

  void _appendToHistory() {
    // var history = histories['raw'];
    // if (null != lastValue || null != history) history!.append(util.uts(), lastValue!);
  }

  Future<void> unsubscribe() async {
    await _init();
    if (_subscription == null) return;
    logD("unsubscribe $runtimeType");
    if (sendBeforeUnsubscribe) {
      util.streamSendIfNotClosed(
        _controller,
        beforeUnsubscribeValue,
        allowNull: true,
      );
    }
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _init() async {
    if (_characteristic != null) return; // already init'd
    if (!device.connected) return;
    try {
      await _exclusiveAccess.protect(() async {
        _characteristic = await device.frbCharacteristic(Uuid.parse(serviceUUID), Uuid.parse(charUUID));
      });
    } catch (e) {
      bleError(debugTag, "_init() readCharacteristic()", e);
      _characteristic = null;
      //  logD("readCharacteristic() serviceUUID: $serviceUUID, characteristicUUID: $characteristicUUID, $e");
    }
  }

  Future<void> deinit() async {
    //logD("deinit()");
    lastValue = null;
    util.streamSendIfNotClosed(_controller, lastValue);
    _characteristic = null;
  }

  Future<T?> onNotify(T value) {
    return Future.value(value);
  }

  Future<void> dispose() async {
    await unsubscribe();
    await _controller.close();
    deinit();
  }

  String lastValueToString() => (null == lastValue) ? "" : lastValue.toString();
}

class BatteryCharacteristic extends BleCharacteristic<int> {
  @override
  final serviceUUID = BleConstants.BATTERY_SERVICE_UUID;
  @override
  final charUUID = BleConstants.BATTERY_LEVEL_CHAR_UUID;

  BatteryCharacteristic(super.device) {
    histories['charge'] = History<int>();
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['charge'];
    if (null != lastValue && null != history) history.append(lastValue!);
  }

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;

  @override
  Uint8List toUint8List(int value) {
    if (value < 0) {
      bleError(debugTag, "toUint8List() negative value");
    } else if (255 < value) {
      bleError(debugTag, "toUint8List() $value clipped");
    }
    return Uint8List.fromList([value]);
  }

  @override
  Future<void> unsubscribe() async {
    bool wasSubscribed = isSubscribed;
    bool wasCharging = device.isCharging.asBool;
    await super.unsubscribe();
    if (!wasSubscribed) return;
    device.isCharging = util.ExtendedBool.eUnknown;
    if (wasCharging) device.notifyCharging();
  }
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  @override
  final serviceUUID = BleConstants.CYCLING_POWER_SERVICE_UUID;
  @override
  final charUUID = BleConstants.CYCLING_POWER_MEASUREMENT_CHAR_UUID;

  int revolutions = 0;
  int lastCrankEvent = 0;
  int lastCrankEventTime = 0;
  int lastPower = 0;
  int lastCadence = 0;
  int lastCadenceZeroTime = 0;

  final _powerController = StreamController<int>.broadcast();
  Stream<int> get powerStream => _powerController.stream;
  final _cadenceController = StreamController<int>.broadcast();
  Stream<int> get cadenceStream => _cadenceController.stream;
  Timer? _timer;

  PowerCharacteristic(super.device) {
    _cadenceController.onListen = () {
      _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
        int now = DateTime.now().millisecondsSinceEpoch;
        int cutoff = now - 4000;
        if (lastCrankEventTime < cutoff && //
            lastCadenceZeroTime < cutoff &&
            lastCadenceZeroTime < lastCrankEventTime) {
          util.streamSendIfNotClosed(_cadenceController, 0);
          lastCadenceZeroTime = now;
        }
      });
    };
    _cadenceController.onCancel = () {
      _timer?.cancel();
    };
    histories['power'] = History<int>(maxEntries: 3600, maxAge: 3600);
    histories['cadence'] = History<int>(maxEntries: 3600, maxAge: 3600);
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['power'];
    if (null != history) history.append(lastPower);
    history = histories['cadence'];
    if (null != history) history.append(lastCadence);
  }

  @override
  Uint8List fromUint8List(Uint8List list) => list;

  @override
  Uint8List toUint8List(Uint8List value) => value;

  @override
  Future<Uint8List?> onNotify(Uint8List value) {
    /// https://github.com/sputnikdev/bluetooth-gatt-parser/blob/master/src/main/resources/gatt/characteristic/org.bluetooth.characteristic.cycling_power_measurement.xml
    /// Format: little-endian
    /// Bytes: [flags: 2][power: 2(int16)]...[revolutions: 2(uint16)][last crank event: 2(uint16)]
    /// Flags: 0b00000000 00000001;  // Pedal Power Balance Present
    /// Flags: 0b00000000 00000010;  // Pedal Power Balance Reference
    /// Flags: 0b00000000 00000100;  // Accumulated Torque Present
    /// Flags: 0b00000000 00001000;  // Accumulated Torque Source
    /// Flags: 0b00000000 00010000;  // Wheel Revolution Data Present
    /// Flags: 0b00000000 00100000;  // *** Crank Revolution Data Present
    /// Flags: 0b00000000 01000000;  // Extreme Force Magnitudes Present
    /// Flags: 0b00000000 10000000;  // Extreme Torque Magnitudes Present
    /// Flags: 0b00000001 00000000;  // Extreme Angles Present
    /// Flags: 0b00000010 00000000;  // Top Dead Spot Angle Present
    /// Flags: 0b00000100 00000000;  // Bottom Dead Spot Angle Present
    /// Flags: 0b00001000 00000000;  // Accumulated Energy Present
    /// Flags: 0b00010000 00000000;  // Offset Compensation Indicator
    /// Flags: 0b00100000 00000000;  // ReservedForFutureUse
    /// Flags: 0b01000000 00000000;  // ReservedForFutureUse
    /// Flags: 0b10000000 00000000;  // ReservedForFutureUse
    /// crank event time unit: 1/1024s, rolls over
    int power = value.buffer.asByteData().getUint16(2, Endian.little);
    lastPower = power;
    util.streamSendIfNotClosed(_powerController, power);

    // TODO depending on the flag bits the offsets need shifting
    int newRevolutions = value.buffer.asByteData().getUint16(4, Endian.little);
    int newCrankEvent = value.buffer.asByteData().getUint16(6, Endian.little);
    double dTime = 0.0;
    if (lastCrankEvent > 0) {
      dTime = (newCrankEvent - ((newCrankEvent < lastCrankEvent) ? (lastCrankEvent - 65535) : lastCrankEvent)) / 1.024 / 60000; // 1 minute
    }

    int cadence = 0;
    int dRev = 0;
    if (revolutions > 0 && dTime > 0) {
      dRev = newRevolutions - ((newRevolutions < revolutions) ? (revolutions - 65535) : revolutions);
      cadence = (dRev / dTime).round();
    }

    int now = DateTime.now().millisecondsSinceEpoch;
    if (lastCrankEventTime < now - 2000) cadence = 0;
    if (lastCrankEvent != newCrankEvent) {
      lastCrankEvent = newCrankEvent;
      lastCrankEventTime = now;
    }

    if ((lastCadence != cadence && cadence > 0) || (lastCrankEventTime < now - 2000)) util.streamSendIfNotClosed(_cadenceController, cadence);
    lastCadence = cadence;
    revolutions = newRevolutions;

    return super.onNotify(value);
  }

  @override
  Future<void> dispose() {
    _powerController.close();
    _cadenceController.close();
    return Future.value(null);
  }
}

abstract class ApiCharacteristic extends BleCharacteristic<String> {
  @override
  final String serviceUUID;
  final String txCharUUID;
  final String rxCharUUID;
  Characteristic? _rxChar;

  ApiCharacteristic(
    super.device, {
    this.serviceUUID = "",
    this.txCharUUID = BleConstants.API_TXCHAR_UUID,
    this.rxCharUUID = BleConstants.API_RXCHAR_UUID,
  });

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    Uint8List list = Uint8List.fromList([]);
    try {
      list = ascii.encode(value);
    } catch (e) {
      logE("error: failed to ascii encode '$value': $e");
      List<int> valid = [];
      for (int code in value.codeUnits) {
        if (code < 256) valid.add(code);
      }
      list = Uint8List.fromList(valid);
    }
    return list;
  }

  @override
  Future<void> write(
    String value, {
    bool withResponse = false,
    Characteristic? char,
  }) async {
    return super.write(
      value,
      withResponse: withResponse,
      char: _rxChar,
    );
  }

  @override
  Future<void> _init() async {
    //await super._init();
    if (_rxChar != null || _characteristic != null) return; // already init'd
    if (!(device.connected)) return;
    try {
      List<Characteristic> chars = [];
      await _exclusiveAccess.protect(() async {
        chars = await device.frbCharacteristics(Uuid.parse(serviceUUID));
      });
      Uuid rxUuid = Uuid.parse(rxCharUUID);
      if (chars.where((char) => char.id == rxUuid).isNotEmpty) {
        _rxChar = chars.firstWhere((char) => char.id == rxUuid);
      }
      Uuid txUuid = Uuid.parse(txCharUUID);
      if (chars.where((char) => char.id == txUuid).isNotEmpty) {
        _characteristic = chars.firstWhere((char) => char.id == txUuid);
      }
    } catch (e) {
      bleError(debugTag, "_init() characteristics()", e);
      _rxChar = null;
      _characteristic = null;
    }
  }

  @override
  Future<void> deinit() async {
    await super.deinit();
    _rxChar = null;
    _characteristic = null;
  }

  @override
  Future<String?> onNotify(String value) async {
    if (null != device.mtu && 0 < device.mtu! && value.length < device.mtu! - 3) return value;
    // read full value as the notification is limited to the size of one packet
    String? fullValue = await read();
    logD("ApiCharacteristic::onNotify() mtu=${device.mtu} value(${value.length}): '$value' fullValue(${fullValue?.length}): '$fullValue'");
    return fullValue;
  }
}

class EspmApiCharacteristic extends ApiCharacteristic {
  @override
  ESPM get device => super.device as ESPM;
  EspmApiCharacteristic(super.device) : super(serviceUUID: BleConstants.ESPM_API_SERVICE_UUID);
}

class EspccApiCharacteristic extends ApiCharacteristic {
  @override
  ESPCC get device => super.device as ESPCC;
  EspccApiCharacteristic(super.device) : super(serviceUUID: BleConstants.ESPCC_API_SERVICE_UUID);

  @override
  Future<String?> onNotify(String value) async {
    // do not read the binary data after "success;rec=get:01231234:0;"
    String tag = "";
    //logD("$tag '$value'");
    final int success = ApiResult.success;
    final int? rec = device.api.commandCode("rec", logOnError: false);
    if (null == rec) {
      // logD("$tag could not find command code for 'rec'");
      return super.onNotify(value);
    }
    final reg = RegExp('(^$success;$rec=get:([0-9a-zA-Z]{8}):([0-9]+);*)(.+)');
    RegExpMatch? match = reg.firstMatch(value);
    String? noBinary = match?.group(1);
    if (null != noBinary && noBinary.isNotEmpty) {
      // logD("$tag found match: '$noBinary'");
      Uint8List? valueAsList;
      if (null != device.mtu && 0 < device.mtu! && null != lastRawValue && lastRawValue!.length < device.mtu! - 2) {
        valueAsList = lastRawValue != null ? Uint8List.fromList(lastRawValue!) : null;
        //logD("$tag $noBinary ready");
      } else {
        valueAsList = await readAsUint8List();
        //logD("$tag $noBinary was re-read, mtu: ${device.mtu}, "
        //    "lastRawValue.length: ${lastRawValue?.length}");
      }
      if (null == valueAsList || valueAsList.isEmpty) {
        logD("$tag could not get valueAsList");
        return super.onNotify(noBinary);
      }
      String fullValue = fromUint8List(valueAsList);
      match = reg.firstMatch(fullValue);
      String? fileName = match?.group(2);
      if (null == fileName || fileName.length < 8) {
        logD("$tag could not get filename");
        return super.onNotify(noBinary);
      }
      String? offsetStr = match?.group(3);
      if (null == offsetStr || offsetStr.isEmpty) {
        logD("$tag could not get offsetStr");
        return super.onNotify(noBinary);
      }
      int? offset = int.tryParse(offsetStr);
      if (null == offset || offset < 0) {
        logD("$tag could not get offset");
        return super.onNotify(noBinary);
      }
      int? binaryStart = match?.group(1)?.length;
      if (null == binaryStart || binaryStart < 0 || valueAsList.length <= binaryStart) {
        logD("$tag could not get binaryStart");
        return super.onNotify(noBinary);
      }
      Uint8List byteData = Uint8List.sublistView(valueAsList, binaryStart);
      //logD("$tag file: $fileName, offset: $offset, byteData: ${byteData.length}B");
      ESPCCFile f = device.files.value.files.firstWhere(
        (candidate) => candidate.name == fileName,
        orElse: () {
          logD("$tag $fileName not found in list, creating new ef");
          var f = ESPCCFile(fileName, device);
          f.updateLocalStatus();
          device.files.value.files.add(f);
          device.files.notifyListeners();
          return f;
        },
      );
      int written = await f.appendLocal(offset: offset, byteData: byteData);
      if (written == byteData.length) return super.onNotify(noBinary);
      logD("$tag file: $fileName, received: ${byteData.length}, written: $written");
      return super.onNotify("${ApiResult.localFsError};$rec=get:$fileName:$offset;");
    }
    return super.onNotify(value);
  }
}

class HomeAutoApiCharacteristic extends ApiCharacteristic {
  @override
  HomeAuto get device => super.device as HomeAuto;
  HomeAutoApiCharacteristic(super.device) : super(serviceUUID: BleConstants.HOMEAUTO_API_SERVICE_UUID);
}

class ApiLogCharacteristic extends BleCharacteristic<String> {
  @override
  final String serviceUUID;
  @override
  String charUUID = "";

  ApiLogCharacteristic(
    super.device,
    this.serviceUUID, {
    this.charUUID = BleConstants.API_LOGCHAR_UUID,
  });

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    return Uint8List(0);
  }

  @override
  Future<String?> onNotify(String value) async {
    String tag = "";
    logD("$tag ${device.name} \"$value\"");
    if (null != device.mtu && 0 < device.mtu! && device.mtu! - 3 <= value.length) {
      // read full value as the notification is limited to the size of one packet
      String? fullValue = await read();
      logD("$tag mtu=${device.mtu} value(${value.length}) fullValue(${fullValue?.length})");
      if (null != fullValue && value.length < fullValue.length) value = fullValue;
    }
    DateTime date = DateTime.now();
    String fileName = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}.log";
    String? path = Platform.isAndroid ? await util.Path().external : await util.Path().documents;
    if (null == path) {
      logD("$tag path is null");
      return value;
    }
    String deviceName = "unnamedDevice";
    if (device.name.isNotEmpty) deviceName = util.Path().sanitize(device.name);
    path = "$path/$deviceName/log/$fileName";
    File f = File(path);
    if (!await f.exists()) {
      try {
        f = await f.create(recursive: true);
      } catch (e) {
        logE("$tag could not create $path, error: $e");
        return value;
      }
    }
    // logD("$tag writing ${value.length} characters to ${f.path}: $value");
    await f.writeAsString(
      "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')} $value\n",
      mode: FileMode.append,
      flush: true,
    );
    return value;
  }
}

class WeightScaleCharacteristic extends BleCharacteristic<double?> {
  @override
  final serviceUUID = BleConstants.WEIGHT_SCALE_SERVICE_UUID;
  @override
  final charUUID = BleConstants.WEIGHT_MEASUREMENT_CHAR_UUID;

  WeightScaleCharacteristic(super.device) {
    histories['measurement'] = History<double>(maxEntries: 360, maxAge: 60, absolute: true);
    super.sendBeforeUnsubscribe = true;
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['measurement'];
    if (null != lastValue || null != history) history!.append(lastValue!);
  }

  @override
  double fromUint8List(Uint8List list) {
    /// Format: little-endian
    /// Bytes: [flags: 1][weight: 2]
    return list.isNotEmpty ? list.buffer.asByteData().getInt16(1, Endian.little) / 200 : 0.0;
  }

  @override
  Uint8List toUint8List(double? value) => Uint8List(3)..buffer.asByteData().setInt16(1, (value ?? 0 * 200).round(), Endian.little);
}

class HallCharacteristic extends BleCharacteristic<int> {
  @override
  final serviceUUID = BleConstants.ESPM_API_SERVICE_UUID;
  @override
  final charUUID = BleConstants.ESPM_HALL_CHAR_UUID;

  HallCharacteristic(super.device);

  @override
  int fromUint8List(Uint8List list) {
    /// Format: little-endian
    return list.isNotEmpty ? list.buffer.asByteData().getInt16(0, Endian.little) : 0;
  }

  @override
  Uint8List toUint8List(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, (value).round(), Endian.little);
}

class HeartRateCharacteristic extends BleCharacteristic<int?> {
  @override
  final serviceUUID = BleConstants.HEART_RATE_SERVICE_UUID;
  @override
  final charUUID = BleConstants.HEART_RATE_MEASUREMENT_CHAR_UUID;

  HeartRateCharacteristic(super.device) {
    histories['measurement'] = History<int>(maxEntries: 120, maxAge: 120);
    super.sendBeforeUnsubscribe = true;
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['measurement'];
    if (null != lastValue || null != history) history!.append(lastValue!);
  }

  @override
  int fromUint8List(Uint8List list) {
    /// https://github.com/oesmith/gatt-xml/blob/master/org.bluetooth.characteristic.heart_rate_measurement.xml
    ///
    /// Format: little-endian
    /// Bytes:
    /// [Flags: 1]
    /// [Heart rate: 1 or 2, depending on bit 0 of the Flags field]
    /// [Energy Expended: 2, presence dependent upon bit 3 of the Flags field]
    /// [RR-Interval: 2, presence dependent upon bit 4 of the Flags field]
    ///
    /// Flags: 0b00000001  // 0: Heart Rate Value Format is set to UINT8, 1: HRVF is UINT16
    /// Flags: 0b00000010  // Sensor Contact Status bit 1
    /// Flags: 0b00000100  // Sensor Contact Status bit 2
    /// Flags: 0b00001000 // Energy Expended Status bit
    /// Flags: 0b00010000 // RR-Interval bit
    /// Flags: 0b00100000 // ReservedForFutureUse
    /// Flags: 0b01000000 // ReservedForFutureUse
    /// Flags: 0b10000000 // ReservedForFutureUse
    ///
    if (list.isEmpty) return 0;
    int byteCount = list.last & 0 == 0 ? 1 : 2;
    var byteData = list.buffer.asByteData();
    int heartRate = 0;
    if (byteData.lengthInBytes < byteCount + 1) {
      logD('fromUint8List() not enough bytes in $list');
      return heartRate;
    }
    if (byteCount == 1) {
      heartRate = byteData.getUint8(1);
    } else if (byteCount == 2) {
      heartRate = byteData.getUint16(1, Endian.little);
    }
    //logD("got list: $list byteCount: $byteCount hr: $heartRate');
    return heartRate;
  }

  @override
  Uint8List toUint8List(int? value) => Uint8List(2); // we are not writing
}

class TemperatureCharacteristic extends BleCharacteristic<double?> {
  @override
  final serviceUUID = BleConstants.ENVIRONMENTAL_SENSING_SERVICE_UUID;
  @override
  final charUUID = BleConstants.TEMPERATURE_CHAR_UUID;

  TemperatureCharacteristic(super.device) {
    histories['measurement'] = History<double>(maxEntries: 360, maxAge: 60);
    super.sendBeforeUnsubscribe = true;
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['measurement'];
    var value = lastValue;
    if (null != value || null != history) history!.append(value!);
  }

  @override
  double fromUint8List(Uint8List list) {
    /// https://github.com/oesmith/gatt-xml/blob/master/org.bluetooth.characteristic.temperature.xml
    ///
    /// Format: little-endian
    /// Bytes:
    /// [Temperature: 2] ˚C*100
    ///
    if (list.isEmpty) return 0;
    return list.buffer.asByteData().getUint16(0, Endian.little).toDouble() / 100;
  }

  @override
  Uint8List toUint8List(double? value) => Uint8List(2); // we are not writing
}

class CharacteristicList with Debug {
  final Map<String, CharacteristicListItem> _items = {};

  BleCharacteristic? get(String name) {
    return _items.containsKey(name) ? _items[name]!.characteristic : null;
  }

  void set(String name, CharacteristicListItem item) => _items[name] = item;

  void addAll(Map<String, CharacteristicListItem> items) => _items.addAll(items);

  void dispose() {
    logD("dispose");
    _items.forEach((_, item) => item.dispose());
    _items.clear();
  }

  void forEachCharacteristic(void Function(String, BleCharacteristic?) f) =>
      _items.forEach((String name, CharacteristicListItem item) => f(name, item.characteristic));

  Future<void> forEachListItem(Future<void> Function(String, CharacteristicListItem) f) async {
    for (MapEntry e in _items.entries) {
      await f(e.key, e.value);
    }
  }

  BleCharacteristic? byUuid(Uuid serviceUuid, Uuid charUuid) {
    BleCharacteristic? ret;
    logD('service: $serviceUuid char: $charUuid');
    forEachCharacteristic((name, char) {
      if (char != null &&
          char.serviceUUID.isNotEmpty &&
          char.charUUID.isNotEmpty &&
          Uuid.parse(char.serviceUUID) == serviceUuid &&
          Uuid.parse(char.charUUID) == charUuid) {
        ret = char;
        return;
      }
    });
    return ret;
  }
}

class CharacteristicListItem {
  bool subscribeOnConnect;
  BleCharacteristic? characteristic;

  CharacteristicListItem(
    this.characteristic, {
    this.subscribeOnConnect = true,
  });

  void dispose() {
    characteristic?.dispose();
  }
}
