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
            info += ": operationCancelled"; // 2
            break;
          case BleErrorCode.operationTimedOut: // 3
            info += ": operationTimedOut";
            break;
          case BleErrorCode.bluetoothPoweredOff: // 102
            info += ": bluetoothPoweredOff";
            break;
          case BleErrorCode.deviceDisconnected: // 201
            info += ": deviceDisconnected";
            break;
          case BleErrorCode.deviceAlreadyConnected: // 203
            info += ": deviceAlreadyConnected";
            break;
          case BleErrorCode.deviceNotConnected: // 205
            info += ": deviceNotConnected";
            break;
          case BleErrorCode.serviceNotFound: // 302
            info += ": serviceNotFound";
            break;
          case BleErrorCode.characteristicReadFailed: // 402
            info += ": characteristicReadFailed";
            break;
          case BleErrorCode.characteristicNotFound: // 404
            info += ": characteristicNotFound";
            break;
          case BleErrorCode.locationServicesDisabled: // 601
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
