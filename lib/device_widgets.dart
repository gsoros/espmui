import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'device.dart';
import 'ble_characteristic.dart';
import 'util.dart';

class Battery extends StatelessWidget {
  final BatteryCharacteristic? char;
  Battery(this.char);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: char?.stream,
      initialData: char?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Container(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Battery"),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  child: Text(
                    "${snapshot.data}",
                    style: const TextStyle(fontSize: 40),
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
      stream: device.weightScale?.stream,
      initialData: device.weightScale?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        String strain = snapshot.hasData && enabled != ExtendedBool.False ? snapshot.data!.toStringAsFixed(2) : "0.00";
        if (strain.length > 6) strain = strain.substring(0, 6);
        if (strain == "-0.00") strain = "0.00";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(strain, style: (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class WeightScale extends StatelessWidget {
  final Device device;
  WeightScale(this.device);

  @override
  Widget build(BuildContext context) {
    void calibrate() async {
      Future<void> apiCalibrate(String knownMassStr) async {
        var api = device.api;
        snackbar("Sending calibration value: $knownMassStr", context);
        String? value = await api.request<String>("calibrateStrain=$knownMassStr");
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

    void toggle(enabled) async {
      device.weightServiceEnabled.value = ExtendedBool.Waiting;
      bool enable = enabled == ExtendedBool.True ? false : true;
      bool? reply = await device.api.request<bool>("weightService=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      if (success) {
        if (enable)
          await device.weightScale?.subscribe();
        else
          await device.characteristic("weightScale")?.unsubscribe();
      } else
        device.weightServiceEnabled.value = ExtendedBool.Unknown;
      snackbar(
        "Weight service " + (enable ? "en" : "dis") + "able" + (success ? "d" : " failed"),
        context,
      );
    }

    void tare() async {
      var resultCode = await device.api.requestResultCode("tare");
      snackbar(
        "Tare " + (resultCode == ApiResult.success.index ? "success" : "failed"),
        context,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.weightServiceEnabled,
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
            if (enabled == ExtendedBool.True || enabled == ExtendedBool.False || enabled == ExtendedBool.Unknown) toggle(enabled);
          },
          child: Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Scale"),
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    child: enabled == ExtendedBool.Waiting ? CircularProgressIndicator() : strainOutput,
                  ),
                ),
                Align(
                  child: Text(
                    "kg",
                    style: TextStyle(color: Colors.white24),
                  ),
                  alignment: Alignment.bottomRight,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HallStreamListener extends StatelessWidget {
  final Device device;
  final ExtendedBool enabled;

  HallStreamListener(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.hall?.stream,
      initialData: device.hall?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        String value = snapshot.hasData && enabled != ExtendedBool.False ? snapshot.data!.toString() : "0";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(value, style: (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class HallSensor extends StatelessWidget {
  final Device device;
  HallSensor(this.device);

  @override
  Widget build(BuildContext context) {
    void settings() async {
      int? hallOffset = await device.api.request<int>("hallOffset");
      int? hallThreshold = await device.api.request<int>("hallThreshold");
      int? hallThresLow = await device.api.request<int>("hallThresLow");

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: Text("Hall Sensor Settings"),
            content: Container(
              child: Column(
                children: [
                  HallStreamListener(device, ExtendedBool.True),
                  Row(
                    children: [
                      ApiSettingInput(
                        name: "Offset",
                        value: hallOffset.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: ApiCommand.hallOffset,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ApiSettingInput(
                        name: "High Threshold",
                        value: hallThreshold.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: ApiCommand.hallThreshold,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ApiSettingInput(
                        name: "Low Threshold",
                        value: hallThresLow.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: ApiCommand.hallThresLow,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    void toggle(enabled) async {
      device.hallEnabled.value = ExtendedBool.Waiting;
      bool enable = enabled == ExtendedBool.True ? false : true;
      bool? reply = await device.api.request<bool>("hallChar=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      if (success) {
        if (enable)
          await device.hall?.subscribe();
        else
          await device.hall?.unsubscribe();
      } else
        device.hallEnabled.value = ExtendedBool.Unknown;
      snackbar(
        "Hall readings " + (enable ? "en" : "dis") + "able" + (success ? "d" : " failed"),
        context,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.hallEnabled,
      builder: (context, enabled, child) {
        return InkWell(
          onLongPress: () {
            if (enabled == ExtendedBool.True) settings();
          },
          onDoubleTap: () {
            if (enabled == ExtendedBool.True || enabled == ExtendedBool.False || enabled == ExtendedBool.Unknown) toggle(enabled);
          },
          child: Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Hall"),
                Flexible(
                  fit: FlexFit.loose,
                  child: Align(
                    child: (enabled == ExtendedBool.Waiting) ? CircularProgressIndicator() : HallStreamListener(device, enabled),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class PowerCadence extends StatelessWidget {
  final PowerCharacteristic? char;
  final String mode;

  /// [mode] = "power" | "cadence"
  PowerCadence(this.char, {this.mode = "power"});

  @override
  Widget build(BuildContext context) {
    var value = StreamBuilder<int>(
      stream: mode == "power" ? char?.powerStream : char?.cadenceStream,
      initialData: mode == "power" ? char?.lastPower : char?.lastCadence,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Text(
          snapshot.hasData ? snapshot.data.toString() : "0",
          style: const TextStyle(fontSize: 60),
        );
      },
    );
    return Container(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
      stream: device.apiCharacteristic?.stream,
      initialData: device.apiCharacteristic?.lastValue,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
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

class ApiSettingInput extends StatelessWidget {
  final Device device;
  final ApiCommand command;
  final String? value;
  final bool enabled;
  final String? name;
  final bool isPassword;
  final String Function(String)? transformInput;
  final Widget? suffix;
  final TextInputType? keyboardType;

  ApiSettingInput({
    required this.device,
    required this.command,
    this.value,
    this.enabled = true,
    this.name,
    this.isPassword = false,
    this.transformInput,
    this.suffix,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Flexible(
      fit: FlexFit.loose,
      child: TextField(
        keyboardType: keyboardType,
        obscureText: isPassword,
        enableSuggestions: false,
        autocorrect: false,
        enabled: enabled,
        controller: TextEditingController(text: value),
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
        onSubmitted: (String edited) async {
          if (transformInput != null) edited = transformInput!(edited);
          final result = await device.api.requestResultCode(
            "${command.index}=$edited",
            minDelayMs: 2000,
          );
          if (name != null) snackbar("$name update${result == ApiResult.success.index ? "d" : " failed"}", context);
          print("[ApiSettingInput] api.request($command): $result");
        },
      ),
    );
  }
}

class ApiSettingSwitch extends StatelessWidget {
  final Device device;
  final ApiCommand command;
  final ExtendedBool value;
  final String? name;
  final void Function()? onChanged;

  ApiSettingSwitch({
    required this.device,
    required this.command,
    required this.value,
    this.name,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    var onOff = value == ExtendedBool.Waiting
        ? CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.True ? true : false,
            activeColor: Colors.red,
            onChanged: (bool enabled) async {
              if (onChanged != null) onChanged!();
              final result = await device.api.requestResultCode(
                "${command.index}=${enabled ? "1" : "0"}",
                minDelayMs: 2000,
              );
              if (name != null) snackbar("$name ${enabled ? "en" : "dis"}able${result == ApiResult.success.index ? "d" : " failed"}", context);
              print("[ApiSettingSwitch] api.requestResultCode($command): $result");
            });
    return (name == null)
        ? onOff
        : Row(children: [
            Flexible(
              fit: FlexFit.tight,
              child: Text(name!),
            ),
            onOff,
          ]);
  }
}

class ApiSettingDropdown extends StatelessWidget {
  final Device device;
  final ApiCommand command;
  final String? value;
  final List<DropdownMenuItem<String>>? items;
  final String? name;
  final void Function(String?)? onChanged;

  ApiSettingDropdown({
    required this.device,
    required this.command,
    required this.value,
    required this.items,
    this.name,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    dynamic dropdown = Text("unknown");
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
            onChanged: (String? value) async {
              if (onChanged != null) onChanged!(value);
              final result = await device.api.requestResultCode(
                "${command.index}=${value ?? value.toString()}",
                minDelayMs: 2000,
              );
              if (name != null) snackbar("$name ${value ?? value.toString()} ${result == ApiResult.success.index ? "success" : " failure"}", context);
              print("[ApiSettingDropdown] api.requestResultCode($command): $result");
            },
          ),
        ),
      );
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 5, 0, 5),
      child: (name == null)
          ? dropdown
          : Row(children: [
              Flexible(
                fit: FlexFit.tight,
                child: Text(name!),
              ),
              Text(" "),
              dropdown,
            ]),
    );
  }
}

class SettingsWidget extends StatelessWidget {
  final Device device;

  SettingsWidget(this.device);

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

    final wifiSettings = ValueListenableBuilder<DeviceWifiSettings>(
      valueListenable: device.wifiSettings,
      builder: (context, settings, child) {
        //print("changed: $settings");
        var widgets = <Widget>[
          ApiSettingSwitch(
            device: device,
            name: "Wifi",
            command: ApiCommand.wifi,
            value: settings.enabled,
            onChanged: () {
              device.wifiSettings.value.enabled = ExtendedBool.Waiting;
              device.wifiSettings.notifyListeners();
            },
          ),
        ];
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            ApiSettingSwitch(
              device: device,
              name: "Access Point",
              command: ApiCommand.wifiApEnabled,
              value: settings.apEnabled,
              onChanged: () {
                device.wifiSettings.value.apEnabled = ExtendedBool.Waiting;
                device.wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.apEnabled == ExtendedBool.True)
            widgets.add(
              Row(
                children: [
                  ApiSettingInput(
                    device: device,
                    name: "SSID",
                    command: ApiCommand.wifiApSSID,
                    value: settings.apSSID,
                    enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  ApiSettingInput(
                    device: device,
                    name: "Password",
                    command: ApiCommand.wifiApPassword,
                    value: "",
                    isPassword: true,
                    enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                ],
              ),
            );
        }
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            ApiSettingSwitch(
              device: device,
              name: "Station",
              command: ApiCommand.wifiStaEnabled,
              value: settings.staEnabled,
              onChanged: () {
                device.wifiSettings.value.staEnabled = ExtendedBool.Waiting;
                device.wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.staEnabled == ExtendedBool.True) {
            widgets.add(
              Row(
                children: [
                  ApiSettingInput(
                    device: device,
                    name: "SSID",
                    command: ApiCommand.wifiStaSSID,
                    value: settings.staSSID,
                    enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  ApiSettingInput(
                    device: device,
                    name: "Password",
                    command: ApiCommand.wifiStaPassword,
                    value: "",
                    isPassword: true,
                    enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                  ),
                ],
              ),
            );
          }
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: widgets,
        );
      },
    );

    final deviceSettings = ValueListenableBuilder<DeviceSettings>(
      valueListenable: device.deviceSettings,
      builder: (context, settings, child) {
        //print("changed: $settings");
        var widgets = <Widget>[
          ApiSettingInput(
            device: device,
            name: "Crank Length",
            command: ApiCommand.crankLength,
            value: settings.cranklength == null ? "" : settings.cranklength.toString(),
            suffix: Text("mm"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingSwitch(
            device: device,
            name: "Reverse Strain",
            command: ApiCommand.reverseStrain,
            value: settings.reverseStrain,
            onChanged: () {
              device.deviceSettings.value.reverseStrain = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          ApiSettingSwitch(
            device: device,
            name: "Double Power",
            command: ApiCommand.doublePower,
            value: settings.doublePower,
            onChanged: () {
              device.deviceSettings.value.doublePower = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          ApiSettingInput(
            device: device,
            name: "Sleep Delay",
            command: ApiCommand.sleepDelay,
            value: settings.sleepDelay == null ? "" : settings.sleepDelay.toString(),
            transformInput: (value) {
              var ms = int.tryParse(value);
              return (ms == null) ? "30000" : "${ms * 1000 * 60}";
            },
            suffix: Text("minutes"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingDropdown(
            name: "Negative Torque Method",
            device: device,
            command: ApiCommand.negativeTorqueMethod,
            value: settings.negativeTorqueMethod.toString(),
            onChanged: (value) {
              print("Negative Torque Method: $value");
            },
            items: settings.negativeTorqueMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text("Unknown"),
                    ),
                  ]
                : settings.validNegativeTorqueMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text(e.value),
                        ))
                    .toList(),
          ),
          ApiSettingDropdown(
            name: "Motion Detection Method",
            device: device,
            command: ApiCommand.motionDetectionMethod,
            value: settings.motionDetectionMethod.toString(),
            onChanged: (value) {
              print("Motion Detection Method: $value");
            },
            items: settings.motionDetectionMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text("Unknown"),
                    ),
                  ]
                : settings.validMotionDetectionMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text(e.value),
                        ))
                    .toList(),
          ),
        ];
        if (settings.motionDetectionMethod ==
            settings.validMotionDetectionMethods.keys.firstWhere((k) => settings.validMotionDetectionMethods[k] == "Strain gauge", orElse: () => -1)) {
          //print("MDM==SG strainThresLow: ${settings.strainThresLow}");
          widgets.add(
            Row(
              children: [
                ApiSettingInput(
                  device: device,
                  name: "Low Threshold",
                  command: ApiCommand.strainThresLow,
                  value: settings.strainThresLow == null ? null : settings.strainThresLow.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThresLow != null,
                  suffix: Text("kg"),
                ),
                Text(' '),
                ApiSettingInput(
                  device: device,
                  name: "High Threshold",
                  command: ApiCommand.strainThreshold,
                  value: settings.strainThreshold == null ? null : settings.strainThreshold.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThreshold != null,
                  suffix: Text("kg"),
                ),
              ],
            ),
          );
        }

        widgets.add(
          ApiSettingSwitch(
            device: device,
            name: "Auto Tare",
            command: ApiCommand.autoTare,
            value: settings.autoTare,
            onChanged: () {
              device.deviceSettings.value.autoTare = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
        );
        if (ExtendedBool.True == settings.autoTare) {
          widgets.add(
            Row(
              children: [
                ApiSettingInput(
                  device: device,
                  name: "Delay",
                  command: ApiCommand.autoTareDelayMs,
                  value: settings.autoTareDelayMs == null ? null : settings.autoTareDelayMs.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareDelayMs != null,
                  suffix: Text("ms"),
                ),
                Text(' '),
                ApiSettingInput(
                  device: device,
                  name: "Max. Range",
                  command: ApiCommand.autoTareRangeG,
                  value: settings.autoTareRangeG == null ? null : settings.autoTareRangeG.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareRangeG != null,
                  suffix: Text("g"),
                ),
              ],
            ),
          );
        }

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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            frame(wifiSettings),
            frame(deviceSettings),
            frame(ApiInterface(device)),
          ],
        )
      ],
    );
  }
}
