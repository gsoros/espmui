import 'dart:async';
//import 'dart:html';
//import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'package:page_transition/page_transition.dart';

import 'ble_characteristic.dart';
import 'api.dart';
import 'device.dart';
import 'espm.dart';
import 'espcc.dart';
import 'homeauto.dart';
import 'temperature_compensation_route.dart';

import 'util.dart';
import 'debug.dart';

class DeviceConnectionState extends StatelessWidget {
  final Device device;
  final void Function()? onConnected;

  DeviceConnectionState(this.device, {this.onConnected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PeripheralConnectionState?>(
      stream: device.stateStream,
      initialData: null,
      builder: (BuildContext context, AsyncSnapshot<PeripheralConnectionState?> snapshot) {
        if (PeripheralConnectionState.connected == snapshot.data && null != onConnected) onConnected!();
        String connState = snapshot.hasData ? snapshot.data.toString() : "....";
        //logD("Device status: connState=$connState");
        return Text(
          connState.substring(connState.lastIndexOf(".") + 1),
          style: TextStyle(fontSize: 10),
        );
      },
    );
  }
}

class DeviceAppBarTitle extends StatelessWidget {
  final Device device;
  final bool nameEditable;
  final String prefix;
  final void Function()? onConnected;

  DeviceAppBarTitle(this.device, {this.nameEditable = true, this.prefix = "", this.onConnected});

  @override
  Widget build(BuildContext context) {
    void editDeviceName() async {
      if (!(device is ESPM) && !(device is ESPCC)) return;

      Future<bool> apiDeviceName(String name) async {
        var api = (ESPM == await device.correctType()) ? (device as ESPM).api : (device as ESPCC).api;
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

    Widget deviceName() {
      return Text(
        prefix + (device.name ?? "unknown"),
        style: Theme.of(context).textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.clip,
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
                      child: nameEditable
                          ? TextButton(
                              style: ButtonStyle(
                                alignment: Alignment.bottomLeft,
                                padding: MaterialStateProperty.all<EdgeInsets>(const EdgeInsets.all(0)),
                              ),
                              onPressed: () {},
                              onLongPress: (device is ESPM) ? editDeviceName : null,
                              child: deviceName(),
                            )
                          : deviceName(),
                    ),
                  ),
                ]),
                Row(
                  children: [
                    DeviceConnectionState(device, onConnected: onConnected),
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
    //logD("initialState: ${device.lastConnectionState}");
    return StreamBuilder<PeripheralConnectionState?>(
      stream: device.stateStream,
      initialData: device.lastConnectionState,
      builder: (BuildContext context, AsyncSnapshot<PeripheralConnectionState?> snapshot) {
        //logD("$snapshot");
        var action;
        var label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          action = device.disconnect;
          label = "Disconnect";
        } else if (snapshot.data == PeripheralConnectionState.connecting) {
          action = device.disconnect;
          label = "Cancel";
        } else if (snapshot.data == PeripheralConnectionState.disconnecting)
          label = "Disonnecting";
        else //if (snapshot.data == PeripheralConnectionState.disconnected)
          action = device.connect;
        return EspmuiElevatedButton(child: Text(label), onPressed: action);
      },
    );
  }
}

class BatteryWidget extends StatelessWidget {
  final Device device;
  BatteryWidget(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.battery?.defaultStream,
      initialData: device.battery?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Container(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Battery"),
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                child: Text(
                  snapshot.hasData ? "${snapshot.data}" : "--",
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
            Align(
              child: Text(
                "%",
                style: TextStyle(color: Colors.white24),
              ),
              alignment: Alignment.bottomRight,
            ),
          ]),
        );
      },
    );
  }
}

class EspmWeightScaleStreamListenerWidget extends StatelessWidget {
  final ESPM device;
  final int mode;

