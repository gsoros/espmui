import 'dart:async';
//import 'dart:developer' as dev;

import 'package:espmui/device_widgets.dart';
import 'package:flutter/material.dart';

import 'ble.dart';
import 'espm.dart';
import 'debug.dart';

class TemperatureCompensationRoute extends StatefulWidget {
  final ESPM device;
  TemperatureCompensationRoute(this.device, {Key? key}) : super(key: key);

  @override
  TemperatureCompensationRouteState createState() => TemperatureCompensationRouteState(device);
}

class TemperatureCompensationRouteState extends State<TemperatureCompensationRoute> with Debug {
  final ESPM device;
  final _key = GlobalKey<TemperatureCompensationRouteState>();

  TemperatureCompensationRouteState(this.device) {
    debugLog("construct");
  }

  @override
  void initState() {
    super.initState();
    debugLog("initState()");
  }

  @override
  void dispose() {
    debugLog("dispose()");
    //scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          Text("Titlebar"),
          ifDisabled: (state) => BleDisabled(state),
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: Text("content"),
      ),
    );
  }
}
