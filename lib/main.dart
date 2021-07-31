// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESPMUI',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: MyHomePage(title: 'Devices'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  StreamSubscription<BluetoothState> adapterListener;
  StreamSubscription<ScanResult> scanListener;
  BleManager bleManager = BleManager();
  bool initDone = false;
  bool scanning = false;
  Map<String, AvailableDevice> availableDevices = {};

  void _init() async {
    await _checkPermissions();
    await _checkAdapter();
    await bleManager.createClient();
    _scan();
    setState(() {
      initDone = true;
    });
    print("Init done");
  }

  @override
  void dispose() async {
    print("State dispose");
    await adapterListener.cancel();
    await scanListener.cancel();
    await bleManager.destroyClient();
    initDone = false;
    super.dispose();
  }

  void _scan() {
    if (scanning) {
      print("Already scanning");
      return;
    }
    Timer(Duration(seconds: 3), () async {
      await scanListener.cancel();
      await bleManager.stopPeripheralScan();
      setState(() {
        scanning = false;
      });
      if (availableDevices.isEmpty) print("No devices found");
    });
    setState(() {
      scanning = true;
    });
    scanListener = bleManager.startPeripheralScan(
      uuids: ["55bebab5-1857-4b14-a07b-d4879edad159"],
    ).listen((scanResult) {
      setState(() {
        availableDevices[scanResult.peripheral.identifier] =
            AvailableDevice(scanResult.peripheral, scanResult.rssi);
      });
      print(
          "Device found: ${scanResult.peripheral.name} (${scanResult.peripheral.identifier})");
    });
  }

  List<Widget> _deviceList() {
    List<Widget> widgets = [];
    if (!scanning && availableDevices.isEmpty)
      widgets.add(Text("No devices found"));
    else
      availableDevices.forEach((id, device) {
        widgets.add(ElevatedButton(
            onPressed: device.connect,
            child: Text(
              device.peripheral.name + " " + device.rssi.toString(),
            )));
      });
    if (scanning)
      widgets.add(Text("Scanning..."));
    else
      widgets.add(ElevatedButton(onPressed: _scan, child: Text("Scan")));
    return widgets;
  }

  void _connectDevice(Peripheral peripheral) {
    peripheral
        .observeConnectionState(
      emitCurrentValue: true,
      completeOnDisconnect: true,
    )
        .listen((connectionState) {
      print("Peripheral ${peripheral.identifier}: $connectionState");
    });
    peripheral.connect();
    //bool connected = await peripheral.isConnected();
    //await peripheral.disconnectOrCancelConnection();
  }

  @override
  Widget build(BuildContext context) {
    if (!initDone) _init();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _deviceList(),
        ),
      ),
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
    adapterListener = bleManager.observeBluetoothState().listen((btState) {
      print(btState);
      if (btState != BluetoothState.POWERED_ON) {
        if (Platform.isAndroid) bleManager.enableRadio(); //ANDROID-ONLY
        print("Adapter not powered on");
      }
    });
  }
}

class AvailableDevice {
  final Peripheral peripheral;
  final int rssi;

  const AvailableDevice(this.peripheral, this.rssi);

  void connect() {
    peripheral
        .observeConnectionState(
      emitCurrentValue: true,
      completeOnDisconnect: true,
    )
        .listen((connectionState) {
      print("Peripheral ${peripheral.identifier}: $connectionState");
    });
    peripheral.connect();
    //bool connected = await peripheral.isConnected();
    //await peripheral.disconnectOrCancelConnection();
  }
}