  EspmWeightScaleStreamListenerWidget(this.device, this.mode);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double?>(
      stream: device.weightScaleChar?.defaultStream,
      initialData: device.weightScaleChar?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double?> snapshot) {
        String weight = snapshot.hasData && 0 < mode ? snapshot.data!.toStringAsFixed(2) : "--";
        if (weight.length > 6) weight = weight.substring(0, 6);
        if (weight == "-0.00") weight = "0.00";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(weight, style: (0 < mode) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class EspmWeightScaleWidget extends StatelessWidget with Debug {
  final ESPM device;
  EspmWeightScaleWidget(this.device);

  @override
  Widget build(BuildContext context) {
    void calibrate() async {
      Future<void> apiCalibrate(String knownMassStr) async {
        var api = device.api;
        snackbar("Sending calibration value: $knownMassStr", context);
        String? value = await api.request<String>("cs=$knownMassStr");
        var errorMsg = "Error calibrating device";
        if (value == null) {
          snackbar(errorMsg, context);
          return;
        }
        var parsedValue = double.tryParse(value);
        if (parsedValue == null) {
          snackbar(errorMsg, context);
          return;
        }
        var parsedKnownMass = double.tryParse(knownMassStr);
        if (parsedKnownMass == null) {
          snackbar(errorMsg, context);
          return;
        }
        if (parsedValue < parsedKnownMass * .999 || parsedValue > parsedKnownMass * 1.001) {
          snackbar(errorMsg, context);
          return;
        }
        snackbar("Success calibrating device", context);
      }

      Widget autoTareWarning = device.settings.value.autoTare == ExtendedBool.True ? Text("Warning: AutoTare is enabled") : Empty();

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: Text("Calibrate device"),
            content: Container(
              child: Column(children: [
                autoTareWarning,
                EspmWeightScaleStreamListenerWidget(device, 1),
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
              ]),
            ),
          );
        },
      );
    }

    void toggle(int mode) async {
      device.weightServiceMode.value = ESPMWeightServiceMode.UNKNOWN;
      bool enable = mode < 1;
      bool success = false;
      int? reply = await device.api.request<int>(
        "wse=" +
            (enable
                ? //
                ESPMWeightServiceMode.WHEN_NO_CRANK.toString()
                : ESPMWeightServiceMode.OFF.toString()),
      );
      if (ESPMWeightServiceMode.ON == reply || ESPMWeightServiceMode.WHEN_NO_CRANK == reply) {
        if (enable) success = true;
        await device.weightScaleChar?.subscribe();
      } else if (ESPMWeightServiceMode.OFF == reply) {
        if (!enable) success = true;
        await device.characteristic("weightScale")?.unsubscribe();
      } else
        device.weightServiceMode.value = ESPMWeightServiceMode.UNKNOWN;
      snackbar(
        "Weight service " + (enable ? "en" : "dis") + "able" + (success ? "d" : " failed"),
        context,
      );
    }

    void tare() async {
      var resultCode = await device.api.requestResultCode("tare=0");
      //debugLog('requestResultCode("tare=0"): $resultCode');
      snackbar(
        "Tare " + (resultCode == ApiResult.success ? "success" : "failed"),
        context,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: device.weightServiceMode,
      builder: (_, mode, __) {
        var strainOutput = EspmWeightScaleStreamListenerWidget(device, mode);

        return InkWell(
          onTap: () {
            if (ESPMWeightServiceMode.OFF < mode) tare();
          },
          onLongPress: () {
            if (ESPMWeightServiceMode.OFF < mode) calibrate();
          },
          onDoubleTap: () {
            toggle(mode);
          },
          child: Container(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Scale"),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  child: device.lastConnectionState == PeripheralConnectionState.connected
                      ? mode == ESPMWeightServiceMode.UNKNOWN
                          ? CircularProgressIndicator()
                          : strainOutput
                      : strainOutput,
                ),
              ),
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

class EspmHallStreamListenerWidget extends StatelessWidget {
  final ESPM device;
  final ExtendedBool enabled;

  EspmHallStreamListenerWidget(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.hallChar?.defaultStream,
      initialData: device.hallChar?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        String value = snapshot.hasData && enabled != ExtendedBool.False ? (snapshot.data! > 0 ? snapshot.data!.toString() : '--') : "--";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(value, style: (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class EspmHallSensorWidget extends StatelessWidget {
  final ESPM device;
  EspmHallSensorWidget(this.device);

  @override
  Widget build(BuildContext context) {
    void settings() async {
      int? hallOffset = await device.api.request<int>("ho");
      int? hallThreshold = await device.api.request<int>("ht");
      int? hallThresLow = await device.api.request<int>("htl");

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: Text("Hall Sensor Settings"),
            content: Container(
              child: Column(children: [
                EspmHallStreamListenerWidget(device, ExtendedBool.True),
                Row(children: [
                  ApiSettingInputWidget(
                    name: "Offset",
                    value: hallOffset.toString(),
                    keyboardType: TextInputType.number,
                    api: device.api,
                    commandCode: device.api.commandCode("ho", logOnError: false),
                  ),
                ]),
                Row(children: [
                  ApiSettingInputWidget(
                    name: "High Threshold",
                    value: hallThreshold.toString(),
                    keyboardType: TextInputType.number,
                    api: device.api,
                    commandCode: device.api.commandCode("ht", logOnError: false),
                  ),
                ]),
                Row(children: [
                  ApiSettingInputWidget(
                    name: "Low Threshold",
                    value: hallThresLow.toString(),
                    keyboardType: TextInputType.number,
                    api: device.api,
                    commandCode: device.api.commandCode("htl", logOnError: false),
                  ),
                ]),
              ]),
            ),
          );
        },
      );
    }

    void toggle(enabled) async {
      device.hallEnabled.value = ExtendedBool.Waiting;
      bool enable = enabled == ExtendedBool.True ? false : true;
      bool? reply = await device.api.request<bool>("hc=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      if (success) {
        if (enable)
          await device.hallChar?.subscribe();
        else
          await device.hallChar?.unsubscribe();
      } else
        device.hallEnabled.value = ExtendedBool.Unknown;
      snackbar(
        "Hall readings " + (enable ? "en" : "dis") + "able" + (success ? "d" : " failed"),
        context,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.hallEnabled,
      builder: (_, enabled, __) {
        return InkWell(
          onLongPress: () {
            if (enabled == ExtendedBool.True) settings();
          },
          onDoubleTap: () {
            if (enabled == ExtendedBool.True || enabled == ExtendedBool.False || enabled == ExtendedBool.Unknown) toggle(enabled);
          },
          child: Container(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Hall"),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  child: (enabled == ExtendedBool.Waiting) ? CircularProgressIndicator() : EspmHallStreamListenerWidget(device, enabled),
                ),
              ),
              Text(" "),
            ]),
          ),
        );
      },
    );
  }
}

class PowerCadenceWidget extends StatelessWidget with Debug {
  final PowerMeter device;
  final String mode;

  /// [mode] = "power" | "cadence"
  PowerCadenceWidget(this.device, {this.mode = "power"});

  @override
  Widget build(BuildContext context) {
    BleCharacteristic? tmpChar = device.power;
    if (!(tmpChar is PowerCharacteristic)) return Text('Error: no power char');
    PowerCharacteristic char = tmpChar;
    Stream<int> stream;
    int lastValue;
    switch (mode) {
      case 'power':
        stream = char.powerStream;
        lastValue = char.lastPower;
        break;
      default: // cadence
        stream = char.cadenceStream;
        lastValue = char.lastCadence;
        break;
    }

    var value = StreamBuilder<int>(
      stream: stream,
      initialData: lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        //debugLog(snapshot.hasData ? snapshot.data!.toString() : "no data");
        return Text(
          snapshot.hasData ? (snapshot.data! > 0 ? snapshot.data.toString() : "--") : "--",
          style: const TextStyle(fontSize: 60),
        );
      },
    );
    return Container(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(mode == "power" ? "Power" : "Cadence"),
        Flexible(
          fit: FlexFit.loose,
          child: Align(child: value),
        ),
        Align(
          child: Text(
            mode == "power" ? "W" : "rpm",
            style: TextStyle(color: Colors.white24),
          ),
          alignment: Alignment.bottomRight,
        ),
      ]),
    );
  }
}

class HeartRateWidget extends StatelessWidget {
  final HeartRateMonitor device;

  HeartRateWidget(this.device);

  @override
  Widget build(BuildContext context) {
    BleCharacteristic? tmpChar = device.heartRate;
    if (!(tmpChar is HeartRateCharacteristic)) return Text('Error: not HR char');
    HeartRateCharacteristic char = tmpChar;

    var value = StreamBuilder<int?>(
      stream: char.defaultStream,
      initialData: char.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int?> snapshot) {
        return Text(
          snapshot.hasData ? (snapshot.data! > 0 ? snapshot.data.toString() : " ") : " ",
          style: const TextStyle(fontSize: 60),
        );
      },
    );
    return Container(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("HR"),
        Flexible(
          fit: FlexFit.loose,
          child: Align(child: value),
        ),
        Align(
          child: Text(
            "bpm",
            style: TextStyle(color: Colors.white24),
          ),
          alignment: Alignment.bottomRight,
        ),
      ]),
    );
  }
}

class ApiStreamWidget extends StatelessWidget {
  final Api api;
  ApiStreamWidget(this.api);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: api.characteristic?.defaultStream,
      initialData: api.characteristic?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        return Text("${snapshot.data}");
      },
    );
  }
}

class ApiCliWidget extends StatelessWidget with Debug {
  final Api api;
  ApiCliWidget(this.api);

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
        String? value = await api.request<String>(command);
        logD("api.request($command): $value");
      },
    );
  }
}

class ApiInterfaceWidget extends StatelessWidget {
  final Api api;

  ApiInterfaceWidget(this.api);

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        fit: FlexFit.loose,
        child: Align(
          alignment: Alignment.topLeft,
          child: ApiStreamWidget(api),
        ),
      ),
      ApiCliWidget(api),
    ]);
  }
}

class SettingInputWidget extends StatelessWidget with Debug {
  final String? value;
  final bool enabled;
  final String? name;
  final bool isPassword;
  final String Function(String)? transformInput;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final void Function(String)? onSubmitted;
  final TextEditingController? textController;

  SettingInputWidget({
    this.value,
    this.enabled = true,
    this.name,
    this.isPassword = false,
    this.transformInput,
    this.suffix,
    this.keyboardType,
    this.onSubmitted,
    this.textController,
  });

  String? getValue() => textController?.text;

  void Function(String)? _onSubmitted(BuildContext context) => null;

  @override
  Widget build(BuildContext context) {
    //logD("SettingInputWidget build() value: $value");
    return TextField(
      keyboardType: keyboardType,
      obscureText: isPassword,
      enableSuggestions: false,
      autocorrect: false,
      enabled: enabled,
      controller: textController ?? TextEditingController(text: value),
      decoration: InputDecoration(
        labelText: name,
        suffix: suffix,
        isDense: true,
        filled: true,
        fillColor: Colors.white10,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
      onSubmitted: _onSubmitted(context),
    );
  }
}

class ApiSettingInputWidget extends SettingInputWidget {
  final Api api;
  final int? commandCode;
  final String? commandArg;

