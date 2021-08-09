// @dart=2.9
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'deviceRoute.dart';
import 'device.dart';
import 'scanner.dart';

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

class ScannerRoute extends StatefulWidget {
  final Scanner scanner;

  ScannerRoute({Key key, this.scanner}) : super(key: key);

  @override
  ScannerRouteState createState() => ScannerRouteState(scanner);
}

class ScannerRouteState extends State<ScannerRoute> {
  final String tag = "[ScannerState]";
  final Scanner scanner;
  final String defaultTitle = "Devices";
  final GlobalKey<ScannerRouteState> _scannerStateKey =
      GlobalKey<ScannerRouteState>();

  ScannerRouteState(this.scanner) {
    print("$tag construct");
  }

  @override
  void initState() {
    print("$tag initState()");
    super.initState();
  }

  @override
  void dispose() {
    print("$tag dispose()");
    scanner.dispose();
    super.dispose();
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
      stream: scanner.scanningStreamController.stream,
      initialData: scanner.scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        String status = snapshot.data
            ? "Scanning..."
            : scanner.availableDevices.length.toString() +
                " device" +
                (scanner.availableDevices.length == 1 ? "" : "s") +
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
      stream: scanner.scanningStreamController.stream,
      initialData: scanner.scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        return ElevatedButton(
          onPressed: snapshot.data ? null : scanner.startScan,
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
      stream: scanner.availableDevicesStreamController.stream,
      //initialData: availableDevices,
      builder: (BuildContext context, AsyncSnapshot<Device> snapshot) {
        // TODO don't rebuild the whole list, just the changed items
        print("[_deviceList()] rebuilding");
        List<Widget> items = [];
        if (scanner.availableDevices.length < 1)
          items.add(Center(child: Text("No devices found")));
        scanner.availableDevices.forEach(
          (id, device) {
            print("[_deviceList()] adding ${device.name} ${device.rssi}");
            items.add(_deviceListItem(device));
          },
        );
        return RefreshIndicator(
          key: _scannerStateKey,
          onRefresh: () {
            scanner.startScan();
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
              scanner.select(device);
              print("[_deviceListItem] onPressed(): stopScan() and connect()");
              // Some phones have an issue with connecting while scanning
              await scanner.stopScan();
              await device.connect();
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
