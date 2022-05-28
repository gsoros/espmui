import 'dart:async';
//import 'dart:html';

import 'package:flutter/material.dart';

import 'api.dart';
import 'device.dart';
import 'ble_characteristic.dart';
import 'util.dart';
import 'debug.dart';

class Battery extends StatelessWidget {
  final Device device;
  Battery(this.device);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: device.battery?.defaultStream,
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
            ],
          ),
        );
      },
    );
  }
}

class EspmWeightScaleStreamListener extends StatelessWidget {
  final ESPM device;
  final int mode;

  EspmWeightScaleStreamListener(this.device, this.mode);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: device.weightScaleChar?.defaultStream,
      initialData: device.weightScaleChar?.lastValue,
      builder: (BuildContext context, AsyncSnapshot<double> snapshot) {
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

      Widget autoTareWarning = device.settings.value.autoTare == ExtendedBool.True ? Text("Warning: AutoTare is enabled") : Empty();

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: Text("Calibrate device"),
            content: Container(
              child: Column(
                children: [
                  autoTareWarning,
                  EspmWeightScaleStreamListener(device, 1),
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

    void toggle(int mode) async {
      device.weightServiceMode.value = -1;
      bool enable = mode < 1;
      bool success = false;
      int? reply = await device.api.request<int>("weightService=" +
          (enable
              ? "2" // on when not pedalling
              : "0" // off
          ));
      if (1 == reply || 2 == reply) {
        if (enable) success = true;
        await device.weightScaleChar?.subscribe();
      } else if (0 == reply) {
        if (!enable) success = true;
        await device.characteristic("weightScale")?.unsubscribe();
      } else
        device.weightServiceMode.value = -1;
      snackbar(
        "Weight service " + (enable ? "en" : "dis") + "able" + (success ? "d" : " failed"),
        context,
      );
    }

    void tare() async {
      var resultCode = await device.api.requestResultCode("tare=0");
      snackbar(
        "Tare " + (resultCode == ApiResult.success ? "success" : "failed"),
        context,
      );
    }

    return ValueListenableBuilder<int>(
      valueListenable: device.weightServiceMode,
      builder: (_, mode, __) {
        var strainOutput = EspmWeightScaleStreamListener(device, mode);

        return InkWell(
          onTap: () {
            if (0 < mode) tare();
          },
          onLongPress: () {
            if (0 < mode) calibrate();
          },
          onDoubleTap: () {
            toggle(mode);
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
                    child: mode == -1 ? CircularProgressIndicator() : strainOutput,
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
                      ApiSettingInput(
                        name: "Offset",
                        value: hallOffset.toString(),
                        keyboardType: TextInputType.number,
                        api: device.api,
                        command: device.api.commandCode("hallOffset"),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ApiSettingInput(
                        name: "High Threshold",
                        value: hallThreshold.toString(),
                        keyboardType: TextInputType.number,
                        api: device.api,
                        command: device.api.commandCode("hallThreshold"),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ApiSettingInput(
                        name: "Low Threshold",
                        value: hallThresLow.toString(),
                        keyboardType: TextInputType.number,
                        api: device.api,
                        command: device.api.commandCode("hallThresLow"),
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
                Text(" "),
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
      stream: char.defaultStream,
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

class ApiStream extends StatelessWidget {
  final Api api;
  ApiStream(this.api);

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

class ApiCli extends StatelessWidget with Debug {
  final Api api;
  ApiCli(this.api);

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
        debugLog("[ApiCli] api.request($command): $value");
      },
    );
  }
}

class ApiInterface extends StatelessWidget {
  final Api api;

  ApiInterface(this.api);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: Align(
            alignment: Alignment.topLeft,
            child: ApiStream(api),
          ),
        ),
        ApiCli(api),
      ],
    );
  }
}

class ApiSettingInput extends StatelessWidget with Debug {
  final Api api;
  final int? command;
  final String? value;
  final bool enabled;
  final String? name;
  final bool isPassword;
  final String Function(String)? transformInput;
  final Widget? suffix;
  final TextInputType? keyboardType;

  ApiSettingInput({
    required this.api,
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
          if (null == command) {
            debugLog("command is null");
            return;
          }
          if (transformInput != null) edited = transformInput!(edited);
          final result = await api.requestResultCode(
            "$command=$edited",
            minDelayMs: 2000,
          );
          if (name != null) snackbar("$name update${result == ApiResult.success ? "d" : " failed"}", context);
          debugLog("api.requestResultCode($command): $result");
        },
      ),
    );
  }
}

class SettingSwitch extends StatelessWidget with Debug {
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
              debugLog("[SettingSwitch] $name changed to $enabled");
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

class ApiSettingSwitch extends StatelessWidget with Debug {
  final Api api;
  final int? command;
  final ExtendedBool value;
  final String? name;
  final void Function()? onChanged;

  ApiSettingSwitch({
    required this.api,
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
              if (null == command) return;
              if (onChanged != null) onChanged!();
              final result = await api.requestResultCode(
                "$command=${enabled ? "1" : "0"}",
                minDelayMs: 2000,
              );
              if (name != null) snackbar("$name ${enabled ? "en" : "dis"}able${result == ApiResult.success ? "d" : " failed"}", context);
              debugLog("api.requestResultCode($command): $result");
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

class EspmuiDropdown extends StatelessWidget with Debug {
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
    // debugLog("EspmuiDropdown build() value: $value items: $items");
    // items?.forEach((item) {
    //   debugLog("EspmuiDropdown build() item: ${item.child.toStringDeep()}");
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
      child: (name == null)
          ? dropdown
          : Row(children: [
              Expanded(
                flex: 5,
                child: Text(name!),
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

class ApiSettingDropdown extends EspmuiDropdown {
  final Api api;
  final int? command;

  ApiSettingDropdown({
    required this.api,
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
            if (null == command) return;
            if (onChanged != null) onChanged(value);
            final result = await api.requestResultCode(
              "$command=${value ?? value.toString()}",
              minDelayMs: 2000,
            );
            if (name != null) snackbar("$name ${value ?? value.toString()} ${result == ApiResult.success ? "success" : " failure"}");
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

    final apiWifiSettings = ApiWifiSettings(this.device.api, this.device.wifiSettings);

    final deviceSettings = ValueListenableBuilder<ESPMSettings>(
      valueListenable: device.settings,
      builder: (_, settings, __) {
        //debugLog("changed: $settings");
        var widgets = <Widget>[
          ApiSettingInput(
            api: device.api,
            name: "Crank Length",
            command: device.api.commandCode("crankLength"),
            value: settings.cranklength == null ? "" : settings.cranklength.toString(),
            suffix: Text("mm"),
            keyboardType: TextInputType.number,
          ),
          ApiSettingSwitch(
            api: device.api,
            name: "Reverse Strain",
            command: device.api.commandCode("reverseStrain"),
            value: settings.reverseStrain,
            onChanged: () {
              device.settings.value.reverseStrain = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
          ApiSettingSwitch(
            api: device.api,
            name: "Double Power",
            command: device.api.commandCode("doublePower"),
            value: settings.doublePower,
            onChanged: () {
              device.settings.value.doublePower = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
          ApiSettingInput(
            api: device.api,
            name: "Sleep Delay",
            command: device.api.commandCode("sleepDelay"),
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
            api: device.api,
            command: device.api.commandCode("negativeTorqueMethod"),
            value: settings.negativeTorqueMethod.toString(),
            onChanged: (value) {
              debugLog("Negative Torque Method: $value");
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
          ApiSettingDropdown(
            name: "Motion Detection Method",
            api: device.api,
            command: device.api.commandCode("motionDetectionMethod"),
            value: settings.motionDetectionMethod.toString(),
            onChanged: (value) {
              debugLog("Motion Detection Method: $value");
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
          //debugLog("MDM==SG strainThresLow: ${settings.strainThresLow}");
          widgets.add(
            Row(
              children: [
                ApiSettingInput(
                  api: device.api,
                  name: "Low Threshold",
                  command: device.api.commandCode("strainThresLow"),
                  value: settings.strainThresLow == null ? null : settings.strainThresLow.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.strainThresLow != null,
                  suffix: Text("kg"),
                ),
                Empty(),
                ApiSettingInput(
                  api: device.api,
                  name: "High Threshold",
                  command: device.api.commandCode("strainThreshold"),
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
            api: device.api,
            name: "Auto Tare",
            command: device.api.commandCode("autoTare"),
            value: settings.autoTare,
            onChanged: () {
              device.settings.value.autoTare = ExtendedBool.Waiting;
              device.settings.notifyListeners();
            },
          ),
        );
        if (ExtendedBool.True == settings.autoTare) {
          widgets.add(
            Row(
              children: [
                ApiSettingInput(
                  api: device.api,
                  name: "Delay",
                  command: device.api.commandCode("autoTareDelayMs"),
                  value: settings.autoTareDelayMs == null ? null : settings.autoTareDelayMs.toString(),
                  keyboardType: TextInputType.number,
                  enabled: settings.autoTareDelayMs != null,
                  suffix: Text("ms"),
                ),
                Empty(),
                ApiSettingInput(
                  api: device.api,
                  name: "Max. Range",
                  command: device.api.commandCode("autoTareRangeG"),
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
            frame(apiWifiSettings),
            frame(deviceSettings),
            frame(ApiInterface(device.api)),
          ],
        )
      ],
    );
  }
}

class EspccPeersEditor extends StatelessWidget with Debug {
  final ESPCC device;
  EspccPeersEditor(this.device);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ESPCCSettings>(
        valueListenable: device.settings,
        builder: (_, settings, __) {
          return Column(
            children: [
              EspmuiElevatedButton(
                child: Text(settings.scanning ? "Scanning..." : "Scan"),
                onPressed: settings.scanning
                    ? null
                    : () {
                        //device.settings.value.scanning = true;
                        device.settings.value.scanResults = [];
                        device.settings.notifyListeners();
                        device.api.sendCommand("scan=10");
                      },
              ),
              PeersList(peers: settings.peers, action: "delete", api: device.api),
              PeersList(
                peers: settings.scanResults.where((element) => settings.peers.contains(element) ? false : true).toList(),
                action: "add",
                api: device.api,
              ),
            ],
          );
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

class EspccTouchEditor extends StatelessWidget with Debug {
  final ESPCC device;
  EspccTouchEditor(this.device);

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
            items.add(Stack(
              children: [
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
                      device.api.sendCommand("touchThres=$k:${newValue.toInt()}");
                    },
                  ),
                ),
              ],
            ));
          });
          return Column(children: items);
        });
  }
}

class PeersList extends StatelessWidget with Debug {
  final List<String> peers;
  final String action;
  final Api? api;

  PeersList({required this.peers, this.action = "none", this.api});

  @override
  Widget build(BuildContext context) {
    var list = Column(children: []);
    peers.forEach((peer) {
      // addr,addrType,deviceType,deviceName
      var parts = peer.split(",");
      if (parts.length != 4) return;
      var icon = Icons.question_mark;
      if (parts[2] == "P") icon = Icons.bolt;
      if (parts[2] == "E") icon = Icons.offline_bolt;
      if (parts[2] == "H") icon = Icons.favorite;
      String? command;
      IconData? commandIcon;
      if (null != api) {
        if ("add" == action) {
          command = "addPeer=$peer";
          commandIcon = Icons.link;
        } else if ("delete" == action) {
          command = "deletePeer=${parts[0]}";
          commandIcon = Icons.link_off;
        }
      }
      var button = null == command
          ? Empty()
          : EspmuiElevatedButton(
              child: Icon(commandIcon),
              onPressed: () {
                api!.sendCommand(command!);
                api!.sendCommand("peers");
              },
            );
      list.children.add(Row(children: [
        Flexible(child: Row(children: [Icon(icon), Text(" "), Text(parts[3])])),
        button,
      ]));
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

    final apiWifiSettings = ApiWifiSettings(device.api, device.wifiSettings);

    Future<void> dialog({required Widget title, required Widget body}) async {
      return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            scrollable: true,
            title: title,
            content: Container(
              child: Column(
                children: [
                  body,
                ],
              ),
            ),
          );
        },
      );
    }

    final deviceSettings = ValueListenableBuilder<ESPCCSettings>(
      valueListenable: device.settings,
      builder: (_, settings, __) {
        var widgets = <Widget>[
          Row(children: [
            Flexible(
              child: Column(
                children: [
                  Row(children: [Text("Peers:")]),
                  PeersList(peers: settings.peers),
                ],
              ),
            ),
            EspmuiElevatedButton(
              onPressed: () {
                dialog(
                  title: Text("Peers"),
                  body: EspccPeersEditor(device),
                );
              },
              child: Icon(Icons.edit),
            ),
          ]),
          Text(" "),
          Row(children: [
            Flexible(
              child: Column(
                children: [
                  Row(children: [Text("Touch Thresholds:")]),
                  Text(settings.touchThres.values.join(", ")),
                ],
              ),
            ),
            EspmuiElevatedButton(
              onPressed: () async {
                final timer = Timer.periodic(const Duration(seconds: 2), (_) {
                  device.api.sendCommand("touchRead=disableFor:3");
                });
                await dialog(
                  title: Text("Touch Thresholds"),
                  body: EspccTouchEditor(device),
                );
                timer.cancel();
              },
              child: Icon(Icons.edit),
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
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            frame(apiWifiSettings),
            frame(deviceSettings),
            frame(ApiInterface(device.api)),
          ],
        )
      ],
    );
  }
}

class ApiWifiSettings extends StatelessWidget {
  final Api api;
  final AlwaysNotifier<WifiSettings> wifiSettings;

  ApiWifiSettings(this.api, this.wifiSettings);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WifiSettings>(
      valueListenable: wifiSettings,
      builder: (context, settings, child) {
        //debugLog("changed: $settings");
        var widgets = <Widget>[
          ApiSettingSwitch(
            api: api,
            name: "Wifi",
            command: api.commandCode("wifi"),
            value: settings.enabled,
            onChanged: () {
              wifiSettings.value.enabled = ExtendedBool.Waiting;
              wifiSettings.notifyListeners();
            },
          ),
        ];
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            ApiSettingSwitch(
              api: api,
              name: "Access Point",
              command: api.commandCode("wifiApEnabled"),
              value: settings.apEnabled,
              onChanged: () {
                wifiSettings.value.apEnabled = ExtendedBool.Waiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.apEnabled == ExtendedBool.True)
            widgets.add(
              Row(
                children: [
                  ApiSettingInput(
                    api: api,
                    name: "SSID",
                    command: api.commandCode("wifiApSSID"),
                    value: settings.apSSID,
                    enabled: settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                  Empty(),
                  ApiSettingInput(
                    api: api,
                    name: "Password",
                    command: api.commandCode("wifiApPassword"),
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
              api: api,
              name: "Station",
              command: api.commandCode("wifiStaEnabled"),
              value: settings.staEnabled,
              onChanged: () {
                wifiSettings.value.staEnabled = ExtendedBool.Waiting;
                wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.staEnabled == ExtendedBool.True) {
            widgets.add(
              Row(
                children: [
                  ApiSettingInput(
                    api: api,
                    name: "SSID",
                    command: api.commandCode("wifiStaSSID"),
                    value: settings.staSSID,
                    enabled: settings.staEnabled == ExtendedBool.True ? true : false,
                  ),
                  Empty(),
                  ApiSettingInput(
                    api: api,
                    name: "Password",
                    command: api.commandCode("wifiStaPassword"),
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
  }
}
