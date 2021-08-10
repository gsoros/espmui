import 'dart:async';

import 'package:flutter/material.dart';

void streamSendIfNotClosed(StreamController stream, dynamic value) {
  if (stream.isClosed)
    print("[streamSendIfNotClosed] Stream ${stream.toString()} is closed");
  else
    stream.sink.add(value);
}

Widget espmuiElevatedButton(String label, {Function()? action}) {
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
