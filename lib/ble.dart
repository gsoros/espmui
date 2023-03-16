import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mutex/mutex.dart';

import 'util.dart';
import 'debug.dart';
import 'device.dart';
//import 'scanner.dart';

/// singleton class
class BLE with Debug {
  static final BLE _instance = BLE._construct();
  bool _createClientRequested = false;
  bool _createClientCompleted = false;
  bool _initDone = false;
  final _exclusiveAccess = Mutex();

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
    await _init();
    if (!_currentStateInitialized) {
      _currentState = await (await manager).bluetoothState();
      streamSendIfNotClosed(stateController, _currentState);
      _currentStateInitialized = true;
    }
    return Future.value(_currentState);
  }

  BluetoothState currentStateSync() {
    _checkClient();
    return _currentState;
  }

  Future<BleManager> get manager async {
    //logD("get manager");
    await _init();
    return BleManager();
  }

  BLE._construct() {
    logD("_construct()");
    _init();
  }

  Future<void> _init() async {
    if (_initDone) return;
    logD("_init()");
    await _exclusiveAccess.protect(() async {
      if (_initDone) return;
      //logD("_init() calling _checkPermissions()");
      await _checkPermissions();
      //logD("_init() calling _checkClient()");
      await _checkClient();
      //logD("_init() calling _checkAdapter()");
      await _checkAdapter();
      _initDone = true;
      //logD("_init() done");
    });
  }

  Future<void> dispose() async {
    logD("dispose()");
    await stateController.close();
    await stateSubscription?.cancel();
    await (await manager).destroyClient();
    _initDone = false;
  }

  Future<void> reinit() async {
    await dispose();
    await _init();
  }

  Future<void> _checkPermissions() async {
    logD("Checking permissions");
    if (!Platform.isAndroid) return;
    if (!await Permission.location.request().isGranted) {
      bleError(debugTag, "No location permission");
      return Future.error(Exception("$runtimeType Location permission not granted"));
    }
    if (!await Permission.bluetooth.request().isGranted) {
      bleError(debugTag, "No blootueth permission");
      return Future.error(Exception("$runtimeType Bluetooth permission not granted"));
    }
    logD("Checking permissions done");
  }

  Future<void> _checkClient() async {
    //logD("_checkClient() start");
    if (!_createClientCompleted) {
      while (!await BleManager().isClientCreated()) {
        // make sure createClient() is called only once
        if (!_createClientRequested) {
          _createClientRequested = true;
          logD("_checkClient() waiting for createClient");
          await BleManager().createClient();
          logD("_checkClient() createClient done");
          /*
          await Future.delayed(Duration(milliseconds: 500));
          // cycling radio
          logD("_checkClient() disabling radio");
          // don't await, the future never completes
          BleManager().disableRadio();
          await Future.delayed(Duration(milliseconds: 500));
          logD("_checkClient() enabling radio");
          await BleManager().enableRadio();
          logD("_checkClient() enabled radio");
          */
        }
        await Future.delayed(Duration(milliseconds: 500));
      }
      _createClientCompleted = true;
    }
    //logD("_checkClient() end");
    //return Future.value(null);
  }

  Future<void> _checkAdapter() async {
    logD("_checkAdaper()");
    await stateSubscription?.cancel();
    stateSubscription = BleManager()
        .observeBluetoothState()
        .handleError(
          (e) => bleError(debugTag, "observeBluetoothState()", e),
        )
        .listen(
      (state) async {
        logD("" + state.toString());
        _currentState = state;
        _currentStateInitialized = true;
        streamSendIfNotClosed(stateController, state);
        if (state == BluetoothState.POWERED_ON) {
          // Probably not a good idea to automatically scan, as of Android 7,
          // starting and stopping scans more than 5 times in a window of
          // 30 seconds will temporarily disable scanning
          //logD("Adapter powered on, starting scan");
          //startScan();
        } else {
          bleError(debugTag, "Adapter not powered on");
          /*
          if (Platform.isAndroid) {
            await bleManager.cancelTransaction("autoEnableBT");
            await bleManager
                .enableRadio(transactionId: "autoEnableBT")
                .catchError((e) => bleError(debugTag, "enableRadio()", e));
          }
          */
        }
      },
      onError: (e) => bleError(debugTag, "stateSubscription", e),
    );
    return Future.value(null);
  }

  Future<void> discover(Peripheral peripheral) async {
    await _exclusiveAccess.protect(() async {
      logD("discover($peripheral)");
      await peripheral.discoverAllServicesAndCharacteristics().catchError((e) {
        bleError(debugTag, "discoverAllServicesAndCharacteristics()", e);
      });
    });
  }

  Future<int?> requestMtu(Device device, int mtuRequest) async {
    String tag = "(${device.peripheral?.name}, $mtuRequest)";
    //logD("$tag");
    if (null == device.peripheral) {
      logD("$tag peripheral is null");
      return null;
    }
    return await _exclusiveAccess.protect<int>(() async {
      int result = await device.peripheral!.requestMtu(mtuRequest).catchError((e) {
        bleError(debugTag, tag, e);
        return 0;
      }).then((newMtu) {
        logD("$tag got MTU=$newMtu");
        device.mtu = newMtu;
        return newMtu;
      });
      return result;
    });
  }

  Future<void> enableRadio() async {
    (await manager).enableRadio();
  }

  Mutex get mutex => _exclusiveAccess;
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
      if (error.errorCode != null && error.errorCode.value != null) {
        info += " [code ${error.errorCode.value}";
        // TODO use reflection to auto parse error code
        switch (error.errorCode.value) {
          case BleErrorCode.operationCancelled:
            info += ": operationCancelled"; // 2
            break;
          case BleErrorCode.operationTimedOut: // 3
            info += ": operationTimedOut";
            break;
          case BleErrorCode.operationStartFailed: // 4
            info += ": operationStartFailed";
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
      String params = errorString.substring(
        errorString.indexOf("(") + 1,
        errorString.lastIndexOf(")"),
      );
      List<String> nonNull = [];
      params.split(", ").forEach((param) {
        List<String> kv = param.split(": ");
        if ((kv.length != 2 || kv.last != "null") && kv.first != "Error code") nonNull.add(param);
      });
      info += " {" + nonNull.join(", ") + "}";
    }
  }
  print("$tag Error: $message$info");
}

