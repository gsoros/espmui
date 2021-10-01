import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'util.dart';
import 'ble.dart';
import 'device.dart';
import 'device_widgets.dart';

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
    device.shouldConnect = false;
    device.disconnect();
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        appBar: AppBar(
          title: BleAdapterCheck(
            AppBarTitle(device),
            ifDisabled: (state) => BleDisabled(state),
          ),
        ),
        body: Container(
          margin: const EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
      ),
    );
  }

  Widget _deviceProperties() {
    var items = <StaggeredGridItem>[
      StaggeredGridItem(
        value: PowerCadence(device.power, mode: "power"),
        colSpan: 3,
      ),
      StaggeredGridItem(
        value: PowerCadence(device.power, mode: "cadence"),
        colSpan: 3,
      ),
      StaggeredGridItem(
        value: WeightScale(device),
        colSpan: 2,
      ),
      StaggeredGridItem(
        value: HallSensor(device),
        colSpan: 2,
      ),
      StaggeredGridItem(
        value: Battery(device.battery),
        colSpan: 2,
      ),
      StaggeredGridItem(
        value: SettingsWidget(device),
        colSpan: 6,
      ),
    ];

    return StaggeredGridView.countBuilder(
      crossAxisCount: 6,
      shrinkWrap: true,
      itemCount: items.length,
      staggeredTileBuilder: (index) {
        return StaggeredTile.fit(
          items[index].colSpan,
        );
      },
      itemBuilder: (context, index) {
        return Container(
          decoration: new BoxDecoration(
            boxShadow: [
              new BoxShadow(
                color: Colors.black38,
                blurRadius: 5.0,
                offset: Offset.fromDirection(1, 2),
              ),
            ],
          ),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5.0),
            ),
            elevation: 3,
            color: Colors.black,
            child: Container(
              padding: const EdgeInsets.all(5),
              child: items[index].value,
            ),
          ),
        );
      },
    );
  }
}

class StaggeredGridItem {
  Widget value;
  int colSpan;
  StaggeredGridItem({
    required this.value,
    required this.colSpan,
  });
}

class StatelessWidgetBoilerplate extends StatelessWidget {
  final Device device;

  StatelessWidgetBoilerplate(this.device);

  @override
  Widget build(BuildContext context) {
    return Text("StatelessWidgetBoilerplate");
  }
}

class Status extends StatelessWidget {
  final Device device;

  Status(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PeripheralConnectionState?>(
      stream: device.stateStream,
      initialData: null,
      builder: (BuildContext context, AsyncSnapshot<PeripheralConnectionState?> snapshot) {
        String connState = snapshot.hasData ? snapshot.data.toString() : "....";
        //print("Device status: snapshot=$connState");
        return Text(
          connState.substring(connState.lastIndexOf(".") + 1),
          style: TextStyle(fontSize: 10),
        );
      },
    );
  }
}

class AppBarTitle extends StatelessWidget {
  final Device device;

  AppBarTitle(this.device);

  @override
  Widget build(BuildContext context) {
    void editDeviceName() async {
      Future<bool> apiDeviceName(String name) async {
        var api = device.api;
        snackbar("Sending new device name: $name", context);
        String? value = await api.request<String>("hostName=$name");
        if (value != name) {
          snackbar("Error renaming device", context);
          return false;
        }
        snackbar("Success setting new hostname on device: $value", context);
        snackbar("Sending reboot command", context);
        await api.request<bool>("reboot=2000"); // reboot in 2s
        snackbar("Disconnecting", context);
        await device.disconnect();
        snackbar("Waiting for device to boot", context);
        await Future.delayed(Duration(milliseconds: 4000));
        snackbar("Connecting to device", context);
        await device.connect();
        snackbar("Success", context);
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
              decoration: const InputDecoration(border: OutlineInputBorder()),
              controller: TextEditingController()..text = device.name ?? "",
              onSubmitted: (text) async {
                Navigator.of(context).pop();
                await apiDeviceName(text);
              },
            ),
          );
        },
      );
    }

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
                          padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.all(0)),
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
                    Status(device),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end, // Align right
            children: [ConnectButton(device)],
          )
        ],
      ),
    );
  }
}

class ConnectButton extends StatelessWidget {
  final Device device;
  ConnectButton(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PeripheralConnectionState?>(
      stream: device.stateStream,
      initialData: null,
      builder: (BuildContext context, AsyncSnapshot<PeripheralConnectionState?> snapshot) {
        var action;
        var label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          action = () {
            device.shouldConnect = false;
            device.disconnect();
          };
          label = "Disconnect";
        }
        if (snapshot.data == PeripheralConnectionState.disconnected)
          action = () {
            device.shouldConnect = true;
            device.connect();
          };
        return EspmuiElevatedButton(label, action: action);
      },
    );
  }
}