  ApiSettingInputWidget({
    required this.api,
    required this.commandCode,
    this.commandArg,
    String? value,
    bool enabled = true,
    String? name,
    bool isPassword = false,
    String Function(String)? transformInput,
    Widget? suffix,
    TextInputType? keyboardType,
    TextEditingController? textController,
  }) : super(
          value: value,
          enabled: enabled,
          name: name,
          isPassword: isPassword,
          transformInput: transformInput,
          suffix: suffix,
          keyboardType: keyboardType,
          textController: textController,
        );

  @override
  void Function(String)? _onSubmitted(BuildContext context) => (String edited) async {
        if (null == commandCode) {
          logD("command is null");
          return;
        }
        if (transformInput != null) edited = transformInput!(edited);
        String command = "$commandCode=" + (null != commandArg ? "$commandArg:" : "") + "$edited";
        String? expect = null != commandArg ? "$commandArg:" : null;
        final result = await api.requestResultCode(
          command,
          expectValue: expect,
          minDelayMs: 2000,
        );
        if (name != null) snackbar("$name update${result == ApiResult.success ? "d" : " failed"}", context);
        logD('api.requestResultCode("$command", expectValue="$expect"): $result');
      };
}

class SettingSwitchWidget extends StatelessWidget with Debug {
  final ExtendedBool value;
  final Widget? label;
  final void Function(bool)? onChanged;

  /// whether the switch can be toggled
  final bool enabled;

  SettingSwitchWidget({
    required this.value,
    this.label,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    var toggler = value == ExtendedBool.Waiting
        ? CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.True ? true : false,
            activeColor: Colors.red,
            onChanged: enabled
                ? (bool state) async {
                    if (onChanged != null) onChanged!(state);
                    logD("[SettingSwitch] $label changed to $state");
                  }
                : null);
    return (label == null)
        ? toggler
        : Row(children: [
            Flexible(
              fit: FlexFit.tight,
              child: label!,
            ),
            toggler,
          ]);
  }
}

class ApiSettingSwitchWidget extends StatelessWidget with Debug {
  final Api api;
  final int? commandCode;
  final String? commandArg;
  final ExtendedBool value;
  final String? name;
  final void Function()? onChanged;

  ApiSettingSwitchWidget({
    required this.api,
    required this.commandCode,
    required this.value,
    this.commandArg,
    this.name,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // TODO use SettingSwitch
    var onOff = value == ExtendedBool.Waiting
        ? CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.True ? true : false,
            activeColor: Colors.red,
            onChanged: (bool enabled) async {
              if (null == commandCode) return;
              if (onChanged != null) onChanged!();
              final result = await api.requestResultCode(
                "$commandCode=" + (null != commandArg ? "$commandArg:" : "") + "${enabled ? "1" : "0"}",
                expectValue: null != commandArg ? "$commandArg:" : null,
                minDelayMs: 2000,
              );
              if (name != null) snackbar("$name ${enabled ? "en" : "dis"}able${result == ApiResult.success ? "d" : " failed"}", context);
              logD("api.requestResultCode($commandCode): $result");
            });
    return (name == null)
        ? onOff
        : Row(
            //mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: FlexFit.tight,
                child: Text(name!),
              ),
              onOff,
            ],
          );
  }
}

class EspmuiDropdownWidget extends StatelessWidget with Debug {
  final String? value;
  final List<DropdownMenuItem<String>>? items;
  final Widget? label;
  final void Function(String?)? onChanged;

  /// Creates a dropdown button.
  /// The [items] must have distinct values. If [value] isn't null then it must be
  /// equal to one of the [DropdownMenuItem] values. If [items] or [onChanged] is
  /// null, the button will be disabled, the down arrow will be greyed out.
  EspmuiDropdownWidget({
    required this.value,
    required this.items,
    this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // logD("EspmuiDropdown build() value: $value items: $items");
    // items?.forEach((item) {
    //   logD("EspmuiDropdown build() item: ${item.child.toStringDeep()}");
    // });
    Widget dropdown = Empty();
    //return dropdown;
    if (items != null) if (items!.any((item) => item.value == value))
      dropdown = DecoratedBox(
        decoration: ShapeDecoration(
          color: Colors.white10,
          shape: RoundedRectangleBorder(
            side: BorderSide(width: 1.0, style: BorderStyle.solid, color: Colors.white24),
            borderRadius: BorderRadius.all(Radius.circular(3.0)),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 0, 0, 0),
          child: DropdownButton<String>(
            value: value,
            items: items,
            underline: SizedBox(),
            onChanged: onChanged,
            isExpanded: true,
          ),
        ),
      );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: (label == null)
          ? dropdown
          : Row(children: [
              Expanded(
                flex: 5,
                child: label!,
              ),
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: dropdown,
                ),
              ),
            ]),
    );
  }
}

class ApiSettingDropdownWidget extends EspmuiDropdownWidget {
  final Api api;
  final int? command;

  ApiSettingDropdownWidget({
    required this.api,
    required this.command,
    required String? value,
    required List<DropdownMenuItem<String>>? items,
    Widget? label,
    String? commandArg,
    void Function(String?)? onChanged,
  }) : super(
          value: value,
          items: items,
          label: label,
          onChanged: (String? value) async {
            if (null == command) return;
            if (onChanged != null) onChanged(value);
            commandArg = null == commandArg ? '' : commandArg! + ':';
            final result = await api.requestResultCode(
              "$command=$commandArg${value ?? value.toString()}",
              minDelayMs: 2000,
            );
            if (label != null) snackbar("$label ${value ?? value.toString()} ${result == ApiResult.success ? "success" : " failure"}");
            print("[ApiSettingDropdown] api.requestResultCode($command): $result");
          },
        );
}

class EspmSettingsWidget extends StatelessWidget with Debug {
  final ESPM device;

