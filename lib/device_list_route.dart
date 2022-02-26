import 'dart:async';
//import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:page_transition/page_transition.dart';

import 'ble.dart';
import 'device_route.dart';
import 'device.dart';
import 'scanner.dart';
import 'preferences.dart';
import 'util.dart';

class DeviceListRoute extends StatefulWidget {
  DeviceListRoute({Key? key}) : super(key: key);

  @override
  DeviceListRouteState createState() => DeviceListRouteState();
}

class DeviceListRouteState extends State<DeviceListRoute> {
  final String defaultTitle = "Devices";
  final _key = GlobalKey<DeviceListRouteState>();
  Scanner get scanner => Scanner();
  late AlwaysNotifier<List<String>> savedDevices;
  late DeviceList devices;

  DeviceListRouteState() {
    print("$runtimeType construct");
  }

  @override
  void initState() {
    super.initState();
    print("$runtimeType initState()");
    _loadSavedDevices();
    devices = DeviceList();
  }

  void _loadSavedDevices() async {
    savedDevices = await Preferences().getDevices();
  }

  @override
  void dispose() {
    print("$runtimeType dispose()");
    scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          _appBarTitle(),
          ifDisabled: (state) => BleDisabled(state),
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: _list(),
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
          status = snapshot.data! ? "Scanning..." : scanner.devices.length.toString() + " device" + (scanner.devices.length == 1 ? "" : "s") + " found";
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
        return EspmuiElevatedButton("Scan", action: scanning ? null : scanner.startScan);
      },
    );
  }

  Widget _list() {
    return StreamBuilder<ScanResult>(
      stream: scanner.resultStream,
      //initialData: availableDevices,
      builder: (BuildContext context, AsyncSnapshot<ScanResult> snapshot) {
        // TODO don't rebuild the whole list, just the changed items
        print("$runtimeType _list() rebuilding");
        List<Widget> items = [];
        if (scanner.devices.length < 1) items.add(Center(child: Text("No devices found")));
        scanner.devices.forEach(
          (identifier, device) {
            //print("$runtimeType _list() adding ${device.runtimeType} ${device.name} ${snapshot.data?.rssi}");
            items.add(_availableListItem(device));
          },
        );
        return RefreshIndicator(
          key: _key,
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

/*
  Widget _scanResultListItem(ScanResult result) {
    void openDevice() async {
      //await Navigator.push(context,
      //    MaterialPageRoute(builder: (context) => DeviceRoute(device)));

      var device = Device.fromScanResult(result);

      Navigator.push(
        context,
        PageTransition(
          type: PageTransitionType.rightToLeft,
          child: DeviceRoute(device),
        ),
      );
      print("[_deviceListItem] openDevice(): stopScan() and connect()");
      //Some phones have an issue with connecting while scanning
      await scanner.stopScan();
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
                  ValueListenableBuilder<List<String>>(
                    valueListenable: savedDeviceNames,
                    builder: (_, devices, __) {
                      dev.log('$runtimeType devicesNotifier fired');
                      return Text(
                        (devices.any((item) => item.endsWith(result.peripheral.identifier)) ? 'AC ' : '   ') +
                            (result.advertisementData.localName ?? "Unnamed device"),
                        style: TextStyle(fontSize: 18),
                      );
                    },
                  ),
                  Text(
                    "rssi: " + result.rssi.toString(),
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
*/

  Widget _availableListItem(Device device) {
    void openDevice() async {
      if (scanner.scanning) scanner.stopScan();
      device.connect();
      Navigator.push(
        context,
        PageTransition(
          type: PageTransitionType.rightToLeft,
          child: DeviceRoute(device),
        ),
      );
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
                    "rssi: ${device.lastScanRssi}",
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
