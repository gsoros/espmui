import 'dart:async';

import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble.dart';
import 'ble_constants.dart';
import 'device.dart';
import 'util.dart';

/// singleton class
class Scanner {
  static final Scanner _instance = Scanner._construct();
  final String tag = "[Scanner]";

  /// returns a singleton
  factory Scanner() {
    return _instance;
  }

  /// ScanResult
  StreamSubscription<ScanResult>? _scanResultSubscription;

  /// Scanning
  bool scanning = false;
  final _scanningController = StreamController<bool>.broadcast();
  StreamSubscription? _scanningSubscription;
  Stream<bool> get scanningStream => _scanningController.stream;

  /// Available devices
  var resultList = ScanResultList();
  Device? selected;
  final _resultController = StreamController<ScanResult>.broadcast();
  StreamSubscription? _resultSubscription;
  Stream<ScanResult> get resultStream => _resultController.stream;

  BLE get ble => BLE();

  Scanner._construct() {
    print("$tag _construct()");
    _init();
  }

  void _init() async {
    print("$tag _init()");
    _scanningSubscription = scanningStream.listen(
      (value) {
        scanning = value;
        print("$tag scanningSubscription: $value");
        if (!scanning) selected?.connect();
      },
    );
    _resultSubscription = resultStream.listen(
      (result) {
        bool isNew = !resultList.containsIdentifier(result.peripheral.identifier);
        //availableDevices.addOrUpdate(device);
        print("$tag _resultSubscription: ${result.peripheral.identifier} new=$isNew rssi=${result.rssi}");
      },
    );
    startScan();
    print("$tag _init() done");
  }

  void dispose() async {
    print("$tag dispose()");
    await _scanResultSubscription?.cancel();
    await _scanningController.close();
    await _scanningSubscription?.cancel();
    await _resultController.close();
    await _resultSubscription?.cancel();
    await resultList.dispose();
    await selected?.dispose();
    await ble.dispose();
  }

  void startScan() async {
    if (scanning) {
      print("$tag startScan() already scanning");
      return;
    }
    if (await ble.currentState() != BluetoothState.POWERED_ON) {
      bleError(tag, "startScan() adapter not powered on, state is: " + (await ble.currentState()).toString());
      return;
    }
    Timer(
      Duration(seconds: 3),
      () async {
        await stopScan();
        if (resultList.isEmpty) print("$tag No devices found");
      },
    );
    streamSendIfNotClosed(_scanningController, true);
    _scanResultSubscription = ble.manager
        .startPeripheralScan(
          uuids: [
            BleConstants.CYCLING_POWER_SERVICE_UUID,
            BleConstants.ESPM_API_SERVICE_UUID,
            BleConstants.HEART_RATE_SERVICE_UUID,
          ],
        )
        .asBroadcastStream()
        .listen(
          (scanResult) {
            ScanResult? updatedResult = resultList.addOrUpdate(scanResult);
            print("$tag Device found: ${updatedResult?.advertisementData.localName} ${updatedResult?.peripheral.identifier}");
            streamSendIfNotClosed(_resultController, updatedResult);
          },
          onError: (e) => bleError(tag, "scanResultSubscription", e),
        );
  }

  Future<void> stopScan() async {
    print("$tag stopScan()");
    await _scanResultSubscription?.cancel();
    await ble.manager.stopPeripheralScan();
    streamSendIfNotClosed(_scanningController, false);
  }

  void select(Device device) {
    print("$tag Selected " + (device.name ?? "!!unnamed device!!"));
    if (selected?.identifier != device.identifier) {
      selected?.disconnect();
      selected?.shouldConnect = false;
    }
    selected = device;
    selected?.shouldConnect = true;
    //print("$tag select() calling connect()");
    //device.connect();
  }
}
