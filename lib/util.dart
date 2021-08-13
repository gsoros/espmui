import 'dart:async';

import 'package:flutter/material.dart';

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
  print("Snackbar message: $s");
  ScaffoldMessengerState sms;
  try {
    sms = ScaffoldMessenger.of(context);
  } catch (e) {
    print("Snackbar error: $e");
    return;
  }
  sms.removeCurrentSnackBar();
  sms.showSnackBar(SnackBar(
    backgroundColor: Colors.black38,
    content: Text(s, textAlign: TextAlign.center),
  ));
}
