//import 'dart:async';
import 'dart:developer' as dev;

// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:logging/logging.dart';
//import 'package:espmui/main.dart';
import 'package:flutter/material.dart';

class DebugBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double width;
  const DebugBorder({
    Key? key,
    required this.child,
    this.color = Colors.yellow,
    this.width = 1,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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

class Debug {
  String get debugTag => "$runtimeType(${identityHashCode(this)})";

  void devLog(String s, {Level level = Level.FINE}) {
    var match = RegExp(r'^#(\d+) +(.+) +(.+)').firstMatch(StackTrace.current.toString().split("\n")[2]);
    dev.log(
      "$s ${match?[3]}",
      //name: debugTag,
      name: match?[2]?.replaceAll(".<anonymous closure>", ".A") ?? "",
      level: level.value,
    );
  }

  void logD(String s) {
    devLog("[D] $s", level: Level.SHOUT);
  }

  void logE(String s) {
    devLog("[E] $s", level: Level.SEVERE);
  }

  void logI(String s) {
    devLog("[I] $s", level: Level.INFO);
  }
}
