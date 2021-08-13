import 'dart:async';

import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

import 'ble.dart';
import 'device_route.dart';
import 'device.dart';
import 'scanner.dart';
import 'util.dart';

class ScannerRoute extends StatefulWidget {
  ScannerRoute({Key? key}) : super(key: key);

  @override
  ScannerRouteState createState() => ScannerRouteState();
}

class ScannerRouteState extends State<ScannerRoute> {
  final String tag = "[ScannerState]";
  final String defaultTitle = "Devices";
  final GlobalKey<ScannerRouteState> _scannerStateKey =
      GlobalKey<ScannerRouteState>();
  Scanner get scanner => Scanner();

  ScannerRouteState() {
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
      appBar: AppBar(
        title: bleByState(
          ifEnabled: _appBarTitle,
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: _deviceList(),
      ),
    );
  }

  Widget _appBarTitle() {
    return Container(
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
    );
  }

  Widget _status() {
    return StreamBuilder<bool>(
      stream: scanner.scanningStream,
      initialData: scanner.scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        String status = "";
        if (snapshot.hasData)
          status = snapshot.data!
              ? "Scanning..."
              : scanner.devices.length.toString() +
                  " device" +
                  (scanner.devices.length == 1 ? "" : "s") +
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
      stream: scanner.scanningStream,
      initialData: scanner.scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        bool scanning = snapshot.hasData ? snapshot.data! : false;
        return espmuiElevatedButton("Scan",
            action: scanning ? null : scanner.startScan);
      },
    );
  }

  Widget _deviceList() {
    return StreamBuilder<Device>(
      stream: scanner.devicesStream,
      //initialData: availableDevices,
      builder: (BuildContext context, AsyncSnapshot<Device> snapshot) {
        // TODO don't rebuild the whole list, just the changed items
        print("[_deviceList()] rebuilding");
        List<Widget> items = [];
        if (scanner.devices.length < 1)
          items.add(Center(child: Text("No devices found")));
        scanner.devices.forEach(
          (_, device) {
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
    void openDevice() async {
      //await Navigator.push(context,
      //    MaterialPageRoute(builder: (context) => DeviceRoute(device)));

      Navigator.push(
        context,
        PageTransition(
          type: PageTransitionType.rightToLeft,
          child: DeviceRoute(device),
        ),
      );
      scanner.select(device);
      print("[_deviceListItem] openDevice(): stopScan() and connect()");
      //Some phones have an issue with connecting while scanning
      //await scanner.stopScan();
      device.connect();
    }

    return InkWell(
      onTap: openDevice,
      child: Container(
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
                    device.name ?? "Unnamed device",
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
              onPressed: openDevice,
              child: Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }
}
