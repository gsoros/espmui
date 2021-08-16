import 'dart:async';

import 'package:espmui/api.dart';
import 'package:espmui/ble_characteristic.dart';
import 'package:espmui/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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
    double cellHeight = MediaQuery.of(context).size.width / 3;

    var items = <StaggeredGridItem>[
      StaggeredGridItem(
        value: PowerCadence(device.power, mode: "power"),
        colSpan: 3,
        height: cellHeight * 1.5,
      ),
      StaggeredGridItem(
        value: PowerCadence(device.power, mode: "cadence"),
        colSpan: 3,
        height: cellHeight * 1.5,
      ),
      StaggeredGridItem(
        value: Strain(device),
        colSpan: 4,
        height: cellHeight,
      ),
      StaggeredGridItem(
        value: Battery(device.battery),
        colSpan: 2,
        height: cellHeight,
      ),
      StaggeredGridItem(
        value: ApiInterface(device),
        colSpan: 6,
        height: cellHeight * 1.5,
      ),
    ];

    return StaggeredGridView.countBuilder(
      crossAxisCount: 6,
      shrinkWrap: true,
      itemCount: items.length,
      staggeredTileBuilder: (index) {
        return StaggeredTile.extent(
          items[index].colSpan,
          items[index].height,
          //MediaQuery.of(context).size.width / items.values.elementAt(index),
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
  double height;
  StaggeredGridItem({
    required this.value,
    required this.colSpan,
    required this.height,
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
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState?> snapshot) {
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
        await api.request<bool>("reboot");
        snackbar("Disconnecting", context);
        await device.disconnect();
        snackbar("Waiting for device to boot", context);
        await Future.delayed(Duration(milliseconds: 3000));
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
                          padding: MaterialStateProperty.all<EdgeInsets>(
                              const EdgeInsets.all(0)),
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
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState?> snapshot) {
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

class Battery extends StatelessWidget {
  final BatteryCharacteristic char;
  Battery(this.char);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: char.stream,
      initialData: char.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Battery"),
              Expanded(
                child: Align(
                  child: Text(
                    "${snapshot.data.toString()}%",
                    style: const TextStyle(fontSize: 30),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StrainStreamListener extends StatelessWidget {
  final Device device;
  final ExtendedBool enabled;

  StrainStreamListener(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: device.apiStrain.stream,
      initialData: device.apiStrain.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        String strain = snapshot.hasData && enabled != ExtendedBool.False
            ? snapshot.data!.toStringAsFixed(2)
            : "0.00";
        if (strain.length > 6) strain = strain.substring(0, 6);
        if (strain == "-0.00") strain = "0.00";
        const styleEnabled = TextStyle(fontSize: 40);
        const styleDisabled = TextStyle(fontSize: 40, color: Colors.white12);
        return Text(strain,
            style:
                (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class Strain extends StatelessWidget {
  final Device device;
  Strain(this.device);

  @override
  Widget build(BuildContext context) {
    void calibrate() async {
      Future<void> apiCalibrate(String knownMassStr) async {
        var api = device.api;
        snackbar("Sending calibration value: $knownMassStr", context);
        String? value =
            await api.request<String>("calibrateStrain=$knownMassStr");
        if (value == null ||
            double.tryParse(value) != double.tryParse(knownMassStr)) {
          snackbar("Error calibrating device", context);
          return;
        }
        snackbar("Success calibrating device", context);
      }

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: Text("Calibrate device"),
            content: Container(
              child: Column(
                children: [
                  StrainStreamListener(device, ExtendedBool.True),
                  TextField(
                    maxLength: 10,
                    maxLines: 1,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter known mass",
                      suffixText: "kg",
                    ),
                    controller: TextEditingController(),
                    onSubmitted: (text) async {
                      Navigator.of(context).pop();
                      await apiCalibrate(text);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    void toggleStrainStream(enabled) async {
      device.apiStrainEnabled.value = ExtendedBool.Waiting;
      bool enable = enabled == ExtendedBool.True ? false : true;
      bool? reply = await device.api
          .request<bool>("apiStrain=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      snackbar(
        "Strain stream: " +
            (enable ? "en" : "dis") +
            "able" +
            (success ? "d" : " failed"),
        context,
      );
    }

    void tare() async {
      var resultCode = await device.api.requestResultCode("tare");
      snackbar(
        "Tare " +
            (resultCode == ApiResult.success.index ? "success" : "failed"),
        context,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.apiStrainEnabled,
      builder: (context, enabled, child) {
        var strainOutput = StrainStreamListener(device, enabled);

        return InkWell(
          onTap: () {
            if (enabled == ExtendedBool.True) tare();
          },
          onLongPress: () {
            if (enabled == ExtendedBool.True) calibrate();
          },
          onDoubleTap: () {
            if (enabled == ExtendedBool.True || enabled == ExtendedBool.False)
              toggleStrainStream(enabled);
          },
          child: Container(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Scale"),
              Expanded(
                  child: Align(
                child: enabled == ExtendedBool.Waiting
                    ? CircularProgressIndicator()
                    : strainOutput,
              )),
              Align(
                child: Text(
                  "kg",
                  style: TextStyle(color: Colors.white24),
                ),
                alignment: Alignment.bottomRight,
              ),
            ]),
          ),
        );
      },
    );
  }
}

class PowerCadence extends StatelessWidget {
  final PowerCharacteristic char;
  final String mode;

  /// [mode] = "power" | "cadence"
  PowerCadence(this.char, {this.mode = "power"});

  @override
  Widget build(BuildContext context) {
    var value = StreamBuilder<int>(
      stream: mode == "power" ? char.powerStream : char.cadenceStream,
      initialData: mode == "power" ? char.lastPower : char.lastCadence,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Text(
          snapshot.hasData ? snapshot.data.toString() : "0",
          style: const TextStyle(fontSize: 60),
        );
      },
    );
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mode == "power" ? "Power" : "Cadence"),
          Expanded(child: Align(child: value)),
          Align(
            child: Text(
              mode == "power" ? "W" : "rpm",
              style: TextStyle(color: Colors.white24),
            ),
            alignment: Alignment.bottomRight,
          ),
        ],
      ),
    );
  }
}

class ApiStream extends StatelessWidget {
  final Device device;
  ApiStream(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: device.apiCharacteristic.stream,
      initialData: device.apiCharacteristic.lastValue,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        return Text("${snapshot.data}");
      },
    );
  }
}

class ApiCli extends StatelessWidget {
  final Device device;
  ApiCli(this.device);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController(text: ""),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.all(4),
        filled: true,
        fillColor: Colors.white10,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
      onSubmitted: (String command) async {
        String? value = await device.api.request<String>(command);
        print("[ApiCli] api.request($command): $value");
      },
    );
  }
}

class ApiInterface extends StatelessWidget {
  final Device device;

  ApiInterface(this.device);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ApiStream(device),
          ),
        ),
        ApiCli(device),
      ],
    );
  }
}
