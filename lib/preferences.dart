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
    _devices.value = devices;
    _sharedPreferences.setStringList('devices', devices);
    dev.log('$runtimeType setDevices $devices');
  }

  /* Tiles */
  var _tiles = AlwaysNotifier<List<String>>([]);

  Future<AlwaysNotifier<List<String>>> getTiles() async {
    await _init();
    return _tiles;
  }

  void setTiles(List<String> tiles) async {
    await _init();
    _tiles.value = tiles;
    _sharedPreferences.setStringList('tiles', tiles);
    dev.log('$runtimeType setTiles $tiles');
  }

  Future<void> _init() async {
    dev.log('$runtimeType init step 1');
    if (_initDone) return;
    await _exclusiveAccess.protect(() async {
      if (_initDone) return;
      dev.log('$runtimeType init step 2');
      _sharedPreferences = await SharedPreferences.getInstance();
      _devices.value = _sharedPreferences.getStringList('devices') ?? [];
      _devices.addListener(() {
        dev.log('$runtimeType _devicesNotifier listener ${_devices.value}');
      });
      _tiles.value = _sharedPreferences.getStringList('tiles') ?? [];
      _tiles.addListener(() {
        dev.log('$runtimeType _tilesNotifier listener ${_tiles.value}');
      });
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
