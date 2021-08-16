import 'package:flutter/material.dart';

import 'scanner_route.dart';

void main() {
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
      //debugShowCheckedModeBanner: false,
      home: ScannerRoute(),
    );
  }
}
