import 'dart:async';
//import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:page_transition/page_transition.dart';

import 'ble.dart';
import 'device_route.dart';
import 'device.dart';
import 'device_list.dart';
import 'scanner.dart';
//import 'preferences.dart';
import 'util.dart';
import 'debug.dart';

class DeviceListRoute extends StatefulWidget {
  DeviceListRoute({Key? key}) : super(key: key);

  @override
  DeviceListRouteState createState() => DeviceListRouteState();
}

class DeviceListRouteState extends State<DeviceListRoute> with Debug {
  final String defaultTitle = "Devices";
  final _key = GlobalKey<DeviceListRouteState>();
  Scanner get scanner => Scanner();

  DeviceListRouteState() {
    debugLog("construct");
  }

  @override
  void initState() {
    super.initState();
    debugLog("initState()");
  }

  @override
  void dispose() {
    debugLog("dispose()");
    //scanner.dispose();
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
          status = snapshot.data! ? "Scanning..." : scanner.devices.length.toString() + " device" + (scanner.devices.length == 1 ? "" : "s");
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
        return EspmuiElevatedButton(child: Text("Scan"), onPressed: scanning ? null : scanner.startScan);
      },
    );
  }

  Widget _list() {
    var devices = DeviceList().devices;
    return StreamBuilder<Map<String, Device>>(
      stream: DeviceList().stream,
      initialData: devices,
      builder: (BuildContext context, AsyncSnapshot<Map<String, Device>> snapshot) {
        //debugLog("_list() rebuilding");
        List<Widget> items = [];
        if (devices.length < 1)
          items.add(Center(child: Text("No devices")));
        else {
          List<Device> sorted = devices.values.toList(growable: false);
          sorted.sort((a, b) {
            // if (a.autoConnect.value == b.autoConnect.value) return a.name?.compareTo(b.name ?? "") ?? -1;
            // return a.autoConnect.value ? 1 : -1;
            return a.name?.compareTo(b.name ?? "") ?? -1;
          });
          sorted.forEach(
            (device) {
              //debugLog("_list() adding ${device.runtimeType} ${device.name} ${device.lastScanRssi}");
              items.add(_listItem(device));
            },
          );
        }
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

  Widget _listItem(Device device) {
    Color active = Color.fromARGB(255, 128, 255, 128);
    Color inactive = Colors.grey;
    return InkWell(
      onTap: () {
        openDevice(device);
      },
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
                  Row(
                    children: [
                      Icon(device.iconData),
                      Text(
                        device.name ?? "Unnamed device",
                        style: TextStyle(fontSize: 18),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ValueListenableBuilder(
                                  valueListenable: device.remember,
                                  builder: (context, bool value, _) {
                                    if (value) return Icon(Icons.star, size: 28, color: active);
                                    return Icon(Icons.star, size: 28, color: inactive);
                                  }),
                              ValueListenableBuilder(
                                  valueListenable: device.autoConnect,
                                  builder: (context, bool value, _) {
                                    if (value) return Icon(Icons.autorenew, size: 28, color: active);
                                    return Icon(Icons.autorenew, size: 28, color: inactive);
                                  }),
                              StreamBuilder(
                                  stream: device.stateStream,
                                  initialData: device.lastConnectionState,
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData) {
                                      if (snapshot.data == PeripheralConnectionState.connected)
                                        return Icon(Icons.link, size: 28, color: active);
                                      else if (snapshot.data == PeripheralConnectionState.connecting)
                                        return Icon(Icons.search, size: 28, color: Colors.yellow);
                                      else if (snapshot.data == PeripheralConnectionState.disconnected)
                                        return Icon(Icons.link_off, size: 28, color: inactive);
                                      else if (snapshot.data == PeripheralConnectionState.disconnecting) return Icon(Icons.cut, size: 28, color: Colors.red);
                                    }
                                    return Text(
                                      " ",
                                      style: TextStyle(fontSize: 10),
                                    );
                                  }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    0 < device.lastScanRssi ? "rssi: ${device.lastScanRssi}" : " ",
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                openDevice(device);
              },
              child: Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }

  void openDevice(Device device) {
    if (scanner.scanning) scanner.stopScan();
    if (PeripheralConnectionState.connected != device.lastConnectionState) device.connect();
    Navigator.push(
      context,
      PageTransition(
        type: PageTransitionType.rightToLeft,
        child: DeviceRoute(device),
      ),
    );
  }
}
