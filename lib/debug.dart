//import 'dart:async';
import 'dart:developer' as dev show log;
import 'package:flutter/foundation.dart' show kDebugMode;

// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:logging/logging.dart' show Level;
//import 'package:espmui/main.dart';
import 'package:flutter/material.dart';

class DebugBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double width;
  const DebugBorder({
    super.key,
    required this.child,
    this.color = Colors.yellow,
    this.width = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return Container(child: child);
    return Container(
      decoration: BoxDecoration(
          border: Border.all(
        color: color,
        width: width,
      )),
      child: child,
    );
  }
}

mixin Debug {
  String get debugTag => !kDebugMode ? "$runtimeType(${identityHashCode(this)})" : "";

  static void log(String s, {Level level = Level.FINE}) {
    if (!kDebugMode) return;
    var match = RegExp(r'^#(\d+) +(.+) +(.+)').firstMatch(StackTrace.current.toString().split("\n")[2]);
    dev.log(
      "$s ${match?[3]}",
      //name: debugTag,
      name: match?[2]?.replaceAll(".<anonymous closure>", ".A") ?? "",
      level: level.value,
    );
  }

  void logD(String s) {
    log("[D] $s", level: Level.SHOUT);
  }

  void logE(String s) {
    log("[E] $s", level: Level.SEVERE);
  }

  void logI(String s) {
    log("[I] $s", level: Level.INFO);
  }
}
