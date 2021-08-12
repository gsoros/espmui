import 'dart:async';
import 'dart:typed_data';

import 'package:espmui/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'ble.dart';
import 'device.dart';

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
          title: bleByState(
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
                        onLongPress: _editDeviceName,
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

  void _editDeviceName() async {
    List<String> status = [];
    var statusController = StreamController<List<String>>.broadcast();

    void statusMessage(String s) {
      print("$tag Status message: $s");
      if (status.length > 10) status.removeAt(0);
      status.add(s);
      streamSendIfNotClosed(statusController, status);
    }

    Future<bool> apiDeviceName(String name) async {
      var api = device.api;
      statusMessage("Sending new device name: $name");
      String? value = await api.requestValue("hostName=$name");
      if (value == name) {
        statusMessage("Success setting new hostname on device: $value");
        setState(() => device.name = value);
        statusMessage("Sending reboot command");
        await api.requestValue("reboot");
        statusMessage("Disconnecting");
        await device.disconnect();
        statusMessage("Waiting for device to boot");
        await Future.delayed(Duration(milliseconds: 3000));
        statusMessage("Connecting to device");
        await device.connect();
        return true;
      }
      return false;
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          scrollable: true,
          title: Text("Rename device"),
          content: Container(
            constraints: BoxConstraints(
              minHeight: 250,
            ),
            child: Column(
              children: [
                TextField(
                  maxLength: 31,
                  maxLines: 1,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(border: OutlineInputBorder()),
                  controller: TextEditingController()..text = device.name ?? "",
                  onSubmitted: (text) async {
                    if (await apiDeviceName(text)) {
                      statusMessage("Success");
                      await Future.delayed(Duration(milliseconds: 5000));
                      Navigator.of(context).pop();
                    } else
                      statusMessage("Error");
                  },
                ),
                StreamBuilder(
                  stream: statusController.stream,
                  builder: (context, AsyncSnapshot<List<String>> snapshot) {
                    if (!snapshot.hasData) return Text("");
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {
                        return Text(
                          snapshot.data![index],
                          style: TextStyle(fontSize: 10),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    statusController.close();
  }

  Widget _status() {
    return StreamBuilder<PeripheralConnectionState>(
      stream: device.stateStream,
      initialData: device.state,
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
      stream: device.stateStream,
      initialData: device.state,
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState> snapshot) {
        var action;
        var label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          action = device.disconnect;
          label = "Disconnect";
        }
        if (snapshot.data == PeripheralConnectionState.disconnected)
          action = device.connect;
        return espmuiElevatedButton(label, action: action);
      },
    );
  }

  Widget _deviceProperties() {
    var battery = device.battery;
    var power = device.power;
    var api = device.api;
    var apiStrain = device.apiStrain;
    var apiChar = device.apiCharacteristic;

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
          StreamBuilder<double>(
            stream: apiStrain.stream,
            initialData: apiStrain.lastValue,
            builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
              return Text(
                "Strain: " +
                    (snapshot.hasData ? snapshot.data!.toString() : ""),
              );
            },
          ),
          StreamBuilder<String>(
            stream: apiChar.stream,
            initialData: apiChar.lastValue,
            builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
              return Text(
                "Api: ${snapshot.data}",
              );
            },
          ),
          TextField(
            controller: TextEditingController()..text = "hostName=ESPM",
            onSubmitted: (String command) async {
              /*
              api.sendCommand(command, onDone: (message) {
                print("$tag api.sendCommand: " +
                    ((message.resultCode == 0) ? "Success" : "Error"));
              });
              await Future.delayed(Duration(milliseconds: 1000));
              */
              String? value = await api.requestValue(command);
              print("$tag api.requestValue: $value");
            },
          ),
        ],
      ),
    );
  }
}
