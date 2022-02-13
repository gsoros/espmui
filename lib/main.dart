import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'scanner_route.dart';
// import 'sensors_route.dart';

void main() {
  //debugRepaintRainbowEnabled = true;
  runApp(EspmUiApp());
}

class EspmUiApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final backgroundColor = const Color(0xff202020);
    final primaryColor = Colors.red;
    return MaterialApp(
      title: 'ESPMUI',
      theme: ThemeData(
        scaffoldBackgroundColor: backgroundColor,
        primarySwatch: primaryColor,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: primaryColor,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: primaryColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      //showPerformanceOverlay: true,
      home: ScannerRoute(),
      //home: SensorsRoute(),
    );
  }
}