  EspmSettingsWidget(this.device);

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Container(
        padding: EdgeInsets.all(5),
        margin: EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
            //color: Colors.white10,
            border: Border.all(width: 1, color: Colors.white12),
            borderRadius: BorderRadius.circular(5)),
        child: child,
      );
    }

    final apiWifiSettings = ApiWifiSettingsWidget(this.device.api, this.device.wifiSettings);

    final deviceSettings = ValueListenableBuilder<ESPMSettings>(
      valueListenable: device.settings,
      builder: (_, settings, __) {
        //logD("changed: $settings");
        var widgets = <Widget>[
          ApiSettingInputWidget(
            api: device.api,
            name: "Crank Length",
            commandCode: device.api.commandCode("cl", logOnError: false),
            value: settings.cranklength == null ? "" : settings.cranklength.toString(),
            suffix: Text("mm"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingSwitchWidget(
            api: device.api,
            name: "Reverse Strain",
            commandCode: device.api.commandCode("rs", logOnError: false),
            value: settings.reverseStrain,
            onChanged: () {
              device.settings.value.reverseStrain = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
          ApiSettingSwitchWidget(
            api: device.api,
            name: "Double Power",
            commandCode: device.api.commandCode("dp", logOnError: false),
            value: settings.doublePower,
            onChanged: () {
              device.settings.value.doublePower = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
          ApiSettingInputWidget(
            api: device.api,
            name: "Sleep Delay",
            commandCode: device.api.commandCode("sd", logOnError: false),
            value: settings.sleepDelay == null ? "" : settings.sleepDelay.toString(),
            transformInput: (value) {
              var ms = int.tryParse(value);
              return (ms == null) ? "30000" : "${ms * 1000 * 60}";
            },
            suffix: Text("minutes"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingDropdownWidget(
            label: Text('Negative Torque Method'),
            api: device.api,
            command: device.api.commandCode("ntm", logOnError: false),
            value: settings.negativeTorqueMethod.toString(),
            onChanged: (value) {
              logD("Negative Torque Method: $value");
            },
            items: settings.negativeTorqueMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text(" "),
                    ),
                  ]
                : settings.negativeTorqueMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text("${e.value}"),
                        ))
                    .toList(),
          ),
          ApiSettingDropdownWidget(
            label: Text('Motion Detection Method'),
            api: device.api,
            command: device.api.commandCode("mdm", logOnError: false),
            value: settings.motionDetectionMethod.toString(),
            onChanged: (value) {
              logD("Motion Detection Method: $value");
            },
            items: settings.motionDetectionMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text(" "),
                    ),
                  ]
                : settings.motionDetectionMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text("${e.value}"),
                        ))
                    .toList(),
          ),
        ];
        if (settings.motionDetectionMethod ==
            settings.motionDetectionMethods.keys.firstWhere((k) => settings.motionDetectionMethods[k] == "Strain gauge", orElse: () => -1)) {
          //logD("MDM==SG strainThresLow: ${settings.strainThresLow}");
          widgets.add(Divider(color: Colors.white38));
          widgets.add(
            Row(children: [
              ApiSettingInputWidget(
                api: device.api,
                name: "Low Threshold",
                commandCode: device.api.commandCode("stl", logOnError: false),
                value: settings.strainThresLow == null ? null : settings.strainThresLow.toString(),
                keyboardType: TextInputType.number,
                enabled: settings.strainThresLow != null,
                suffix: Text("kg"),
              ),
              Empty(),
              ApiSettingInputWidget(
                api: device.api,
                name: "High Threshold",
                commandCode: device.api.commandCode("st", logOnError: false),
                value: settings.strainThreshold == null ? null : settings.strainThreshold.toString(),
                keyboardType: TextInputType.number,
                enabled: settings.strainThreshold != null,
                suffix: Text("kg"),
              ),
            ]),
          );
        }

        int? tcCode = device.api.commandCode("tc", logOnError: false);
        if (null != tcCode && ExtendedBool.Unknown != settings.tc.enabled) {
          widgets.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                EspmuiElevatedButton(
                  child: Icon(Icons.edit),
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageTransition(
                        type: PageTransitionType.rightToLeft,
                        child: TCRoute(device),
                      ),
                    );
                  },
                ),
                Text("  "),
                Flexible(
                  child: ApiSettingSwitchWidget(
                    api: device.api,
                    name: "Temperature Compensation",
                    commandCode: device.api.commandCode("tc", logOnError: false),
                    value: settings.tc.enabled,
                    onChanged: () {
                      device.settings.value.tc.enabled = ExtendedBool.Waiting;
                      device.settings.notifyListeners();
                    },
                  ),
                ),
              ],
            ),
          );
        }

        widgets.add(
          ApiSettingSwitchWidget(
            api: device.api,
            name: "Auto Tare",
            commandCode: device.api.commandCode("at", logOnError: false),
            value: settings.autoTare,
            onChanged: () {
              device.settings.value.autoTare = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
        );
        if (ExtendedBool.True == settings.autoTare) {
          widgets.add(
            Row(children: [
              ApiSettingInputWidget(
                api: device.api,
                name: "Delay",
                commandCode: device.api.commandCode("atd", logOnError: false),
                value: settings.autoTareDelayMs == null ? null : settings.autoTareDelayMs.toString(),
                keyboardType: TextInputType.number,
                enabled: settings.autoTareDelayMs != null,
                suffix: Text("ms"),
              ),
              Empty(),
              ApiSettingInputWidget(
                api: device.api,
                name: "Max. Range",
                commandCode: device.api.commandCode("atr", logOnError: false),
                value: settings.autoTareRangeG == null ? null : settings.autoTareRangeG.toString(),
                keyboardType: TextInputType.number,
                enabled: settings.autoTareRangeG != null,
                suffix: Text("g"),
              ),
            ]),
          );
        }

        widgets.add(
          Column(children: [
            Divider(color: Colors.white38),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              EspmuiElevatedButton(
                backgroundColorEnabled: Colors.blue.shade900,
                onPressed: settings.otaMode
                    ? null
                    : () async {
                        int? code = await device.api.requestResultCode("system=ota");
                        if (1 == code) {
                          device.settings.value.otaMode = true;
                          device.settings.notifyListeners();
                          snackbar("Waiting for OTA update, reboot to cancel", context);
                        } else
                          snackbar("Failed to enter OTA mode", context);
                      },
                child: Row(children: [
                  Icon(Icons.system_update),
                  Text("OTA"),
                ]),
              ),
              EspmuiElevatedButton(
                backgroundColorEnabled: Colors.yellow.shade900,
                onPressed: () async {
                  device.api.request<String>("system=reboot");
                },
                child: Row(children: [
                  Icon(Icons.restart_alt),
                  Text("Reboot"),
                ]),
              ),
            ]),
          ]),
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );

    return ExpansionTile(title: Text("Settings"), textColor: Colors.white, iconColor: Colors.white, children: [
      Column(mainAxisSize: MainAxisSize.min, children: [
        frame(apiWifiSettings),
        frame(deviceSettings),
        frame(ApiInterfaceWidget(device.api)),
      ])
    ]);
  }
}

class PeersEditorWidget extends StatelessWidget with Debug {
  final DeviceWithPeers device;
  PeersEditorWidget(this.device);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PeerSettings>(
        valueListenable: device.peerSettings,
        builder: (_, settings, __) {
          return Column(children: [
            PeersListWidget(
              peers: settings.peers,
              action: "delete",
              device: device,
            ),
            PeersListWidget(
              peers: settings.scanResults.where((element) => settings.peers.contains(element) ? false : true).toList(),
              action: "add",
              device: device,
            ),
            EspmuiElevatedButton(
              child: Text(settings.scanning ? "Scanning..." : "Scan"),
              onPressed: settings.scanning
                  ? null
                  : () {
                      //device.peerSettings.value.scanning = true;
                      device.peerSettings.value.scanResults = [];
                      device.peerSettings.notifyListeners();
                      (device as DeviceWithApi).api.sendCommand("peers=scan:10");
                    },
            ),
          ]);
        });
  }
}

class FullWidthTrackShape extends RoundedRectSliderTrackShape {
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double? trackHeight = sliderTheme.trackHeight;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - (trackHeight ?? 0)) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, (trackHeight ?? 0));
  }
}

