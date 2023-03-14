//import 'dart:async';
//import 'dart:developer' as dev;
import 'dart:math';

import 'package:espmui/util.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'ble.dart';
import 'espm.dart';
//import 'util.dart';
//import 'device_widgets.dart';
import 'debug.dart';

class TemperatureCompensationRoute extends StatelessWidget with Debug {
  final ESPM device;
  //final _key = GlobalKey<TemperatureCompensationRouteState>();

  TemperatureCompensationRoute(this.device, {Key? key}) : super(key: key) {
    debugLog("construct");
    device.settings.value.tc.readFromDevice();
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
            Expanded(child: zoomableChart()),
            buttons(),
            status(),
          ],
        ),
      ),
    );
  }

  Widget buttons() {
    var tc = device.settings.value.tc;
    return ValueListenableBuilder(
      valueListenable: device.settings,
      builder: (context, ESPMSettings settings, widget) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                child: EspmuiElevatedButton(
                  child: Text("Read"),
                  onPressed: tc.statusType == TCSST.reading
                      ? null
                      : () {
                          tc.readFromDevice();
                        },
                  backgroundColorEnabled: Colors.blueGrey,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: EspmuiElevatedButton(
                  child: Text("Collect"),
                  onPressed: () {},
                  backgroundColorEnabled: Colors.green,
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
      valueListenable: device.settings,
      builder: (context, ESPMSettings settings, widget) {
        return Text(settings.tc.statusMessage);
      },
    );
  }

  List<FlSpot> spots(TemperatureControlSettings tc) {
    var spots = List<FlSpot>.empty(growable: true);
    int key = 0;
    tc.values?.forEach((value) {
      if (null == value || TemperatureControlSettings.valueUnset == value) {
        if (0 < spots.length && spots.last != FlSpot.nullSpot) spots.add(FlSpot.nullSpot);
      } else
        spots.add(FlSpot(
          tc.keyToTemperature(key),
          tc.valueToMass(value),
        ));
      key++;
    });
    return spots;
  }

  Widget chart() {
    return ValueListenableBuilder(
      //key: _key,
      valueListenable: device.settings,
      builder: (context, ESPMSettings settings, widget) {
        var tc = settings.tc;
        if (null == tc.values) return Text("Waiting for chart data...");
        //int numValues = tc.size ?? 0;
        //double tempMin = tc.keyToTemperature(0);
        //double tempMax = tc.keyToTemperature(0 < numValues ? numValues - 1 : 0);
        //print("tempMin: $tempMin, tempMax: $tempMax, tc: ${tc.values}");
        return LineChart(
          LineChartData(
              clipData: FlClipData.all(),
              //minX: minX,
              //maxX: maxX,
              lineTouchData: LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots(tc),
                  isCurved: false,
                  barWidth: 2,
                  color: Colors.blueAccent,
                  dotData: FlDotData(show: false),
                ),
              ],
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    axisNameWidget: Text("Temperature (˚C)"),
                  ),
                  rightTitles: AxisTitles(
                    axisNameWidget: Text("Mass (kg)"),
                  ))),
        );
      },
    );
  }

  Widget zoomableChart() {
    return ValueListenableBuilder(
      // key: _key,
      valueListenable: device.settings,
      builder: (context, ESPMSettings settings, widget) {
        var tc = settings.tc;
        print("rebuilding chart size: ${tc.size}, keyOffset: ${tc.keyOffset}, keyResolution: ${tc.keyResolution}, valueResolution: ${tc.valueResolution}");
        if (null == tc.values) return Text("Waiting for chart data...");
        int numValues = tc.size ?? 0;
        double tempMin = tc.keyToTemperature(0);
        double tempMax = tc.keyToTemperature(0 < numValues ? numValues - 1 : 0);
        //print("tempMin: $tempMin, tempMax: $tempMax, tc: ${tc.values}");
        return ZoomableChart(
          minX: tempMin,
          maxX: tempMax,
          builder: (minX, maxX) {
            print("rebuilding chart");
            return LineChart(
              LineChartData(
                  clipData: FlClipData.all(),
                  minX: minX,
                  maxX: maxX,
                  lineTouchData: LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots(tc),
                      isCurved: false,
                      barWidth: 2,
                      color: Colors.blueAccent,
                      dotData: FlDotData(show: false),
                    ),
                  ],
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
