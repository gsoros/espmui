import 'dart:async';
//import 'dart:developer' as dev;

import 'package:espmui/device_widgets.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
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
  const DeviceListRoute({super.key});

  @override
  DeviceListRouteState createState() => DeviceListRouteState();
}

class DeviceListRouteState extends State<DeviceListRoute> with Debug {
  final String defaultTitle = "Devices";
  final _key = GlobalKey<DeviceListRouteState>();
  Scanner get scanner => Scanner();

  DeviceListRouteState() {
    logD("construct");
  }

  @override
  void initState() {
    super.initState();
    logD("initState()");
  }

  @override
  void dispose() {
    logD("dispose()");
    //scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          _appBarTitle(),
          ifNotReady: (state) => BleNotReady(state),
        ),
      ),
      body: Container(
        margin: const EdgeInsets.all(6),
        child: _list(),
      ),
    );
  }

  Widget _appBarTitle() {
    return Row(
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
    );
  }

  Widget _status() {
    return StreamBuilder<bool>(
      stream: scanner.scanningStream,
      initialData: scanner.scanning,
      builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
        String status = "";
        if (snapshot.hasData) {
          status = snapshot.data! ? "Scanning..." : "${scanner.devices.length} device${scanner.devices.length == 1 ? "" : "s"}";
        }
        return Text(
          status,
          style: const TextStyle(fontSize: 10),
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
        return EspmuiElevatedButton(onPressed: scanning ? null : scanner.startScan, child: const Text("Scan"));
      },
    );
  }

  Widget _list() {
    var devices = DeviceList().devices;
    return StreamBuilder<Map<String, Device>>(
      stream: DeviceList().stream,
      initialData: devices,
      builder: (BuildContext context, AsyncSnapshot<Map<String, Device>> snapshot) {
        //logD("_list() rebuilding");
        List<Widget> items = [];
        if (devices.isEmpty) {
          items.add(const Center(child: Text("No devices")));
        } else {
          List<Device> sorted = devices.values.toList(growable: false);
          sorted.sort((a, b) {
            // if (a.autoConnect.value == b.autoConnect.value) return a.name?.compareTo(b.name ?? "") ?? -1;
            // return a.autoConnect.value ? 1 : -1;
            return a.name.compareTo(b.name);
          });
          for (var device in sorted) {
            //logD("_list() adding ${device.runtimeType} ${device.name} ${device.lastScanRssi}");
            items.add(_listItem(device));
          }
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
    return InkWell(
      onTap: () {
        openDevice(device);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 6),
        decoration: const BoxDecoration(
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
                        device.name.isNotEmpty ? device.name : 'Unnamed device',
                        style: const TextStyle(fontSize: 18),
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
                                    return FavoriteIcon(active: value);
                                  }),
                              ValueListenableBuilder(
                                  valueListenable: device.autoConnect,
                                  builder: (context, bool value, _) {
                                    return AutoConnectIcon(active: value);
                                  }),
                              StreamBuilder(
                                  stream: device.stateStream,
                                  initialData: device.lastConnectionState,
                                  builder: (context, snapshot) {
                                    return ConnectionStateIcon(state: snapshot.data);
                                    /*
                                    if (snapshot.hasData) {
                                      return ConnectionStateIcon(state: snapshot.data);
                                    }
                                    return Text(
                                      " ",
                                      style: TextStyle(fontSize: 10),
                                    );
                                    */
                                  }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    0 < device.lastScanRssi ? "rssi: ${device.lastScanRssi}" : " ",
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                openDevice(device);
              },
              child: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }

  void openDevice(Device device) {
    if (scanner.scanning) scanner.stopScan();
    if (!device.connected) device.connect();
    Navigator.push(
      context,
      PageTransition(
        type: PageTransitionType.rightToLeft,
        child: DeviceRoute(device),
      ),
    );
  }
}
