import 'dart:async';
//import 'dart:developer' as dev;

import 'package:flutter/material.dart';
//import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'util.dart';
import 'debug.dart';
import 'ble.dart';
import 'device.dart';
import 'device_list.dart';
import 'device_widgets.dart';
import 'espm.dart';
import 'espcc.dart';
import 'homeauto.dart';
import 'tile.dart';

class DeviceRoute extends StatefulWidget with Debug {
  final Device device;
  final String? focus;
  final List<String> open; // list of initially open nodes

  DeviceRoute(this.device, {super.key, this.focus, this.open = const []}) {
    logD("construct focus: $focus, opened: $open");
  }

  @override
  // ignore: no_logic_in_create_state
  DeviceRouteState createState() {
    logD("createState()");
    if (device is ESPM) return ESPMRouteState(device as ESPM);
    if (device is ESPCC) return ESPCCRouteState(device as ESPCC);
    if (device is HomeAuto) return HomeAutoRouteState(device as HomeAuto, focus: focus, open: open);
    if (device is PowerMeter) return PowerMeterRouteState(device as PowerMeter);
    if (device is HeartRateMonitor) return HeartRateMonitorRouteState(device as HeartRateMonitor);
    return DeviceRouteState(device);
  }
}

class DeviceRouteState extends State<DeviceRoute> with Debug {
  Device device;
  String? focus;
  List<String> open;

  DeviceRouteState(this.device, {this.focus, this.open = const []}) {
    logD("construct device: ${device.name}, focus: $focus, open: $open");
  }

  @override
  void initState() {
    logD("initState");
    _checkCorrectType();
    super.initState();
  }

  Future<void> _checkCorrectType() async {
    //logD("_checkCorrectType() $device");
    if (await device.isCorrectType()) return;
    var newDevice = await device.copyToCorrectType();
    device.dispose();
    device = newDevice;
    DeviceList().addOrUpdate(device);
    if (!context.mounted) {
      logD('_checkCorrectType() context not mounted for $device');
      return;
    }
    logD("_checkCorrectType() reloading DeviceRoute($device)");
    // ignore: use_build_context_synchronously
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DeviceRoute(device)));
  }

  @override
  void dispose() async {
    logD("dispose");
    // if (!device.autoConnect.value) device.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        appBar: AppBar(
          title: BleAdapterCheck(
            DeviceAppBarTitle(device),
            ifNotReady: (state) => BleNotReady(state),
          ),
        ),
        body: Container(
          margin: const EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
      ),
    );
  }

  List<StaggeredGridItem> _deviceStreamTiles() {
    List<StaggeredGridItem> items = [];
    device.tileStreams.forEach((name, stream) {
      //logD("_deviceStreamTiles: name: $name, label: ${stream.label}");
      if (ESPM == device.runtimeType && "scale" == name) return; // TODO
      Tile tile = Tile(
        device: device.id,
        stream: name,
        color: Colors.black,
        showDeviceName: false,
      );
      StaggeredGridItem item = StaggeredGridItem(
        colSpan: 2,
        value: tile,
      );
      items.add(item);
    });
    return items;
  }

  List<StaggeredGridItem> _devicePropertyItems() {
    List<StaggeredGridItem> items = [];
    items.addAll([
      StaggeredGridItem(
        value: ValueListenableBuilder<bool>(
          valueListenable: device.remember,
          builder: (_, value, __) {
            //logD("remember changed: $value");
            return SettingSwitchWidget(
              label: FavoriteIcon(active: value),
              value: ExtendedBool.fromBool(value),
              onChanged: (value) {
                device.setRemember(value);
              },
            );
          },
        ),
        colSpan: 2,
      ),
      StaggeredGridItem(
        value: ValueListenableBuilder<bool>(
          valueListenable: device.autoConnect,
          builder: (_, value, __) {
            //logD("autoconnect changed: $value");
            return SettingSwitchWidget(
              label: AutoConnectIcon(active: value),
              value: ExtendedBool.fromBool(value),
              onChanged: (value) {
                device.setAutoConnect(value);
              },
            );
          },
        ),
        colSpan: 2,
      ),
      StaggeredGridItem(
        value: ValueListenableBuilder<bool>(
            valueListenable: device.saveLog,
            builder: (_, value, __) {
              //logD("saveLog changed: $value");
              return SettingSwitchWidget(
                label: const Text("Log"),
                value: ExtendedBool.fromBool(device.saveLog.value),
                onChanged: device.setSaveLog,
                enabled: null != device.characteristic("apiLog"),
              );
            }),
        colSpan: 2,
      ),
      // StaggeredGridItem(
      //   value: BatteryWidget(device),
      //   colSpan: 2,
      // ),
    ]);
    items.addAll(_deviceStreamTiles());
    return items;
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
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
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
              padding: const EdgeInsets.all(2),
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
      ...super._devicePropertyItems()
      // StaggeredGridItem(
      //   value: PowerCadenceWidget(powerMeter, mode: "power"),
      //   colSpan: 3,
      // ),
      // StaggeredGridItem(
      //   value: PowerCadenceWidget(powerMeter, mode: "cadence"),
      //   colSpan: 3,
      // ),
    ];
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
          value: EspmWeightScaleWidget(espm),
          colSpan: 2,
        ),
        StaggeredGridItem(
          value: EspmHallSensorWidget(espm),
          colSpan: 2,
        ),
        StaggeredGridItem(
          value: EspmSettingsWidget(espm),
          colSpan: 6,
        ),
      ]);
  }
}

class ESPCCRouteState extends DeviceRouteState {
  ESPCC espcc;

  ESPCCRouteState(this.espcc) : super(espcc);

  @override
  _devicePropertyItems() {
    return super._devicePropertyItems()
      ..addAll([
        StaggeredGridItem(
          value: EspccSettingsWidget(espcc),
          colSpan: 6,
        ),
      ]);
  }
}

class HomeAutoRouteState extends DeviceRouteState {
  HomeAuto homeAuto;

  HomeAutoRouteState(this.homeAuto, {super.focus, super.open}) : super(homeAuto);

  @override
  _devicePropertyItems() {
    return super._devicePropertyItems()
      ..addAll([
        StaggeredGridItem(
          value: HomeAutoSettingsWidget(homeAuto, focus: focus, open: open),
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
      ...super._devicePropertyItems()
      // StaggeredGridItem(
      //   value: HeartRateWidget(hrm),
      //   colSpan: 3,
      // ),
    ];
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