class BleAdapterCheck extends StatelessWidget with Debug {
  final Widget ifEnabled;
  final Widget Function(BluetoothState? state)? ifDisabled;

  /// Displays [ifEnabled] or [ifDisabled] depending on the current
  /// state of the bluetooth adapter.
  BleAdapterCheck(this.ifEnabled, {this.ifDisabled});

  @override
  Widget build(BuildContext context) {
    BLE ble = BLE();
    return StreamBuilder<BluetoothState>(
      stream: ble.stateStream,
      initialData: ble.currentStateSync(),
      builder: (BuildContext context, AsyncSnapshot<BluetoothState> snapshot) {
        return (snapshot.data == BluetoothState.POWERED_ON) ? ifEnabled : ifDisabled!(snapshot.data);
      },
    );
  }
}

class BleDisabled extends StatelessWidget with Debug {
  final BluetoothState? state;
  const BleDisabled(this.state);

  @override
  Widget build(BuildContext context) {
    String message = "";
    switch (state) {
      case BluetoothState.POWERED_OFF:
        message = "Enable to scan and connect";
        break;
      case BluetoothState.POWERED_ON:
        message = "powered on";
        break;
      case BluetoothState.RESETTING:
        message = "resetting";
        break;
      case BluetoothState.UNAUTHORIZED:
        message = "unauthorized";
        break;
      case BluetoothState.UNSUPPORTED:
        message = "unsupported";
        break;
      case BluetoothState.UNKNOWN:
      default:
        message = "unknown state";
        break;
    }
    return Container(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, // Align left
              children: [
                Row(
                  children: [
                    Text(
                      "Bluetooth is disabled",
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      message,
                      style: TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end, // Align right
            children: [
              EspmuiElevatedButton(
                child: Text("Enable"),
                onPressed: () {
                  logD("Radio enable button pressed");
                  BLE().enableRadio();
                },
              ),
            ],
          )
        ],
      ),
    );
  }
}
