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

class WeightScale extends StatelessWidget {
  final Device device;
  WeightScale(this.device);

  @override
  Widget build(BuildContext context) {
    void calibrate() async {
      Future<void> apiCalibrate(String knownMassStr) async {
        var api = device.api;
        snackbar("Sending calibration value: $knownMassStr", context);
        String? value =
            await api.request<String>("calibrateStrain=$knownMassStr");
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
        if (parsedValue < parsedKnownMass * .999 ||
            parsedValue > parsedKnownMass * 1.001) {
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

    void toggleWeightScale(enabled) async {
      device.weightServiceEnabled.value = ExtendedBool.Waiting;
      bool enable = enabled == ExtendedBool.True ? false : true;
      bool? reply = await device.api
          .request<bool>("weightService=" + (enable ? "true" : "false"));
      bool success = reply == enable;
      if (success) {
        if (enable)
          await device.weightScale?.subscribe();
        else
          await device.characteristic("weightScale")?.unsubscribe();
      } else
        device.weightServiceEnabled.value = ExtendedBool.Unknown;
      snackbar(
        "Weight service " +
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
            if (enabled == ExtendedBool.True ||
                enabled == ExtendedBool.False ||
                enabled == ExtendedBool.Unknown) toggleWeightScale(enabled);
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
                    child: enabled == ExtendedBool.Waiting
                        ? CircularProgressIndicator()
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

class SettingsWidget extends StatelessWidget {
  final Device device;

  SettingsWidget(this.device);

  @override
  Widget build(BuildContext context) {
    Widget input({
      required ApiCommand command,
      String? value,
      bool enabled = true,
      String? name,
      bool isPassword = false,
      String Function(String)? processor,
      Widget? suffix,
      TextInputType? keyboardType,
    }) {
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
            if (processor != null) edited = processor(edited);
            final result = await device.api.requestResultCode(
              "${command.index}=$edited",
              minDelayMs: 2000,
            );
            if (name != null)
              snackbar(
                  "$name update${result == ApiResult.success.index ? "d" : " failed"}",
                  context);
            print("[Wifi Wijit] api.request($command): $result");
          },
        ),
      );
    }

    Widget onOffSwitch({
      required ApiCommand command,
      required ExtendedBool value,
      String? name,
      void Function()? onChanged,
    }) {
      var onOff = value == ExtendedBool.Waiting
          ? CircularProgressIndicator()
          : Switch(
              value: value == ExtendedBool.True ? true : false,
              activeColor: Colors.red,
              onChanged: (bool enabled) async {
                if (onChanged != null) onChanged();
                final result = await device.api.requestResultCode(
                  "${command.index}=${enabled ? "1" : "0"}",
                  minDelayMs: 2000,
                );
                if (name != null)
                  snackbar(
                      "$name ${enabled ? "en" : "dis"}able${result == ApiResult.success.index ? "d" : " failed"}",
                      context);
                print("[Wifi Wijit] api.requestResultCode($command): $result");
              });
      return (name == null)
          ? onOff
          : Row(children: [
              Flexible(
                fit: FlexFit.tight,
                child: Text(name),
              ),
              onOff,
            ]);
    }

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
        var widgets = [
          onOffSwitch(
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
            onOffSwitch(
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
                  input(
                    name: "SSID",
                    command: ApiCommand.wifiApSSID,
                    value: settings.apSSID,
                    enabled:
                        settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  input(
                    name: "Password",
                    command: ApiCommand.wifiApPassword,
                    value: "",
                    isPassword: true,
                    enabled:
                        settings.apEnabled == ExtendedBool.True ? true : false,
                  ),
                ],
              ),
            );
        }
        if (settings.enabled == ExtendedBool.True) {
          widgets.add(
            onOffSwitch(
              name: "Station",
              command: ApiCommand.wifiStaEnabled,
              value: settings.staEnabled,
              onChanged: () {
                device.wifiSettings.value.staEnabled = ExtendedBool.Waiting;
                device.wifiSettings.notifyListeners();
              },
            ),
          );
          if (settings.staEnabled == ExtendedBool.True)
            widgets.add(
              Row(
                children: [
                  input(
                    name: "SSID",
                    command: ApiCommand.wifiStaSSID,
                    value: settings.staSSID,
                    enabled:
                        settings.staEnabled == ExtendedBool.True ? true : false,
                  ),
                  Text(' '),
                  input(
                    name: "Password",
                    command: ApiCommand.wifiStaPassword,
                    value: "",
                    isPassword: true,
                    enabled:
                        settings.staEnabled == ExtendedBool.True ? true : false,
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

    final deviceSettings = ValueListenableBuilder<DeviceSettings>(
      valueListenable: device.deviceSettings,
      builder: (context, settings, child) {
        //print("changed: $settings");
        var widgets = [
          input(
            name: "Crank Length",
            command: ApiCommand.crankLength,
            value: settings.cranklength == null
                ? ""
                : settings.cranklength.toString(),
            suffix: Text("mm"),
            keyboardType: TextInputType.number,
          ),
          onOffSwitch(
            name: "Reverse Strain",
            command: ApiCommand.reverseStrain,
            value: settings.reverseStrain,
            onChanged: () {
              device.deviceSettings.value.reverseStrain = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          onOffSwitch(
            name: "Double Power",
            command: ApiCommand.doublePower,
            value: settings.doublePower,
            onChanged: () {
              device.deviceSettings.value.doublePower = ExtendedBool.Waiting;
              device.deviceSettings.notifyListeners();
            },
          ),
          input(
            name: "Sleep Delay",
            command: ApiCommand.sleepDelay,
            value: settings.sleepDelay == null
                ? ""
                : settings.sleepDelay.toString(),
            processor: (value) {
              var ms = int.tryParse(value);
              return (ms == null) ? "30000" : "${ms * 1000 * 60}";
            },
            suffix: Text("minutes"),
            keyboardType: TextInputType.number,
          ),
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
            frame(wifiSettings),
            frame(deviceSettings),
            frame(ApiInterface(device)),
          ],
        )
      ],
    );
  }
}
