import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:page_transition/page_transition.dart';

import 'ble.dart';
import 'device_route.dart';
import 'device.dart';
import 'scanner.dart';
import 'preferences.dart';
import 'util.dart';

class ScannerRoute extends StatefulWidget {
  ScannerRoute({Key? key}) : super(key: key);

  @override
  ScannerRouteState createState() => ScannerRouteState();
}

class ScannerRouteState extends State<ScannerRoute> {
  final String tag = "[ScannerState]";
  final String defaultTitle = "Devices";
  final GlobalKey<ScannerRouteState> _scannerStateKey = GlobalKey<ScannerRouteState>();
  Scanner get scanner => Scanner();
  late AlwaysNotifier<List<String>> savedDevices;

  ScannerRouteState() {
    print("$tag construct");
  }

  @override
  void initState() {
    super.initState();
    print("$tag initState()");
    _loadSavedDevices();
  }

  void _loadSavedDevices() async {
    savedDevices = await Preferences().getDevices();
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
        title: BleAdapterCheck(
          _appBarTitle(),
          ifDisabled: (state) => BleDisabled(state),
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: _resultList(),
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
          status = snapshot.data! ? "Scanning..." : scanner.resultList.length.toString() + " device" + (scanner.resultList.length == 1 ? "" : "s") + " found";
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

  Widget _resultList() {
    return StreamBuilder<ScanResult>(
      stream: scanner.resultStream,
      //initialData: availableDevices,
      builder: (BuildContext context, AsyncSnapshot<ScanResult> snapshot) {
        // TODO don't rebuild the whole list, just the changed items
        print("[_resultList()] rebuilding");
        List<Widget> items = [];
        if (scanner.resultList.length < 1) items.add(Center(child: Text("No devices found")));
        scanner.resultList.forEach(
          (identifier, result) {
            print("[_resultList()] adding ${result.advertisementData.localName} ${result.rssi}");
            items.add(_resultListItem(result));
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

  Widget _resultListItem(ScanResult result) {
    void openDevice() async {
      //await Navigator.push(context,
      //    MaterialPageRoute(builder: (context) => DeviceRoute(device)));

      var device = createDevice(result);

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
                    valueListenable: savedDevices,
                    builder: (_, devices, __) {
                      dev.log('$tag devicesNotifier fired');
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
}
