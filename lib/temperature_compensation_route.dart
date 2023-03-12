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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          Text("${device.name} TC"),
          ifDisabled: (state) => BleDisabled(state),
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: Column(
          children: [
            Flexible(
              fit: FlexFit.tight,
              child: Text("Chart"),
            ),
            Flexible(
              child: Row(
                children: [
                  Text("Button"),
                  Text("Button"),
                  Text("Button"),
                  Text("Button"),
                  Text("Button"),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
