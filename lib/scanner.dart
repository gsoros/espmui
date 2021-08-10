import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'ble.dart';
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

  final String apiServiceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";

  // scanResult
  StreamSubscription<ScanResult>? scanResultSubscription;

  // scanning
  bool scanning = false;
  final StreamController<bool> scanningStreamController =
      StreamController<bool>.broadcast();
  StreamSubscription? scanningSubscription;

  // devices
  DeviceList availableDevices = DeviceList();
  Device? _selected;
  final StreamController<Device> availableDevicesStreamController =
      StreamController<Device>.broadcast();
  StreamSubscription? availableDevicesSubscription;

  BLE get ble => BLE();

  Scanner._construct() {
    print("$tag _construct()");
    _init();
  }

  void _init() async {
    print("$tag _init()");
    scanningSubscription = scanningStreamController.stream.listen(
      (value) {
        scanning = value;
        print("$tag scanningSubscription: $value");
      },
    );
    availableDevicesSubscription =
        availableDevicesStreamController.stream.listen(
      (device) {
        bool isNew = !availableDevices.containsIdentifier(device.identifier);
        //availableDevices.addOrUpdate(device);
        print("$tag availableDevicesSubscription: " +
            device.identifier +
            " new=$isNew rssi=${device.rssi}");
      },
    );
    startScan();
    print("$tag _init() done");
  }

  void dispose() async {
    print("$tag dispose()");
    await scanResultSubscription?.cancel();
    await scanningStreamController.close();
    await scanningSubscription?.cancel();
    await availableDevicesStreamController.close();
    await availableDevicesSubscription?.cancel();
    await ble.dispose();
    availableDevices.dispose();
    _selected?.dispose();
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
        if (availableDevices.isEmpty) print("$tag No devices found");
      },
    );
    streamSendIfNotClosed(scanningStreamController, true);
    scanResultSubscription = ble.manager
        .startPeripheralScan(
          uuids: [apiServiceUUID],
        )
        .asBroadcastStream()
        .listen(
          (scanResult) {
            Device? device = availableDevices.addOrUpdate(scanResult);
            print("$tag Device found: ${device?.name} ${device?.identifier}");
            streamSendIfNotClosed(availableDevicesStreamController, device);
          },
          onError: (e) => bleError(tag, "scanResultSubscription", e),
        );
  }

  Future<void> stopScan() async {
    print("$tag stopScan()");
    await scanResultSubscription?.cancel();
    await ble.manager.stopPeripheralScan();
    streamSendIfNotClosed(scanningStreamController, false);
  }

  void select(Device device) {
    print("$tag Selected " + (device.name ?? "!!unnamed device!!"));
    if (_selected?.identifier != device.identifier) _selected?.disconnect();
    _selected = device;
    //print("$tag select() calling connect()");
    //device.connect();
  }
}
