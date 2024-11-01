import 'dart:async';
//import 'dart:html';
//import 'dart:math';

import 'package:flutter/material.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

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

class DeviceConnState extends StatelessWidget {
  final Device device;
  final void Function()? onConnected;

  const DeviceConnState(this.device, {super.key, this.onConnected});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DeviceConnectionState?>(
      stream: device.stateStream,
      initialData: null,
      builder: (BuildContext context, AsyncSnapshot<DeviceConnectionState?> snapshot) {
        if (DeviceConnectionState.connected == snapshot.data && null != onConnected) onConnected!();
        String connState = snapshot.hasData ? snapshot.data.toString() : "....";
        //logD("Device status: connState=$connState");
        return Text(
          connState.substring(connState.lastIndexOf(".") + 1),
          style: const TextStyle(fontSize: 10),
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

  const DeviceAppBarTitle(this.device, {super.key, this.nameEditable = true, this.prefix = "", this.onConnected});

  @override
  Widget build(BuildContext context) {
    void editDeviceName() async {
      if (device is! ESPM && device is! ESPCC) return;

      Future<bool> apiDeviceName(String name) async {
        var co = context.mounted ? context : null;
        var api = (ESPM == await device.correctType()) ? (device as ESPM).api : (device as ESPCC).api;
        // ignore: use_build_context_synchronously
        snackbar("Sending new device name: $name", co);
        String? value = await api.request<String>("hostName=$name");
        if (value != name) {
          // ignore: use_build_context_synchronously
          snackbar("Error renaming device", co);
          return false;
        }
        // ignore: use_build_context_synchronously
        snackbar("Success setting new hostname on device: $value", co);
        // ignore: use_build_context_synchronously
        snackbar("Sending reboot command", co);
        await api.request<bool>("reboot=2000"); // reboot in 2s
        // ignore: use_build_context_synchronously
        snackbar("Disconnecting", co);
        await device.disconnect();
        // ignore: use_build_context_synchronously
        snackbar("Waiting for device to boot", co);
        await Future.delayed(const Duration(milliseconds: 4000));
        // ignore: use_build_context_synchronously
        snackbar("Connecting to device", co);
        await device.connect();
        // ignore: use_build_context_synchronously
        snackbar("Success", co);
        return true;
      }

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: const Text("Rename device"),
            content: TextField(
              maxLength: 31,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              controller: TextEditingController()..text = device.name,
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
        prefix + (device.name.isNotEmpty ? device.name : 'unknown'),
        style: Theme.of(context).textTheme.titleLarge,
        maxLines: 1,
        overflow: TextOverflow.clip,
      );
    }

    return Row(
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
                              padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.all(0)),
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
                  DeviceConnState(device, onConnected: onConnected),
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
    );
  }
}

class ConnectButton extends StatelessWidget with Debug {
  final Device device;
  ConnectButton(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    //logD("initialState: ${device.lastConnectionState}");
    return StreamBuilder<DeviceConnectionState?>(
      stream: device.stateStream,
      initialData: device.lastConnectionState,
      builder: (BuildContext context, AsyncSnapshot<DeviceConnectionState?> snapshot) {
        //logD("$snapshot");
        Future<void> Function()? action;
        var label = "Connect";
        if (snapshot.data == DeviceConnectionState.connected) {
          action = device.disconnect;
          label = "Disconnect";
        } else if (snapshot.data == DeviceConnectionState.connecting) {
          action = device.disconnect;
          label = "Cancel";
        } else if (snapshot.data == DeviceConnectionState.disconnecting) {
          label = "Disonnecting";
        } else {
          //if (snapshot.data == PeripheralConnectionState.disconnected)
          action = device.connect;
        }
        return EspmuiElevatedButton(onPressed: action, child: Text(label));
      },
    );
  }
}

class BatteryWidget extends StatelessWidget {
  final Device device;
  const BatteryWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.battery?.defaultStream,
      initialData: device.battery?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Battery"),
          Flexible(
            fit: FlexFit.loose,
            child: Align(
              child: Text(
                snapshot.hasData ? "${snapshot.data}" : "--",
                style: const TextStyle(fontSize: 30),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomRight,
            child: Text(
              "%",
              style: TextStyle(color: Colors.white24),
            ),
          ),
        ]);
      },
    );
  }
}

class EspmWeightScaleStreamListenerWidget extends StatelessWidget {
  final ESPM device;
  final int mode;

