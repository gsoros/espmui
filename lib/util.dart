// // @dart=2.9
import 'dart:async';
// ignore: import_of_legacy_library_into_null_safe
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

void streamSendIfNotClosed(StreamController stream, dynamic value) {
  if (stream.isClosed)
    print("[streamSendIfNotClosed] Stream ${stream.toString()} is closed");
  else
    stream.sink.add(value);
}

// https://github.com/dotintent/FlutterBleLib/blob/develop/lib/error/ble_error.dart
void bleError(String tag, String message, [dynamic error]) {
  String info = "";
  if (error != null) {
    String errorString = error.toString();
    String className = errorString.substring(0, errorString.indexOf(" ("));
    if (className != "BleError") {
      info += " (Non-Ble Error: '$className') " + errorString;
    } else {
      if (error.errorCode != null) {
        if (error.errorCode.value != null) {
          info += " [code ${error.errorCode.value}";
          // TODO use reflection to auto parse error code
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
            case BleErrorCode.characteristicNotifyChangeFailed: // 403
              info += ": characteristicNotifyChangeFailed";
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
      String params = errorString.substring(
        errorString.indexOf("(") + 1,
        errorString.lastIndexOf(")"),
      );
      List<String> nonNull = [];
      params.split(", ").forEach((param) {
        List<String> kv = param.split(": ");
        if ((kv.length != 2 || kv.last != "null") && kv.first != "Error code")
          nonNull.add(param);
      });
      info += " {" + nonNull.join(", ") + "}";
    }
  }
  print("$tag Error: $message$info");
}