class EspccTouchEditorWidget extends StatelessWidget with Debug {
  final ESPCC device;
  EspccTouchEditorWidget(this.device);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ESPCCSettings>(
        valueListenable: device.settings,
        builder: (_, settings, __) {
          List<Widget> items = [];
          settings.touchThres.forEach((k, v) {
            int cur = settings.touchRead.containsKey(k) ? settings.touchRead[k] ?? 0 : 0;
            if (cur < 0) cur = 0;
            if (100 < cur) cur = 100;
            items.add(Stack(children: [
              FractionallySizedBox(
                widthFactor: map(cur.toDouble(), 0.0, 100.0, 0.0, 1.0),
                alignment: Alignment.topLeft,
                child: Container(
                  color: Color.fromARGB(110, 36, 124, 28),
                  child: Text(""),
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackShape: FullWidthTrackShape(),
                ),
                child: Slider(
                  label: v.toString(),
                  value: v.toDouble(),
                  min: 0.0,
                  max: 100.0,
                  onChanged: (newValue) {
                    //logD("$k changed to $newValue");
                    device.settings.value.touchThres[k] = newValue.toInt();
                  },
                  onChangeEnd: (newValue) {
                    String thres = "";
                    device.settings.value.touchThres.forEach((key, value) {
                      if (0 < thres.length) thres += ",";
                      if (key == k)
                        thres += "$key:${newValue.toInt()}";
                      else
                        thres += "$key:$value";
                    });
                    device.api.sendCommand("touch=thresholds:$thres");
                  },
                ),
              ),
            ]));
          });
          return Column(children: items);
        });
  }
}

class EspccSyncWidget extends StatelessWidget with Debug {
  final ESPCC device;
  EspccSyncWidget(this.device);

  @override
  Widget build(BuildContext context) {
    device.syncer.start();
    //logD("files: ${device.files.value.files}");
    return ValueListenableBuilder<ESPCCFileList>(
      valueListenable: device.files,
      builder: (_, filelist, __) {
        List<Widget> items = [];
        filelist.files.sort((a, b) => b.name.compareTo(a.name)); // desc
        filelist.files.forEach((f) {
          String details = "";
          String separator = "\n";
          if (0 <= f.remoteSize) details += bytesToString(f.remoteSize);
          if (0 <= f.localSize) details += " (${bytesToString(f.localSize)})";
          if (0 < f.distance) {
            details += "$separator→${distanceToString(f.distance)}";
            separator = " ";
          }
          if (0 < f.altGain) details += "$separator↑${f.altGain.toString()}m";
          List<Widget> actions = [];
          bool isQueued = device.syncer.isQueued(f);
          bool isDownloading = device.syncer.isDownloading(f);
          bool isDownloadable = !isQueued &&
              !isDownloading &&
              f.remoteExists == ExtendedBool.True &&
              0 < f.remoteSize &&
              f.localExists != ExtendedBool.Unknown &&
              f.localSize < f.remoteSize;
          int downloadedPercent = map(
            0 <= f.localSize ? f.localSize.toDouble() : 0,
            0,
            0 <= f.remoteSize ? f.remoteSize.toDouble() : 0,
            0,
            100,
          ).toInt();
          //logD("${f.name}: isQueued: $isQueued, isDownloading: $isDownloading, isDownloadable: $isDownloadable, downloadedPercent: $downloadedPercent");
          if (isQueued) {
            actions.add(EspmuiElevatedButton(
              child: Wrap(children: [
                Icon(isDownloading ? Icons.downloading : Icons.queue),
                Text("$downloadedPercent%"),
              ]),
              padding: EdgeInsets.all(0),
            ));
          }
          var onPressed;
          if (isQueued)
            onPressed = () {
              device.syncer.dequeue(f);
              device.files.notifyListeners();
            };
          else if (isDownloadable)
            onPressed = () {
              device.syncer.queue(f);
              device.files.notifyListeners();
            };
          actions.add(EspmuiElevatedButton(
            child: Icon(isQueued ? Icons.stop : Icons.download),
            padding: EdgeInsets.all(0),
            onPressed: onPressed,
          ));
          actions.add(EspmuiElevatedButton(
            child: Icon(Icons.delete),
            padding: EdgeInsets.all(0),
            onPressed: () async {
              bool sure = false;
              await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                      scrollable: false,
                      title: Text("Delete ${f.name}?"),
                      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          "Downloaded $downloadedPercent%",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text("$details"),
                      ]),
                      actions: [
                        EspmuiElevatedButton(
                          child: Text("Yes"),
                          onPressed: () {
                            sure = true;
                            Navigator.of(context).pop();
                          },
                        ),
                        EspmuiElevatedButton(
                          child: Text("No"),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ]);
                },
              );
              logD("delete: ${f.name} sure: $sure");
              if (sure) {
                int? code = await device.api.requestResultCode("rec=delete:${f.name}", expectValue: "deleted: ${f.name}");
                if (code == 1) {
                  device.syncer.dequeue(f);
                  device.files.value.files.removeWhere((file) => file.name == f.name);
                  device.files.notifyListeners();
                  snackbar("Deleted ${f.name}", context);
                } else
                  snackbar("Could not delete ${f.name}", context);
              }
            },
          ));
          var item = Card(
            color: Colors.black12,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  f.name,
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  details,
                  style: const TextStyle(
                    fontSize: 14.0,
                    color: Colors.white54,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: actions,
                ),
              ]),
            ),
            // ListTile(
            //   title: Text(f.name),
            //   subtitle: Text(details),
            //   trailing: Wrap(children: actions),
            //   //isThreeLine: true,
            //   contentPadding: EdgeInsets.fromLTRB(0, 0, 0, 5),
            // ),
          );
          items.add(item);
        });
        if (filelist.syncing == ExtendedBool.True) items.add(Text("Syncing..."));
        if (0 == items.length) items.add(Text("No files"));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items +
                [
                  EspmuiElevatedButton(
                    onPressed: filelist.syncing == ExtendedBool.True
                        ? null
                        : () {
                            device.refreshFileList();
                          },
                    child: Row(children: [
                      Icon(Icons.sync),
                      Text("Refresh"),
                    ]),
                  )
                ]);
      },
    );
  }
}

class DeviceIcon extends StatelessWidget {
  final String? type;
  DeviceIcon(this.type);
  Widget build(BuildContext context) {
    return Icon(data());
  }

  IconData data() {
    IconData id = Icons.question_mark;
    if ("ESPM" == type)
      id = Icons.offline_bolt;
    else if ("PM" == type)
      id = Icons.bolt;
    else if ("ESPCC" == type)
      id = Icons.smartphone;
    else if ("HRM" == type)
      id = Icons.favorite;
    else if ("Vesc" == type)
      id = Icons.electric_bike;
    else if ("BMS" == type)
      id = Icons.battery_std;
    else if ("HomeAuto" == type) id = Icons.control_point;
    return id;
  }
}

class PeersListWidget extends StatelessWidget with Debug {
  final List<String> peers;
  final String action;
  final DeviceWithPeers device;

  PeersListWidget({required this.peers, this.action = "none", required this.device});

