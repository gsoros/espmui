// @dart=2.9
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'device.dart';

class DeviceRoute extends StatefulWidget {
  final String tag = "[DevicePage]";
  final Device device;

  DeviceRoute(this.device) {
    print("$tag construct");
  }

  @override
  DeviceRouteState createState() {
    print("$tag createState()");
    return DeviceRouteState(device);
  }
}

class DeviceRouteState extends State<DeviceRoute> {
  final String tag = "[DeviceRouteState]";
  Device device;

  DeviceRouteState(this.device) {
    print("$tag construct");
  }

  @override
  void dispose() async {
    print("$tag ${device.name} dispose");
    super.dispose();
    device.disconnect();
  }

  Future<bool> _onBackPressed() {
    device.disconnect();
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    print("$tag build() calling device.connect()");
    device.connect();
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        appBar: _appBar(),
        body: Container(
          margin: EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
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
                    Text(device.name),
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
              children: [_connectButton()],
            )
          ],
        ),
      ),
    );
  }

  Widget _status() {
    return StreamBuilder<PeripheralConnectionState>(
      stream: device.connectionStateStreamController.stream,
      initialData: device.connectionState,
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState> snapshot) {
        String connState = snapshot.data.toString();
        print("$tag _status() connState: $connState");
        return Text(
          connState.substring(connState.lastIndexOf(".") + 1),
          style: TextStyle(fontSize: 10),
        );
      },
    );
  }

  Widget _connectButton() {
    return StreamBuilder<PeripheralConnectionState>(
      stream: device.connectionStateStreamController.stream,
      initialData: device.connectionState,
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState> snapshot) {
        Function action;
        String label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          action = device.disconnect;
          label = "Disconnect";
        }
        if (snapshot.data == PeripheralConnectionState.disconnected)
          action = device.connect;
        return ElevatedButton(
          onPressed: action,
          child: Text(label),
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

  Widget _deviceProperties() {
    return Container(
      child: Column(
        children: [
          StreamBuilder<Uint8List>(
            stream: device.battery.controller.stream,
            initialData: device.battery.currentValue,
            builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
              int val = snapshot.data.length > 0 ? snapshot.data.first : 0;
              return Text(
                "Battery: ${val.toString()}%",
              );
            },
          ),
          StreamBuilder<Uint8List>(
            stream: device.power.controller.stream,
            initialData: device.power.currentValue,
            builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
              return Text(
                "Power: ${snapshot.data.toString()}",
              );
            },
          ),
        ],
      ),
    );
  }
}
