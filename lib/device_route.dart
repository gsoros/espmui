import 'dart:async';

import 'package:espmui/api.dart';
import 'package:espmui/ble_characteristic.dart';
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
  StreamSubscription<PeripheralConnectionState>? stateSubsciption;
  bool? apiStrainEnabled;

  DeviceRouteState(this.device) {
    print("$tag construct");
  }

  @override
  void initState() {
    print("$tag initState");
    super.initState();

    /// listen to connection state changes
    stateSubsciption = device.stateStream.listen((state) {
      switch (state) {
        case PeripheralConnectionState.connected:
          requestInit();
          break;
        case PeripheralConnectionState.disconnected:
          // set some members to initial state
          setState(() {
            apiStrainEnabled = null;
          });
          break;
        default:
      }
    });

    /// listen to api message done events and set matching state members
    apiSubsciption = device.api.messageDoneStream.listen((message) {
      if (message.resultCode == ApiResult.success.index) {
        switch (message.commandStr) {
          case "hostName":
            setState(() => device.name = message.valueAsString);
            break;
          case "apiStrain":
            setState(() => apiStrainEnabled = message.valueAsBool);
            break;
        }
      }
    });

    requestInit();
  }

  /// request initial values, returned values are discarded
  /// because the subscription will handle them
  void requestInit() async {
    if (!await device.connected) return;
    print("$tag Requesting init");
    [
      "hostName",
      "secureApi",
      "apiStrain",
    ].forEach((key) async {
      device.api.request<String>(
        key,
        minDelayMs: 1000,
        maxAttempts: 10,
        maxAgeMs: 20000,
      );
      await Future.delayed(Duration(milliseconds: 150));
    });
  }

  @override
  void dispose() async {
    print("$tag ${device.name} dispose");
    apiSubsciption?.cancel();
    stateSubsciption?.cancel();
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
          title: BleAdapterCheck(AppBarTitle(device)),
        ),
        body: Container(
          margin: const EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
      ),
    );
  }

  Widget _deviceProperties() {
    var items = [
      PowerCadence(device.power, mode: "power"),
      PowerCadence(device.power, mode: "cadence"),
      Strain(device, apiStrainEnabled),
      Battery(device.battery),
      ApiStream(device.apiCharacteristic),
      ApiCommand(device.api),
    ];

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 5.0,
        mainAxisSpacing: 5.0,
      ),
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        return Card(
          color: Colors.black12,
          child:
              Container(padding: const EdgeInsets.all(5), child: items[index]),
        );
      },
    );
  }
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
    void _editDeviceName() async {
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

class Strain extends StatelessWidget {
  final Device device;
  final bool? enabled;
  Strain(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    void toggleStrainStream() async {
      bool enable = enabled == true ? false : true;
      bool? reply = await device.api
          .request<bool>("apiStrain=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      snackbar(
        "Strain stream: " +
            (enable ? "en" : "dis") +
            "abl" +
            (success ? "ed" : "ing failed"),
        context,
      );
    }

    var strainOutput = StreamBuilder<double>(
      stream: device.apiStrain.stream,
      initialData: device.apiStrain.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        String strain = snapshot.hasData && enabled != null
            ? snapshot.data!.toStringAsFixed(2)
            : "0.00";
        if (strain.length > 6) strain = strain.substring(0, 6);
        const styleEnabled = TextStyle(fontSize: 40);
        const styleDisabled = TextStyle(fontSize: 40, color: Colors.white12);
        return Text(strain,
            style: (enabled == true) ? styleEnabled : styleDisabled);
      },
    );

    return InkWell(
      onTap: toggleStrainStream,
      child: Container(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Strain"),
            Expanded(child: Align(child: strainOutput)),
          ],
        ),
      ),
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
          style: const TextStyle(fontSize: 40),
        );
      },
    );
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(mode == "power" ? "Power" : "Cadence"),
          Expanded(child: Align(child: value)),
        ],
      ),
    );
  }
}

class ApiStream extends StatelessWidget {
  final ApiCharacteristic char;
  ApiStream(this.char);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: char.stream,
      initialData: char.lastValue,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        return Text("Api: ${snapshot.data}");
      },
    );
  }
}

class ApiCommand extends StatelessWidget {
  final Api api;
  ApiCommand(this.api);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: TextEditingController()..text = "hostName=ESPM",
      onSubmitted: (String command) async {
        String? value = await api.request<String>(command);
        print("[ApiCommand] api.requestValue: $value");
      },
    );
  }
}