  const EspmWeightScaleStreamListenerWidget(this.device, this.mode, {super.key});

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
  EspmWeightScaleWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    void calibrate() async {
      Future<void> apiCalibrate(String knownMassStr) async {
        var co = context.mounted ? context : null;
        var api = device.api;
        snackbar("Sending calibration value: $knownMassStr", co);
        String? value = await api.request<String>("cs=$knownMassStr");
        var errorMsg = "Error calibrating device";
        if (value == null) {
          // ignore: use_build_context_synchronously
          snackbar(errorMsg, co);
          return;
        }
        var parsedValue = double.tryParse(value);
        if (parsedValue == null) {
          // ignore: use_build_context_synchronously
          snackbar(errorMsg, co);
          return;
        }
        var parsedKnownMass = double.tryParse(knownMassStr);
        if (parsedKnownMass == null) {
          // ignore: use_build_context_synchronously
          snackbar(errorMsg, co);
          return;
        }
        if (parsedValue < parsedKnownMass * .999 || parsedValue > parsedKnownMass * 1.001) {
          // ignore: use_build_context_synchronously
          snackbar(errorMsg, co);
          return;
        }
        // ignore: use_build_context_synchronously
        snackbar("Success calibrating device", co);
      }

      Widget autoTareWarning = device.settings.value.autoTare == ExtendedBool.eTrue ? const Text("Warning: AutoTare is enabled") : const Empty();

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: const Text("Calibrate device"),
            content: Column(children: [
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
          );
        },
      );
    }

    void toggle(int mode) async {
      device.weightServiceMode.value = ESPMWeightServiceMode.wsmUnknown;
      bool enable = mode < 1;
      bool success = false;
      int? reply = await device.api.request<int>(
        "wse=${enable ? //
            ESPMWeightServiceMode.wsmWhenNoCrank.toString() : ESPMWeightServiceMode.wsmOff.toString()}",
      );
      if (ESPMWeightServiceMode.wsmOn == reply || ESPMWeightServiceMode.wsmWhenNoCrank == reply) {
        if (enable) success = true;
        await device.weightScaleChar?.subscribe();
      } else if (ESPMWeightServiceMode.wsmOff == reply) {
        if (!enable) success = true;
        await device.characteristic("weightScale")?.unsubscribe();
      } else {
        device.weightServiceMode.value = ESPMWeightServiceMode.wsmUnknown;
      }
      snackbar(
        "Weight service ${enable ? "en" : "dis"}able${success ? "d" : " failed"}",
        context.mounted ? context : null,
      );
    }

    void tare() async {
      var resultCode = await device.api.requestResultCode("tare=0");
      //debugLog('requestResultCode("tare=0"): $resultCode');
      snackbar(
        "Tare ${resultCode == ApiResult.success ? "success" : "failed"}",
        context.mounted ? context : null,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: device.weightServiceMode,
      builder: (_, mode, __) {
        var strainOutput = EspmWeightScaleStreamListenerWidget(device, mode);

        return InkWell(
          onTap: () {
            if (ESPMWeightServiceMode.wsmOff < mode) tare();
          },
          onLongPress: () {
            if (ESPMWeightServiceMode.wsmOff < mode) calibrate();
          },
          onDoubleTap: () {
            toggle(mode);
          },
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Scale"),
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                child: device.connected
                    ? mode == ESPMWeightServiceMode.wsmUnknown
                        ? const CircularProgressIndicator()
                        : strainOutput
                    : strainOutput,
              ),
            ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Text(
                "kg",
                style: TextStyle(color: Colors.white24),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class EspmHallStreamListenerWidget extends StatelessWidget {
  final ESPM device;
  final ExtendedBool enabled;

  const EspmHallStreamListenerWidget(this.device, this.enabled, {super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.hallChar?.defaultStream,
      initialData: device.hallChar?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        String value = snapshot.hasData && enabled != ExtendedBool.eFalse ? (snapshot.data! > 0 ? snapshot.data!.toString() : '--') : "--";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(value, style: (enabled == ExtendedBool.eTrue) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class EspmHallSensorWidget extends StatelessWidget {
  final ESPM device;
  const EspmHallSensorWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    void settings() async {
      int? hallOffset = await device.api.request<int>("ho");
      int? hallThreshold = await device.api.request<int>("ht");
      int? hallThresLow = await device.api.request<int>("htl");

      await showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: const Text("Hall Sensor Settings"),
            content: Column(children: [
              EspmHallStreamListenerWidget(device, ExtendedBool.eTrue),
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
          );
        },
      );
    }

    void toggle(enabled) async {
      device.hallEnabled.value = ExtendedBool.eWaiting;
      bool enable = enabled == ExtendedBool.eTrue ? false : true;
      bool? reply = await device.api.request<bool>("hc=${enable ? "true" : "false"}");
      bool success = reply == enable;
      if (success) {
        if (enable) {
          await device.hallChar?.subscribe();
        } else {
          await device.hallChar?.unsubscribe();
        }
      } else {
        device.hallEnabled.value = ExtendedBool.eUnknown;
      }
      snackbar(
        "Hall readings ${enable ? "en" : "dis"}able${success ? "d" : " failed"}",
        context.mounted ? context : null,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.hallEnabled,
      builder: (_, enabled, __) {
        return InkWell(
          onLongPress: () {
            if (enabled == ExtendedBool.eTrue) settings();
          },
          onDoubleTap: () {
            if (enabled == ExtendedBool.eTrue || enabled == ExtendedBool.eFalse || enabled == ExtendedBool.eUnknown) toggle(enabled);
          },
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Hall"),
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                child: (enabled == ExtendedBool.eWaiting) ? const CircularProgressIndicator() : EspmHallStreamListenerWidget(device, enabled),
              ),
            ),
            const Text(" "),
          ]),
        );
      },
    );
  }
}

class PowerCadenceWidget extends StatelessWidget with Debug {
  final PowerMeter device;
  final String mode;

  /// [mode] = "power" | "cadence"
  PowerCadenceWidget(this.device, {super.key, this.mode = "power"});

  @override
  Widget build(BuildContext context) {
    BleCharacteristic? tmpChar = device.power;
    if (tmpChar is! PowerCharacteristic) return const Text('Error: no power char');
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
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(mode == "power" ? "Power" : "Cadence"),
      Flexible(
        fit: FlexFit.loose,
        child: Align(child: value),
      ),
      Align(
        alignment: Alignment.bottomRight,
        child: Text(
          mode == "power" ? "W" : "rpm",
          style: const TextStyle(color: Colors.white24),
        ),
      ),
    ]);
  }
}

class HeartRateWidget extends StatelessWidget {
  final HeartRateMonitor device;

  const HeartRateWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    BleCharacteristic? tmpChar = device.heartRate;
    if (tmpChar is! HeartRateCharacteristic) return const Text('Error: not HR char');
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
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("HR"),
      Flexible(
        fit: FlexFit.loose,
        child: Align(child: value),
      ),
      const Align(
        alignment: Alignment.bottomRight,
        child: Text(
          "bpm",
          style: TextStyle(color: Colors.white24),
        ),
      ),
    ]);
  }
}