  @override
  Widget build(BuildContext context) {
    var list = Column(children: []);
    peers.forEach((peer) {
      // addr,addrType,deviceType,deviceName
      var parts = peer.split(",");
      if (parts.length < 4) return;
      String? iconType;
      String? command;
      String? Function(String?, SettingInputWidget?)? commandProcessor;
      IconData? commandIcon;
      SettingInputWidget? passcodeEntry;

      if (parts[2] == "E") {
        /* ESPM */
        iconType = "ESPM";
        if ("add" == action) {
          passcodeEntry = SettingInputWidget(
            name: "Passcode",
            keyboardType: TextInputType.number,
            textController: device.peerSettings.value.getController(peer: peer),
          );
          commandProcessor = (command, passcodeEntry) {
            if (null == command) return command;
            String? value = passcodeEntry?.getValue();
            logD("commandProcessor: value=$value");
            if (null == value) return command;
            command += ",${int.tryParse(value)}";
            return command;
          };
        }
      } else if (parts[2] == "P") {
        /* Powermeter */
        iconType = "PM";
      } else if (parts[2] == "H") {
        /* Heartrate monitor */
        iconType = "HRM";
      } else if (parts[2] == "V") {
        /* VESC */
        iconType = "Vesc";
      } else if (parts[2] == "B") {
        /* JkBms */
        iconType = "BMS";
        if ("add" == action) {
          passcodeEntry = SettingInputWidget(
            name: "Passcode",
            keyboardType: TextInputType.number,
            textController: device.peerSettings.value.getController(peer: peer),
          );
          commandProcessor = (command, passcodeEntry) {
            if (null == command) return command;
            String? value = passcodeEntry?.getValue();
            logD("commandProcessor: value=$value");
            if (null == value) return command;
            command += ",${int.tryParse(value)}";
            return command;
          };
        }
      }
      if ("add" == action) {
        command = "peers=add:$peer";
        commandIcon = Icons.link;
      } else if ("delete" == action) {
        command = "peers=delete:${parts[0]}";
        commandIcon = Icons.link_off;
      }
      var button = null == command
          ? Empty()
          : EspmuiElevatedButton(
              child: Icon(commandIcon),
              onPressed: () {
                if (null != commandProcessor) command = commandProcessor(command, passcodeEntry);
                (device as DeviceWithApi).api.sendCommand(command!);
                (device as DeviceWithApi).api.sendCommand("peers");
              },
            );
      list.children.add(
        Card(
          color: Colors.black12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                DeviceIcon(iconType),
                Text(" "),
                Text(parts[3]),
              ]),
              Row(children: [
                passcodeEntry ?? Text(" "),
                Text(" "),
                button,
              ])
            ]),
          ),
        ),
      );
    });
    return list;
  }
}

class EspccSettingsWidget extends StatelessWidget with Debug {
  final ESPCC device;

  EspccSettingsWidget(this.device);

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Container(
        padding: EdgeInsets.all(5),
        margin: EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
            //color: Colors.white10,
            border: Border.all(width: 1, color: Colors.white12),
            borderRadius: BorderRadius.circular(5)),
        child: child,
      );
    }

    final apiWifiSettings = ApiWifiSettingsWidget(device.api, device.wifiSettings);

    Future<void> dialog({required Widget title, required Widget body, bool scrollable = true}) async {
      return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: scrollable,
            title: title,
            content: Container(
              child: Column(children: [
                body,
              ]),
            ),
          );
        },
      );
    }

    final peers = ValueListenableBuilder<PeerSettings>(
      valueListenable: device.peerSettings,
      builder: (_, settings, __) {
        return PeersListWidget(peers: settings.peers, device: device);
      },
    );

    final deviceSettings = ValueListenableBuilder<ESPCCSettings>(
      valueListenable: device.settings,
      builder: (_, settings, __) {
        var widgets = <Widget>[
          EspmuiElevatedButton(
            backgroundColorEnabled: Colors.cyan.shade900,
            onPressed: () async {
              device.refreshFileList();
              await dialog(
                title: Text("Sync recordings"),
                body: EspccSyncWidget(device),
                //scrollable: false,
              );
            },
            child: Row(children: [
              Icon(Icons.sync),
              Text("Sync recordings"),
            ]),
          ),
          Divider(color: Colors.white38),
          Row(children: [
            Flexible(
              child: Column(children: [
                Row(children: [Text("Peers")]),
                peers,
              ]),
            ),
            EspmuiElevatedButton(
              onPressed: () {
                dialog(
                  title: Text("Peers"),
                  body: PeersEditorWidget(device),
                );
              },
              child: Icon(Icons.edit),
            ),
          ]),
          Divider(color: Colors.white38),
          Row(children: [
            Flexible(
              child: Column(children: [
                Row(children: [Text("Touch")]),
              ]),
            ),
            EspmuiElevatedButton(
              backgroundColorEnabled: settings.touchEnabled ? Color.fromARGB(255, 2, 150, 2) : Color.fromARGB(255, 141, 2, 2),
              onPressed: () {
                device.api.sendCommand("touch=enabled:${settings.touchEnabled ? 0 : 1}");
              },
              child: Icon(settings.touchEnabled ? Icons.pan_tool : Icons.do_not_touch),
            ),
            EspmuiElevatedButton(
              onPressed: () async {
                final timer = Timer.periodic(const Duration(seconds: 2), (_) {
                  device.api.sendCommand("touch=disableFor:3");
                  device.api.sendCommand("touch=read");
                });
                await dialog(
                  title: Text("Touch Thresholds"),
                  body: EspccTouchEditorWidget(device),
                );
                timer.cancel();
              },
              child: Icon(Icons.edit),
            ),
          ]),
          Divider(color: Colors.white38),
          Flexible(
            child: ExpansionTile(
              title: Text("Vesc"),
              tilePadding: EdgeInsets.only(left: 0),
              childrenPadding: EdgeInsets.only(top: 10),
              textColor: Colors.white,
              iconColor: Colors.white,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Flexible(
                          flex: 5,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Number of Battery Cells",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "BNS",
                            value: -1 == settings.vescBattNumSeries ? "" : settings.vescBattNumSeries.toString(),
                            suffix: Text("in Series"),
                            keyboardType: TextInputType.number,
                          )),
                      Flexible(
                          flex: 5,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Battery Capacity",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "BC",
                            value: -1 == settings.vescBattCapacityWh ? "" : settings.vescBattCapacityWh.toString(),
                            suffix: Text("Wh"),
                            keyboardType: TextInputType.number,
                          )),
                    ]),
                    Row(children: [
                      Flexible(
                          flex: 3,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Max Power",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "MP",
                            value: -1 == settings.vescMaxPower ? "" : settings.vescMaxPower.toString(),
                            suffix: Text("W"),
                            keyboardType: TextInputType.number,
                          )),
                      Flexible(
                          flex: 4,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Min Current",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "MiC",
                            value: -1 == settings.vescMinCurrent ? "" : settings.vescMinCurrent.toString(),
                            suffix: Text("A"),
                            keyboardType: TextInputType.number,
                          )),
                      Flexible(
                          flex: 3,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Max Current",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "MaC",
                            value: -1 == settings.vescMaxCurrent ? "" : settings.vescMaxCurrent.toString(),
                            suffix: Text("A"),
                            keyboardType: TextInputType.number,
                          )),
                    ]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                            flex: 4,
                            child: ApiSettingSwitchWidget(
                              api: device.api,
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "RU",
                              name: 'Ramp up',
                              value: settings.vescRampUp,
                            )),
                        Flexible(flex: 1, child: Empty()),
                        Flexible(
                            flex: 4,
                            child: ApiSettingSwitchWidget(
                              api: device.api,
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "RD",
                              name: 'Ramp down',
                              value: settings.vescRampDown,
                            )),
                      ],
                    ),
                    Row(children: [
                      Flexible(
                          flex: 3,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Diff",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "RMCD",
                            value: -1 == settings.vescRampMinCurrentDiff ? "" : settings.vescRampMinCurrentDiff.toString(),
                            suffix: Text("A"),
                            keyboardType: TextInputType.number,
                          )),
                      Flexible(
                          flex: 4,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Steps",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "RNS",
                            value: -1 == settings.vescRampNumSteps ? "" : settings.vescRampNumSteps.toString(),
                            keyboardType: TextInputType.number,
                          )),
                      Flexible(
                          flex: 3,
                          child: ApiSettingInputWidget(
                            api: device.api,
                            name: "Time",
                            commandCode: device.api.commandCode("vesc"),
                            commandArg: "RT",
                            value: -1 == settings.vescRampTime ? "" : settings.vescRampTime.toString(),
                            suffix: Text("ms"),
                            keyboardType: TextInputType.number,
                          )),
                    ]),
                    Row(
                      children: [
                        Flexible(
                            flex: 3,
                            child: ApiSettingInputWidget(
                              api: device.api,
                              name: "Mot Warn",
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "TMW",
                              value: -1 == settings.vescTempMotorWarning ? "" : settings.vescTempMotorWarning.toString(),
                              suffix: Text("˚C"),
                              keyboardType: TextInputType.number,
                            )),
                        Flexible(
                            flex: 2,
                            child: ApiSettingInputWidget(
                              api: device.api,
                              name: "Mot Limit",
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "TML",
                              value: -1 == settings.vescTempMotorLimit ? "" : settings.vescTempMotorLimit.toString(),
                              suffix: Text("˚C"),
                              keyboardType: TextInputType.number,
                            )),
                        Flexible(
                            flex: 2,
                            child: ApiSettingInputWidget(
                              api: device.api,
                              name: "ESC Warn",
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "TEW",
                              value: -1 == settings.vescTempEscWarning ? "" : settings.vescTempEscWarning.toString(),
                              suffix: Text("˚C"),
                              keyboardType: TextInputType.number,
                            )),
                        Flexible(
                            flex: 3,
                            child: ApiSettingInputWidget(
                              api: device.api,
                              name: "ESC Limit",
                              commandCode: device.api.commandCode("vesc"),
                              commandArg: "TEL",
                              value: -1 == settings.vescTempEscLimit ? "" : settings.vescTempEscLimit.toString(),
                              suffix: Text("˚C"),
                              keyboardType: TextInputType.number,
                            )),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
          Divider(color: Colors.white38),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            EspmuiElevatedButton(
              backgroundColorEnabled: Colors.blue.shade900,
              onPressed: settings.otaMode
                  ? null
                  : () async {
                      int? code = await device.api.requestResultCode("system=ota");
                      if (1 == code) {
                        device.settings.value.otaMode = true;
                        device.settings.notifyListeners();
                        snackbar("Waiting for OTA update, reboot to cancel", context);
                      } else
                        snackbar("Failed to enter OTA mode", context);
                    },
              child: Row(children: [
                Icon(Icons.system_update),
                Text("OTA"),
              ]),
            ),
            EspmuiElevatedButton(
              backgroundColorEnabled: Colors.yellow.shade900,
              onPressed: () async {
                int? code = await device.api.requestResultCode("system=reboot");
                if (code == ApiResult.success) {
                  // snackbar("Rebooting", context);
                  // device.disconnect();
                  // await Future.delayed(Duration(seconds: 2));
                  // device.connect();
                } else
                  snackbar("Failed to reboot", context);
              },
              child: Row(children: [
                Icon(Icons.restart_alt),
                Text("Reboot"),
              ]),
            ),
          ]),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );

    return ExpansionTile(
      title: Text("Settings"),
      textColor: Colors.white,
      iconColor: Colors.white,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          frame(apiWifiSettings),
          frame(deviceSettings),
          frame(ApiInterfaceWidget(device.api)),
        ])
      ],
    );
  }
}

