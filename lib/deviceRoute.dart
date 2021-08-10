import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'ble.dart';
import 'device.dart';
import 'bleCharacteristic.dart';

class DeviceRoute extends StatefulWidget {
  final String tag = "[DeviceRoute]";
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
  void initState() {
    print("$tag initState");
    super.initState();
  }

  @override
  void dispose() async {
    print("$tag ${device.name} dispose");
    device.disconnect();
    super.dispose();
  }

  Future<bool> _onBackPressed() {
    device.disconnect();
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    //print("$tag build() calling device.connect()");
    //device.connect();
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        appBar: AppBar(
          title: bleEnabledFork(
            ifEnabled: _appBarTitle,
          ),
        ),
        body: Container(
          margin: EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
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
                  Expanded(
                    child: Container(
                      height: 40,
                      alignment: Alignment.bottomLeft,
                      child: TextButton(
                        style: ButtonStyle(
                          alignment: Alignment.bottomLeft,
                          padding: MaterialStateProperty.all<EdgeInsets>(
                              EdgeInsets.all(0)),
                        ),
                        onPressed: () {},
                        onLongPress: editDeviceName,
                        child: Text(
                          device.name ?? "",
                          style: Theme.of(context).textTheme.headline6,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    ),
                  ),
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
    );
  }

  void editDeviceName() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Rename device"),
          content: TextField(
            controller: TextEditingController()..text = device.name ?? "",
            onSubmitted: (text) async {
              BleCharacteristic? api = device.characteristic("api");
              print("$tag new device name: $text");
              await api?.write("hostname=$text");
              String reply = await api?.read();
              String pattern = "0:OK;2:hostname=";
              if (0 == reply.indexOf(pattern)) {
                String hostName = reply.substring(pattern.length);
                print("Device said: hostname=$hostName");
                setState(() {
                  device.name = hostName;
                });
                await api?.write("reboot");
                await device.disconnect();
                sleep(Duration(milliseconds: 3000));
                await device.connect();
              }
              Navigator.of(context).pop();
            },
          ),
          /*
          actions: <Widget>[
            new ElevatedButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
          */
        );
      },
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
        Function()? action;
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
    BleCharacteristic? battery = device.characteristic("battery");
    BleCharacteristic? power = device.characteristic("power");
    BleCharacteristic? api = device.characteristic("api");
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<int>(
            stream: battery?.stream as Stream<int>,
            initialData: battery?.lastValue,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              return Text(
                "Battery: ${snapshot.data.toString()}%",
              );
            },
          ),
          StreamBuilder<Uint8List>(
            stream: power?.stream as Stream<Uint8List>,
            initialData: power?.lastValue,
            builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
              return Text(
                "Power: ${snapshot.data.toString()}",
              );
            },
          ),
          StreamBuilder<String>(
            stream: api?.stream as Stream<String>,
            initialData: api?.lastValue,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              return Text(
                "Api: ${snapshot.data}",
              );
            },
          ),
          TextField(
            controller: TextEditingController()..text = "hostname",
            onSubmitted: (String command) async {
              print('$tag writing "$command" to api');
              await api?.write(command).catchError((e) {
                bleError(tag, "write($command)", e);
              });
            },
          ),
        ],
      ),
    );
  }
}
