import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

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
class AlwaysNotifier<T> extends ValueNotifier<T> {
  AlwaysNotifier(T value) : super(value);

  @override
  set value(T newValue) {
    dev.log('AlwaysNotifier set value');
    if (super.value == value) notifyListeners();
    super.value = newValue;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}

/// Unix timestamp in milliseconds
int uts() {
  return DateTime.now().millisecondsSinceEpoch;
}

void streamSendIfNotClosed(StreamController stream, dynamic value) {
  if (stream.isClosed) {
    print("[streamSendIfNotClosed] Stream ${stream.toString()} is closed");
    return;
  }
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

void snackbar(String s, BuildContext context) {
  print("[Snackbar] message: $s");
  ScaffoldMessengerState sms;
  try {
    sms = ScaffoldMessenger.of(context);
  } catch (e) {
    print("[Snackbar] error: $e");
    return;
  }
  sms.removeCurrentSnackBar();
  sms.showSnackBar(SnackBar(
    backgroundColor: Colors.black45,
    content: Text(s, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
  ));
}

class DebugBorder extends StatelessWidget {
  final Widget child;
  const DebugBorder({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.white38)),
      child: child,
    );
  }
}