class EpeverSettingsWidget extends StatelessWidget with Debug {
  final Api api;
  final EpeverSettings settings;
  EpeverSettingsWidget(this.settings, this.api);

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [];
    int cs = settings.get('cs')?.value ?? 1;
    settings.values.forEach((arg, setting) {
      Widget input;
      if ('typ' == arg) {
        input = ApiSettingDropdownWidget(
          api: api,
          command: api.commandCode('ep'),
          commandArg: arg,
          label: Text('Battery type'),
          value: setting.value.toString(),
          items: [
            DropdownMenuItem(value: '0', child: Text('User')),
            DropdownMenuItem(value: '1', child: Text('Sealed LA')),
            DropdownMenuItem(value: '2', child: Text('Gel')),
            DropdownMenuItem(value: '3', child: Text('Flooded')),
          ],
        );
      } else {
        input = ApiSettingInputWidget(
          api: api,
          commandCode: api.commandCode('ep'),
          commandArg: arg,
          name: setting.name,
          value: null == setting.value ? '' : setting.value.toString(),
          suffix: Text(setting.unit),
          keyboardType: TextInputType.number,
        );
      }
      if ('V' == setting.unit) {
        widgets.add(Flexible(
            child: Row(children: [
          Flexible(flex: 5, child: input),
          Flexible(
            flex: 5,
            child: ApiSettingInputWidget(
              api: api,
              commandCode: api.commandCode('ep'),
              commandArg: arg,
              value: null == setting.value ? '' : (setting.value / cs).toString(),
              transformInput: (String val) {
                var out = double.tryParse(val);
                return null == out ? '' : (out * cs).toString();
              },
              suffix: Text('Vpc'),
              keyboardType: TextInputType.number,
            ),
          ),
        ])));
        return;
      }
      widgets.add(
        Flexible(
          child: input,
        ),
      );
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class SwitchesSettingsWidget extends StatelessWidget with Debug {
  final Api api;
  final HomeAutoSwitches switches;
  SwitchesSettingsWidget(this.switches, this.api);

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [];

    List<DropdownMenuItem<String>> modes = [];
    HomeAutoSwitchModes.values.forEach((_, mode) {
      modes.add(DropdownMenuItem(value: mode.name, child: Text(mode.label)));
    });

    switches.values.forEach((name, sw) {
      if (0 < widgets.length) widgets.add(Divider(color: Colors.white38));

      if (null == sw.mode) {
        widgets.add(Text(name));
        return;
      }
      widgets.add(Flexible(
        child: ApiSettingDropdownWidget(
          api: api,
          command: api.commandCode('switch'),
          commandArg: name,
          label: Row(children: [sw.stateIcon(size: 25), Text(name)]),
          value: sw.mode?.name,
          items: modes,
        ),
      ));

      if (null == sw.mode?.unit) return;
      widgets.addAll({
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                flex: 5,
                child: ApiSettingInputWidget(
                  api: api,
                  commandCode: api.commandCode('switch'),
                  commandArg: name,
                  name: 'On above',
                  value: sw.onValue().toString(),
                  suffix: null == sw.mode?.unit ? null : Text(sw.mode!.unit!),
                  keyboardType: TextInputType.number,
                  transformInput: (input) {
                    return (sw.mode?.name ?? 'NO_MODE') + ',' + input + ',' + sw.offValue().toString();
                  },
                )),
            Flexible(
                flex: 5,
                child: ApiSettingInputWidget(
                  api: api,
                  commandCode: api.commandCode('switch'),
                  commandArg: name,
                  name: 'Off below',
                  value: sw.offValue().toString(),
                  suffix: null == sw.mode?.unit ? null : Text(sw.mode!.unit!),
                  keyboardType: TextInputType.number,
                  transformInput: (input) {
                    return (sw.mode?.name ?? 'NO_MODE') + ',' + sw.onValue().toString() + ',' + input;
                  },
                )),
          ],
        ),
      });
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}

class HomeAutoSettingsWidget extends StatelessWidget with Debug {
  final HomeAuto device;

  HomeAutoSettingsWidget(this.device);

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Flexible(
        child: Container(
          padding: EdgeInsets.all(5),
          margin: EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
              //color: Colors.white10,
              border: Border.all(width: 1, color: Colors.white12),
              borderRadius: BorderRadius.circular(5)),
          child: child,
        ),
      );
    }

