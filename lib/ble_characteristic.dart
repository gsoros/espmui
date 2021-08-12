import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'util.dart';
import 'ble.dart';

abstract class BleCharacteristic<T> {
  final String tag = "[Characteristic]";
  Peripheral _peripheral;
  String serviceUUID = "";
  String characteristicUUID = "";
  CharacteristicWithValue? _characteristic;
  Stream<Uint8List>? _rawStream;
  StreamSubscription<Uint8List>? _subscription;
  final _controller = StreamController<T>.broadcast();
  T? lastValue;

  Stream<T> get stream => _controller.stream;

  BleCharacteristic(this._peripheral) {
    lastValue = fromUint8List(Uint8List.fromList([]));
    print("$tag construct " + _peripheral.identifier);
  }

  T fromUint8List(Uint8List list);
  Uint8List toUint8List(T value);

  /// read value from characteristic and set lastValue
  Future<T?> read() async {
    if (null == _characteristic) {
      bleError(tag, "read() characteristic is null");
      return fromUint8List(Uint8List.fromList([]));
    }
    if (!_characteristic!.isReadable) {
      bleError(tag, "read() characteristic not readable");
      return fromUint8List(Uint8List.fromList([]));
    }
    lastValue = fromUint8List(await _characteristic!.read().catchError((e) {
      bleError(tag, "read()", e);
      return Uint8List.fromList([]);
    }));
    return lastValue;
  }

  Future<void> write(
    T value, {
    bool withResponse = false,
    String? transactionId,
  }) {
    if (_characteristic == null) {
      bleError(tag, "write() characteristic is null");
      return Future.value(null);
    }
    if (!_characteristic!.isWritableWithoutResponse &&
        !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writable");
      return Future.value(null);
    }
    if (withResponse && !_characteristic!.isWritableWithResponse) {
      bleError(tag, "write() characteristic not writableWithResponse");
      return Future.value(null);
    }
    return _characteristic!
        .write(
      toUint8List(value),
      withResponse,
      transactionId: transactionId,
    )
        .catchError((e) {
      bleError(tag, "write($value)", e);
    });
  }

  void subscribe() async {
    print("$tag subscribe()");
    if (_subscription != null) {
      bleError(tag, "already subscribed");
      return;
    }
    /*
    _characteristic = await _peripheral.readCharacteristic(serviceUUID, characteristicUUID).catchError((e) {
      bleError(tag, "readCharacteristic()", e);
      return Future.value(null);
    });
    */
    try {
      _characteristic =
          await _peripheral.readCharacteristic(serviceUUID, characteristicUUID);
    } catch (e) {
      bleError(tag, "readCharacteristic()", e);
      //  print("$tag readCharacteristic() serviceUUID: $serviceUUID, characteristicUUID: $characteristicUUID, $e");
    }
    if (_characteristic == null) {
      bleError(tag, "subscribe() characteristic is null");
      return;
    }
    await read();
    print("$tag subscribe() initial value: $lastValue");
    streamSendIfNotClosed(_controller, lastValue);
    if (!_characteristic!.isIndicatable && !_characteristic!.isNotifiable) {
      bleError(tag, "characteristic neither indicatable nor notifiable");
      return;
    }
    _rawStream = _characteristic!.monitor().handleError((e) {
      bleError(tag, "_rawStream", e);
    }).asBroadcastStream();
    if (_rawStream == null) {
      bleError(tag, "subscribe() _rawStream is null");
      return;
    }
    _subscription = _rawStream!.listen(
      (value) async {
        lastValue = await onNotify(fromUint8List(value));
        //print("$tag $lastValue");
        streamSendIfNotClosed(_controller, lastValue);
      },
      onError: (e) => bleError(tag, "subscription", e),
    );
  }

  Future<T?> onNotify(T value) {
    return Future.value(value);
  }

  Future<void> unsubscribe() async {
    if (_subscription == null) return;
    print("$tag unsubscribe");
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await unsubscribe();
    await _controller.close();
  }
}

class BatteryCharacteristic extends BleCharacteristic<int> {
  final String tag = "[BatteryCharacteristic]";
  final String serviceUUID = "0000180f-0000-1000-8000-00805f9b34fb";
  final String characteristicUUID = "00002a19-0000-1000-8000-00805f9b34fb";

  BatteryCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  int fromUint8List(Uint8List list) => list.isEmpty ? 0 : list.first;

  @override
  Uint8List toUint8List(int value) {
    if (value < 0)
      bleError(tag, "toUint8List() negative value");
    else if (255 < value) bleError(tag, "toUint8List() $value clipped");
    return Uint8List.fromList([value]);
  }
}

class PowerCharacteristic extends BleCharacteristic<Uint8List> {
  final String tag = "[PowerCharacteristic]";
  final String serviceUUID = "00001818-0000-1000-8000-00805f9b34fb";
  final String characteristicUUID = "00002a63-0000-1000-8000-00805f9b34fb";

  PowerCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  Uint8List fromUint8List(Uint8List list) => list;

  @override
  Uint8List toUint8List(Uint8List value) => value;
}

class ApiCharacteristic extends BleCharacteristic<String> {
  final String tag = "[ApiCharacteristic]";
  final String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final String characteristicUUID = "da34811a-03c0-4efe-a266-ed014e181b65";

  ApiCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  String fromUint8List(Uint8List list) => String.fromCharCodes(list);

  @override
  Uint8List toUint8List(String value) {
    Uint8List list = Uint8List.fromList([]);
    try {
      list = ascii.encode(value);
    } catch (e) {
      print("$tag error: failed to ascii encode '$value': $e");
      List<int> valid = [];
      for (int code in value.codeUnits) if (code < 256) valid.add(code);
      list = Uint8List.fromList(valid);
    }
    return list;
  }

  @override
  Future<String?> onNotify(String value) {
    // read full value as the notification is limited to 20 bytes
    return read();
  }
}

class ApiStrainCharacteristic extends BleCharacteristic<double> {
  final String tag = "[ApiStrainCharacteristic]";
  final String serviceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final String characteristicUUID = "1d7fd29e-86bc-4640-86b5-00fa3462b480";

  ApiStrainCharacteristic(Peripheral peripheral) : super(peripheral);

  @override
  double fromUint8List(Uint8List list) => list.isNotEmpty
      ? list.buffer.asByteData().getFloat32(0, Endian.little)
      : 0.0;

  @override
  Uint8List toUint8List(double value) =>
      Uint8List(4)..buffer.asByteData().setFloat32(0, value, Endian.little);
}
