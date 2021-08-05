// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device.dart';

class DeviceList {
  Map<String, Device> _devices = {};

  bool containsIdentifier(String identifier) {
    return _devices.containsKey(identifier);
  }

  // if a device with the same identifier already exists, updates rssi and lastSeen, and returns false
  // otherwise adds device and returns true
  bool addOrUpdate(Device device) {
    Device existing = byIdentifier(device.peripheral.identifier);
    if (existing != null) {
      existing.rssi = device.rssi;
      if (existing.lastSeen < device.lastSeen)
        existing.lastSeen = device.lastSeen;
      return false;
    }
    _devices[device.peripheral.identifier] = device;
    return true;
  }

  Device byIdentifier(String identifier) {
    if (containsIdentifier(identifier)) return _devices[identifier];
    return null;
  }

  int get length => _devices.length;
  bool get isEmpty => _devices.isEmpty;
  void forEach(void Function(String, Device) f) => _devices.forEach(f);
}

class Scanner extends StatefulWidget {
  final BleManager bleManager;

  Scanner({Key key, this.bleManager}) : super(key: key);

  @override
  ScannerState createState() => ScannerState(bleManager);
}

class ScannerState extends State<Scanner> {
  final BleManager bleManager;
  final String defaultTitle = "Devices";

  StreamSubscription<BluetoothState> bluetoothStateSubscription;
  StreamSubscription<ScanResult> scanResultSubscription;

  // scanning
  bool scanning = false;
  final StreamController<bool> scanningStreamController =
      StreamController<bool>.broadcast();
  StreamSubscription scanningSubscription;

  // devices
  DeviceList availableDevices = DeviceList();
  final StreamController<Device> availableDevicesStreamController =
      StreamController<Device>.broadcast();
  StreamSubscription availableDevicesSubscription;
  Device _selected;

  ScannerState(this.bleManager) {
    _init();
  }

  void _init() async {
    await _checkPermissions();
    await _checkAdapter();
    await bleManager.createClient();
    scanningSubscription = scanningStreamController.stream.listen(
      (value) {
        scanning = value;
        print("scanningSubscription: $value");
      },
    );
    availableDevicesSubscription =
        availableDevicesStreamController.stream.listen(
      (device) {
        bool isNew = availableDevices.addOrUpdate(device);
        print("availableDevicesSubscription: " +
            device.peripheral.identifier +
            " new=$isNew");
      },
    );
    startScan();
    print("ScannerState init done");
  }

  @override
  void dispose() {
    print("ScannerState dispose");
    bluetoothStateSubscription.cancel();
    scanResultSubscription.cancel();
    bleManager.destroyClient();
    scanningStreamController.close();
    scanningSubscription.cancel();
    availableDevicesStreamController.close();
    availableDevicesSubscription.cancel();
    super.dispose();
  }

  void startScan() {
    if (scanning) {
      print("Already scanning");
      return;
    }
    Timer(
      Duration(seconds: 3),
      () async {
        await scanResultSubscription.cancel();
        await bleManager.stopPeripheralScan();
        scanningStreamController.sink.add(false);
        if (availableDevices.isEmpty) print("No devices found");
      },
    );
    scanningStreamController.add(true);
    scanResultSubscription = bleManager.startPeripheralScan(
      uuids: ["55bebab5-1857-4b14-a07b-d4879edad159"],
    ).listen(
      (scanResult) {
        availableDevicesStreamController.sink.add(
          Device(
            scanResult.peripheral,
            rssi: scanResult.rssi,
            lastSeen: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        );
        print("Device found: " +
            scanResult.peripheral.name +
            " " +
            scanResult.peripheral.identifier);
      },
    );
  }

  void select(Device device) {
    print("Selected " +
        (device.peripheral != null ? device.peripheral.name : "null"));
    if (_selected != null) _selected.dispose();
    setState(
      () {
        _selected = device;
      },
    );
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    print("Checking permissions");
    if (!await Permission.location.request().isGranted) {
      print("No location permission");
      return Future.error(Exception("Location permission not granted"));
    }
    if (!await Permission.bluetooth.request().isGranted) {
      print("No blootueth permission");
      return Future.error(Exception("Bluetooth permission not granted"));
    }
  }

  Future<void> _checkAdapter() async {
    bluetoothStateSubscription = bleManager.observeBluetoothState().listen(
      (btState) {
        print(btState);
        if (btState != BluetoothState.POWERED_ON) {
          if (Platform.isAndroid) bleManager.enableRadio();
          print("Adapter not powered on");
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _appBar(),
      body: Container(
        margin: EdgeInsets.all(6),
        child: _deviceList(),
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      title: Container(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align left
                children: [
                  Row(children: [
                    Text(defaultTitle),
                  ]),
                  Row(
                    children: [
                      _status(),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end, // Align right
              children: [_scanButton()],
            )
          ],
        ),
      ),
    );
  }

  Widget _status() {
    return StreamBuilder<bool>(
      stream: scanningStreamController.stream,
      initialData: scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        String status = snapshot.data
            ? "Scanning..."
            : availableDevices.length.toString() +
                " device" +
                (availableDevices.length == 1 ? "" : "s") +
                " found";
        return Text(
          status,
          style: TextStyle(fontSize: 10),
        );
      },
    );
  }

  Widget _scanButton() {
    return StreamBuilder<bool>(
      stream: scanningStreamController.stream,
      initialData: scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        return ElevatedButton(
          onPressed: snapshot.data ? null : startScan,
          child: Text("Scan"),
          style: ButtonStyle(
            backgroundColor: MaterialStateProperty.resolveWith((state) {
              return state.contains(MaterialState.disabled)
                  ? Colors.red.shade400
                  : Colors.red.shade900;
            }),
            foregroundColor: MaterialStateProperty.resolveWith((state) {
              return state.contains(MaterialState.disabled)
                  ? Colors.grey
                  : Colors.white;
            }),
          ),
        );
      },
    );
  }

  Widget _deviceList() {
    return StreamBuilder<Device>(
      stream: availableDevicesStreamController.stream,
      //initialData: availableDevices,
      builder: (BuildContext context, AsyncSnapshot<Device> snapshot) {
        if (availableDevices.length < 1)
          return Center(child: Text("No devices found"));
        List<Widget> items = [];
        availableDevices.forEach(
          (id, device) {
            items.add(_deviceListItem(device));
          },
        );
        return ListView(
          children: items,
        );
      },
    );
  }

  Widget _deviceListItem(Device device) {
    return Container(
      padding: EdgeInsets.all(10),
      margin: EdgeInsets.fromLTRB(0, 0, 0, 6),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.all(
          Radius.circular(10),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.peripheral.name,
                  style: TextStyle(fontSize: 18),
                ),
                Text(
                  "rssi: " + device.rssi.toString(),
                  style: TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              select(device);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    return device.screen();
                  },
                ),
              );
              device.connect();
            },
            child: Text("Connect"),
          ),
        ],
      ),
    );
  }
}
