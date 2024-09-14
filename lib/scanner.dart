import 'dart:async';

// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'ble.dart';
import 'ble_constants.dart';
import 'device_list.dart';
import 'util.dart';
import 'debug.dart';

/// singleton class
class Scanner with Debug {
  static final Scanner _instance = Scanner._construct();

  /// returns a singleton
  factory Scanner() {
    return _instance;
  }

  /// ScanResult
  StreamSubscription<DiscoveredDevice>? _scanResultSubscription;

  /// Scanning
  bool scanning = false;
  final _scanningController = StreamController<bool>.broadcast();
  StreamSubscription? _scanningSubscription;
  Stream<bool> get scanningStream => _scanningController.stream;

  var devices = DeviceList();
  final _resultController = StreamController<DiscoveredDevice>.broadcast();
  StreamSubscription<DiscoveredDevice>? _resultSubscription;
  Stream<DiscoveredDevice> get resultStream => _resultController.stream;

  BLE get ble => BLE();

  Timer? _stopTimer;

  Scanner._construct() {
    logD("_construct()");
    _init();
  }

  void _init() async {
    logD("_init()");
    _scanningSubscription = scanningStream.listen(
      (value) {
        scanning = value;
        //logD("scanningSubscription: $value");
      },
    );
    _resultSubscription = resultStream.listen(
      (result) {
        devices.addFromScanResult(result);
        //bool isNew = !devices.containsIdentifier(result.peripheral.identifier);
        //logD("_resultSubscription: ${result.peripheral.identifier} new=$isNew rssi=${result.rssi}");
      },
    );
    logD("_init() done");
  }

  void dispose() async {
    logD("dispose()");
    await _scanResultSubscription?.cancel();
    await _scanningController.close();
    await _scanningSubscription?.cancel();
    await _resultController.close();
    await _resultSubscription?.cancel();
    //await devices.dispose();
    //await ble.dispose();
  }

  void startScan() async {
    if (scanning) {
      logD("startScan() already scanning");
      return;
    }
    if (await ble.currentStatus() != BleStatus.ready) {
      bleError(runtimeType.toString(), "startScan() adapter not ready, state is: ${await ble.currentStatus()}");
      return;
    }
    if (_stopTimer != null) _stopTimer!.cancel();
    _stopTimer = Timer(
      const Duration(seconds: 5),
      () async {
        await stopScan();
      },
    );
    streamSendIfNotClosed(_scanningController, true);
    logD("starting scan");
    _scanResultSubscription = (await ble.manager).scanForDevices(
      withServices: [
        Uuid.parse(BleConstants.ESPM_API_SERVICE_UUID),
        Uuid.parse(BleConstants.ESPCC_API_SERVICE_UUID),
        Uuid.parse(BleConstants.HOMEAUTO_API_SERVICE_UUID),
        Uuid.parse(BleConstants.CYCLING_POWER_SERVICE_UUID),
        Uuid.parse(BleConstants.HEART_RATE_SERVICE_UUID),
      ],
    )
        //.asBroadcastStream()
        .listen(
      (result) {
        // devices.addFromScanResult(result);
        logD("Device found: ${result.name} ${result.id}");
        streamSendIfNotClosed(_resultController, result);
      },
      onError: (e) => bleError(runtimeType.toString(), "scanResultSubscription", e),
      onDone: () => streamSendIfNotClosed(_scanningController, false),
      cancelOnError: false,
    );
  }

  Future<void> stopScan() async {
    //logD("stopScan()");
    if (_stopTimer != null) {
      _stopTimer!.cancel();
      _stopTimer = null;
    }
    await _scanResultSubscription?.cancel();
    streamSendIfNotClosed(_scanningController, false);
  }
}

/*
class ScanResultList {
  Map<String, ScanResult> _items = {};

  ScanResultList() {
    logD("construct");
  }

  bool containsIdentifier(String identifier) {
    return _items.containsKey(identifier);
  }

  /// Adds or updates an item from a [ScanResult]
  ///
  /// If an item with the same identifier already exists, updates the item,
  /// otherwise adds new item.
  /// Returns the new or updated [ScanResult] or null on error.
  ScanResult? addOrUpdate(ScanResult scanResult) {
    final subject = scanResult.peripheral.name.toString() + " rssi=" + scanResult.rssi.toString();
    _items.update(
      scanResult.peripheral.identifier,
      (existing) {
        logD("updating $subject");
        existing = scanResult;
        return existing;
      },
      ifAbsent: () {
        logD("adding $subject");
        return scanResult;
      },
    );
    return _items[scanResult.peripheral.identifier];
  }

  ScanResult? byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _items[identifier];
    return null;
  }

  Future<void> dispose() async {
    logD("dispose");
    //_items.forEach((_, scanResult) => scanResult.dispose());
    _items.clear();
  }

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  void forEach(void Function(String, ScanResult) f) => _items.forEach(f);
}
*/