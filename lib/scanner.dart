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
  DeviceList devices = DeviceList();
  Device? selected;
  final _devicesController = StreamController<Device>.broadcast();
  StreamSubscription? _devicesSubscription;
  Stream<Device> get devicesStream => _devicesController.stream;

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
    _devicesSubscription = devicesStream.listen(
      (device) {
        bool isNew = !devices.containsIdentifier(device.identifier);
        //availableDevices.addOrUpdate(device);
        print("$tag devicesSubscription: " +
            device.identifier +
            " new=$isNew rssi=${device.rssi}");
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
    await _devicesController.close();
    await _devicesSubscription?.cancel();
    await ble.dispose();
    devices.dispose();
    selected?.dispose();
  }

  void startScan() async {
    if (scanning) {
      print("$tag startScan() already scanning");
      return;
    }
    if (await ble.currentState() != BluetoothState.POWERED_ON) {
      bleError(
          tag,
          "startScan() adapter not powered on, state is: " +
              (await ble.currentState()).toString());
      return;
    }
    Timer(
      Duration(seconds: 3),
      () async {
        await stopScan();
        if (devices.isEmpty) print("$tag No devices found");
      },
    );
    streamSendIfNotClosed(_scanningController, true);
    _scanResultSubscription = ble.manager
        .startPeripheralScan(
          uuids: [BleConstants.CYCLING_POWER_SERVICE_UUID],
        )
        .asBroadcastStream()
        .listen(
          (scanResult) {
            Device? device = devices.addOrUpdate(scanResult);
            print("$tag Device found: ${device?.name} ${device?.identifier}");
            streamSendIfNotClosed(_devicesController, device);
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
