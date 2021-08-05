// @dart=2.9
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

class Device extends StatefulWidget {
  DeviceState _state = DeviceState();

  Device({Peripheral peripheral, int rssi, double lastSeen}) {
    print("[Device] construct");
    update(peripheral, rssi, lastSeen);
  }

  void update(Peripheral peripheral, int rssi, double lastSeen) {
    print("[Device] update()");
    _state.peripheral = peripheral;
    _state.rssi = rssi;
    _state.lastSeen = lastSeen;
  }

  Peripheral get peripheral => _state.peripheral;
  String get name => _state.name;
  String get identifier => _state.identifier;

  int get rssi => _state.rssi;
  set rssi(int rssi) => _state.rssi = rssi;

  double get lastSeen => _state.lastSeen;
  set lastSeen(double lastSeen) => _state.lastSeen = lastSeen;

  void connect() => _state.connect();
  void disconnect() => _state.disconnect();

  @override
  DeviceState createState() {
    print("[Device] createState()");
    DeviceState oldState = _state;
    _state = DeviceState();
    update(oldState.peripheral, oldState.rssi, oldState.lastSeen);
    _state.connectionState = oldState.connectionState;
    return _state;
  }

  void dispose() => _state.dispose();
}

class DeviceState extends State<Device> {
  Peripheral peripheral;
  int rssi = 0;
  double lastSeen = 0;
  // connectionState
  PeripheralConnectionState connectionState =
      PeripheralConnectionState.disconnected;
  final StreamController<PeripheralConnectionState>
      _connectionStateStreamController =
      StreamController<PeripheralConnectionState>.broadcast();
  StreamSubscription<PeripheralConnectionState> _connectionStateSubscription;
  // battery
  CharacteristicWithValue _batteryCharacteristic;
  final StreamController<int> _batteryStreamController =
      StreamController<int>.broadcast();
  Stream<Uint8List> _batteryStream;
  StreamSubscription<Uint8List> _batteryStreamSubscription;

  String get name => peripheral.name;
  String get identifier => peripheral.identifier;

  DeviceState() {
    print("[DeviceState] construct");
  }

  @override
  void dispose() async {
    print("[DeviceState] ${peripheral.name} dispose");
    super.dispose();
    disconnect();
    await _connectionStateStreamController.close();
    await _batteryStreamController.close();
  }

  void connect() async {
    _connectionStateSubscription = peripheral
        .observeConnectionState(
      emitCurrentValue: true,
      completeOnDisconnect: true,
    )
        .listen((state) {
      connectionState = state;
      print("[_connectionStateSubscription] ${peripheral.name} $state");
      if (_connectionStateStreamController.isClosed)
        print("[connect()] Error: connState stream is closed");
      else
        _connectionStateStreamController.sink.add(state);
    });
    if (!await peripheral.isConnected()) {
      print("[connect()] Connecting to ${peripheral.name}");
      try {
        await peripheral.connect();
      } catch (e) {
        print("[connect()] peripheral.connect() error: ${e.toString()}");
      }
    } else
      print(
          "[connect()] Not connecting to ${peripheral.name}, already connected");
    try {
      await peripheral.discoverAllServicesAndCharacteristics();
      _batteryCharacteristic = await peripheral.readCharacteristic(
          "0000180F-0000-1000-8000-00805F9B34FB",
          "00002A19-0000-1000-8000-00805F9B34FB");
      _batteryStream = _batteryCharacteristic.monitor().asBroadcastStream();
      _batteryStreamSubscription = _batteryStream.listen((value) {
        if (_batteryStreamController.isClosed)
          print("[_batteryStreamSubscription] Error: stream is closed");
        else
          print("[_batteryStreamSubscription] " + value.toString());
        _batteryStreamController.sink.add(value.first);
      });
    } catch (e) {
      print("[connect()] Error: ${e.toString()}");
    }
  }

  void disconnect() async {
    print("[DeviceState] disconnect() ${peripheral.name}");
    try {
      await peripheral.disconnectOrCancelConnection();
      if (_batteryStreamSubscription != null)
        await _batteryStreamSubscription.cancel();
      if (_connectionStateSubscription != null)
        await _connectionStateSubscription.cancel();
      //connectionState = PeripheralConnectionState.disconnected;
    } catch (e) {
      print("[DeviceState] disconnect() Error: ${e.toString()}");
    }
  }

  Future<bool> _onBackPressed() {
    disconnect();
    return Future.value(true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        appBar: _appBar(),
        body: Container(
          margin: EdgeInsets.all(6),
          child: _deviceProperties(),
        ),
      ),
    );
  }

  AppBar _appBar() {
    return AppBar(
      title: Container(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, // Align left
                children: [
                  Row(children: [
                    Text(peripheral.name),
                  ]),
                  Row(
                    children: [
                      _status(),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end, // Align right
              children: [_connectButton()],
            )
          ],
        ),
      ),
    );
  }

  Widget _status() {
    return StreamBuilder<PeripheralConnectionState>(
      stream: _connectionStateStreamController.stream,
      initialData: connectionState,
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState> snapshot) {
        String connState = snapshot.data.toString();
        print("[DeviceState._status()] state: $connState");
        return Text(
          connState.substring(connState.lastIndexOf(".") + 1),
          style: TextStyle(fontSize: 10),
        );
      },
    );
  }

  Widget _connectButton() {
    return StreamBuilder<PeripheralConnectionState>(
      stream: _connectionStateStreamController.stream,
      initialData: connectionState,
      builder: (BuildContext context,
          AsyncSnapshot<PeripheralConnectionState> snapshot) {
        Function action;
        String label = "Connect";
        if (snapshot.data == PeripheralConnectionState.connected) {
          action = disconnect;
          label = "Disconnect";
        }
        if (snapshot.data == PeripheralConnectionState.disconnected)
          action = connect;
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
      },
    );
  }

  Widget _deviceProperties() {
    return StreamBuilder<int>(
      stream: _batteryStreamController.stream,
      initialData: _batteryCharacteristic != null
          ? _batteryCharacteristic.value.first
          : 0,
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return Text("Battery: ${snapshot.data > 0 ? snapshot.data : "?"}%");
      },
    );
  }
}
