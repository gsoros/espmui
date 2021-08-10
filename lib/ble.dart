import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';

import 'util.dart';

/// singleton class
class BLE {
  static final BLE _instance = BLE._construct();
  final String tag = "[BLE]";

  /// returns a singleton
  factory BLE() {
    return _instance;
  }

  // state
  StreamSubscription<BluetoothState>? stateSubscription;
  final stateController = StreamController<BluetoothState>.broadcast();
  Stream<BluetoothState> get stateStream => stateController.stream;
  BluetoothState _currentState = BluetoothState.UNKNOWN;
  bool _currentStateInitialized = false;

  Future<BluetoothState> currentState() async {
    await _checkClient();
    if (!_currentStateInitialized) {
      _currentState = await manager.bluetoothState();
      streamSendIfNotClosed(stateController, _currentState);
      _currentStateInitialized = true;
    }
    return Future.value(_currentState);
  }

  BluetoothState currentStateSync() {
    _checkClient();
    return _currentState;
  }

  Future<void> _checkClient() async {
    if (!await BleManager().isClientCreated()) {
      print("$tag waiting for createClient");
      await BleManager().createClient();
      print("$tag createClient done");
    }
    return Future.value(null);
  }

  BleManager get manager {
    _checkClient();
    return BleManager();
  }

  BLE._construct() {
    print("$tag _construct()");
    _init();
  }

  void _init() async {
    print("$tag _init()");
    await _checkPermissions();
    await _checkClient();
    print("$tag _init() _checkClient() done");
    await _checkAdapter();
    print("$tag _init() done");
  }

  Future<void> dispose() async {
    print("$tag dispose()");
    await stateController.close();
    await stateSubscription?.cancel();
    await manager.destroyClient();
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;
    print("$tag Checking permissions");
    if (!await Permission.location.request().isGranted) {
      bleError(tag, "No location permission");
      return Future.error(Exception("$tag Location permission not granted"));
    }
    if (!await Permission.bluetooth.request().isGranted) {
      bleError(tag, "No blootueth permission");
      return Future.error(Exception("$tag Bluetooth permission not granted"));
    }
  }

  Future<void> _checkAdapter() async {
    print("$tag _checkAdaper()");
    await stateSubscription?.cancel();
    stateSubscription = manager
        .observeBluetoothState()
        .handleError(
          (e) => bleError(tag, "observeBluetoothState()", e),
        )
        .listen(
      (state) async {
        print("$tag " + state.toString());
        _currentState = state;
        _currentStateInitialized = true;
        streamSendIfNotClosed(stateController, state);
        if (state == BluetoothState.POWERED_ON) {
          // Probably not a good idea to automatically scan, as of Android 7,
          // starting and stopping scans more than 5 times in a window of
          // 30 seconds will temporarily disable scanning
          //print("$tag Adapter powered on, starting scan");
          //startScan();
          //if (_selected != null) {
          //  print("$tag Adapter powered on, connecting to ${_selected.name}");
          //  _selected.connect();
          //}
        } else {
          bleError(tag, "Adapter not powered on");
          /*
          if (Platform.isAndroid) {
            await bleManager.cancelTransaction("autoEnableBT");
            await bleManager
                .enableRadio(transactionId: "autoEnableBT")
                .catchError((e) => bleError(tag, "enableRadio()", e));
          }
          */
        }
      },
      onError: (e) => bleError(tag, "stateSubscription", e),
    );
    return Future.value(null);
  }
}

/// https://github.com/dotintent/FlutterBleLib/blob/develop/lib/error/ble_error.dart
void bleError(String tag, String message, [dynamic error]) {
  String info = "";
  if (error != null) {
    String errorString = error.toString();
    int opening = errorString.indexOf(" (");
    String className = "Unknown Class";
    if (opening > 0) className = errorString.substring(0, opening);
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

/// Returns the result of [ifEnabled] or [ifDisabled] depending on the current
/// state of the bluetooth adapter.
Widget bleByState({
  required Widget Function() ifEnabled,
  Widget Function() ifDisabled = bleDisabledContainer,
}) {
  BLE ble = BLE();
  return StreamBuilder<BluetoothState>(
    stream: ble.stateStream,
    initialData: ble.currentStateSync(),
    builder: (BuildContext context, AsyncSnapshot<BluetoothState> snapshot) {
      return (snapshot.data == BluetoothState.POWERED_ON)
          ? ifEnabled()
          : ifDisabled();
    },
  );
}

Widget bleDisabledContainer() {
  return Container(
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Align left
            children: [Text("BT is disabled")],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end, // Align right
          children: [
            espmuiElevatedButton(
              "Enable",
              action: () {
                print("Enable radio pressed");
                BLE().manager.enableRadio();
              },
            ),
          ],
        )
      ],
    ),
  );
}
