import 'dart:async';
//import 'dart:developer' as dev;
import 'dart:math';
import 'package:collection/collection.dart';

import 'package:espmui/util.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'ble.dart';
import 'espm.dart';
//import 'util.dart';
import 'device_widgets.dart';
import 'debug.dart';

class TCRoute extends StatefulWidget with Debug {
  final ESPM device;

  TCRoute(this.device, {Key? key}) : super(key: key) {
    debugLog("construct");
    device.settings.value.tc.readFromDevice();
  }

  @override
  State<TCRoute> createState() => _TCRouteState(device);
}

class _TCRouteState extends State<TCRoute> with Debug {
  ESPM device;
  late StreamSubscription<double>? temperatureSubscription;
  late StreamSubscription<double>? weightSubscription;
  double? temperature, weight;

  _TCRouteState(this.device) {
    temperatureSubscription = device.tempChar?.defaultStream.listen((value) {
      onTempChange(value);
    });
    weightSubscription = device.weightScaleChar?.defaultStream.listen((value) {
      onWeightChange(value);
    });
  }

  void dispose() {
    temperatureSubscription?.cancel();
    temperatureSubscription = null;
    weightSubscription?.cancel();
    weightSubscription = null;
    super.dispose();
  }

  void onTempChange(double value) {
    temperature = value;
    var tc = device.settings.value.tc;
    if (!tc.isCollecting || null == weight) return;
    tc.addCollected(value, weight!);
    //debugLog("onTempChange $value ${tc.collectedSize()}");
  }

