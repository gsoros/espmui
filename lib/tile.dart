import 'dart:async';
import 'dart:convert';
//import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_ble_lib/flutter_ble_lib.dart';

import 'preferences.dart';
import 'device.dart';
import 'device_list.dart';
import 'ble_characteristic.dart';
import 'util.dart';
import 'debug.dart';

class Tile extends StatelessWidget with Debug {
  final Color color;
  final Color textColor;
  final int width;
  final int height;
  final String device;
  final String stream;

  /// tap action
  final String tap;

  /// history length in seconds
  final int history;

  Tile({
    Key? key,
    this.color = Colors.red,
    this.textColor = Colors.white,
    this.width = 5,
    this.height = 2,
    this.device = "",
    this.stream = "",
    this.tap = "",
    this.history = 0,
  }) : super(key: key);

  Tile.from(
    Tile other, {
    Key? key,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    String? device,
    String? stream,
    String? tap,
    int? history,
  }) : this(
          key: key ?? other.key,
          color: color ?? other.color,
          textColor: textColor ?? other.textColor,
          width: colSpan ?? other.width,
          height: height ?? other.height,
          device: device ?? other.device,
          stream: stream ?? other.stream,
          tap: tap ?? other.tap,
          history: history ?? other.history,
        );

  Tile copyWith(
    Key? key,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    String? device,
    String? stream,
    String? tap,
  ) {
    return Tile.from(
      this,
      key: key ?? this.key,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
      colSpan: colSpan ?? this.width,
      height: height ?? this.height,
      device: device ?? this.device,
      stream: stream ?? this.stream,
      tap: tap ?? this.tap,
    );
  }

  Tile.fromJson(Map<String, dynamic> json)
      : color = Color(json['color']),
        textColor = Color(json['textColor']),
        width = json['colSpan'] ?? 3,
        height = json['height'] ?? 3,
        device = json['device'] ?? "",
        stream = json['stream'] ?? "",
        tap = json['tap'] ?? "",
        history = json['history'] ?? 0;

  Map<String, dynamic> toJson() => {
        'color': color.value,
        'textColor': textColor.value,
        'colSpan': width,
        'height': height,
        'device': device,
        'stream': stream,
        'tap': tap,
        'history': history,
      };

  @override
  Widget build(BuildContext context) {
    double sizeUnit = MediaQuery.of(context).size.width / 10;
    Device? device = DeviceList().byIdentifier(this.device);
    //if (null == device) return Text("No device");
    //if (!device?.tileStreams.containsKey(this.stream)) return Text("No stream");
    DeviceTileStream? stream = device?.tileStreams[this.stream];
    //if (null == stream) return Text("Invalid source");
    //debugLog("build device: ${device?.name ?? 'null'} dl.l: ${DeviceList().devices.length}");

    Widget getValue() {
      return StreamBuilder<String>(
        stream: stream?.stream,
        initialData: stream?.initialData != null ? stream?.initialData!() : null,
        builder: (_, snapshot) {
          //debugLog("Tile build getValue ${device.name} ${source.label} ${snapshot.data}");
          return Text(snapshot.hasData ? snapshot.data.toString() : " ");
        },
      );
    }

    Widget getValueWhenConnected() {
      return StreamBuilder<PeripheralConnectionState>(
        stream: device?.stateStream,
        initialData: device?.lastConnectionState,
        builder: (_, snapshot) {
          //debugLog("Tile build getValueWhenConnected ${device.name} ${source.label} ${snapshot.data}");
          if (!snapshot.hasData || snapshot.data == null || snapshot.data == PeripheralConnectionState.connected) return getValue();
          if (snapshot.data == PeripheralConnectionState.disconnected) return Empty();
          return CircularProgressIndicator();
        },
      );
    }

    Widget background() {
      if (0 == history) return Empty();
      CharacteristicHistory? charHistory = DeviceList().byIdentifier(this.device)?.tileStreams[this.stream]?.history;
      if (null == charHistory) return Empty();
      return StreamBuilder<String>(
        stream: stream?.stream,
        initialData: stream?.initialData != null ? stream?.initialData!() : null,
        builder: (_, snapshot) {
          return charHistory.graph(timestamp: uts() - history * 1000);
        },
      );
    }

    return Material(
      child: Container(
        padding: const EdgeInsets.all(2.0),
        height: height * sizeUnit,
        width: width * sizeUnit,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5.0),
          ),
          padding: const EdgeInsets.all(4.0),
          child: Column(
            //crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${stream?.label ?? ''} (${device?.name ?? 'No source'})",
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(fontSize: 10, color: textColor),
                    ),
                  ),
                  /*
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        " ",
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 10, color: textColor),
                      ),
                    ),
                  ),
                  */
                ],
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  alignment: AlignmentDirectional.bottomEnd,
                  children: [
                    FittedBox(
                      child: background(),
                      fit: BoxFit.fill,
                    ),
                    Align(
                      child: FittedBox(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: textColor,
                            fontSize: 120,
                          ),
                          child: getValueWhenConnected(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  /*
                  Expanded(
                    child: Text(
                      " ",
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(fontSize: 10, color: textColor),
                    ),
                  ),
                  */
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        stream?.units ?? " ",
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 10, color: textColor),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Singleton class
class TileList with Debug {
  static final TileList _instance = TileList._construct();
  static int _instances = 0;
  var notifier = AlwaysNotifier<List<Tile>>([]);
  List<Tile> get tiles => notifier.value;

  set tiles(List<Tile> tileList) {
    notifier.value = tileList;
  }

  Tile? operator [](int i) => tiles[i];
  operator []=(int i, Tile tile) {
    tiles[i] = tile;
    notifier.notifyListeners();
  }

  void clear() {
    tiles.clear();
    notifier.notifyListeners();
  }

  void add(Tile tile) {
    tiles.add(tile);
    notifier.notifyListeners();
  }

  void removeWhere(bool Function(Tile) test) {
    tiles.removeWhere(test);
    notifier.notifyListeners();
  }

  void insert(int index, Tile tile) {
    tiles.insert(index, tile);
    notifier.notifyListeners();
  }

  Timer? _saveTimer;

  /// returns a singleton
  factory TileList() {
    return _instance;
  }

  TileList._construct() {
    _instances++;
    debugLog('_construct() # of instances: $_instances');
    load();
  }

  Future<void> load() async {
    //debugLog("load() start");
    await DeviceList().load();
    _fromJsonStringList((await Preferences().getTiles()).value);
    //debugLog("load() end");
    notifier.notifyListeners();
  }

  void save([bool delayed = true]) async {
    if (delayed) {
      dev.log(_saveTimer == null ? '$runtimeType new save timer' : '$runtimeType updating save timer');
      _saveTimer?.cancel();
      _saveTimer = Timer(Duration(seconds: 1), () {
        save(false);
      });
      return;
    }
    Preferences().setTiles(toJsonStringList());
    _saveTimer = null;
  }

  void _fromJsonStringList(List<String> json) {
    tiles.clear();
    json.forEach((tileString) {
      tiles.add(Tile.fromJson(jsonDecode(tileString)));
    });
  }

  List<String> toJsonStringList() {
    List<String> tileString = [];
    tiles.forEach((tile) {
      tileString.add(jsonEncode(tile.toJson()));
    });
    return tileString;
  }

  int get length => tiles.length;
}
