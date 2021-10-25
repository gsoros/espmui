import 'dart:async';

import 'package:flutter/material.dart';

enum ExtendedBool {
  False,
  True,
  Unknown,
  Waiting,
}

/// Workaround for "The member 'notifyListeners' can only be used within
/// 'package:flutter/src/foundation/change_notifier.dart' or a test.dart
/// (invalid_use_of_visible_for_testing_member)""
class PropertyValueNotifier<T> extends ValueNotifier<T> {
  PropertyValueNotifier(T value) : super(value);

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
  if (stream.isClosed)
    print("[streamSendIfNotClosed] Stream ${stream.toString()} is closed");
  else
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
          return state.contains(MaterialState.disabled)
              ? Colors.red.shade400
              : Colors.red.shade900;
        }),
        foregroundColor: MaterialStateProperty.resolveWith((state) {
          return state.contains(MaterialState.disabled)
              ? Colors.grey
              : Colors.white;
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
    content: Text(s,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white)),
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
