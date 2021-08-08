// @dart=2.9
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

void streamSendIfNotClosed(StreamController stream, dynamic value) {
  if (stream.isClosed)
    print("[streamSendIfNotClosed] ${stream.toString()} stream is closed");
  else
    stream.sink.add(value);
}

void bleError(String tag, String message, [dynamic error]) {
  String info = "";
  if (error != null) {
    if (error.errorCode != null) {
      if (error.errorCode.value != null) {
        info += " [code ${error.errorCode.value}";
        switch (error.errorCode.value) {
          case BleErrorCode.operationCancelled:
            info += ": operationCancelled";
            break;
          case BleErrorCode.operationTimedOut:
            info += ": operationTimedOut";
            break;
          case BleErrorCode.bluetoothPoweredOff:
            info += ": bluetoothPoweredOff";
            break;
          case BleErrorCode.deviceDisconnected:
            info += ": deviceDisconnected";
            break;
          case BleErrorCode.deviceNotConnected:
            info += ": deviceNotConnected";
            break;
          case BleErrorCode.locationServicesDisabled:
            info += ": locationServicesDisabled";
            break;
        }
        info += "]";
      }
    }
    info += " " + error.toString();
  }
  print("$tag Error: $message$info");
}
