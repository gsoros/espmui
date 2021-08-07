// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'deviceRoute.dart';
import 'device.dart';

class DeviceList {
  final String tag = "[DeviceList]";
  Map<String, Device> _devices = {};

  bool containsIdentifier(String identifier) {
    return _devices.containsKey(identifier);
  }

  // if a device with the same identifier already exists, updates rssi and lastSeen
  // otherwise adds device
  void addOrUpdate(Device device) {
    _devices.update(
      device.identifier,
      (existing) {
        print("$tag updating ${device.name} rssi=${device.rssi}");
        existing.rssi = device.rssi;
        if (existing.lastSeen < device.lastSeen)
          existing.lastSeen = device.lastSeen;
        return existing;
      },
      ifAbsent: () {
        print("$tag adding ${device.name} rssi=${device.rssi}");
        return device;
      },
    );
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

class ScannerRoute extends StatefulWidget {
  final BleManager bleManager;

  ScannerRoute({Key key, this.bleManager}) : super(key: key);

  @override
  ScannerRouteState createState() => ScannerRouteState(bleManager);
}

class ScannerRouteState extends State<ScannerRoute> {
  final String tag = "[ScannerState]";
  final String apiServiceUUID = "55bebab5-1857-4b14-a07b-d4879edad159";
  final BleManager bleManager;
  final String defaultTitle = "Devices";
  final GlobalKey<ScannerRouteState> _scannerStateKey =
      GlobalKey<ScannerRouteState>();

  StreamSubscription<BluetoothState> bluetoothStateSubscription;
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

  ScannerRouteState(this.bleManager) {
    _init();
  }

  void _init() async {
    print("$tag _init()");
    await _checkPermissions();
    await _checkAdapter();
    await bleManager.createClient();
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
        availableDevices.addOrUpdate(device);
        print("$tag availableDevicesSubscription: " +
            device.identifier +
            " new=$isNew rssi=${device.rssi}");
      },
    );
    startScan();
    print("$tag _init() done");
  }

  @override
  void dispose() {
    print("$tag dispose()");
    bluetoothStateSubscription.cancel();
    scanResultSubscription.cancel();
    bleManager.destroyClient();
    scanningStreamController.close();
    scanningSubscription.cancel();
    availableDevicesStreamController.close();
    availableDevicesSubscription.cancel();
    availableDevices.dispose();
    if (_selected != null) _selected.dispose();
    super.dispose();
  }

  void startScan() {
    if (scanning) {
      print("[ScannerState] startScan() already scanning");
      return;
    }
    Timer(
      Duration(seconds: 3),
      () async {
        await scanResultSubscription.cancel();
        await bleManager.stopPeripheralScan();
        scanningStreamController.sink.add(false);
        if (availableDevices.isEmpty) print("[ScannerState] No devices found");
      },
    );
    scanningStreamController.add(true);
    scanResultSubscription = bleManager.startPeripheralScan(
      uuids: [apiServiceUUID],
    ).listen(
      (scanResult) {
        availableDevicesStreamController.sink.add(
          Device(
            scanResult.peripheral,
            rssi: scanResult.rssi,
            lastSeen: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        );
        print("$tag Device found: " +
            scanResult.peripheral.name +
            " " +
            scanResult.peripheral.identifier);
      },
    );
  }

  void select(Device device) {
    print(
        "$tag Selected " + (device.peripheral != null ? device.name : "null"));
    if (_selected != null && _selected.identifier != device.identifier)
      _selected.disconnect();
    //setState(() {
    _selected = device;
    //});
    print("$tag select() calling connect()");
    device.connect();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    print("$tag Checking permissions");
    if (!await Permission.location.request().isGranted) {
      print("$tag No location permission");
      return Future.error(Exception("$tag Location permission not granted"));
    }
    if (!await Permission.bluetooth.request().isGranted) {
      print("$tag No blootueth permission");
      return Future.error(Exception("$tag Bluetooth permission not granted"));
    }
  }

  Future<void> _checkAdapter() {
    try {
      bluetoothStateSubscription =
          bleManager.observeBluetoothState().handleError((e) {
        print("$tag _checkAdapter() handleE: " + e.toString());
      }).listen(
        (btState) async {
          print("$tag " + btState.toString());
          if (btState != BluetoothState.POWERED_ON) {
            print("$tag Adapter not powered on");
            if (Platform.isAndroid) await bleManager.enableRadio();
          }
        },
      );
    } catch (e) {
      print("$tag _checkAdapter() catchE: " + e.toString());
    }
    return Future.value(null);
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
        print("[_deviceList()] rebuilding");
        List<Widget> items = [];
        if (availableDevices.length < 1)
          items.add(Center(child: Text("No devices found")));
        availableDevices.forEach(
          (id, device) {
            print("[_deviceList()] adding ${device.name} ${device.rssi}");
            items.add(_deviceListItem(device));
          },
        );
        return RefreshIndicator(
          key: _scannerStateKey,
          onRefresh: () {
            startScan();
            return Future.value(null);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: items,
          ),
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
                  device.name,
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
            onPressed: () async {
              //select(device);
              //print("[_deviceListItem] onPressed() calling connect()");
              //device.connect();
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    //select(device);
                    return DeviceRoute(device);
                  },
                ),
              );
            },
            child: Icon(Icons.arrow_forward),
          ),
        ],
      ),
    );
  }
}
