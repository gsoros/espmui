import 'dart:async';

import 'package:flutter/material.dart';

import 'espm_api.dart';
import 'device.dart';
import 'ble_characteristic.dart';
import 'util.dart';

class Battery extends StatelessWidget {
  final Device device;
  Battery(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.battery?.stream,
      initialData: device.battery?.lastValue,
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
                    snapshot.hasData && snapshot.data! > 0 ? "${snapshot.data}" : "--",
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

class EspmWeightScaleStreamListener extends StatelessWidget {
  final ESPM device;
  final ExtendedBool enabled;

  EspmWeightScaleStreamListener(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: device.weightScale?.stream,
      initialData: device.weightScale?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
        String weight = snapshot.hasData && enabled != ExtendedBool.False ? snapshot.data!.toStringAsFixed(2) : "--";
        if (weight.length > 6) weight = weight.substring(0, 6);
        if (weight == "-0.00") weight = "0.00";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(weight, style: (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class EspmWeightScale extends StatelessWidget {
  final ESPM device;
  EspmWeightScale(this.device);

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
                  EspmWeightScaleStreamListener(device, ExtendedBool.True),
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
      var resultCode = await device.api.requestResultCode("tare=0");
      snackbar(
        "Tare " + (resultCode == EspmApiResult.success.index ? "success" : "failed"),
        context,
      );
    }

    return ValueListenableBuilder<ExtendedBool>(
      valueListenable: device.weightServiceEnabled,
      builder: (_, enabled, __) {
        var strainOutput = EspmWeightScaleStreamListener(device, enabled);

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

class EspmHallStreamListener extends StatelessWidget {
  final ESPM device;
  final ExtendedBool enabled;

  EspmHallStreamListener(this.device, this.enabled);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.hall?.stream,
      initialData: device.hall?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        String value = snapshot.hasData && enabled != ExtendedBool.False ? (snapshot.data! > 0 ? snapshot.data!.toString() : '--') : "--";
        const styleEnabled = TextStyle(fontSize: 30);
        const styleDisabled = TextStyle(fontSize: 30, color: Colors.white12);
        return Text(value, style: (enabled == ExtendedBool.True) ? styleEnabled : styleDisabled);
      },
    );
  }
}

class EspmHallSensor extends StatelessWidget {
  final ESPM device;
  EspmHallSensor(this.device);

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
                  EspmHallStreamListener(device, ExtendedBool.True),
                  Row(
                    children: [
                      EspmApiSettingInput(
                        name: "Offset",
                        value: hallOffset.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: EspmApiCommand.hallOffset,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      EspmApiSettingInput(
                        name: "High Threshold",
                        value: hallThreshold.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: EspmApiCommand.hallThreshold,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      EspmApiSettingInput(
                        name: "Low Threshold",
                        value: hallThresLow.toString(),
                        keyboardType: TextInputType.number,
                        device: device,
                        command: EspmApiCommand.hallThresLow,
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
      builder: (_, enabled, __) {
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
                    child: (enabled == ExtendedBool.Waiting) ? CircularProgressIndicator() : EspmHallStreamListener(device, enabled),
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
  final PowerMeter device;
  final String mode;

  /// [mode] = "power" | "cadence"
  PowerCadence(this.device, {this.mode = "power"});

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
        return Text(
          snapshot.hasData ? (snapshot.data! > 0 ? snapshot.data.toString() : "--") : "--",
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

class HeartRate extends StatelessWidget {
  final HeartRateMonitor device;

  HeartRate(this.device);

  @override
  Widget build(BuildContext context) {
    BleCharacteristic? tmpChar = device.heartRate;
    if (!(tmpChar is HeartRateCharacteristic)) return Text('Error: not HR char');
    HeartRateCharacteristic char = tmpChar;

    var value = StreamBuilder<int>(
      stream: char.stream,
      initialData: char.lastValue,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Text(
          snapshot.hasData ? (snapshot.data! > 0 ? snapshot.data.toString() : "--") : "--",
          style: const TextStyle(fontSize: 60),
        );
      },
    );
    return Container(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      ),
    );
  }
}

class EspmApiStream extends StatelessWidget {
  final ESPM device;
  EspmApiStream(this.device);

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

class EspmApiCli extends StatelessWidget {
  final ESPM device;
  EspmApiCli(this.device);

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

class EspmApiInterface extends StatelessWidget {
  final ESPM device;

  EspmApiInterface(this.device);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Align(
            alignment: Alignment.topLeft,
            child: EspmApiStream(device),
          ),
        ),
        EspmApiCli(device),
      ],
    );
  }
}

class EspmApiSettingInput extends StatelessWidget {
  final ESPM device;
  final EspmApiCommand command;
  final String? value;
  final bool enabled;
  final String? name;
  final bool isPassword;
  final String Function(String)? transformInput;
  final Widget? suffix;
  final TextInputType? keyboardType;

  EspmApiSettingInput({
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
          if (name != null) snackbar("$name update${result == EspmApiResult.success.index ? "d" : " failed"}", context);
          print("[ApiSettingInput] api.request($command): $result");
        },
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget {
  final ExtendedBool value;
  final String? name;
  final void Function(bool)? onChanged;

  SettingSwitch({
    required this.value,
    this.name,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    var toggler = value == ExtendedBool.Waiting
        ? CircularProgressIndicator()
        : Switch(
            value: value == ExtendedBool.True ? true : false,
            activeColor: Colors.red,
            onChanged: (bool enabled) async {
              if (onChanged != null) onChanged!(enabled);
              print("[SettingSwitch] $name changed to $enabled");
            });
    return (name == null)
        ? toggler
        : Row(children: [
            Flexible(
              fit: FlexFit.tight,
              child: Text(name!),
            ),
            toggler,
          ]);
  }
}

class EspmApiSettingSwitch extends StatelessWidget {
  final ESPM device;
  final EspmApiCommand command;
  final ExtendedBool value;
  final String? name;
  final void Function()? onChanged;

  EspmApiSettingSwitch({
    required this.device,
    required this.command,
    required this.value,
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
              if (onChanged != null) onChanged!();
              final result = await device.api.requestResultCode(
                "${command.index}=${enabled ? "1" : "0"}",
                minDelayMs: 2000,
              );
              if (name != null) snackbar("$name ${enabled ? "en" : "dis"}able${result == EspmApiResult.success.index ? "d" : " failed"}", context);
              print("[EspmApiSettingSwitch] api.requestResultCode($command): $result");
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

class EspmuiDropdown extends StatelessWidget {
  final String? value;
  final List<DropdownMenuItem<String>>? items;
  final String? name;
  final void Function(String?)? onChanged;

  /// Creates a dropdown button.
  /// The [items] must have distinct values. If [value] isn't null then it must be
  /// equal to one of the [DropdownMenuItem] values. If [items] or [onChanged] is
  /// null, the button will be disabled, the down arrow will be greyed out.
  EspmuiDropdown({
    required this.value,
    required this.items,
    this.name,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    //print("EspmuiDropdown build() value: $value items: $items");
    Widget dropdown = Text("");
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

class EspmApiSettingDropdown extends EspmuiDropdown {
  final ESPM device;
  final EspmApiCommand command;

  EspmApiSettingDropdown({
    required this.device,
    required this.command,
    required String? value,
    required List<DropdownMenuItem<String>>? items,
    String? name,
    void Function(String?)? onChanged,
  }) : super(
          value: value,
          items: items,
          name: name,
          onChanged: (String? value) async {
            if (onChanged != null) onChanged(value);
            final result = await device.api.requestResultCode(
              "${command.index}=${value ?? value.toString()}",
              minDelayMs: 2000,
            );
            if (name != null) snackbar("$name ${value ?? value.toString()} ${result == EspmApiResult.success.index ? "success" : " failure"}");
            print("[ApiSettingDropdown] api.requestResultCode($command): $result");
          },
        );
}

class EspmSettingsWidget extends StatelessWidget {
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

    final wifiSettings = ValueListenableBuilder<ESPMWifiSettings>(
      valueListenable: device.wifiSettings,
      builder: (context, settings, child) {
        //print("changed: $settings");
        var widgets = <Widget>[
          EspmApiSettingSwitch(
            device: device,
            name: "Wifi",
            command: EspmApiCommand.wifi,
            value: settings.enabled,
            onChanged: () {
              device.wifiSettings.value.enabled = ExtendedBool.Waiting;
              device.wifiSettings.notifyListeners();
            },
          ),
        ];
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            EspmApiSettingSwitch(
              device: device,
              name: "Access Point",
              command: EspmApiCommand.wifiApEnabled,
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
                  EspmApiSettingInput(
                    device: device,
                    name: "SSID",
                    command: EspmApiCommand.wifiApSSID,
                    value: settings.apSSID,
                    enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  EspmApiSettingInput(
                    device: device,
                    name: "Password",
                    command: EspmApiCommand.wifiApPassword,
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
            EspmApiSettingSwitch(
              device: device,
              name: "Station",
              command: EspmApiCommand.wifiStaEnabled,
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
                  EspmApiSettingInput(
                    device: device,
                    name: "SSID",
                    command: EspmApiCommand.wifiStaSSID,
                    value: settings.staSSID,
                    enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  EspmApiSettingInput(
                    device: device,
                    name: "Password",
                    command: EspmApiCommand.wifiStaPassword,
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

    final deviceSettings = ValueListenableBuilder<ESPMSettings>(
      valueListenable: device.deviceSettings,
      builder: (_, settings, __) {
        //print("changed: $settings");
        var widgets = <Widget>[
          EspmApiSettingInput(
            device: device,
            name: "Crank Length",
            command: EspmApiCommand.crankLength,
            value: settings.cranklength == null ? "" : settings.cranklength.toString(),
            suffix: Text("mm"),
            keyboardType: TextInputType.number,
          ),
          EspmApiSettingSwitch(
            device: device,
            name: "Reverse Strain",
            command: EspmApiCommand.reverseStrain,
            value: settings.reverseStrain,
            onChanged: () {
              device.deviceSettings.value.reverseStrain = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          EspmApiSettingSwitch(
            device: device,
            name: "Double Power",
            command: EspmApiCommand.doublePower,
            value: settings.doublePower,
            onChanged: () {
              device.deviceSettings.value.doublePower = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          EspmApiSettingInput(
            device: device,
            name: "Sleep Delay",
            command: EspmApiCommand.sleepDelay,
            value: settings.sleepDelay == null ? "" : settings.sleepDelay.toString(),
            transformInput: (value) {
              var ms = int.tryParse(value);
              return (ms == null) ? "30000" : "${ms * 1000 * 60}";
            },
            suffix: Text("minutes"),
            keyboardType: TextInputType.number,
          ),
          EspmApiSettingDropdown(
            name: "Negative Torque Method",
            device: device,
            command: EspmApiCommand.negativeTorqueMethod,
            value: settings.negativeTorqueMethod.toString(),
            onChanged: (value) {
              print("Negative Torque Method: $value");
            },
            items: settings.negativeTorqueMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text(""),
                    ),
                  ]
                : settings.validNegativeTorqueMethods.entries
                    .map((e) => DropdownMenuItem<String>(
                          value: e.key.toString(),
                          child: Text(e.value),
                        ))
                    .toList(),
          ),
          EspmApiSettingDropdown(
            name: "Motion Detection Method",
            device: device,
            command: EspmApiCommand.motionDetectionMethod,
            value: settings.motionDetectionMethod.toString(),
            onChanged: (value) {
              print("Motion Detection Method: $value");
            },
            items: settings.motionDetectionMethod == null
                ? [
                    DropdownMenuItem<String>(
                      child: Text(""),
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
                EspmApiSettingInput(
                  device: device,
                  name: "Low Threshold",
                  command: EspmApiCommand.strainThresLow,
                  value: settings.strainThresLow == null ? null : settings.strainThresLow.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThresLow != null,
                  suffix: Text("kg"),
                ),
                Text(' '),
                EspmApiSettingInput(
                  device: device,
                  name: "High Threshold",
                  command: EspmApiCommand.strainThreshold,
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
          EspmApiSettingSwitch(
            device: device,
            name: "Auto Tare",
            command: EspmApiCommand.autoTare,
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
                EspmApiSettingInput(
                  device: device,
                  name: "Delay",
                  command: EspmApiCommand.autoTareDelayMs,
                  value: settings.autoTareDelayMs == null ? null : settings.autoTareDelayMs.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareDelayMs != null,
                  suffix: Text("ms"),
                ),
                Text(' '),
                EspmApiSettingInput(
                  device: device,
                  name: "Max. Range",
                  command: EspmApiCommand.autoTareRangeG,
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
            frame(EspmApiInterface(device)),
          ],
        )
      ],
    );
  }
}
