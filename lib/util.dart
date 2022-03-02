import 'dart:async';
import 'dart:developer' as dev;

import 'package:espmui/main.dart';
import 'package:flutter/material.dart';
import 'debug.dart';

/// bool plus Unknown and Waiting
enum ExtendedBool {
  False,
  True,
  Unknown,
  Waiting,
}

/// converts bool to extended
ExtendedBool extendedBoolFrom(bool value) => value ? ExtendedBool.True : ExtendedBool.False;

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
    //debugLog("notifyListeners");
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
  //debugLog("[streamSendIfNotClosed] Stream ${stream.toString()} sending value: $value");
  stream.sink.add(value);
}

class EspmuiElevatedButton extends StatelessWidget {
  final String label;
  final Function()? action;

  EspmuiElevatedButton(this.label, {this.action});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: action,
      child: Text(label),
      style: ButtonStyle(
        backgroundColor: MaterialStateProperty.resolveWith((state) {
          return state.contains(MaterialState.disabled) ? Colors.red.shade400 : Colors.red.shade900;
        }),
        foregroundColor: MaterialStateProperty.resolveWith((state) {
          return state.contains(MaterialState.disabled) ? Colors.grey : Colors.white;
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
