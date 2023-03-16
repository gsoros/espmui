import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';

import 'package:espmui/main.dart';
// import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'debug.dart';

/// bool plus Unknown and Waiting
enum ExtendedBool {
  Unknown(0),
  Waiting(1),
  False(2),
  True(3);

  final int value;

  const ExtendedBool(this.value);

  factory ExtendedBool.fromBool(bool b) => b ? True : False;

  factory ExtendedBool.fromString(String s) {
    if (s.toLowerCase() == "true" || s == "1") return True;
    if (s.toLowerCase() == "false" || s == "0") return False;
    return Unknown;
  }

  bool get asBool => value == True.value;
}

/// A [ValueNotifier] that notifies listeners in the setter even when [value] is replaced
/// with something that is equal to the old value as evaluated by the equality operator ==.
///
/// After modifying a value indirectly (e.g. "alwaysNotifier.value.x = y;"), call [notifyListeners()].
class AlwaysNotifier<T> extends ValueNotifier<T> with Debug {
  AlwaysNotifier(T value) : super(value);

  @override
  set value(T newValue) {
    //debugLog('AlwaysNotifier set value: $newValue');
    if (super.value == value) notifyListeners();
    super.value = newValue;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    //logD("notifyListeners");
  }
}

/// Unix timestamp in milliseconds
int uts() {
  return DateTime.now().millisecondsSinceEpoch;
}

void streamSendIfNotClosed(StreamController stream, dynamic value) {
  if (stream.isClosed) {
    dev.log("[streamSendIfNotClosed] Stream ${stream.toString()} is closed");
    return;
  }
  if (null == value) {
    dev.log("[streamSendIfNotClosed] not sending null to stream ${stream.toString()}");
    return;
  }
  //logD("[streamSendIfNotClosed] Stream ${stream.toString()} sending value: $value");
  stream.sink.add(value);
}

class EspmuiElevatedButton extends StatelessWidget {
  final Widget child;
  final void Function()? onPressed;
  final EdgeInsetsGeometry? padding;
  late final Color? foregroundColorEnabled;
  late final Color? foregroundColorDisabled;
  late final Color? backgroundColorEnabled;
  late final Color? backgroundColorDisabled;

  EspmuiElevatedButton({
    required this.child,
    this.onPressed,
    this.padding,
    Color? foregroundColorEnabled,
    Color? foregroundColorDisabled,
    Color? backgroundColorEnabled,
    Color? backgroundColorDisabled,
  }) {
    this.foregroundColorEnabled = foregroundColorEnabled ?? Colors.white;
    this.foregroundColorDisabled = foregroundColorDisabled ?? Colors.grey;
    this.backgroundColorEnabled = backgroundColorEnabled ?? Colors.red.shade900;
    this.backgroundColorDisabled = backgroundColorDisabled ?? Colors.red.shade400;
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      child: child,
      style: ButtonStyle(
        padding: MaterialStateProperty.all<EdgeInsetsGeometry?>(padding),
        backgroundColor: MaterialStateProperty.resolveWith((state) {
          return state.contains(MaterialState.disabled) ? backgroundColorDisabled : backgroundColorEnabled;
        }),
        foregroundColor: MaterialStateProperty.resolveWith((state) {
          return state.contains(MaterialState.disabled) ? foregroundColorDisabled : foregroundColorEnabled;
        }),
      ),
    );
  }
}

void snackbar(String s, [BuildContext? context]) {
  print("[Snackbar] message: $s");
  ScaffoldMessengerState? sms;
  try {
    if (null != context)
      sms = ScaffoldMessenger.of(context);
    else
      sms = scaffoldMessengerKey.currentState;
    if (null == sms) throw ("ScaffoldMessengerState is null");
  } catch (e) {
    print("[Snackbar] error: $e");
    return;
  }
  sms.removeCurrentSnackBar();
  sms.showSnackBar(SnackBar(
    backgroundColor: Colors.black45,
    content: Text(
      s,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white),
    ),
  ));
}

double map(double x, double inMin, double inMax, double outMin, double outMax) {
  double out = (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
  return out.isNaN || out.isInfinite ? 0 : out;
}

class Empty extends StatelessWidget {
  const Empty();
  Widget build(BuildContext context) => const SizedBox.square(dimension: 1);
}

String bytesToString(int b, {int digits = 2}) {
  if (digits < 0) digits = 0;
  int k = 1024;
  if (b >= pow(k, 4)) return (b / pow(k, 4)).toStringAsFixed(digits) + "TB";
  if (b >= pow(k, 3)) return (b / pow(k, 3)).toStringAsFixed(digits) + "GB";
  if (b >= pow(k, 2)) return (b / pow(k, 2)).toStringAsFixed(digits) + "MB";
  if (b >= k) return (b / k).toStringAsFixed(digits) + "kB";
  return "${b}B";
}

String distanceToString(int d, {int digits = 2}) {
  if (digits < 0) digits = 0;
  int k = 1000;
  if (d >= k) return (d / k).toStringAsFixed(digits) + "km";
  return "${d}m";
}

/// singleton class
class Path with Debug {
  String? _documents;
  String? _external;
  static final Path _instance = Path._construct();

  factory Path() {
    return _instance;
  }
  Path._construct();

  Future<String?> get documents async {
    if (_documents != null) return _documents;
    try {
      _documents = (await getApplicationDocumentsDirectory()).path;
    } catch (e) {
      logE("could not getApplicationDocumentsDirectory(), error: $e");
      return null;
    }
    return _documents;
  }

  Future<String?> get external async {
    if (_external != null) return _external;
    if (!Platform.isAndroid) return null;
    try {
      var dir = await getExternalStorageDirectory();
      if (null == dir) return null;
      _external = dir.path;
    } catch (e) {
      logE("could not getExternalStorageDirectory(), error: $e");
      return null;
    }
    return _external;
  }

  String sanitize(String s) {
    return s.replaceAll("[^A-Za-z0-9]", "_");
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1).toLowerCase()}";
  }
}
