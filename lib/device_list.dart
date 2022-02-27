import 'dart:async';
import 'dart:developer' as dev;

import 'package:espmui/util.dart';

import 'device.dart';
import 'preferences.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'util.dart';

/// Singleton class
class DeviceList {
  static final DeviceList _instance = DeviceList._construct();
  Map<String, Device> _items = {};
  Map<String, Device> get devices => _items;
  final _controller = StreamController<Map<String, Device>>.broadcast();
  Stream<Map<String, Device>> get stream => _controller.stream;

  /// returns a singleton
  factory DeviceList() {
    return _instance;
  }

  DeviceList._construct() {
    dev.log('$runtimeType _construct()');
    _loadSaved();
    //_controller
  }

  Future<void> _loadSaved() async {
    (await Preferences().getDevices()).value.forEach((str) {
      var device = Device.fromSaved(str);
      device?.autoConnect.value = true;
      if (null != device) addOrUpdate(device);
    });
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
        print("$runtimeType addOrUpdate adding ${device.peripheral!.name}");
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
        //print("$runtimeType addFromScanResult already exists: ${existing.peripheral.name}");
        existing.lastScanRssi = result.rssi;
        //var device = Device.fromScanResult(result);
        //if (existing.runtimeType != device.runtimeType) dev.log("$runtimeType type mismatch: existing: ${existing.runtimeType} new: ${existing.runtimeType}");
        return existing;
      },
      ifAbsent: () {
        Device device = Device.fromScanResult(result);
        print("$runtimeType addFromScanResult adding ${device.peripheral!.name}");
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
    print("$runtimeType dispose");
    _items.forEach((_, device) => device.dispose());
    _items.clear();
    _controller.close();
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  void forEach(void Function(String, Device) f) => _items.forEach(f);
}
