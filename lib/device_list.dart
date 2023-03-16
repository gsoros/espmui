import 'dart:async';
import 'dart:developer' as dev;

import 'package:espmui/util.dart';
import 'package:mutex/mutex.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'device.dart';
import 'preferences.dart';
//import 'util.dart';
import 'debug.dart';

/// Singleton class
class DeviceList with Debug {
  static final DeviceList _instance = DeviceList._construct();
  static int _instances = 0;
  Map<String, Device> _items = {};
  Map<String, Device> get devices => _items;
  final _controller = StreamController<Map<String, Device>>.broadcast();
  Stream<Map<String, Device>> get stream => _controller.stream;
  bool _loaded = false;
  final _exclusiveAccess = Mutex();

  /// returns a singleton
  factory DeviceList() {
    return _instance;
  }

  DeviceList._construct() {
    _instances++;
    logD('_construct() # of instances: $_instances');
    load();
    //_controller
  }

  Map<String, Device> where(bool filter(String k, Device v)) => Map.from(_items)..removeWhere((k, v) => !filter(k, v));

  Future<void> load({bool reload = false}) async {
    if (_loaded && !reload) return;
    await _exclusiveAccess.protect(() async {
      if (_loaded && !reload) return;
      var saved = await Preferences().getDevices();
      for (String str in saved.value) {
        var device = await Device.fromSaved(str);
        if (null != device) {
          addOrUpdate(device);
          if (device.autoConnect.value) device.connect();
        }
      }
    });
    _loaded = true;
  }

  bool containsIdentifier(String identifier) {
    return _items.containsKey(identifier);
  }

  /// Adds or updates an item
  ///
  /// If an item with the same identifier already exists, updates the item disposing of the old one,
  /// otherwise adds new item.
  /// Returns the new or updated [Device] or null on error.
  Device? addOrUpdate(Device device) {
    if (null == device.peripheral) return null;
    var id = device.peripheral!.identifier;
    _items.update(
      id,
      (existing) {
        dev.log("$runtimeType addOrUpdate Warning: updating ${device.peripheral!.name}, calling dispose() on old device");
        existing.dispose();
        existing = device;
        return existing;
      },
      ifAbsent: () {
        logD("addOrUpdate adding ${device.peripheral!.name}");
        return device;
      },
    );
    var item = byIdentifier(id);
    if (null != item) streamSendIfNotClosed(_controller, {id: item});
    return item;
  }

  /// Adds a [Device] from a [ScanResult]
  ///
  /// If a [Device] with the same identifier already exists, updates [lastScanRssi]
  /// and returns the existing item, otherwise adds new item.
  /// Returns the new or updated [Device] or null on error.
  Device? addFromScanResult(ScanResult result) {
    _items.update(
      result.peripheral.identifier,
      (existing) {
        //logD("addFromScanResult already exists: ${existing.peripheral.name}");
        existing.lastScanRssi = result.rssi;
        //var device = Device.fromScanResult(result);
        //if (existing.runtimeType != device.runtimeType) dev.log("$runtimeType type mismatch: existing: ${existing.runtimeType} new: ${existing.runtimeType}");
        return existing;
      },
      ifAbsent: () {
        Device device = Device.fromScanResult(result);
        logD("addFromScanResult adding ${device.peripheral!.name}");
        return device;
      },
    );
    var item = byIdentifier(result.peripheral.identifier);
    if (null != item) streamSendIfNotClosed(_controller, {result.peripheral.identifier: item});
    return item;
  }

  Device? byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _items[identifier];
    return null;
  }

  Future<void> dispose() async {
    logD("dispose");
    _items.forEach((_, device) => device.dispose());
    _items.clear();
    _controller.close();
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  void forEach(void Function(String, Device) f) => _items.forEach(f);
}