class ApiStreamWidget extends StatelessWidget {
  final Api api;
  const ApiStreamWidget(this.api, {super.key});

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
  ApiCliWidget(this.api, {super.key});

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

  const ApiInterfaceWidget(this.api, {super.key});

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
  final void Function(String, BuildContext? context)? onChanged;
  final void Function(String, BuildContext? context)? onSubmitted;
  final TextEditingController? controller;

  SettingInputWidget({
    super.key,
    this.value,
    this.enabled = true,
    this.name,
    this.isPassword = false,
    this.transformInput,
    this.suffix,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.controller,
  }) {
    //logD("construct $name key: $key, value: $value, controller: $textController");
  }

  String? getValue() => controller?.text;

  void setValue(String value) {
    logD("setting $value on controller: $controller");
    controller?.value = TextEditingValue(text: value);
  }

  @override
  Widget build(BuildContext context) {
    //logD("_SettingInputWidgetState build() value: $value");
    return TextField(
      keyboardType: keyboardType,
      obscureText: isPassword,
      enableSuggestions: false,
      autocorrect: false,
      enabled: enabled,
      controller: controller ?? TextEditingController(text: value),
      /*
      controller: controller ??
          TextEditingController.fromValue(
            TextEditingValue(
              text: value ?? '',
              //selection: TextSelection.collapsed(offset: value?.length ?? 0),
            ),
          ),
      */
      decoration: InputDecoration(
        labelText: name,
        suffix: suffix,
        isDense: true,
        filled: true,
        fillColor: Colors.white10,
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
      onSubmitted: (text) {
        logD("onSubmitted $name $text");
        if (null != onSubmitted) onSubmitted!(text, context);
      },
      onChanged: (text) {
        logD("onChanged $name $text");
        if (null != onChanged) onChanged!(text, context);
      },
    );
  }
}

class ApiSettingInputWidget extends SettingInputWidget {
  final Api api;
  final int? commandCode;
  final String? commandArg;
  final String commandArgValueSeparator;
  final String? expect;

  ApiSettingInputWidget({
    super.key,
    required this.api,
    required this.commandCode,
    this.commandArg,
    this.commandArgValueSeparator = ':',
    this.expect,
    super.value,
    super.enabled,
    super.name,
    super.isPassword,
    super.transformInput,
    super.suffix,
    super.keyboardType,
    super.controller,
    super.onChanged,
  }) : super(
          onSubmitted: (edited, context) async {
            if (null == commandCode) {
              //logD("command is null");
              return;
            }
            if (transformInput != null) edited = transformInput(edited);
            var sep = commandArgValueSeparator;
            String command = "$commandCode=${null != commandArg ? "$commandArg$sep" : ""}$edited";
            String? expectValue = expect ?? (null != commandArg ? "$commandArg$sep" : null);
            final result = await api.requestResultCode(
              command,
              expectValue: expectValue,
              minDelayMs: 2000,
            );
            if (name != null) {
              snackbar(
                  "$name update${result == ApiResult.success ? "d" : " failed"}",
                  context != null
                      ? context.mounted
                          ? context
                          : null
                      : null);
            }
            //logD('api.requestResultCode("$command", expectValue="$expect"): $result');
          },
        );
}

class SettingSwitchWidget extends StatelessWidget with Debug {
  final ExtendedBool value;
  final Widget? label;
  final void Function(bool)? onChanged;

  /// whether the switch can be toggled
  final bool enabled;

