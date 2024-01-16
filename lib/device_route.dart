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

  DeviceRoute(this.device) {
    logD("construct");
  }

  @override
  DeviceRouteState createState() {
    logD("createState()");
    if (device is ESPM) return ESPMRouteState(device as ESPM);
    if (device is ESPCC) return ESPCCRouteState(device as ESPCC);
    if (device is HomeAuto) return HomeAutoRouteState(device as HomeAuto);
    if (device is PowerMeter) return PowerMeterRouteState(device as PowerMeter);
    if (device is HeartRateMonitor) return HeartRateMonitorRouteState(device as HeartRateMonitor);
    return DeviceRouteState(device);
  }
}

class DeviceRouteState extends State<DeviceRoute> with Debug {
  Device device;

  DeviceRouteState(this.device) {
    logD("construct");
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
    device.peripheral = null;
    device.dispose();
    device = newDevice;
    DeviceList().addOrUpdate(device);
    logD("_checkCorrectType() reloading DeviceRoute($device)");
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => DeviceRoute(device)));
  }

  @override
  void dispose() async {
    logD("dispose");
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
            DeviceAppBarTitle(device),
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

  List<StaggeredGridItem> _deviceStreamTiles() {
    List<StaggeredGridItem> items = [];
    device.tileStreams.forEach((name, stream) {
      //logD("_deviceStreamTiles: name: $name, label: ${stream.label}");
      if (ESPM == device.runtimeType && "scale" == name) return; // TODO
      Tile tile = Tile(
        device: device.identifier,
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
                label: Text("Log"),
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
      // StaggeredGridItem(
      //   value: PowerCadenceWidget(powerMeter, mode: "power"),
      //   colSpan: 3,
      // ),
      // StaggeredGridItem(
      //   value: PowerCadenceWidget(powerMeter, mode: "cadence"),
      //   colSpan: 3,
      // ),
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

  HomeAutoRouteState(this.homeAuto) : super(homeAuto);

  @override
  _devicePropertyItems() {
    return super._devicePropertyItems()
      ..addAll([
        StaggeredGridItem(
          value: HomeAutoSettingsWidget(homeAuto),
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
      // StaggeredGridItem(
      //   value: HeartRateWidget(hrm),
      //   colSpan: 3,
      // ),
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
