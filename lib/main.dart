// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(EspmUiApp());
}

class EspmUiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESPMUI',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.red,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.red,
        ),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: EspmPage(title: 'ESPM UI'),
    );
  }
}

class EspmPage extends StatefulWidget {
  EspmPage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  EspmPageState createState() => EspmPageState();
}

class EspmPageState extends State<EspmPage> {
  final String defaultTitle = "ESPM Devices";
  String title;
  StreamSubscription<BluetoothState> adapterListener;
  StreamSubscription<ScanResult> scanListener;
  StreamSubscription<PeripheralConnectionState> deviceListener;
  BleManager bleManager = BleManager();
  bool initDone = false;
  bool scanning = false;
  Map<String, Peripheral> availablePeripherals = {};
  Peripheral _selected;
  PeripheralConnectionState _connectionState;

  @override
  Widget build(BuildContext context) {
    if (!initDone) _init();
    return Scaffold(
      appBar: AppBar(
        title: Text(title == null ? defaultTitle : title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _contentsView(),
        ),
      ),
    );
  }

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
      if (availablePeripherals.isEmpty) print("No devices found");
    });
    setState(() {
      scanning = true;
    });
    scanListener = bleManager.startPeripheralScan(
      uuids: ["55bebab5-1857-4b14-a07b-d4879edad159"],
    ).listen((scanResult) {
      setState(() {
        availablePeripherals[scanResult.peripheral.identifier] =
            scanResult.peripheral;
      });
      print(
          "Device found: ${scanResult.peripheral.name} (${scanResult.peripheral.identifier})");
    });
  }

  List<Widget> _deviceScanView() {
    List<Widget> widgets = [Text("deviceScanView")];
    setState(() {
      title = defaultTitle;
    });
    if (!scanning && availablePeripherals.isEmpty)
      widgets.add(Text("No devices found"));
    else
      availablePeripherals.forEach((id, peripheral) {
        widgets.add(ElevatedButton(
            onPressed: () {
              _select(peripheral);
              _connect(peripheral);
            },
            child: Text(
              peripheral.name,
            )));
      });
    if (scanning)
      widgets.add(ElevatedButton(onPressed: null, child: Text("Scanning...")));
    else
      widgets.add(ElevatedButton(onPressed: _scan, child: Text("Scan")));
    return widgets;
  }

  List<Widget> _deviceView() {
    List<Widget> widgets = [Text("deviceView")];
    if (_connectionState != PeripheralConnectionState.connected) {
      widgets.add(ElevatedButton(
          onPressed: () {
            _connect(_selected);
          },
          child: Text(
            "Connect",
          )));
      return widgets;
    }
    widgets.add(ElevatedButton(
        onPressed: () {
          _disconnect(_selected);
          _select(null);
          _scan();
        },
        child: Text("Disconnect")));
    return widgets;
  }

  List<Widget> _contentsView() {
    if (_selected != null) return _deviceView();
    return _deviceScanView();
  }

  void _select(Peripheral peripheral) {
    print("Selected ${peripheral != null ? peripheral.name : "null"}");
    setState(() {
      _selected = peripheral;
    });
    _updateTitle();
  }

  void _setConnectionState(PeripheralConnectionState state) {
    print("State $state");
    setState(() {
      _connectionState = state;
    });
    _updateTitle();
  }

  void _updateTitle() {
    String device = _selected != null ? _selected.name : "...";
    String state = _connectionState != null
        ? _connectionState
            .toString()
            .substring(_connectionState.toString().lastIndexOf(".") + 1)
        : "...";
    setState(() {
      title = "Device $device $state";
    });
  }

  void _connect(Peripheral peripheral) async {
    deviceListener = peripheral
        .observeConnectionState(
      emitCurrentValue: true,
      completeOnDisconnect: false,
    )
        .listen((connectionState) {
      print("Peripheral ${peripheral.identifier}: $connectionState");
      _setConnectionState(connectionState);
    });
    if (!await peripheral.isConnected()) {
      print("Connecting to ${peripheral.name}");
      try {
        await peripheral.connect();
      } catch (e) {
        print(e.toString());
      }
    } else
      print("Not connecting to ${peripheral.name}, already connected");
  }

  void _disconnect(Peripheral peripheral) async {
    await peripheral.disconnectOrCancelConnection();
    await deviceListener.cancel();
    _setConnectionState(null);
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
