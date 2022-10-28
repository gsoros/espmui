import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'dart:collection';

import 'package:espmui/api.dart';
import 'package:flutter/material.dart';

import 'package:espmui/debug.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:mutex/mutex.dart';

import 'util.dart' as util;
import 'ble.dart';
import 'ble_constants.dart';
import 'device.dart';
import 'espm.dart';
import 'espcc.dart';

abstract class BleCharacteristic<T> with Debug {
  Device device;
  final serviceUUID = "";
  final charUUID = "";
  //CharacteristicWithValue? _characteristicWithValue;
  Characteristic? _characteristic;
  Stream<Uint8List>? _rawStream;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<T>.broadcast();
  T? lastValue;
  Uint8List? lastRawValue;

  /// mutex shared with BLE
  final _exclusiveAccess = BLE().mutex;

  /// Histories associated with the streams
  Map<String, CharacteristicHistory> histories = {};

  Stream<T> get defaultStream => _controller.stream;

  BleCharacteristic(this.device) {
    debugLog("construct ${device.peripheral?.identifier}");
    lastValue = fromUint8List(Uint8List.fromList([]));
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
    String tag = "readAsUint8List()";
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
      value = await _characteristic?.read().catchError((e) {
        bleError(debugTag, tag, e);
        error = true;
        return Uint8List.fromList([]);
      });
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
    String? transactionId,
    Characteristic? char,
  }) async {
    await _init();
    if (char == null) char = _characteristic;
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
    //debugLog("write($value)");
    await _exclusiveAccess.protect(() async {
      if (null == char) return;
      char
          .write(
        toUint8List(value),
        withResponse,
        transactionId: transactionId,
      )
          .catchError((e) {
        bleError(debugTag, "write($value)", e);
      });
    });
  }

  Future<void> subscribe() async {
    debugLog("subscribe()");
    if (_subscription != null) {
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
    _rawStream = _characteristic?.monitor().handleError((e) {
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
          lastValue = await onNotify(fromUint8List(value));
          //debugLog("$lastValue");
          util.streamSendIfNotClosed(_controller, lastValue);
          _appendToHistory();
        },
        onError: (e) => bleError(debugTag, "subscription", e),
      );
    });
    await read();
    _appendToHistory();
    debugLog("subscribe() initial value: $lastValue");
    util.streamSendIfNotClosed(_controller, lastValue);
  }

  void _appendToHistory() {
    // var history = histories['raw'];
    // if (null != lastValue || null != history) history!.append(util.uts(), lastValue!);
  }

  Future<void> unsubscribe() async {
    await _init();
    if (_subscription == null) return;
    debugLog("unsubscribe");
    util.streamSendIfNotClosed(_controller, fromUint8List(Uint8List.fromList([])));
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _init() async {
    if (_characteristic != null) return; // already init'd
    if (null == device.peripheral) {
      debugLog("_init(): peripheral is null");
      return;
    }
    if (!(await device.peripheral!.isConnected())) return;
    try {
      //_characteristic = await _peripheral.readCharacteristic(serviceUUID, characteristicUUID);
      List<Characteristic> chars = [];
      await _exclusiveAccess.protect(() async {
        chars = await device.peripheral!.characteristics(serviceUUID);
      });
      _characteristic = chars.firstWhere((char) => char.uuid == charUUID);
    } catch (e) {
      bleError(debugTag, "_init() readCharacteristic()", e);
      _characteristic = null;
      //  debugLog("readCharacteristic() serviceUUID: $serviceUUID, characteristicUUID: $characteristicUUID, $e");
    }
  }

  Future<void> deinit() async {
    //debugLog("deinit()");
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
}

class BatteryCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.BATTERY_SERVICE_UUID;
  final charUUID = BleConstants.BATTERY_LEVEL_CHAR_UUID;

  BatteryCharacteristic(Device device) : super(device) {
    histories['charge'] = CharacteristicHistory<int>(maxEntries: 3600, maxAge: 3600);
  }

  @override
  void _appendToHistory() {
    super._appendToHistory();
    var history = histories['charge'];
    if (null != lastValue || null != history) history!.append(lastValue!);
  }

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;

  @override
  Uint8List toUint8List(int value) {
    if (value < 0)
      bleError(debugTag, "toUint8List() negative value");
    else if (255 < value) bleError(debugTag, "toUint8List() $value clipped");
    return Uint8List.fromList([value]);
  }
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  final serviceUUID = BleConstants.CYCLING_POWER_SERVICE_UUID;
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

  PowerCharacteristic(Device device) : super(device) {
    _cadenceController.onListen = () {
      _timer = Timer.periodic(Duration(seconds: 2), (timer) {
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
    histories['power'] = CharacteristicHistory<int>(maxEntries: 3600, maxAge: 3600);
    histories['cadence'] = CharacteristicHistory<int>(maxEntries: 3600, maxAge: 3600);
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
  final String serviceUUID;
  final String txCharUUID;
  final String rxCharUUID;
  Characteristic? _rxChar;

  ApiCharacteristic(
    Device device, {
    this.serviceUUID = "",
    this.txCharUUID = BleConstants.API_TXCHAR_UUID,
    this.rxCharUUID = BleConstants.API_RXCHAR_UUID,
  }) : super(device);

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    Uint8List list = Uint8List.fromList([]);
    try {
      list = ascii.encode(value);
    } catch (e) {
      debugLog("error: failed to ascii encode '$value': $e");
      List<int> valid = [];
      for (int code in value.codeUnits) if (code < 256) valid.add(code);
      list = Uint8List.fromList(valid);
    }
    return list;
  }

  @override
  Future<void> write(
    String value, {
    bool withResponse = false,
    String? transactionId,
    Characteristic? char,
  }) async {
    return super.write(
      value,
      withResponse: withResponse,
      transactionId: transactionId,
      char: _rxChar,
    );
  }

  @override
  Future<void> _init() async {
    //await super._init();
    if (_rxChar != null || _characteristic != null) return; // already init'd
    if (null == device.peripheral) {
      debugLog("_init(): peripheral is null");
      return;
    }
    if (!(await device.peripheral!.isConnected())) return;
    try {
      List<Characteristic> chars = [];
      await _exclusiveAccess.protect(() async {
        chars = await device.peripheral!.characteristics(serviceUUID);
      });
      if (chars.where((char) => char.uuid == rxCharUUID).isNotEmpty) {
        _rxChar = chars.firstWhere((char) => char.uuid == rxCharUUID);
      }
      if (chars.where((char) => char.uuid == txCharUUID).isNotEmpty) {
        _characteristic = chars.firstWhere((char) => char.uuid == txCharUUID);
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
    debugLog("ApiCharacteristic::onNotify() mtu=${device.mtu} value(${value.length}) fullValue(${fullValue?.length})");
    return fullValue;
  }
}

class EspmApiCharacteristic extends ApiCharacteristic {
  ESPM get device => super.device as ESPM;
  EspmApiCharacteristic(Device device) : super(device, serviceUUID: BleConstants.ESPM_API_SERVICE_UUID);
}

class EspccApiCharacteristic extends ApiCharacteristic {
  ESPCC get device => super.device as ESPCC;
  EspccApiCharacteristic(Device device) : super(device, serviceUUID: BleConstants.ESPCC_API_SERVICE_UUID);

  @override
  Future<String?> onNotify(String value) async {
    // do not read the binary data after "success;rec=get:01231234:0;"
    String tag = "EspccApiCharacteristic::onNotify:";
    //debugLog("$tag '$value'");
    final int success = ApiResult.success;
    final int? rec = device.api.commandCode("rec");
    if (null == rec) {
      debugLog("$tag could not find command code for 'rec'");
      return super.onNotify(value);
    }
    final reg = RegExp('(^$success;$rec=get:([0-9a-zA-Z]{8}):([0-9]+);*)(.+)');
    RegExpMatch? match = reg.firstMatch(value);
    String? noBinary = match?.group(1);
    if (null != noBinary && 0 < noBinary.length) {
      // debugLog("$tag found match: '$noBinary'");
      Uint8List? valueAsList;
      if (null != device.mtu && 0 < device.mtu! && null != lastRawValue && lastRawValue!.length < device.mtu! - 5)
        valueAsList = lastRawValue;
      else
        valueAsList = await readAsUint8List();
      if (null == valueAsList || 0 == valueAsList.length) {
        debugLog("$tag could not get valueAsList");
        return super.onNotify(noBinary);
      }
      String fullValue = fromUint8List(valueAsList);
      match = reg.firstMatch(fullValue);
      String? fileName = match?.group(2);
      if (null == fileName || fileName.length < 8) {
        debugLog("$tag could not get filename");
        return super.onNotify(noBinary);
      }
      String? offsetStr = match?.group(3);
      if (null == offsetStr || offsetStr.length < 1) {
        debugLog("$tag could not get offsetStr");
        return super.onNotify(noBinary);
      }
      int? offset = int.tryParse(offsetStr);
      if (null == offset || offset < 0) {
        debugLog("$tag could not get offset");
        return super.onNotify(noBinary);
      }
      int? binaryStart = match?.group(1)?.length;
      if (null == binaryStart || binaryStart < 0 || valueAsList.length <= binaryStart) {
        debugLog("$tag could not get binaryStart");
        return super.onNotify(noBinary);
      }
      Uint8List byteData = Uint8List.sublistView(valueAsList, binaryStart);
      //debugLog("$tag file: $fileName, offset: $offset, byteData: ${byteData.length}B");
      ESPCCFile f = device.files.value.files.firstWhere(
        (candidate) => candidate.name == fileName,
        orElse: () {
          var f = ESPCCFile(fileName, device);
          f.updateLocalStatus();
          device.files.value.files.add(f);
          device.files.notifyListeners();
          return f;
        },
      );
      int written = await f.appendLocal(offset: offset, byteData: byteData);
      if (written == byteData.length) return super.onNotify(noBinary);
      debugLog("$tag file: $fileName, received: ${byteData.length}, written: $written");
      return super.onNotify("${ApiResult.localFsError};$rec=get:$fileName:$offset;");
    }
    return super.onNotify(value);
  }
}

class WeightScaleCharacteristic extends BleCharacteristic<double> {
  final serviceUUID = BleConstants.WEIGHT_SCALE_SERVICE_UUID;
  final charUUID = BleConstants.WEIGHT_MEASUREMENT_CHAR_UUID;

  WeightScaleCharacteristic(Device device) : super(device) {
    histories['measurement'] = CharacteristicHistory<double>(maxEntries: 360, maxAge: 60, absolute: true);
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
  Uint8List toUint8List(double value) => Uint8List(3)..buffer.asByteData().setInt16(1, (value * 200).round(), Endian.little);
}

class HallCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.ESPM_API_SERVICE_UUID;
  final charUUID = BleConstants.ESPM_HALL_CHAR_UUID;

  HallCharacteristic(Device device) : super(device);

  @override
  int fromUint8List(Uint8List list) {
    /// Format: little-endian
    return list.isNotEmpty ? list.buffer.asByteData().getInt16(0, Endian.little) : 0;
  }

  @override
  Uint8List toUint8List(int value) => Uint8List(2)..buffer.asByteData().setInt16(0, (value).round(), Endian.little);
}

class HeartRateCharacteristic extends BleCharacteristic<int> {
  final serviceUUID = BleConstants.HEART_RATE_SERVICE_UUID;
  final charUUID = BleConstants.HEART_RATE_MEASUREMENT_CHAR_UUID;

  HeartRateCharacteristic(Device device) : super(device) {
    histories['measurement'] = CharacteristicHistory<int>(maxEntries: 120, maxAge: 120);
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
      debugLog('fromUint8List() not enough bytes in $list');
      return heartRate;
    }
    if (byteCount == 1)
      heartRate = byteData.getUint8(1);
    else if (byteCount == 2) heartRate = byteData.getUint16(1, Endian.little);
    //debugLog("got list: $list byteCount: $byteCount hr: $heartRate');
    return heartRate;
  }

  @override
  Uint8List toUint8List(int value) => Uint8List(2); // we are not writing
}

class CharacteristicList with Debug {
  Map<String, CharacteristicListItem> _items = {};

  BleCharacteristic? get(String name) {
    return _items.containsKey(name) ? _items[name]!.characteristic : null;
  }

  void set(String name, CharacteristicListItem item) => _items[name] = item;

  void addAll(Map<String, CharacteristicListItem> items) => _items.addAll(items);

  void dispose() {
    debugLog("dispose");
    _items.forEach((_, item) => item.dispose());
    _items.clear();
  }

  void forEachCharacteristic(void Function(String, BleCharacteristic?) f) =>
      _items.forEach((String name, CharacteristicListItem item) => f(name, item.characteristic));

  Future<void> forEachListItem(Future<void> Function(String, CharacteristicListItem) f) async {
    for (MapEntry e in _items.entries) await f(e.key, e.value);
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

class CharacteristicHistory<T> with Debug {
  final _data = LinkedHashMap<int, T>();
  final int maxEntries;
  final int maxAge;
  final bool absolute;

  /// The oldest entries will be deleted when either
  /// - the number of entries exceeds [maxEntries]
  /// - or the age of the entry in seconds is greater than [maxAge].
  CharacteristicHistory({required this.maxEntries, required this.maxAge, this.absolute = false});

  /// Append a value to the history.
  /// - [timestamp]: milliseconds since Epoch
  void append(T value, {int? timestamp}) {
    if (null == timestamp) timestamp = util.uts();
    //debugLog("append timestamp: $timestamp value: $value length: ${_data.length}");
    if (absolute) {
      if (value.runtimeType == int) value = int.tryParse(value.toString())?.abs() as T;
      if (value.runtimeType == double) value = double.tryParse(value.toString())?.abs() as T;
    }
    _data[timestamp] = value;
    // Prune on every ~100 appends
    if (.99 < Random().nextDouble()) {
      if (.5 < Random().nextDouble())
        while (maxEntries < _data.length) _data.remove(_data.entries.first.key);
      else
        _data.removeWhere((time, _) => time < util.uts() - maxAge * 1000);
    }
  }

  /// [timestamp] is milliseconds since the Epoch
  Map<int, T> since({required int timestamp}) {
    Map<int, T> filtered = Map.of(_data);
    filtered.removeWhere((time, _) => time < timestamp);
    //debugLog("since  timestamp: $timestamp data: ${_data.length} filtered: ${filtered.length}");
    return filtered;
  }

  /// [timestamp] is milliseconds since the Epoch
  Widget graph({required int timestamp, Color? color}) {
    Map<int, T> filtered = since(timestamp: timestamp);
    if (filtered.length < 1) return util.Empty();
    var data = Map<int, num>.from(filtered);
    double? min;
    double? max;
    data.forEach((_, val) {
      if (null == min || val < min!) min = val.toDouble();
      if (null == max || max! < val) max = val.toDouble();
    });
    //debugLog("min: $min max: $max");
    if (null == min || null == max) return util.Empty();
    var widgets = <Widget>[];
    Color outColor = color ?? Colors.red;
    data.forEach((time, value) {
      var height = util.map(value.toDouble(), min!, max!, 0, 1000);
      widgets.add(Container(
        width: 50,
        height: (0 < height) ? height : 1,
        color: outColor, //.withOpacity((0 < height) ? .5 : 0),
        margin: EdgeInsets.all(1),
      ));
    });
    if (widgets.length < 1) return util.Empty();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: widgets,
    );
  }
}
