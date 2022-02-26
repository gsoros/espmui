import 'dart:async';
import 'dart:developer' as dev;

//import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mutex/mutex.dart';

import 'util.dart';

class Preferences {
  static final Preferences _instance = Preferences._construct();
  late final SharedPreferences _sharedPreferences;
  bool _initDone = false;
  final _exclusiveAccess = Mutex();

  /* Devices */
  var _devices = AlwaysNotifier<List<String>>([]);

  Future<AlwaysNotifier<List<String>>> getDevices() async {
    await _init();
    return _devices;
  }

  void setDevices(List<String> devices) async {
    await _init();
    dev.log('$runtimeType setDevices($devices)');
    _devices.value = devices;
    _sharedPreferences.setStringList('devices', devices);
  }

  /* Tiles */
  List<String> _tiles = [];

  Future<List<String>> getTiles() async {
    await _init();
    return _tiles;
  }

  void setTiles(List<String> tiles) async {
    await _init();
    _tiles = tiles;
    _sharedPreferences.setStringList('tiles', tiles);
    dev.log('$runtimeType saved tiles: $tiles');
  }

  Future<void> _init() async {
    dev.log('$runtimeType init step 1');
    if (_initDone) return;
    await _exclusiveAccess.protect(() async {
      if (_initDone) return;
      _sharedPreferences = await SharedPreferences.getInstance();
      _devices.value = _sharedPreferences.getStringList('devices') ?? [];
      _devices.addListener(() {
        dev.log('$runtimeType _devicesNotifier listener ${_devices.value}');
      });
      _tiles = _sharedPreferences.getStringList('tiles') ?? [];
      _initDone = true;
    });
  }

  /// returns a singleton
  factory Preferences() {
    return _instance;
  }

  Preferences._construct() {
    dev.log('$runtimeType _construct()');
    _init();
  }
}
