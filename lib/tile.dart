import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

import 'preferences.dart';
import 'util.dart';

class Tile extends StatelessWidget {
  final String name;
  final Color color;
  final Color textColor;
  final int colSpan;
  final int height;
  final Widget value;
  final Widget background;
  final String sourceDevice;
  final String sourceStream;

  Tile({
    Key? key,
    this.name = "unnamed",
    this.color = Colors.red,
    this.textColor = Colors.white,
    this.colSpan = 5,
    this.height = 2,
    this.value = const Text(""),
    this.background = const Text(""),
    this.sourceDevice = "",
    this.sourceStream = "",
  }) : super(key: key);

  Tile.random({Key? key})
      : this(
          key: key,
          name: "Tile ${Random().nextInt(1000).toString()}",
          color: Color((Random().nextDouble() * 0xffffff).toInt()).withOpacity(1.0),
          textColor: Colors.white,
          //textColor: Color((Random().nextDouble() * 0xffffff).toInt()).withOpacity(1.0),
          colSpan: Random().nextInt(9) + 2,
          height: Random().nextInt(3) + 2,
          value: Text("${Random().nextInt(20000).toString()}"),
          background: Graph.random(),
        );

  Tile.from(
    Tile other, {
    Key? key,
    String? name,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    Widget? value,
    Widget? background,
    String? sourceDevice,
    String? sourceStream,
  }) : this(
          key: key ?? other.key,
          name: name ?? other.name,
          color: color ?? other.color,
          textColor: textColor ?? other.textColor,
          colSpan: colSpan ?? other.colSpan,
          height: height ?? other.height,
          value: value ?? other.value,
          sourceDevice: sourceDevice ?? other.sourceDevice,
          sourceStream: sourceStream ?? other.sourceStream,
        );

  Tile copyWith(
    Key? key,
    String? name,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    Widget? value,
    Widget? background,
  ) {
    return Tile.from(
      this,
      key: key ?? this.key,
      name: name ?? this.name,
      color: color ?? this.color,
      textColor: textColor ?? this.textColor,
      colSpan: colSpan ?? this.colSpan,
      height: height ?? this.height,
      value: value ?? this.value,
      background: background ?? this.background,
    );
  }

  Tile.fromJson(Map<String, dynamic> json)
      : name = json['name'] ?? "unnamed",
        color = Color(json['color']),
        textColor = Color(json['textColor']),
        colSpan = json['colSpan'] ?? 3,
        height = json['height'] ?? 3,
        background = Graph(),
        value = Text('Loading...'),
        sourceDevice = json['sourceDevice'] ?? "",
        sourceStream = json['sourceStream'] ?? "";

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': color.value,
        'textColor': textColor.value,
        'colSpan': colSpan,
        'height': height,
        'sourceDevice': sourceDevice,
        'sourceStream': sourceStream,
      };

  @override
  Widget build(BuildContext context) {
    var sizeUnit = MediaQuery.of(context).size.width / 10;
    return Material(
      child: Container(
        padding: const EdgeInsets.all(2.0),
        height: height * sizeUnit,
        width: colSpan * sizeUnit,
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
                      name,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(fontSize: 10, color: textColor),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        "topRight",
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: TextStyle(fontSize: 10, color: textColor),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  alignment: AlignmentDirectional.bottomEnd,
                  children: [
                    FittedBox(child: background, fit: BoxFit.scaleDown),
                    Align(
                      child: FittedBox(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: textColor,
                            fontSize: 120,
                          ),
                          child: value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "bottomLeft",
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: TextStyle(fontSize: 10, color: textColor),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Text(
                        "bottomRight",
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

class Graph extends StatelessWidget {
  const Graph({Key? key}) : super(key: key);
  const Graph.random({Key? key}) : this();

  @override
  Widget build(BuildContext context) {
    var widgets = <Widget>[];
    for (int i = 0; i < 10; i++)
      widgets.add(Container(
        width: 50,
        height: Random().nextDouble() * 1000,
        color: Colors.red.withOpacity(.5),
        margin: EdgeInsets.all(1),
      ));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: widgets,
    );
  }
}

/// Singleton class
class TileList {
  static final TileList _instance = TileList._construct();
  var notifier = AlwaysNotifier<List<Tile>>([]);
  List<Tile> get tiles => notifier.value;

  set tiles(List<Tile> tileList) {
    notifier.value = tileList;
  }

  Tile operator [](int i) => tiles[i];

  Timer? _saveTimer;

  /// returns a singleton
  factory TileList() {
    return _instance;
  }

  TileList._construct() {
    dev.log('$runtimeType _construct()');
    load();
  }

  Future<void> load() async {
    _fromJsonStringList((await Preferences().getTiles()).value);
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
