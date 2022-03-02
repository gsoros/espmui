import 'dart:async';
//import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'util.dart';
import 'debug.dart';
import 'ble.dart';
import 'device.dart';
import 'device_list.dart';
import 'device_widgets.dart';

class DeviceRoute extends StatefulWidget with Debug {
  final Device device;

  DeviceRoute(this.device) {
    debugLog("construct");
  }

  @override
  DeviceRouteState createState() {
    debugLog("createState()");
    if (device is ESPM)
      return ESPMRouteState(device as ESPM);
    else if (device is PowerMeter)
      return PowerMeterRouteState(device as PowerMeter);
    else if (device is HeartRateMonitor)
      return HeartRateMonitorRouteState(device as HeartRateMonitor);
    else
      return DeviceRouteState(device);
  }
}

class DeviceRouteState extends State<DeviceRoute> with Debug {
  Device device;

  DeviceRouteState(this.device) {
    debugLog("construct");
  }

  @override
  void initState() {
    debugLog("initState");
    _checkCorrectType();
    super.initState();
  }

  Future<void> _checkCorrectType() async {
    //debugLog("_checkCorrectType() $device");
    if (await device.isCorrectType()) return;
    var newDevice = await device.copyToCorrectType();
    device.peripheral = null;
    device.dispose();
    device = newDevice;
    DeviceList().addOrUpdate(device);
    debugLog("_checkCorrectType() reloading DeviceRoute($device)");
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DeviceRoute(device)));
  }

  @override
  void dispose() async {
    debugLog("dispose");
    // if (!device.autoConnect.value) device.disconnect();
    super.dispose();
  }

  Future<bool> _onBackPressed() {
    //if (!device.autoConnect.value) device.disconnect();
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

  List<StaggeredGridItem> _devicePropertyItems() {
    return [
      StaggeredGridItem(
        value: ValueListenableBuilder<bool>(
          valueListenable: device.autoConnect,
          builder: (_, value, __) {
            //debugLog("autoconnect changed: $value");
            return SettingSwitch(
              name: "Auto Connect",
              value: extendedBoolFrom(value),
              onChanged: (value) {
                device.setAutoConnect(value);
              },
            );
          },
        ),
        colSpan: 6,
      ),
      StaggeredGridItem(
        value: Battery(device),
        colSpan: 2,
      ),
    ];
  }

  Widget _deviceProperties() {
    var items = _devicePropertyItems();

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

class PowerMeterRouteState extends DeviceRouteState {
  PowerMeter powerMeter;

  PowerMeterRouteState(this.powerMeter) : super(powerMeter);

  @override
  _devicePropertyItems() {
    return [
      StaggeredGridItem(
        value: PowerCadence(powerMeter, mode: "power"),
        colSpan: 3,
      ),
      StaggeredGridItem(
        value: PowerCadence(powerMeter, mode: "cadence"),
        colSpan: 3,
      ),
    ]..addAll(super._devicePropertyItems());
  }
}

class ESPMRouteState extends PowerMeterRouteState {
  ESPM espm;

  ESPMRouteState(this.espm) : super(espm);

  @override
  _devicePropertyItems() {
    return super._devicePropertyItems()
      ..addAll([
        StaggeredGridItem(
          value: EspmWeightScale(espm),
          colSpan: 2,
        ),
        StaggeredGridItem(
          value: EspmHallSensor(espm),
          colSpan: 2,
        ),
        StaggeredGridItem(
          value: EspmSettingsWidget(espm),
          colSpan: 6,
        ),
      ]);
  }
}

class HeartRateMonitorRouteState extends DeviceRouteState {
  HeartRateMonitor hrm;

  HeartRateMonitorRouteState(this.hrm) : super(hrm);

  @override
  _devicePropertyItems() {
    return [
      StaggeredGridItem(
        value: HeartRate(hrm),
        colSpan: 3,
      ),
    ]..addAll(super._devicePropertyItems());
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
        //debugLog("Device status: snapshot=$connState");
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
      if (!(device is ESPM)) return;

      Future<bool> apiDeviceName(String name) async {
        var espm = device as ESPM;
        var api = espm.api;
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
                        onLongPress: (device is ESPM) ? editDeviceName : null,
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

class ConnectButton extends StatelessWidget with Debug {
  final Device device;
  ConnectButton(this.device);

  @override
  Widget build(BuildContext context) {
    //debugLog("initialState: ${device.lastConnectionState}");
    return StreamBuilder<PeripheralConnectionState?>(
      stream: device.stateStream,
      initialData: device.lastConnectionState,
      builder: (BuildContext context, AsyncSnapshot<PeripheralConnectionState?> snapshot) {
        //debugLog("$snapshot");
        var action;
        var label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          if (!device.autoConnect.value) action = device.disconnect;
          label = "Disconnect";
        } else if (snapshot.data == PeripheralConnectionState.connecting) {
          action = device.disconnect;
          label = "Cancel";
        } else if (snapshot.data == PeripheralConnectionState.disconnecting)
          label = "Disonnecting";
        else //if (snapshot.data == PeripheralConnectionState.disconnected)
          action = device.connect;
        return EspmuiElevatedButton(label, action: action);
      },
    );
  }
}
