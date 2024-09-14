import 'package:flutter/material.dart';
//import 'package:flutter/rendering.dart';

//import 'scanner_route.dart';
import 'tiles_route.dart';

void main() {
  //debugRepaintRainbowEnabled = true;
  runApp(const EspmUiApp());
}

/// TODO move to some globals class
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class EspmUiApp extends StatelessWidget {
  const EspmUiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xff202020);
    const primaryColor = Colors.red;
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
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      //showPerformanceOverlay: true,
      //home: ScannerRoute(),
      home: const TilesRoute(),
    );
  }
}
