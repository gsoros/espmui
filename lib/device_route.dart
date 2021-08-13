import 'dart:async';
import 'dart:typed_data';

import 'package:espmui/api.dart';
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

  StreamSubscription<ApiMessage>? apiSubsciption;
  bool? apiStrainEnabled;

  DeviceRouteState(this.device) {
    print("$tag construct");
  }

  @override
  void initState() {
    print("$tag initState");
    super.initState();

    /// listen to api messages and set matching state members
    apiSubsciption = device.api.messageDoneStream.listen((message) {
      print("$tag apiSubscription $message");
      if (message.commandStr == "apiStrain" && message.resultStr == "OK") {
        var value = message.value;
        print("$tag intercept apiStrainEnabled=$value");
        setState(() {
          apiStrainEnabled = value == "1:true";
        });
      }
    });

    /// request initial values
    device.api.requestValue("apiStrain", minDelay: 1000, maxAttempts: 10);
  }

  @override
  void dispose() async {
    print("$tag ${device.name} dispose");
    apiSubsciption?.cancel();
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
    void statusMessage(String s) {
      print("$tag Status message: $s");
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.black38,
        content: Text(s, textAlign: TextAlign.center),
      ));
    }

    Future<bool> apiDeviceName(String name) async {
      var api = device.api;
      statusMessage("Sending new device name: $name");
      String? value = await api.requestValue("hostName=$name");
      if (value != name) return false;
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

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          scrollable: true,
          title: Text("Rename device"),
          content: TextField(
            maxLength: 31,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            decoration: InputDecoration(border: OutlineInputBorder()),
            controller: TextEditingController()..text = device.name ?? "",
            onSubmitted: (text) async {
              Navigator.of(context).pop();
              statusMessage(await apiDeviceName(text) ? "Success" : "Error");
            },
          ),
        );
      },
    );
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

  Widget _battery() {
    return StreamBuilder<int>(
      stream: device.battery.stream,
      initialData: device.battery.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Text("Battery: ${snapshot.data.toString()}%");
      },
    );
  }

  Widget _power() {
    return StreamBuilder<Uint8List>(
      stream: device.power.stream,
      initialData: device.power.lastValue,
      builder: (BuildContext context, AsyncSnapshot<Uint8List> snapshot) {
        return Text("Power: ${snapshot.data.toString()}");
      },
    );
  }

  Widget _strain() {
    var strainOutput = StreamBuilder<double>(
      stream: device.apiStrain.stream,
      initialData: device.apiStrain.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        String strain =
            snapshot.hasData ? snapshot.data!.toStringAsFixed(2) : "0.00";
        return Text("Strain: $strain");
      },
    );

    print("switch rebuild enabled=$apiStrainEnabled");
    var enableSwitch = Switch(
      value: apiStrainEnabled ?? false,
      onChanged: (enable) async {
        String? reply = await device.api
            .requestValue("apiStrain=" + (enable ? "true" : "false"));
        print("$tag reply: $reply");
        bool success = reply == (enable ? "1:true" : "0:false");
        print("deviceRoute Switch " +
            (enable ? "en" : "dis") +
            "able " +
            (success ? "success" : "failure"));
      },
      activeColor: Colors.red,
    );

    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          strainOutput,
          enableSwitch,
        ],
      ),
    );
  }

  Widget _api() {
    return StreamBuilder<String>(
      stream: device.apiCharacteristic.stream,
      initialData: device.apiCharacteristic.lastValue,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        return Text("Api: ${snapshot.data}");
      },
    );
  }

  Widget _apiCommand() {
    return TextField(
      controller: TextEditingController()..text = "hostName=ESPM",
      onSubmitted: (String command) async {
        String? value = await device.api.requestValue(command);
        print("$tag api.requestValue: $value");
      },
    );
  }

  Widget _deviceProperties() {
    var items = [
      _battery(),
      _power(),
      _strain(),
      _api(),
      _apiCommand(),
    ];

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 5.0,
        mainAxisSpacing: 5.0,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        return Card(color: Colors.black12, child: items[index]);
      },
    );
  }
}