  void onWeightChange(double value) {
    weight = value;
    var tc = device.settings.value.tc;
    if (!tc.isCollecting || null == temperature) return;
    tc.addCollected(temperature!, value);
    //debugLog("onWeightChange $value ${tc.collectedSize()}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          DeviceAppBarTitle(
            widget.device,
            nameEditable: false,
            prefix: "TC ",
            onConnected: () async {
              widget.device.settings.value.tc.status("waiting for init to complete");
              int attempts = 0;
              await Future.doWhile(() async {
                await Future.delayed(Duration(milliseconds: 300));
                //debugLog("attempt #$attempts checking if tc command is available...");
                if (null != widget.device.api.commandCode("tc")) return false;
                attempts++;
                return attempts < 50;
              });
              debugLog("${widget.device.name} init done, calling readFromDevice()");
              widget.device.settings.value.tc.readFromDevice();
            },
          ),
          ifDisabled: (state) => BleDisabled(state),
        ),
      ),
      body: Container(
        margin: EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: chart()),
            buttons(),
            status(),
          ],
        ),
      ),
    );
  }

  Widget buttons() {
    var tc = widget.device.settings.value.tc;
    return ValueListenableBuilder(
      valueListenable: widget.device.settings,
      builder: (context, ESPMSettings settings, widget) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                child: EspmuiElevatedButton(
                  child: Text(tc.statusType == TCSST.reading ? "Reading" : "Read"),
                  onPressed: tc.statusType == TCSST.reading || tc.statusType == TCSST.collecting
                      ? null
                      : () async {
                          var success = await tc.readFromDevice();
                          debugLog("read button onPressed success: $success");
                        },
                  backgroundColorEnabled: Colors.blueGrey,
                  backgroundColorDisabled: Colors.black54,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: EspmuiElevatedButton(
                  child: Text(tc.statusType == TCSST.collecting ? "Stop" : "Collect"),
                  onPressed: tc.statusType == TCSST.collecting
                      ? () {
                          tc.stopCollecting();
                        }
                      : () {
                          tc.startCollecting();
                        },
                  backgroundColorEnabled: tc.statusType == TCSST.collecting ? Colors.deepOrange : Colors.green,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 0, 0),
                child: EspmuiElevatedButton(
                  child: Text("Write"),
                  onPressed: () {},
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget status() {
    return ValueListenableBuilder(
      valueListenable: widget.device.settings,
      builder: (context, ESPMSettings settings, widget) {
        return Text(settings.tc.statusMessage);
      },
    );
  }

  List<FlSpot> savedSpots(TemperatureControlSettings tc) {
    var spots = List<FlSpot>.empty(growable: true);
    int key = 0;
    tc.values.forEach((value) {
      if (null == value || TemperatureControlSettings.valueUnset == value) {
        if (0 < spots.length && spots.last != FlSpot.nullSpot) spots.add(FlSpot.nullSpot);
      } else
        spots.add(FlSpot(
          tc.keyToTemperature(key),
          tc.valueToWeight(value),
        ));
      key++;
    });
    return spots;
  }

  List<FlSpot> collectedSpots(TemperatureControlSettings tc) {
    var spots = List<FlSpot>.empty(growable: true);
    tc.collected.forEach((key, value) {
      if (0 < value.length)
        spots.add(FlSpot(
          key,
          value.average,
        ));
    });
    return spots;
  }

  List<LineChartBarData> lineBars(TemperatureControlSettings tc) {
    List<LineChartBarData> data = [
      LineChartBarData(
        spots: savedSpots(tc),
        isCurved: false,
        barWidth: 2,
        color: Colors.blueAccent,
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: collectedSpots(tc),
        isCurved: false,
        barWidth: 2,
        color: Colors.red,
        dotData: FlDotData(show: false),
      ),
    ];
    if (null != temperature && null != weight) {
      data.add(LineChartBarData(
        spots: [FlSpot(temperature!, weight!)],
        isCurved: false,
        barWidth: 2,
        color: Colors.yellow,
        dotData: FlDotData(show: true),
      ));
    }
    return data;
  }

  Widget chart() {
    return ValueListenableBuilder(
      // key: _key,
      valueListenable: widget.device.settings,
      builder: (context, ESPMSettings settings, widget) {
        var tc = settings.tc;
        //print("rebuilding chart size: ${tc.size}, keyOffset: ${tc.keyOffset}, keyResolution: ${tc.keyResolution}, valueResolution: ${tc.valueResolution}");
        if (tc.size < 1) return Text("No chart data");
        int numValues = tc.size;
        double savedMin = tc.keyToTemperature(0);
        double savedMax = tc.keyToTemperature(0 < numValues ? numValues - 1 : 0);
        double? collectedMin = tc.collectedMinTemp();
        double? collectedMax = tc.collectedMaxTemp();
        double tempMin = null == collectedMin ? savedMin : min(savedMin, collectedMin);
        double tempMax = null == collectedMax ? savedMax : max(savedMax, collectedMax);
        //print("collectedMin: $collectedMin, collectedMax: $collectedMax, tempMin: $tempMin, tempMax: $tempMax, tc: ${tc.values}");
        return ZoomableChart(
          minX: tempMin,
          maxX: tempMax,
          builder: (minX, maxX) {
            //print("rebuilding chart");
            return LineChart(
              LineChartData(
                  clipData: FlClipData.all(),
                  minX: minX,
                  maxX: maxX,
                  lineTouchData: LineTouchData(enabled: false),
                  lineBarsData: lineBars(tc),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                      show: true,
                      topTitles: AxisTitles(
                        axisNameWidget: Text("Temperature (˚C)"),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: Text("Compensation (kg)"),
                      ))),
            );
          },
        );
      },
    );
  }
}

// https://github.com/imaNNeo/fl_chart/issues/71#issuecomment-1414267612
class ZoomableChart extends StatefulWidget {
  final double minX, maxX;
  final Widget Function(double, double) builder;

  ZoomableChart({
    super.key,
    required this.minX,
    required this.maxX,
    required this.builder,
  });

  @override
  State<ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<ZoomableChart> {
  late double minX, maxX, lastMaxX, lastMinX;

  @override
  void initState() {
    super.initState();
    minX = widget.minX;
    maxX = widget.maxX;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        setState(() {
          minX = widget.minX;
          maxX = widget.maxX;
        });
      },
      onHorizontalDragStart: (details) {
        lastMinX = minX;
        lastMaxX = maxX;
      },
      onHorizontalDragUpdate: (details) {
        var horizontalDistance = details.primaryDelta ?? 0;
        if (horizontalDistance == 0) return;
        //print("_ZoomableChartState build horizontalDistance: $horizontalDistance");
        var lastMinMaxDistance = (lastMaxX - lastMinX).abs();

        setState(() {
          minX -= lastMinMaxDistance * 0.005 * horizontalDistance;
          maxX -= lastMinMaxDistance * 0.005 * horizontalDistance;

          if (minX < widget.minX) {
            minX = widget.minX;
            maxX = minX + lastMinMaxDistance;
          }
          if (maxX > widget.maxX) {
            maxX = widget.maxX;
            minX = maxX - lastMinMaxDistance;
          }
          //print("_ZoomableChartState onHorizontalDragUpdate $minX, $maxX");
        });
      },
      onScaleStart: (details) {
        lastMinX = minX;
        lastMaxX = maxX;
      },
      onScaleUpdate: (details) {
        const double minDistance = 10.0;
        var horizontalScale = details.horizontalScale;
        if (horizontalScale == 0) return;
        var lastMinMaxDistance = (lastMaxX - lastMinX).abs();
        var newMinMaxDistance = max(lastMinMaxDistance / horizontalScale, minDistance);
        var distanceDifference = newMinMaxDistance - lastMinMaxDistance;
        //print("_ZoomableChartState build onScaleUpdate horizontalScale: $horizontalScale "
        //    "lastMinMaxDistance: $lastMinMaxDistance, newMinMaxDistance: $newMinMaxDistance, "
        //    "distanceDifference: $distanceDifference");
        setState(() {
          final newMinX = lastMinX - distanceDifference;
          final newMaxX = lastMaxX + distanceDifference;

          if (minDistance < newMaxX - newMinX) {
            minX = newMinX;
            maxX = newMaxX;
          }
          //print("_ZoomableChartState build onScaleUpdate $minX, $maxX");
        });
      },
      child: widget.builder(minX, maxX),
    );
  }
}
