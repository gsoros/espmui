import 'dart:async';
import 'dart:convert';
//import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'preferences.dart';
import 'device.dart';
import 'device_list.dart';
//import 'ble_characteristic.dart';
import 'util.dart';
import 'debug.dart';

class Tile extends StatelessWidget with Debug {
  final Color color;
  final Color textColor;
  final int width;
  final int height;
  final String device;
  final String stream;
  final bool showDeviceName;

  /// tap action
  final String tap;

  /// history length in seconds
  final int history;

  Tile({
    super.key,
    this.color = Colors.black54,
    this.textColor = Colors.white,
    this.width = 5,
    this.height = 2,
    this.device = "",
    this.stream = "",
    this.tap = "",
    this.history = 0,
    this.showDeviceName = true,
  });

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
    bool? showDeviceName,
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
          showDeviceName: showDeviceName ?? other.showDeviceName,
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
    int? history,
    bool? showDeviceName,
  ) {
    return Tile.from(
      this,
      key: key ?? this.key,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
      colSpan: colSpan ?? width,
      height: height ?? this.height,
      device: device ?? this.device,
      stream: stream ?? this.stream,
      tap: tap ?? this.tap,
      history: history ?? this.history,
      showDeviceName: showDeviceName ?? this.showDeviceName,
    );
  }

  Tile.fromJson(Map<String, dynamic> json, {super.key})
      : color = Color(json['color']),
        textColor = Color(json['textColor']),
        width = json['colSpan'] ?? 3,
        height = json['height'] ?? 3,
        device = json['device'] ?? "",
        stream = json['stream'] ?? "",
        tap = json['tap'] ?? "",
        history = json['history'] ?? 0,
        showDeviceName = json["showDeviceName"] ?? true;

  Map<String, dynamic> toJson() => {
        'color': color.value,
        'textColor': textColor.value,
        'colSpan': width,
        'height': height,
        'device': device,
        'stream': stream,
        'tap': tap,
        'history': history,
        'showDeviceName': showDeviceName,
      };

  @override
  Widget build(BuildContext context) {
    double sizeUnit = MediaQuery.of(context).size.width / 10;
    Device? device = DeviceList().byIdentifier(this.device);
    //if (null == device) return Text("No device");
    //if (!device?.tileStreams.containsKey(this.stream)) return Text("No stream");
    DeviceTileStream? stream = device?.tileStreams[this.stream];
    //if (null == stream) return Text("Invalid source");
    //logD("build device: ${device?.name ?? 'null'} dl.l: ${DeviceList().devices.length}");

    Widget getValue() {
      return StreamBuilder<Widget>(
        stream: stream?.stream,
        initialData: stream?.initialData != null ? stream?.initialData!() : null,
        builder: (_, snapshot) {
          if (!snapshot.hasData || (null == snapshot.data) || ('Text("")' == snapshot.data.toString())) return const Empty();
          //logD('snapshot.data: ' + snapshot.data.toString());
          return snapshot.data!;
        },
      );
    }

    Widget getValueIfConnected() {
      return StreamBuilder<DeviceConnectionState>(
        stream: device?.stateStream,
        initialData: device?.lastConnectionState,
        builder: (_, snapshot) {
          //logD("Tile build getValueIfConnected ${device?.name} ${stream?.label} ${snapshot.data}");
          if (!snapshot.hasData || snapshot.data == null || snapshot.data == DeviceConnectionState.connected) return getValue();
          if (snapshot.data == DeviceConnectionState.disconnected) return const Empty();
          return const CircularProgressIndicator();
        },
      );
    }

    Widget background() {
      if (0 == history) return const Empty();
      History? charHistory = DeviceList().byIdentifier(this.device)?.tileStreams[this.stream]?.history;
      if (null == charHistory) return const Empty();
      return StreamBuilder<Widget>(
        stream: stream?.stream,
        initialData: stream?.initialData != null ? stream?.initialData!() : null,
        builder: (_, snapshot) {
          return charHistory.graph(
            timestamp: uts() - history * 1000,
            color: Color.fromARGB(
              127,
              ((255 - color.blue)).round(),
              ((255 - color.red)).round(),
              ((255 - color.green)).round(),
            ),
          );
        },
      );
    }

    String label = stream?.label ?? '';
    if (showDeviceName) label += ' ${device?.name ?? 'No source'}';

    var rows = <Widget>[];
    int dataRowFlex = null == stream?.units ? 6 : 5;
    if (label.isNotEmpty) {
      dataRowFlex--;
      rows.add(
        // label row
        Flexible(
          flex: 1,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: TextStyle(fontSize: 10, color: textColor.withAlpha(100)),
                ),
              ),
            ],
          ),
        ),
      );
    }
    rows.add(
      // data row
      Flexible(
        flex: dataRowFlex,
        child: Stack(
          fit: StackFit.expand,
          alignment: AlignmentDirectional.bottomEnd,
          children: [
            FittedBox(
              fit: BoxFit.fill,
              child: background(),
            ),
            FittedBox(
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: textColor,
                  fontSize: 120,
                ),
                child: getValueIfConnected(),
              ),
            ),
          ],
        ),
      ),
    );
    if (null != stream?.units) {
      rows.add(
        // footer row
        Flexible(
          flex: 1,
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    stream?.units ?? ' ',
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(fontSize: 10, color: textColor.withAlpha(100)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      child: Container(
        //padding: const EdgeInsets.all(2.0),
        height: height * sizeUnit,
        width: width * sizeUnit,
        decoration: BoxDecoration(
          color: color,
          //borderRadius: BorderRadius.circular(5.0),
        ),
        //padding: const EdgeInsets.all(4.0),
        child: Column(
          //mainAxisSize: MainAxisSize.min,
          //crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
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

  int add(Tile tile) {
    tiles.add(tile);
    notifier.notifyListeners();
    return tiles.length;
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
    logD('_construct() # of instances: $_instances');
    load();
  }

  Future<void> load() async {
    //logD("load() start");
    await DeviceList().load();
    _fromJsonStringList((await Preferences().getTiles()).value);
    //logD("load() end");
    notifier.notifyListeners();
  }

  void save([bool delayed = true]) async {
    if (delayed) {
      dev.log(_saveTimer == null ? '$runtimeType new save timer' : '$runtimeType updating save timer');
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(seconds: 1), () {
        save(false);
      });
      return;
    }
    Preferences().setTiles(toJsonStringList());
    _saveTimer = null;
  }

  void _fromJsonStringList(List<String> json) {
    tiles.clear();
    for (var tileString in json) {
      tiles.add(Tile.fromJson(jsonDecode(tileString)));
    }
  }

  List<String> toJsonStringList() {
    List<String> tileString = [];
    for (var tile in tiles) {
      tileString.add(jsonEncode(tile.toJson()));
    }
    return tileString;
  }

  int get length => tiles.length;
}