  SettingSwitchWidget({
    super.key,
    required this.value,
    this.label,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    var toggler = value == ExtendedBool.eWaiting
        ? const CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.eTrue ? true : false,
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
    super.key,
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
    var onOff = value == ExtendedBool.eWaiting
        ? const CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.eTrue ? true : false,
            activeColor: Colors.red,
            onChanged: (bool enabled) async {
              if (null == commandCode) return;
              if (onChanged != null) onChanged!();
              final result = await api.requestResultCode(
                "$commandCode=${null != commandArg ? "$commandArg:" : ""}${enabled ? "1" : "0"}",
                expectValue: null != commandArg ? "$commandArg:" : null,
                minDelayMs: 2000,
              );
              if (name != null) {
                snackbar("$name ${enabled ? "en" : "dis"}able${result == ApiResult.success ? "d" : " failed"}", context.mounted ? context : null);
              }
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
  final String? name;
  final Widget? label;
  final void Function(String?)? onChanged;

  /// Creates a dropdown button.
  /// The [items] must have distinct values. If [value] isn't null then it must be
  /// equal to one of the [DropdownMenuItem] values. If [items] or [onChanged] is
  /// null, the button will be disabled, the down arrow will be greyed out.
  EspmuiDropdownWidget({
    super.key,
    required this.value,
    required this.items,
    this.name,
    this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // logD("EspmuiDropdown build() value: $value items: $items");
    // items?.forEach((item) {
    //   logD("EspmuiDropdown build() item: ${item.child.toStringDeep()}");
    // });
    Widget dropdown = const Empty();
    //return dropdown;
    if (items != null && items!.any((item) => item.value == value)) {
      dropdown = DecoratedBox(
        decoration: const ShapeDecoration(
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
            underline: const SizedBox(),
            onChanged: onChanged,
            isExpanded: true,
          ),
        ),
      );
    }
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
                  padding: const EdgeInsets.only(left: 10),
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
    required super.value,
    required super.items,
    super.name,
    super.label,
    super.key,
    String? commandArg,
    void Function(String?)? onChanged,
  }) : super(
          onChanged: (String? value) async {
            if (null == command) return;
            if (onChanged != null) onChanged(value);
            commandArg = null == commandArg ? '' : '${commandArg!}:';
            final result = await api.requestResultCode(
              "$command=$commandArg${value ?? value.toString()}",
              minDelayMs: 2000,
            );
            if (name != null) snackbar("$name ${value ?? value.toString()} ${result == ApiResult.success ? "success" : " failure"}");
            //logD("[ApiSettingDropdown] api.requestResultCode($command): $result");
          },
        );
}

class EspmSettingsWidget extends StatelessWidget with Debug {
  final ESPM device;

  EspmSettingsWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Container(
        padding: const EdgeInsets.all(5),
        margin: const EdgeInsets.only(bottom: 15),
        decoration: BoxDecoration(
            //color: Colors.white10,
            border: Border.all(width: 1, color: Colors.white12),
            borderRadius: BorderRadius.circular(5)),
        child: child,
      );
    }

    final apiWifiSettings = ApiWifiSettingsWidget(device.api, device.wifiSettings);

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
            suffix: const Text("mm"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingSwitchWidget(
            api: device.api,
            name: "Reverse Strain",
            commandCode: device.api.commandCode("rs", logOnError: false),
            value: settings.reverseStrain,
            onChanged: () {
              device.settings.value.reverseStrain = ExtendedBool.eWaiting;
              device.settings.notifyListeners();
            },
          ),
          ApiSettingSwitchWidget(
            api: device.api,
            name: "Double Power",
            commandCode: device.api.commandCode("dp", logOnError: false),
            value: settings.doublePower,
            onChanged: () {
              device.settings.value.doublePower = ExtendedBool.eWaiting;
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
            suffix: const Text("minutes"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingDropdownWidget(
            label: const Text('Negative Torque Method'),
            api: device.api,
            command: device.api.commandCode("ntm", logOnError: false),
            value: settings.negativeTorqueMethod.toString(),
            onChanged: (value) {
              logD("Negative Torque Method: $value");
            },
            items: settings.negativeTorqueMethod == null
                ? [
                    const DropdownMenuItem<String>(
                      child: Text(" "),
                    ),
                  ]
                : settings.negativeTorqueMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text(e.value),
                        ))
                    .toList(),
          ),
          ApiSettingDropdownWidget(
            label: const Text('Motion Detection Method'),
            api: device.api,
            command: device.api.commandCode("mdm", logOnError: false),
            value: settings.motionDetectionMethod.toString(),
            onChanged: (value) {
              logD("Motion Detection Method: $value");
            },
            items: settings.motionDetectionMethod == null
                ? [
                    const DropdownMenuItem<String>(
                      child: Text(" "),
                    ),
                  ]
                : settings.motionDetectionMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text(e.value),
                        ))
                    .toList(),
          ),
        ];
        if (settings.motionDetectionMethod ==
            settings.motionDetectionMethods.keys.firstWhere((k) => settings.motionDetectionMethods[k] == "Strain gauge", orElse: () => -1)) {
          //logD("MDM==SG strainThresLow: ${settings.strainThresLow}");
          widgets.add(const Divider(color: Colors.white38));
          widgets.add(
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                child: ApiSettingInputWidget(
                  api: device.api,
                  name: "Low Threshold",
                  commandCode: device.api.commandCode("stl", logOnError: false),
                  value: settings.strainThresLow?.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThresLow != null,
                  suffix: const Text("kg"),
                ),
              ),
              Flexible(
                child: ApiSettingInputWidget(
                  api: device.api,
                  name: "High Threshold",
                  commandCode: device.api.commandCode("st", logOnError: false),
                  value: settings.strainThreshold?.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThreshold != null,
                  suffix: const Text("kg"),
                ),
              ),
            ]),
          );
        }

        int? tcCode = device.api.commandCode("tc", logOnError: false);
        if (null != tcCode && ExtendedBool.eUnknown != settings.tc.enabled) {
          widgets.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                EspmuiElevatedButton(
                  child: const Icon(Icons.edit),
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
                const Text("  "),
                Flexible(
                  child: ApiSettingSwitchWidget(
                    api: device.api,
                    name: "Temperature Compensation",
                    commandCode: device.api.commandCode("tc", logOnError: false),
                    value: settings.tc.enabled,
                    onChanged: () {
                      device.settings.value.tc.enabled = ExtendedBool.eWaiting;
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
              device.settings.value.autoTare = ExtendedBool.eWaiting;
              device.settings.notifyListeners();
            },
          ),
        );
        if (ExtendedBool.eTrue == settings.autoTare) {
          widgets.add(
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(
                child: ApiSettingInputWidget(
                  api: device.api,
                  name: "Delay",
                  commandCode: device.api.commandCode("atd", logOnError: false),
                  value: settings.autoTareDelayMs?.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareDelayMs != null,
                  suffix: const Text("ms"),
                ),
              ),
              Flexible(
                child: ApiSettingInputWidget(
                  api: device.api,
                  name: "Max. Range",
                  commandCode: device.api.commandCode("atr", logOnError: false),
                  value: settings.autoTareRangeG?.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareRangeG != null,
                  suffix: const Text("g"),
                ),
              ),
            ]),
          );
        }

        widgets.add(
          Column(children: [
            const Divider(color: Colors.white38),
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
                          snackbar("OTA enabled", context.mounted ? context : null);
                        } else {
                          snackbar("OTA failed", context.mounted ? context : null);
                        }
                      },
                child: const Row(children: [
                  Icon(Icons.system_update),
                  Text("OTA"),
                ]),
              ),
              EspmuiElevatedButton(
                backgroundColorEnabled: Colors.yellow.shade900,
                onPressed: () async {
                  device.api.request<String>("system=reboot");
                },
                child: const Row(children: [
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

    return ExpansionTile(title: const Text("Settings"), textColor: Colors.white, iconColor: Colors.white, children: [
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
  PeersEditorWidget(this.device, {super.key});

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
              onPressed: settings.scanning
                  ? null
                  : () {
                      logD("before: ${device.peerSettings.value.peers}");
                      //device.peerSettings.value.scanning = true;
                      device.peerSettings.value.scanResults = [];
                      device.peerSettings.notifyListeners();
                      logD("after: ${device.peerSettings.value.peers}");
                      (device as DeviceWithApi).api.sendCommand("peers=scan:10");
                    },
              child: Text(settings.scanning ? "Scanning..." : "Scan"),
            ),
          ]);
        });
  }
}

