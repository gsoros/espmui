// @dart=2.9
import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device.dart';
import 'util.dart';

class DeviceList {
  final String tag = "[DeviceList]";
  Map<String, Device> _devices = {};

  bool containsIdentifier(String identifier) {
    return _devices.containsKey(identifier);
  }

  // if a device with the same identifier already exists, updates name, rssi and lastSeen
  // otherwise adds new device
  // returns the new or updated device
  Device addOrUpdate(ScanResult scanResult) {
    double now = DateTime.now().millisecondsSinceEpoch / 1000;
    _devices.update(
      scanResult.peripheral.identifier,
      (existing) {
        print(
            "$tag updating ${scanResult.peripheral.name} rssi=${scanResult.rssi}");
        existing.peripheral.name = scanResult.peripheral.name;
        existing.rssi = scanResult.rssi;
        existing.lastSeen = now;
        return existing;
      },
      ifAbsent: () {
        print(
            "$tag adding ${scanResult.peripheral.name} rssi=${scanResult.rssi}");
        return Device(
          scanResult.peripheral,
          rssi: scanResult.rssi,
          lastSeen: now,
        );
      },
    );
    return _devices[scanResult.peripheral.identifier];
  }

  Device byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _devices[identifier];
    return null;
  }

  void dispose() {
    Device device = _devices.remove(_devices.keys.first);
    while (null != device) {
      device.dispose();
      device = _devices.remove(_devices.keys.first);
    }
  }

  int get length => _devices.length;
  bool get isEmpty => _devices.isEmpty;
  void forEach(void Function(String, Device) f) => _devices.forEach(f);
}

class Scanner {
  final String tag = "[Scanner]";
  final String apiServiceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final BleManager bleManager;

  StreamSubscription<BluetoothState> bluetoothStateSubscription;
  //final StreamController<BluetoothState> bluetoothStateController =
  //    StreamController<BluetoothState>.broadcast();

  // scanResult
  StreamSubscription<ScanResult> scanResultSubscription;

  // scanning
  bool scanning = false;
  final StreamController<bool> scanningStreamController =
      StreamController<bool>.broadcast();
  StreamSubscription scanningSubscription;

  // devices
  DeviceList availableDevices = DeviceList();
  Device _selected;
  final StreamController<Device> availableDevicesStreamController =
      StreamController<Device>.broadcast();
  StreamSubscription availableDevicesSubscription;

  Scanner(this.bleManager) {
    _init();
  }

  void _init() async {
    print("$tag _init()");
    await _checkPermissions();
    await bleManager.createClient();
    await _checkAdapter();
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
    await bluetoothStateSubscription.cancel();
    await scanResultSubscription.cancel();
    await scanningStreamController.close();
    await scanningSubscription.cancel();
    await availableDevicesStreamController.close();
    await availableDevicesSubscription.cancel();
    await bleManager.destroyClient();
    availableDevices.dispose();
    if (_selected != null) _selected.dispose();
  }

  void startScan() async {
    if (scanning) {
      print("$tag startScan() already scanning");
      return;
    }
    if (await bleManager.bluetoothState() != BluetoothState.POWERED_ON) {
      bleError(tag, "startScan() adapter not powered on");
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
    scanResultSubscription = bleManager
        .startPeripheralScan(
          uuids: [apiServiceUUID],
        )
        .asBroadcastStream()
        .listen(
          (scanResult) {
            Device device = availableDevices.addOrUpdate(scanResult);
            print("$tag Device found: ${device.name} ${device.identifier}");
            streamSendIfNotClosed(availableDevicesStreamController, device);
          },
          onError: (e) => bleError(tag, "scanResultSubscription", e),
        );
  }

  Future<void> stopScan() async {
    print("$tag stopScan()");
    await scanResultSubscription.cancel();
    await bleManager.stopPeripheralScan();
    streamSendIfNotClosed(scanningStreamController, false);
  }

  void select(Device device) {
    print("$tag Selected " + device.name);
    if (_selected != null && _selected.identifier != device.identifier)
      _selected.disconnect();
    _selected = device;
    //print("$tag select() calling connect()");
    //device.connect();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    print("$tag Checking permissions");
    if (!await Permission.location.request().isGranted) {
      bleError(tag, "No location permission");
      return Future.error(Exception("$tag Location permission not granted"));
    }
    if (!await Permission.bluetooth.request().isGranted) {
      bleError(tag, "No blootueth permission");
      return Future.error(Exception("$tag Bluetooth permission not granted"));
    }
  }

  Future<void> _checkAdapter() async {
    if (bluetoothStateSubscription != null) {
      await bluetoothStateSubscription.cancel();
    }
    bluetoothStateSubscription = bleManager
        .observeBluetoothState()
        .handleError(
          (e) => bleError(tag, "observeBluetoothState()", e),
        )
        .listen(
      (btState) async {
        print("$tag " + btState.toString());
        if (btState == BluetoothState.POWERED_ON) {
          // Probably not a good idea to automatically scan, as of Android 7,
          // starting and stopping scans more than 5 times in a window of
          // 30 seconds will temporarily disable scanning
          //print("$tag Adapter powered on, starting scan");
          //startScan();
          if (_selected != null) {
            print("$tag Adapter powered on, connecting to ${_selected.name}");
            _selected.connect();
          }
        } else {
          bleError(tag, "Adapter not powered on");
          if (Platform.isAndroid) {
            //await bleManager.cancelTransaction("autoEnableBT");
            await bleManager
                .enableRadio(transactionId: "autoEnableBT")
                .catchError((e) => bleError(tag, "enableRadio()", e));
          }
        }
      },
      onError: (e) => bleError(tag, "bluetoothStateSubscription", e),
    );
    return Future.value(null);
  }
}
