//import 'dart:async';
import 'dart:developer' as dev;

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
  String get debugTag => "[$runtimeType(${identityHashCode(this)})]";

  void debugLog(String s) {
    dev.log("$debugTag $s");
  }
}