class FullWidthTrackShape extends RoundedRectSliderTrackShape {
  @override
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
  EspccTouchEditorWidget(this.device, {super.key});

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
                  color: const Color.fromARGB(110, 36, 124, 28),
                  child: const Text(""),
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
                      if (thres.isNotEmpty) thres += ",";
                      if (key == k) {
                        thres += "$key:${newValue.toInt()}";
                      } else {
                        thres += "$key:$value";
                      }
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
  EspccSyncWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    device.syncer.start();
    //logD("files: ${device.files.value.files}");
    return ValueListenableBuilder<ESPCCFileList>(
      valueListenable: device.files,
      builder: (_, filelist, __) {
        List<Widget> items = [];
        filelist.files.sort((a, b) => b.name.compareTo(a.name)); // desc
        for (var f in filelist.files) {
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
              f.remoteExists == ExtendedBool.eTrue &&
              0 < f.remoteSize &&
              f.localExists != ExtendedBool.eUnknown &&
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
              padding: const EdgeInsets.all(0),
              child: Wrap(children: [
                Icon(isDownloading ? Icons.downloading : Icons.queue),
                Text("$downloadedPercent%"),
              ]),
            ));
          }
          Null Function()? onPressed;
          if (isQueued) {
            onPressed = () {
              device.syncer.dequeue(f);
              device.files.notifyListeners();
            };
          } else if (isDownloadable) {
            onPressed = () {
              device.syncer.queue(f);
              device.files.notifyListeners();
            };
          }
          actions.add(EspmuiElevatedButton(
            padding: const EdgeInsets.all(0),
            onPressed: onPressed,
            child: Icon(isQueued ? Icons.stop : Icons.download),
          ));
          actions.add(EspmuiElevatedButton(
            padding: const EdgeInsets.all(0),
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
                        Text(details),
                      ]),
                      actions: [
                        EspmuiElevatedButton(
                          child: const Text("Yes"),
                          onPressed: () {
                            sure = true;
                            Navigator.of(context).pop();
                          },
                        ),
                        EspmuiElevatedButton(
                          child: const Text("No"),
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
                  snackbar("Deleted ${f.name}", context.mounted ? context : null);
                } else {
                  snackbar("Could not delete ${f.name}", context.mounted ? context : null);
                }
              }
            },
            child: const Icon(Icons.delete),
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
        }
        if (filelist.syncing == ExtendedBool.eTrue) items.add(const Text("Syncing..."));
        if (items.isEmpty) items.add(const Text("No files"));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items +
                [
                  EspmuiElevatedButton(
                    onPressed: filelist.syncing == ExtendedBool.eTrue
                        ? null
                        : () {
                            device.refreshFileList();
                          },
                    child: const Row(children: [
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
  const DeviceIcon(this.type, {super.key});
  @override
  Widget build(BuildContext context) {
    return Icon(data());
  }

  IconData data() {
    IconData id = Icons.question_mark;
    if ("ESPM" == type) {
      id = Icons.offline_bolt;
    } else if ("PM" == type) {
      id = Icons.bolt;
    } else if ("ESPCC" == type) {
      id = Icons.smartphone;
    } else if ("HRM" == type) {
      id = Icons.favorite;
    } else if ("Vesc" == type) {
      id = Icons.electric_bike;
    } else if ("BMS" == type) {
      id = Icons.battery_std;
    } else if ("HomeAuto" == type) {
      id = Icons.control_point;
    }
    return id;
  }
}

class PeersListWidget extends StatelessWidget with Debug {
  final List<String> peers;
  final String action;
  final DeviceWithPeers device;

  PeersListWidget({super.key, required this.peers, this.action = "none", required this.device});

  @override
  Widget build(BuildContext context) {
    var list = List<Widget>.empty(growable: true);
    for (var peer in peers) {
      // addr,addrType,deviceType,deviceName
      var parts = peer.split(",");
      if (parts.length < 4) continue;
      String? iconType;
      String? command;
      String? Function(String?, SettingInputWidget?)? commandProcessor;
      IconData? commandIcon;
      SettingInputWidget? passcodeEntry;

      if (parts[2] == "E") {
        /* ESPM */
        iconType = "ESPM";
        if ("add" == action) {
          var controller = device.peerSettings.value.getController(peer: peer);
          passcodeEntry = SettingInputWidget(
            name: "Passcode",
            keyboardType: TextInputType.number,
            controller: controller,
          );
          commandProcessor = (command, passcodeEntry) {
            if (null == command) return command;
            String? value = controller?.value.text;
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
          var controller = device.peerSettings.value.getController(peer: peer);
          passcodeEntry = SettingInputWidget(
            name: "Passcode",
            keyboardType: TextInputType.number,
            controller: controller,
          );
          commandProcessor = (command, passcodeEntry) {
            if (null == command) return command;
            String? value = controller?.value.text;
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
          ? const Empty()
          : EspmuiElevatedButton(
              child: Icon(commandIcon),
              onPressed: () {
                if (null != commandProcessor) command = commandProcessor(command, passcodeEntry);
                (device as DeviceWithApi).api.sendCommand(command!);
                (device as DeviceWithApi).api.sendCommand("peers");
              },
            );
      list.add(
        Card(
          color: Colors.black12,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                DeviceIcon(iconType),
                const Text(" "),
                Text(parts[3]),
              ]),
              Row(children: [
                (null != passcodeEntry) ? Expanded(child: passcodeEntry) : const Text(" "),
                const Text(" "),
                button,
              ])
            ]),
          ),
        ),
      );
    }
    return Column(children: list);
  }
}

class EspccSettingsWidget extends StatelessWidget with Debug {
  final ESPCC device;

  EspccSettingsWidget(this.device, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Container(
        padding: const EdgeInsets.all(5),
        margin: const EdgeInsets.only(bottom: 15),
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
            content: Column(children: [
              body,
            ]),
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
                title: const Text("Sync recordings"),
                body: EspccSyncWidget(device),
                //scrollable: false,
              );
            },
            child: const Row(children: [
              Icon(Icons.sync),
              Text("Sync recordings"),
            ]),
          ),
          const Divider(color: Colors.white38),
          Row(children: [
            Flexible(
              child: Column(children: [
                const Row(children: [Text("Peers")]),
                peers,
              ]),
            ),
            EspmuiElevatedButton(
              onPressed: () {
                dialog(
                  title: const Text("Peers"),
                  body: PeersEditorWidget(device),
                );
              },
              child: const Icon(Icons.edit),
            ),
          ]),
          const Divider(color: Colors.white38),
          Row(children: [
            const Flexible(
              child: Column(children: [
                Row(children: [Text("Touch")]),
              ]),
            ),
            EspmuiElevatedButton(
              backgroundColorEnabled: settings.touchEnabled ? const Color.fromARGB(255, 2, 150, 2) : const Color.fromARGB(255, 141, 2, 2),
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
                  title: const Text("Touch Thresholds"),
                  body: EspccTouchEditorWidget(device),
                );
                timer.cancel();
              },
              child: const Icon(Icons.edit),
            ),
          ]),
          const Divider(color: Colors.white38),
          Flexible(
            child: ExpansionTile(
              title: const Text("Vesc"),
              tilePadding: const EdgeInsets.only(left: 0),
              childrenPadding: const EdgeInsets.only(top: 10),
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
                            suffix: const Text("in Series"),
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
                            suffix: const Text("Wh"),
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
                            suffix: const Text("W"),
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
                            suffix: const Text("A"),
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
                            suffix: const Text("A"),
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
                        const Flexible(flex: 1, child: Empty()),
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
                            suffix: const Text("A"),
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
                            suffix: const Text("ms"),
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
                              suffix: const Text("˚C"),
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
                              suffix: const Text("˚C"),
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
                              suffix: const Text("˚C"),
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
                              suffix: const Text("˚C"),
                              keyboardType: TextInputType.number,
                            )),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white38),
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
                        snackbar("Waiting for OTA update, reboot to cancel", context.mounted ? context : null);
                      } else {
                        snackbar("Failed to enter OTA mode", context.mounted ? context : null);
                      }
                    },
              child: const Row(children: [
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
                } else {
                  snackbar("Failed to reboot", context.mounted ? context : null);
                }
              },
              child: const Row(children: [
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
      title: const Text("Settings"),
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
  final AutoChargingVoltage acv;
  EpeverSettingsWidget(this.settings, this.acv, this.api, {super.key});

  Widget get suffixVpack => const Row(mainAxisSize: MainAxisSize.min, children: [Text('V'), Text('pack', style: TextStyle(fontSize: 5))]);

  Widget get suffixVcell => const Row(mainAxisSize: MainAxisSize.min, children: [Text('V'), Text('cell', style: TextStyle(fontSize: 5))]);

  TextInputType get keyboardNumDec => const TextInputType.numberWithOptions(decimal: true);

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [];
    widgets.add(ApiSettingSwitchWidget(
      api: api,
      commandCode: api.commandCode('acv'),
      value: ExtendedBool.fromBool(acv.enabled),
      name: 'Auto Charging Voltage',
      onChanged: () {
        logD('onChanged');
      },
    ));
    if (acv.enabled ?? false) {
      widgets.addAll([
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            flex: 5,
            child: ApiSettingInputWidget(
              api: api,
              commandCode: api.commandCode('acv'),
              commandArg: 'min',
              expect: '',
              value: acv.min.toString(),
              name: 'Min',
              suffix: suffixVpack,
              keyboardType: keyboardNumDec,
            ),
          ),
          Flexible(
            flex: 5,
            child: ApiSettingInputWidget(
              api: api,
              commandCode: api.commandCode('acv'),
              commandArg: 'max',
              expect: '',
              value: acv.max.toString(),
              name: 'Max',
              suffix: suffixVpack,
              keyboardType: keyboardNumDec,
            ),
          ),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            flex: 5,
            child: ApiSettingInputWidget(
              api: api,
              commandCode: api.commandCode('acv'),
              commandArg: 'release',
              expect: '',
              value: acv.release.toString(),
              name: 'Low trigger',
              suffix: suffixVcell,
              keyboardType: keyboardNumDec,
            ),
          ),
          Flexible(
            flex: 5,
            child: ApiSettingInputWidget(
              api: api,
              commandCode: api.commandCode('acv'),
              commandArg: 'trigger',
              expect: '',
              value: acv.trigger.toString(),
              name: 'High trigger',
              suffix: suffixVcell,
              keyboardType: keyboardNumDec,
            ),
          ),
        ]),
      ]);
    }
    widgets.add(const Divider(color: Colors.white38));
    int cellCount = settings.get('cs')?.value ?? 1;
    settings.values.forEach((arg, setting) {
      Widget input;
      if ('typ' == arg) {
        input = ApiSettingDropdownWidget(
          api: api,
          command: api.commandCode('ep'),
          commandArg: arg,
          label: const Text('Battery type'),
          value: setting.value.toString(),
          items: const [
            DropdownMenuItem(value: '0', child: Text('User')),
            DropdownMenuItem(value: '1', child: Text('Sealed LA')),
            DropdownMenuItem(value: '2', child: Text('Gel')),
            DropdownMenuItem(value: '3', child: Text('Flooded')),
          ],
        );
      } else {
        var onChanged = ('V' != setting.unit)
            ? null
            : (changed, context) {
                logD("changed $arg");
              };
        input = ApiSettingInputWidget(
          api: api,
          commandCode: api.commandCode('ep'),
          commandArg: arg,
          name: setting.name,
          suffix: ('V' == setting.unit) ? suffixVpack : Text(setting.unit),
          keyboardType: keyboardNumDec,
          onChanged: onChanged,
          controller: setting.controller,
        );
      }
      if ('V' == setting.unit && input is ApiSettingInputWidget) {
        var inputVpc = ApiSettingInputWidget(
          api: api,
          commandCode: api.commandCode('ep'),
          commandArg: arg,
          value: null == setting.value ? '' : (setting.value / cellCount).toString(),
          transformInput: (String val) {
            var out = double.tryParse(val);
            return null == out ? '' : (out * cellCount).toString();
          },
          suffix: suffixVcell,
          keyboardType: keyboardNumDec,
          onChanged: (changed, context) {
            var d = double.tryParse(changed);
            if (null != d) setting.controller.value = TextEditingValue(text: (d * cellCount).toString());
            logD("changed: $arg $changed Vpc, set: ${setting.controller.value.text}");
          },
        );
        widgets.add(Flexible(
            child: Row(children: [
          Flexible(flex: 5, child: input),
          Flexible(flex: 5, child: inputVpc),
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
  final focusNode = FocusNode();
  final List<String> open;

  SwitchesSettingsWidget(this.switches, this.api, {super.key, this.open = const []});

  @override
  Widget build(BuildContext context) {
    List<Widget> widgets = [];

    List<DropdownMenuItem<String>> modes = [];
    HomeAutoSwitchModes.values.forEach((_, mode) {
      modes.add(DropdownMenuItem(value: mode.name, child: Text(mode.label)));
    });

    switches.values.forEach((name, sw) {
      if (widgets.isNotEmpty) widgets.add(const Divider(color: Colors.white38));

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
      widgets.add(
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
                  value: sw.onValue.toString(),
                  suffix: null == sw.mode?.unit ? null : Text(sw.mode!.unit!),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  transformInput: (input) {
                    var ret = '${sw.mode?.name ?? 'NO_MODE'},$input,${sw.offValue}';
                    logD("$input transformed to $ret");
                    return ret;
                  },
                )),
            Flexible(
                flex: 5,
                child: ApiSettingInputWidget(
                  api: api,
                  commandCode: api.commandCode('switch'),
                  commandArg: name,
                  name: 'Off below',
                  value: sw.offValue.toString(),
                  suffix: null == sw.mode?.unit ? null : Text(sw.mode!.unit!),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  transformInput: (input) {
                    var ret = '${sw.mode?.name ?? 'NO_MODE'},${sw.onValue},$input';
                    logD("$input transformed to $ret");
                    return ret;
                  },
                )),
          ],
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

class HomeAutoSettingsWidget extends StatelessWidget with Debug {
  final HomeAuto device;
  final String? focus;
  final List<String> open;

  HomeAutoSettingsWidget(this.device, {super.key, this.focus, this.open = const []}) {
    logD("construct focus: $focus, open: $open");
  }

  @override
  Widget build(BuildContext context) {
    Widget frame(Widget child) {
      return Flexible(
        child: Container(
          padding: const EdgeInsets.all(5),
          margin: const EdgeInsets.only(bottom: 15),
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
            content: Column(children: [
              body,
            ]),
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
        var switchesSettingsWidget = SwitchesSettingsWidget(
          settings.switches,
          device.api,
          open: open,
        );
        if ('switches' == focus) {
          switchesSettingsWidget.focusNode.requestFocus();
        }
        var widgets = <Widget>[
          ExpansionTile(
            title: const Text('Switches'),
            initiallyExpanded: open.contains('switches'),
            children: [
              switchesSettingsWidget,
            ],
          ),
          const Divider(color: Colors.white38),
          ExpansionTile(title: const Text('Charger'), children: [
            const SizedBox(width: 1, height: 5),
            EpeverSettingsWidget(
              settings.epever,
              settings.acv,
              device.api,
            )
          ]),
          const Divider(color: Colors.white38),
          const ExpansionTile(title: Text('BMS'), children: [Text('not implemented')]),
          const Divider(color: Colors.white38),
          ExpansionTile(title: const Text('Peers'), children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                peers,
                EspmuiElevatedButton(
                  onPressed: () {
                    dialog(
                      title: const Text("Peers"),
                      body: PeersEditorWidget(device),
                    );
                  },
                  child: const Icon(Icons.edit),
                ),
              ],
            ),
          ]),
          const Divider(color: Colors.white38),
          ExpansionTile(title: const Text('System'), children: [
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
                          snackbar("Waiting for OTA update, reboot to cancel", context.mounted ? context : null);
                        } else {
                          snackbar("Failed to enter OTA mode", context.mounted ? context : null);
                        }
                      },
                child: const Row(children: [
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
                  } else {
                    snackbar("Failed to reboot", context.mounted ? context : null);
                  }
                },
                child: const Row(children: [
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
      title: const Text("Settings"),
      textColor: Colors.white,
      iconColor: Colors.white,
      initiallyExpanded: open.contains('settings'),
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

  const ApiWifiSettingsWidget(this.api, this.wifiSettings, {super.key});

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
              wifiSettings.value.enabled = ExtendedBool.eWaiting;
              wifiSettings.notifyListeners();
            },
          ),
        ];
        if (settings.enabled == ExtendedBool.eTrue) {
          widgets.add(
            ApiSettingSwitchWidget(
              api: api,
              name: "Access Point",
              commandCode: api.commandCode("wa"),
              value: settings.apEnabled,
              onChanged: () {
                wifiSettings.value.apEnabled = ExtendedBool.eWaiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.apEnabled == ExtendedBool.eTrue) {
            widgets.add(
              Row(children: [
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "SSID",
                      commandCode: api.commandCode("was"),
                      value: settings.apSSID,
                      enabled: settings.apEnabled == ExtendedBool.eTrue ? true : false,
                    )),
                const Empty(),
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "Password",
                      commandCode: api.commandCode("wap"),
                      value: "",
                      isPassword: true,
                      enabled: settings.apEnabled == ExtendedBool.eTrue ? true : false,
                    )),
              ]),
            );
          }
        }
        if (settings.enabled == ExtendedBool.eTrue) {
          widgets.add(
            ApiSettingSwitchWidget(
              api: api,
              name: "Station",
              commandCode: api.commandCode("ws"),
              value: settings.staEnabled,
              onChanged: () {
                wifiSettings.value.staEnabled = ExtendedBool.eWaiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.staEnabled == ExtendedBool.eTrue) {
            widgets.add(
              Row(children: [
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "SSID",
                      commandCode: api.commandCode("wss"),
                      value: settings.staSSID,
                      enabled: settings.staEnabled == ExtendedBool.eTrue ? true : false,
                    )),
                const Empty(),
                Flexible(
                    flex: 5,
                    child: ApiSettingInputWidget(
                      api: api,
                      name: "Password",
                      commandCode: api.commandCode("wsp"),
                      value: "",
                      isPassword: true,
                      enabled: settings.staEnabled == ExtendedBool.eTrue ? true : false,
                    )),
              ]),
            );
          }
        }
        return ExpansionTile(title: const Text('Wifi'), children: widgets);
      },
    );
  }
}

class FavoriteIcon extends StatelessWidget {
  final Color activeColor = const Color.fromARGB(255, 128, 255, 128);
  final Color inactiveColor = Colors.grey;
  final bool active;
  final double size;

  const FavoriteIcon({super.key, this.active = true, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.star, size: size, color: active ? activeColor : inactiveColor);
  }
}

class AutoConnectIcon extends StatelessWidget {
  final Color activeColor = const Color.fromARGB(255, 128, 255, 128);
  final Color inactiveColor = Colors.grey;
  final bool active;
  final double size;

  const AutoConnectIcon({super.key, this.active = true, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.autorenew, size: size, color: active ? activeColor : inactiveColor);
  }
}

class ConnectionStateIcon extends StatelessWidget {
  final Color connectedColor = const Color.fromARGB(255, 128, 255, 128);
  final Color connectingColor = Colors.yellow;
  final Color disconnectedColor = Colors.grey;
  final Color disconnecingColor = Colors.red;
  final Object? state;
  final double size;

  const ConnectionStateIcon({super.key, this.state, this.size = 28});

  @override
  Widget build(BuildContext context) {
    if (state == DeviceConnectionState.connected) return Icon(Icons.link, size: size, color: connectedColor);
    if (state == DeviceConnectionState.connecting) return Icon(Icons.search, size: size, color: connectingColor);
    if (state == DeviceConnectionState.disconnected) return Icon(Icons.link_off, size: size, color: disconnectedColor);
    if (state == DeviceConnectionState.disconnecting) return Icon(Icons.cut, size: size, color: disconnecingColor);
    return const Empty();
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
