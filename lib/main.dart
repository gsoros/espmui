// @dart=2.9
import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'scannerRoute.dart';

void main() {
  runApp(EspmUiApp());
}

class EspmUiApp extends StatelessWidget {
  final BleManager bleManager = BleManager();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESPMUI',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.red,
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.red,
        ),
      ),
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: ScannerRoute(bleManager: bleManager),
    );
  }
}
