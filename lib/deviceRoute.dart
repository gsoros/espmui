// @dart=2.9
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'device.dart';
import 'bleCharacteristic.dart';

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
    BleCharacteristic battery = device.characteristic("battery");
    BleCharacteristic power = device.characteristic("power");
    BleCharacteristic api = device.characteristic("api");
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: battery.stream,
            initialData: battery.lastValue,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              return Text(
                "Battery: ${snapshot.data.toString()}%",
              );
            },
          ),
          StreamBuilder<Uint8List>(
            stream: power.stream,
            initialData: power.lastValue,
            builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
              return Text(
                "Power: ${snapshot.data.toString()}",
              );
            },
          ),
          StreamBuilder<String>(
            stream: api.stream,
            initialData: api.lastValue,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              return Text(
                "Api: ${snapshot.data}",
              );
            },
          ),
        ],
      ),
    );
  }
}