    final apiWifiSettings = ApiWifiSettingsWidget(device.api, device.wifiSettings);

    Future<void> dialog({required Widget title, required Widget body, bool scrollable = true}) async {
      return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: scrollable,
            title: title,
            content: Container(
              child: Column(children: [
                body,
              ]),
            ),
          );
        },
      );
    }

    final peers = ValueListenableBuilder<PeerSettings>(
      valueListenable: device.peerSettings,
      builder: (_, settings, __) {
        return PeersListWidget(peers: settings.peers, device: device);
      },
    );

    final deviceSettings = ValueListenableBuilder<HomeAutoSettings>(
      valueListenable: device.settings,
      builder: (_, settings, __) {
        var widgets = <Widget>[
          ExpansionTile(title: Text('Switches'), children: [
            SwitchesSettingsWidget(
              settings.switches,
              device.api,
            ),
          ]),
          Divider(color: Colors.white38),
          ExpansionTile(title: Text('Charger'), children: [
            SizedBox(width: 1, height: 5),
            EpeverSettingsWidget(
              settings.epever,
              device.api,
            )
          ]),
          Divider(color: Colors.white38),
          ExpansionTile(title: Text('BMS'), children: [Text('not implemented')]),
          Divider(color: Colors.white38),
          ExpansionTile(title: Text('Peers'), children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                peers,
                EspmuiElevatedButton(
                  onPressed: () {
                    dialog(
                      title: Text("Peers"),
                      body: PeersEditorWidget(device),
                    );
                  },
                  child: Icon(Icons.edit),
                ),
              ],
            ),
          ]),
          Divider(color: Colors.white38),
          ExpansionTile(title: Text('System'), children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              EspmuiElevatedButton(
                backgroundColorEnabled: Colors.blue.shade900,
                onPressed: settings.otaMode
                    ? null
                    : () async {
                        int? code = await device.api.requestResultCode("system=ota");
                        if (1 == code) {
                          device.settings.value.otaMode = true;
                          device.settings.notifyListeners();
                          snackbar("Waiting for OTA update, reboot to cancel", context);
                        } else
                          snackbar("Failed to enter OTA mode", context);
                      },
                child: Row(children: [
                  Icon(Icons.system_update),
                  Text("OTA"),
                ]),
              ),
              EspmuiElevatedButton(
                backgroundColorEnabled: Colors.yellow.shade900,
                onPressed: () async {
                  int? code = await device.api.requestResultCode("system=reboot");
                  if (code == ApiResult.success) {
                    // snackbar("Rebooting", context);
                    // device.disconnect();
                    // await Future.delayed(Duration(seconds: 2));
                    // device.connect();
                  } else
                    snackbar("Failed to reboot", context);
                },
                child: Row(children: [
                  Icon(Icons.restart_alt),
                  Text("Reboot"),
                ]),
              ),
            ])
          ]),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );

    return ExpansionTile(
      title: Text("Settings"),
      textColor: Colors.white,
      iconColor: Colors.white,
      children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          frame(deviceSettings),
          frame(apiWifiSettings),
          frame(ApiInterfaceWidget(device.api)),
        ])
      ],
    );
  }
}

class ApiWifiSettingsWidget extends StatelessWidget {
  final Api api;
  final AlwaysNotifier<WifiSettings> wifiSettings;

  ApiWifiSettingsWidget(this.api, this.wifiSettings);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WifiSettings>(
      valueListenable: wifiSettings,
      builder: (context, settings, child) {
        //logD("changed: $settings");
        var widgets = <Widget>[
          ApiSettingSwitchWidget(
            api: api,
            name: "Enable Wifi",
            commandCode: api.commandCode("w", logOnError: false),
            value: settings.enabled,
            onChanged: () {
              wifiSettings.value.enabled = ExtendedBool.Waiting;
              wifiSettings.notifyListeners();
            },
          ),
        ];
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            ApiSettingSwitchWidget(
              api: api,
              name: "Access Point",
              commandCode: api.commandCode("wa"),
              value: settings.apEnabled,
              onChanged: () {
                wifiSettings.value.apEnabled = ExtendedBool.Waiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.apEnabled == ExtendedBool.True)
            widgets.add(
              Row(children: [
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "SSID",
                      commandCode: api.commandCode("was"),
                      value: settings.apSSID,
                      enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                    )),
                Empty(),
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "Password",
                      commandCode: api.commandCode("wap"),
                      value: "",
                      isPassword: true,
                      enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                    )),
              ]),
            );
        }
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            ApiSettingSwitchWidget(
              api: api,
              name: "Station",
              commandCode: api.commandCode("ws"),
              value: settings.staEnabled,
              onChanged: () {
                wifiSettings.value.staEnabled = ExtendedBool.Waiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.staEnabled == ExtendedBool.True) {
            widgets.add(
              Row(children: [
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "SSID",
                      commandCode: api.commandCode("wss"),
                      value: settings.staSSID,
                      enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                    )),
                Empty(),
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "Password",
                      commandCode: api.commandCode("wsp"),
                      value: "",
                      isPassword: true,
                      enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                    )),
              ]),
            );
          }
        }
        return ExpansionTile(title: Text('Wifi'), children: widgets);
      },
    );
  }
}

class FavoriteIcon extends StatelessWidget {
  final Color activeColor = Color.fromARGB(255, 128, 255, 128);
  final Color inactiveColor = Colors.grey;
  final bool active;
  final double size;

  FavoriteIcon({this.active = true, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.star, size: size, color: active ? activeColor : inactiveColor);
  }
}

class AutoConnectIcon extends StatelessWidget {
  final Color activeColor = Color.fromARGB(255, 128, 255, 128);
  final Color inactiveColor = Colors.grey;
  final bool active;
  final double size;

  AutoConnectIcon({this.active = true, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.autorenew, size: size, color: active ? activeColor : inactiveColor);
  }
}

class ConnectionStateIcon extends StatelessWidget {
  final Color connectedColor = Color.fromARGB(255, 128, 255, 128);
  final Color connectingColor = Colors.yellow;
  final Color disconnectedColor = Colors.grey;
  final Color disconnecingColor = Colors.red;
  final Object? state;
  final double size;

  ConnectionStateIcon({this.state, this.size = 28});

  @override
  Widget build(BuildContext context) {
    if (state == PeripheralConnectionState.connected) return Icon(Icons.link, size: size, color: connectedColor);
    if (state == PeripheralConnectionState.connecting) return Icon(Icons.search, size: size, color: connectingColor);
    if (state == PeripheralConnectionState.disconnected) return Icon(Icons.link_off, size: size, color: disconnectedColor);
    if (state == PeripheralConnectionState.disconnecting) return Icon(Icons.cut, size: size, color: disconnecingColor);
    return Empty();
  }
}

class HeroDialogRoute<T> extends PageRoute<T> {
  late bool _opaque, _barrierDismissible;
  late Color _barrierColor;

  HeroDialogRoute({
    required this.builder,
    bool opaque = false,
    bool barrierDismissible = true,
    Color barrierColor = Colors.black54,
  }) : super() {
    _opaque = opaque;
    _barrierDismissible = barrierDismissible;
    _barrierColor = barrierColor;
  }

  final WidgetBuilder builder;

  @override
  bool get opaque => _opaque;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  bool get maintainState => true;

  @override
  Color get barrierColor => _barrierColor;

  @override
  String? get barrierLabel => "barrierLabel";

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return builder(context);
  }
}
