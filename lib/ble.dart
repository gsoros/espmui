// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mutex/mutex.dart';

import 'util.dart';
import 'debug.dart';
import 'device.dart';
//import 'scanner.dart';

/// singleton class
class BLE with Debug {
  static final BLE _instance = BLE._construct();
  final _manager = FlutterReactiveBle();
  bool _initDone = false;
  final _exclusiveAccess = Mutex();

  /// returns a singleton
  factory BLE() {
    return _instance;
  }

  // status
  StreamSubscription<BleStatus>? statusSubscription;
  final statusStreamController = StreamController<BleStatus>.broadcast();
  Stream<BleStatus> get statusStream => statusStreamController.stream;
  BleStatus _currentStatus = BleStatus.unknown;

  Future<BleStatus> currentStatus() async {
    _currentStatus = (await manager).status;
    return Future.value(_currentStatus);
  }

  Future<FlutterReactiveBle> get manager async {
    //logD("get manager");
    await _init();
    return _manager;
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
      //logD("_init() calling _checkAdapter()");
      await _checkAdapter();
      _initDone = true;
      //logD("_init() done");
    });
  }

  Future<void> dispose() async {
    logD("dispose()");
    await statusStreamController.close();
    await statusSubscription?.cancel();
    await (await manager).deinitialize();
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
      logD('No bluetooth (<= Android 10) permission');
      if (!await Permission.bluetoothScan.request().isGranted) {
        bleError(debugTag, "No blootueth scan permission");
        return Future.error(Exception("$runtimeType Bluetooth scan permission not granted"));
      }
      if (!await Permission.bluetoothConnect.request().isGranted) {
        bleError(debugTag, "No blootueth connect permission");
        return Future.error(Exception("$runtimeType Bluetooth connect permission not granted"));
      }
    }
    /*
    if (!await Permission.bluetoothScan.request().isGranted) {
      bleError(debugTag, "No blootueth scan permission");
      return Future.error(Exception("$runtimeType Bluetooth scan permission not granted"));
    }
    if (!await Permission.bluetoothConnect.request().isGranted) {
      bleError(debugTag, "No blootueth connect permission");
      return Future.error(Exception("$runtimeType Bluetooth connect permission not granted"));
    }
    */
    logD("Checking permissions done");
  }

  Future<void> _checkAdapter() async {
    logD('_checkAdaper()');

    logD('await statusSubscription?.cancel();');
    await statusSubscription?.cancel();
    logD('statusSubscription = _manager...');
    statusSubscription = _manager.statusStream.listen(
      (status) {
        frbOnAdapterStatusUpdate(status);
      },
      onError: (e) => bleError(debugTag, "statusSubscription", e),
    );
    logD('frbOnAdapterStatusUpdate(_manager.status);');
    frbOnAdapterStatusUpdate(_manager.status);
    logD('_checkAdaper() done');
    return Future.value(null);
  }

  /// flutter_reactive_ble adapter status update
  void frbOnAdapterStatusUpdate(BleStatus status) {
    logD('status: $status');
    _currentStatus = status;
    statusStreamController.sink.add(status);
    if (status == BleStatus.ready) {
      // Probably not a good idea to automatically scan, as of Android 7,
      // starting and stopping scans more than 5 times in a window of
      // 30 seconds will temporarily disable scanning
      //logD("Adapter powered on, starting scan");
      //startScan();
    } else {
      bleError(debugTag, "Adapter not ready");
      /*
          if (Platform.isAndroid) {
            await bleManager.cancelTransaction("autoEnableBT");
            await bleManager
                .enableRadio(transactionId: "autoEnableBT")
                .catchError((e) => bleError(debugTag, "enableRadio()", e));
          }
          */
    }
  }

  Future<int?> requestMtu(Device device, int mtuRequest) async {
    String tag = "(${device.name}, $mtuRequest)";
    //logD("$tag");
    return await _exclusiveAccess.protect<int>(() async {
      int result = await (await manager).requestMtu(deviceId: device.id, mtu: mtuRequest).catchError((e) {
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
    logD('not available on FRB');
    // (await manager).enableRadio();
  }

  Mutex get mutex => _exclusiveAccess;
}

/// https://github.com/dotintent/FlutterBleLib/blob/develop/lib/error/ble_error.dart
void bleError(String tag, String message, [dynamic error]) {
  String info = "";
  /*
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
  */
  print("$tag Error: $message$info $error");
}

class BleAdapterCheck extends StatelessWidget with Debug {
  final Widget ifReady;
  final Widget Function(BleStatus? status)? ifNotReady;

  /// Displays [ifEnabled] or [ifDisabled] depending on the current
  /// state of the bluetooth adapter.
  BleAdapterCheck(this.ifReady, {super.key, this.ifNotReady});

  @override
  Widget build(BuildContext context) {
    BLE ble = BLE();
    return StreamBuilder<BleStatus>(
      stream: ble.statusStream,
      initialData: ble._currentStatus,
      builder: (BuildContext context, AsyncSnapshot<BleStatus> snapshot) {
        if (snapshot.data == BleStatus.ready) return ifReady;
        return null != ifNotReady ? ifNotReady!(snapshot.data) : const Text('Not ready');
      },
    );
  }
}

class BleNotReady extends StatelessWidget with Debug {
  final BleStatus? status;
  const BleNotReady(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    String message = "";
    switch (status) {
      case BleStatus.poweredOff:
        message = "Enable to scan and connect";
        break;
      case BleStatus.ready:
        message = "ready";
        break;
      case BleStatus.locationServicesDisabled:
        message = "Location Services Disabled";
        break;
      case BleStatus.unauthorized:
        message = "unauthorized";
        break;
      case BleStatus.unsupported:
        message = "unsupported";
        break;
      case BleStatus.unknown:
      default:
        message = "unknown state";
        break;
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, // Align left
            children: [
              const Row(
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
                    style: const TextStyle(fontSize: 10),
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
              child: const Text("Press me"),
              onPressed: () {
                logD("Radio enable button pressed");
                //BLE().enableRadio();
              },
            ),
          ],
        )
      ],
    );
  }
}
