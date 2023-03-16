import 'dart:async';
//import 'dart:developer' as dev;
import 'dart:math';
//import 'package:collection/collection.dart';

import 'package:espmui/util.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'ble.dart';
import 'espm.dart';
import 'temperature_compensation.dart';
//import 'util.dart';
import 'device_widgets.dart';
import 'debug.dart';

class TCRoute extends StatefulWidget with Debug {
  final ESPM espm;

  TCRoute(this.espm, {Key? key}) : super(key: key) {
    logD("construct");
    espm.settings.value.tc.readFromDevice();
  }

  @override
  State<TCRoute> createState() => _TCRouteState(espm);
}

class _TCRouteState extends State<TCRoute> with Debug {
  ESPM espm;
  late StreamSubscription<double?>? temperatureSubscription;
  late StreamSubscription<double?>? weightSubscription;
  double? temperature, weight, lastTemperature, lastWeight;

  _TCRouteState(this.espm) {
    temperatureSubscription = espm.tempChar?.defaultStream.listen((value) {
      onTempChange(value);
    });
    weightSubscription = espm.weightScaleChar?.defaultStream.listen((value) {
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

  void onTempChange(double? value) {
    temperature = value;
    var tc = espm.settings.value.tc;
    if (null == weight || weight == lastWeight) return;
    lastWeight = weight;
    if (null == value) return;
    if (tc.isCollecting)
      tc.addCollected(value, weight!);
    else
      espm.settings.notifyListeners();
    //logD("onTempChange $value ${tc.collectedSize()}");
  }

  void onWeightChange(double? value) {
    if (null == value) {
      weight = value;
      return;
    }
    value = -value; // flip sign
    weight = value;
    var tc = espm.settings.value.tc;
    if (null == temperature || temperature == lastTemperature) return;
    lastTemperature = temperature;
    if (tc.isCollecting)
      tc.addCollected(temperature!, value);
    else
      espm.settings.notifyListeners();
    //logD("onWeightChange $value ${tc.collectedSize()}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BleAdapterCheck(
          DeviceAppBarTitle(
            espm,
            nameEditable: false,
            prefix: "TC ",
            onConnected: () async {
              espm.settings.value.tc.status("waiting for init to complete");
              int attempts = 0;
              await Future.doWhile(() async {
                await Future.delayed(Duration(milliseconds: 300));
                //logD("attempt #$attempts checking if tc command is available...");
                if (null != espm.api.commandCode("tc", logOnError: false)) return false;
                attempts++;
                return attempts < 50;
              });
              logD("${espm.name} init done, calling readFromDevice()");
              espm.settings.value.tc.readFromDevice();
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
    return ValueListenableBuilder(
      valueListenable: espm.settings,
      builder: (context, ESPMSettings settings, widget) {
        var tc = settings.tc;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 3, 0),
                child: EspmuiElevatedButton(
                  child: Text(tc.isReading ? "Reading" : "Read"),
                  onPressed: tc.isReading || tc.isCollecting
                      ? null
                      : () async {
                          var success = await tc.readFromDevice();
                          logD("read button onPressed success: $success");
                        },
                  backgroundColorEnabled: Colors.blue.shade900,
                  backgroundColorDisabled: Colors.black54,
                  padding: EdgeInsets.all(0),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
                child: EspmuiElevatedButton(
                  child: Text(tc.isCollecting ? "Stop" : "Collect"),
                  onPressed: tc.isCollecting
                      ? () {
                          tc.stopCollecting();
                        }
                      : () {
                          tc.startCollecting();
                        },
                  backgroundColorEnabled: tc.isCollecting ? Colors.red : Colors.green.shade900,
                  padding: EdgeInsets.all(0),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 0, 3, 0),
                child: EspmuiElevatedButton(
                  child: Text("Clear"),
                  onPressed: 0 < tc.collected.length && !tc.isCollecting
                      ? () {
                          tc.collected.clear();
                          espm.settings.notifyListeners();
                        }
                      : null,
                  backgroundColorEnabled: Colors.purple.shade900,
                  backgroundColorDisabled: Colors.black54,
                  padding: EdgeInsets.all(0),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(3, 0, 0, 0),
                child: EspmuiElevatedButton(
                  child: Text("Write"),
                  onPressed: !tc.isCollecting && !tc.isWriting
                      ? () async {
                          if (await tc.writeToDevice()) tc.readFromDevice();
                        }
                      : null,
                  backgroundColorDisabled: Colors.black54,
                  padding: EdgeInsets.all(0),
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
      valueListenable: espm.settings,
      builder: (context, ESPMSettings settings, widget) {
        return Text(settings.tc.statusMessage);
      },
    );
  }

  List<FlSpot> savedSpots(TC tc) {
    var spots = List<FlSpot>.empty(growable: true);
    int key = 0;
    tc.values.forEach((value) {
      // if (0 == value) {
      //   if (0 < spots.length && spots.last != FlSpot.nullSpot) spots.add(FlSpot.nullSpot);
      // } else
      spots.add(FlSpot(
        tc.keyToTemperature(key),
        tc.valueToWeight(value),
      ));
      key++;
    });
    return spots;
  }

  List<FlSpot> collectedSpots(TC tc) {
    var spots = List<FlSpot>.empty(growable: true);
    tc.collected.forEach((value) {
      if (value.length < 2) return;
      spots.add(FlSpot(
        value[0],
        value[1],
      ));
    });
    return spots;
  }

  List<FlSpot> suggestedSpots(TC tc) {
    var spots = List<FlSpot>.empty(growable: true);
    tc.suggested.forEach((key, value) {
      spots.add(FlSpot(key, value));
    });
    return spots;
  }

  LineTouchData? touchData(TC tc) {
    /*
    LineTouchData LineTouchData({
      bool? enabled,
      void Function(FlTouchEvent, LineTouchResponse?)? touchCallback,
      MouseCursor Function(FlTouchEvent, LineTouchResponse?)? mouseCursorResolver,
      Duration? longPressDuration,
      LineTouchTooltipData? touchTooltipData,
      List<TouchedSpotIndicatorData?> Function(LineChartBarData, List<int>)? getTouchedSpotIndicator,
      double? touchSpotThreshold,
      double Function(Offset, Offset)? distanceCalculator,
      bool? handleBuiltInTouches,
      double Function(LineChartBarData, int)? getTouchLineStart,
      double Function(LineChartBarData, int)? getTouchLineEnd,
    })
    package:fl_chart/src/chart/line_chart/line_chart_data.dart

    You can disable or enable the touch system using [enabled] flag,

    [touchCallback] notifies you about the happened touch/pointer events. It gives you a [FlTouchEvent] which is the happened event such as [FlPointerHoverEvent], [FlTapUpEvent], ... It also gives you a [LineTouchResponse] which contains information about the elements that has touched.

    Using [mouseCursorResolver] you can change the mouse cursor based on the provided [FlTouchEvent] and [LineTouchResponse]

    if [handleBuiltInTouches] is true, [LineChart] shows a tooltip popup on top of the spots if touch occurs (or you can show it manually using, [LineChartData.showingTooltipIndicators]) and also it shows an indicator (contains a thicker line and larger dot on the targeted spot), You can define how this indicator looks like through [getTouchedSpotIndicator] callback, You can customize this tooltip using [touchTooltipData], indicator lines starts from position controlled by [getTouchLineStart] and ends at position controlled by [getTouchLineEnd]. If you need to have a distance threshold for handling touches, use [touchSpotThreshold].
    */
    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: false,
      longPressDuration: Duration(milliseconds: 800),
      touchCallback: (event, response) {
        if (!(event is FlLongPressStart)) return;
        var data = response?.lineBarSpots;
        if (null == data || data.length < 1) return;
        logD("${data.firstWhere((e) => 2 == e.barIndex).spotIndex}");
      },
    );
  }

  List<LineChartBarData> chartData(TC tc) {
    List<LineChartBarData> data = [
      LineChartBarData(
        spots: savedSpots(tc),
        isCurved: false,
        barWidth: 2,
        color: Colors.blue.shade500,
        dotData: FlDotData(show: false),
      ),
      LineChartBarData(
        spots: collectedSpots(tc),
        isCurved: true,
        barWidth: 2,
        color: Colors.green.shade700,
        dotData: FlDotData(show: false),
      ),
    ];
    var suggested = suggestedSpots(tc);
    if (0 < suggested.length) {
      data.add(LineChartBarData(
        spots: suggested,
        isCurved: false,
        //barWidth: 5,
        color: Colors.purple.shade500,
        dotData: FlDotData(show: true),
      ));
    }
    if (null != temperature && null != weight) {
      data.add(LineChartBarData(
        spots: [FlSpot(temperature!, weight!)],
        isCurved: false,
        //barWidth: 5,
        color: Colors.yellow,
        dotData: FlDotData(show: true),
      ));
    }
    return data;
  }

  Widget chart() {
    return ValueListenableBuilder(
      // key: _key,
      valueListenable: espm.settings,
      builder: (context, ESPMSettings settings, widget) {
        var tc = settings.tc;
        //print("rebuilding chart size: ${tc.size}, keyOffset: ${tc.keyOffset}, keyResolution: ${tc.keyResolution}, valueResolution: ${tc.valueResolution}");
        if (tc.size < 1) return Text("No chart data");
        int numValues = tc.size;
        double savedMin = tc.keyToTemperature(0);
        double savedMax = tc.keyToTemperature(0 < numValues ? numValues - 1 : 0);
        double? collectedMin = tc.collectedMinTemp;
        double? collectedMax = tc.collectedMaxTemp;
        double tempMin = null == collectedMin ? savedMin : min(savedMin, collectedMin);
        double tempMax = null == collectedMax ? savedMax : max(savedMax, collectedMax);
        //print("collectedMin: $collectedMin, collectedMax: $collectedMax, tempMin: $tempMin, tempMax: $tempMax, tc: ${tc.values}");
        return ZoomableChart(
          minX: tempMin,
          maxX: tempMax,
          builder: (minX, maxX) {
            return LineChart(
              LineChartData(
                  clipData: FlClipData.none(),
                  minX: minX,
                  maxX: maxX,
                  lineTouchData: touchData(tc),
                  lineBarsData: chartData(tc),
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

/// https://github.com/imaNNeo/fl_chart/issues/71#issuecomment-1414267612
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
          if (minX == widget.minX && maxX == widget.maxX) {
            var diff = (maxX - minX).abs() / 2.5;
            minX += diff;
            maxX -= diff;
          } else {
            minX = widget.minX;
            maxX = widget.maxX;
          }
        });
      },
      onHorizontalDragStart: (details) {
        lastMinX = minX;
        lastMaxX = maxX;
      },
      onHorizontalDragUpdate: (details) {
        var distance = details.primaryDelta ?? 0;
        if (distance == 0) return;
        //print("_ZoomableChartState build horizontalDistance: $horizontalDistance");
        var lastDistance = (lastMaxX - lastMinX).abs();

        setState(() {
          minX -= lastDistance * 0.004 * distance;
          maxX -= lastDistance * 0.004 * distance;

          if (minX < widget.minX) {
            minX = widget.minX;
            maxX = minX + lastDistance;
          }
          if (maxX > widget.maxX) {
            maxX = widget.maxX;
            minX = maxX - lastDistance;
          }
          //print("_ZoomableChartState onHorizontalDragUpdate $minX, $maxX");
        });
      },
      onScaleStart: (details) {
        lastMinX = minX;
        lastMaxX = maxX;
        //print("_ZoomableChartState build onScaleStart");
      },
      onScaleUpdate: (details) {
        const double minDistance = 2.0;
        var scale = details.scale;
        if (scale == 0) return;
        var lastDistance = (lastMaxX - lastMinX).abs();
        var newDistance = max(lastDistance / scale, minDistance);
        var diff = newDistance - lastDistance;
        setState(() {
          final newMinX = lastMinX - diff;
          final newMaxX = lastMaxX + diff;

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
