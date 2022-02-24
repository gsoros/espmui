import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:espmui/preferences.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_circle_color_picker/flutter_circle_color_picker.dart';

// import 'package:espmui/util.dart';
import 'package:espmui/scanner_route.dart';

class SensorsRoute extends StatefulWidget {
  const SensorsRoute({Key? key}) : super(key: key);

  @override
  _SensorsRouteState createState() => _SensorsRouteState();
}

class _SensorsRouteState extends State<SensorsRoute> {
  static const String tag = '[_SensorsRouteState]';
  bool _fabVisible = false;
  Timer? _fabTimer;

  var _tiles = SensorTileList();

  @override
  void initState() {
    dev.log("_SensorsRouteState initState");
    super.initState();
  }

  Future<void> _showFab(dynamic _) async {
    debugPrint("showFab");
    setState(() {
      _fabVisible = true;
    });
    _fabTimer?.cancel();
    _fabTimer = Timer(Duration(seconds: 3), () {
      debugPrint("hide Fab");
      setState(() {
        _fabVisible = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _showFab,
      onVerticalDragDown: _showFab,
      child: Scaffold(
        floatingActionButton: _fabVisible
            ? FloatingActionButton(
                onPressed: () {
                  print("fab pressed");
                  Navigator.push(
                    context,
                    HeroDialogRoute(
                      builder: (BuildContext context) {
                        return Center(
                          child: AlertDialog(
                            title: Hero(tag: 'fab', child: Icon(Icons.settings)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 150.0,
                                  height: 50.0,
                                  child: ElevatedButton(
                                      onPressed: () => setState(() {
                                            dev.log('$tag calling SensorTileList(fromPreferences: true)');
                                            _tiles = SensorTileList(
                                              key: UniqueKey(),
                                              mode: 'fromPreferences',
                                            );
                                          }),
                                      child: Text("Load tiles")),
                                ),
                                Container(
                                  width: 150.0,
                                  height: 50.0,
                                  margin: EdgeInsets.only(top: 30),
                                  child: ElevatedButton(
                                      onPressed: () => setState(() {
                                            _tiles = SensorTileList(
                                              key: UniqueKey(),
                                              mode: 'random',
                                            );
                                          }),
                                      child: Text("Randomize tiles")),
                                ),
                                Container(
                                  width: 150.0,
                                  height: 50.0,
                                  margin: EdgeInsets.only(top: 30),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context).pop(); // close dialog
                                      Navigator.push(
                                        context,
                                        PageTransition(
                                          type: PageTransitionType.rightToLeft,
                                          child: ScannerRoute(),
                                        ),
                                      );
                                    },
                                    child: Text("Devices"),
                                  ),
                                ),
                              ],
                            ),
                            actions: <Widget>[
                              TextButton(
                                child: Text('Close'),
                                onPressed: Navigator.of(context).pop,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  );
                },
                child: Icon(Icons.settings),
                heroTag: "fab",
              )
            : Container(),
        body: SafeArea(
          child: _tiles,
        ),
      ),
    );
  }
}

class SensorTile extends StatelessWidget {
  final String name;
  final Color color;
  final Color textColor;
  final int colSpan;
  final int height;
  final Widget value;
  final Widget background;

  SensorTile({
    Key? key,
    this.name = "unnamed",
    this.color = Colors.red,
    this.textColor = Colors.white,
    this.colSpan = 5,
    this.height = 2,
    this.value = const Text(""),
    this.background = const Text(""),
  }) : super(key: key);

  SensorTile.random({Key? key})
      : this(
          key: key,
          name: "Sensor ${Random().nextInt(1000).toString()}",
          color: Color((Random().nextDouble() * 0xffffff).toInt()).withOpacity(1.0),
          textColor: Colors.white,
          //textColor: Color((Random().nextDouble() * 0xffffff).toInt()).withOpacity(1.0),
          colSpan: Random().nextInt(9) + 2,
          height: Random().nextInt(3) + 2,
          value: Text("${Random().nextInt(20000).toString()}"),
          background: Graph.random(),
        );

  SensorTile.from(
    SensorTile other, {
    Key? key,
    String? name,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    Widget? value,
    Widget? background,
  }) : this(
          key: key ?? other.key,
          name: name ?? other.name,
          color: color ?? other.color,
          textColor: textColor ?? other.textColor,
          colSpan: colSpan ?? other.colSpan,
          height: height ?? other.height,
          value: value ?? other.value,
          background: background ?? other.background,
        );

  SensorTile copyWith(
    Key? key,
    String? name,
    Color? color,
    Color? textColor,
    int? colSpan,
    int? height,
    Widget? value,
    Widget? background,
  ) {
    return SensorTile.from(
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

  SensorTile.fromJson(Map<String, dynamic> json)
      : name = json['name'],
        color = Color(json['color']),
        textColor = Color(json['textColor']),
        colSpan = json['colSpan'],
        height = json['height'],
        background = Graph(),
        value = Text('Loading...');

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': color.value,
        'textColor': textColor.value,
        'colSpan': colSpan,
        'height': height,
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

class SensorTileList extends StatefulWidget {
  static const String tag = '[SensorTileList]';
  final String mode;

  const SensorTileList({
    Key? key,
    this.mode = 'fromPreferences',
  }) : super(key: key);

  @override
  _SensorTileListState createState() {
    dev.log('$tag createState()');
    _SensorTileListState state = _SensorTileListState();
    if (mode == 'fromPreferences')
      state._loadFromPreferences();
    else if (mode == 'random') state._randomize();
    return state;
  }
}

class _SensorTileListState extends State<SensorTileList> {
  static const String tag = '[_SensorTileListState]';
  var _tiles = <SensorTile>[];
  Timer? _saveToPreferencesTimer;
  double dialogOpacity = 1;
  bool colorPicker = false;
  void Function(Color)? colorPickerCallback;
  Color? colorPickerInitialColor;

  @override
  void initState() {
    dev.log('$tag initState');
    super.initState();
  }

  void _randomize() {
    dev.log('$tag _randomize');
    _tiles.clear();
    for (var i = 0; i < 5; i++) {
      SensorTile tile = SensorTile.random();
      _tiles.add(tile);
    }
  }

  void _moveTile(SensorTile tile, int index) {
    dev.log('$tag reorder tile:${tile.name} newIndex:$index');
    setState(() {
      _tiles.removeWhere((existing) => existing.hashCode == tile.hashCode);
      _tiles.insert(index, tile);
    });
    //_savePreferences();
  }

  void _saveToPreferences([bool delayed = true]) async {
    if (delayed) {
      dev.log(_saveToPreferencesTimer == null ? '$tag new savePrefs timer' : '$tag updating savePrefs timer');
      _saveToPreferencesTimer?.cancel();
      _saveToPreferencesTimer = Timer(Duration(seconds: 1), () {
        _saveToPreferences(false);
      });
      return;
    }
    List<String> tilePrefs = [];
    _tiles.forEach((tile) {
      tilePrefs.add(jsonEncode(tile));
    });
    dev.log('$tag saving prefs: ${tilePrefs.join(', ')}');
    Preferences().setTiles(tilePrefs);
    _saveToPreferencesTimer = null;
  }

  Future<bool> _loadFromPreferences() async {
    dev.log('$tag loadFromPreferences');
    var tiles = await Preferences().getTiles();
    dev.log('$tag tiles: $tiles');
    setState(() {
      _tiles.clear();
      tiles.forEach((tileString) {
        SensorTile tile = SensorTile.fromJson(jsonDecode(tileString));
        dev.log('$tag loading $tileString');
        //dev.log('$tag loading ${tile.toJson().toString()}');
        _tiles.add(tile);
      });
    });
    return _tiles.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    var sizeUnit = MediaQuery.of(context).size.width / 10;
    return StaggeredGridView.countBuilder(
      crossAxisCount: 10,
      //mainAxisSpacing: 4,
      //crossAxisSpacing: 4,
      shrinkWrap: true,
      itemCount: _tiles.length,
      staggeredTileBuilder: (index) {
        return StaggeredTile.extent(
          _tiles[index].colSpan,
          _tiles[index].height * sizeUnit,
        );
        /*
        return StaggeredTile.fit(
          _tiles[index].colSpan,
        );
        */
      },
      itemBuilder: (context, index) {
        return DragTarget<SensorTile>(
          onAccept: (tile) {
            dev.log("onAccept $index ${tile.name}");
            _saveToPreferences();
          },
          onWillAccept: (tile) {
            if (tile == null) return false;
            if (_tiles[index] == tile) return false;
            dev.log("onWillAccept $index ${tile.name} ${_tiles[index].name}");
            _moveTile(tile, index);
            return true;
          },
          onLeave: (tile) {
            dev.log("onLeave $index ${tile?.name}");
          },
          builder: (
            BuildContext context,
            List<SensorTile?> accepted,
            List<dynamic> rejected,
          ) {
            return LongPressDraggable<SensorTile>(
              data: _tiles[index],
              feedback: Opacity(child: Material(color: Colors.transparent, child: _tiles[index]), opacity: .5),
              child: Hero(
                placeholderBuilder: (_, __, child) => child,
                tag: _tiles[index].hashCode,
                child: Material(
                  child: InkWell(
                    child: _tiles[index],
                    onTap: () => print("tile ${_tiles[index].name} tap"),
                    onDoubleTap: () {
                      print("tile ${_tiles[index].name} doubleTap");
                      Navigator.push(
                        context,
                        HeroDialogRoute(
                          builder: (context) {
                            return WillPopScope(
                              onWillPop: () async {
                                setState(() {
                                  colorPicker = false;
                                });
                                return true;
                              },
                              child: Center(
                                child: Dialog(
                                  backgroundColor: Colors.black38,
                                  child: StatefulBuilder(
                                    builder: (context, setDialogState) {
                                      if (colorPicker && colorPickerInitialColor != null && colorPickerCallback != null) {
                                        var colorPickerController = CircleColorPickerController(initialColor: colorPickerInitialColor!);
                                        return CircleColorPicker(
                                          controller: colorPickerController,
                                          textStyle: TextStyle(color: Colors.transparent),
                                          onChanged: (color) {
                                            dev.log("colorpicker $color");
                                            colorPickerController.color = color;
                                            setState(() {
                                              setDialogState(() {
                                                colorPickerCallback!(color);
                                              });
                                            });
                                          },
                                          onEnded: (color) {
                                            setState(() {
                                              setDialogState(() {
                                                colorPicker = false;
                                              });
                                            });
                                          },
                                        );
                                      }
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Column(
                                            children: [
                                              Slider(
                                                value: _tiles[index].colSpan.toDouble(),
                                                min: 2,
                                                max: 10,
                                                divisions: 8,
                                                onChangeStart: (_) {
                                                  setDialogState(() {
                                                    dialogOpacity = .5;
                                                  });
                                                },
                                                onChangeEnd: (_) {
                                                  setDialogState(() {
                                                    dialogOpacity = 1;
                                                  });
                                                  _saveToPreferences();
                                                },
                                                onChanged: (value) {
                                                  dev.log("colspan changed");
                                                  setState(() {
                                                    setDialogState(() {
                                                      _tiles[index] = SensorTile.from(
                                                        _tiles[index],
                                                        colSpan: value.round(),
                                                      );
                                                    });
                                                  });
                                                },
                                              ),
                                              Row(
                                                children: [
                                                  RotatedBox(
                                                    quarterTurns: 1,
                                                    child: Slider(
                                                      value: _tiles[index].height.toDouble(),
                                                      min: 2,
                                                      max: 6,
                                                      divisions: 4,
                                                      onChangeStart: (_) {
                                                        setDialogState(() {
                                                          dialogOpacity = .5;
                                                        });
                                                      },
                                                      onChangeEnd: (_) {
                                                        setDialogState(() {
                                                          dialogOpacity = 1;
                                                        });
                                                        _saveToPreferences();
                                                      },
                                                      onChanged: (value) {
                                                        dev.log("height changed");
                                                        setState(() {
                                                          setDialogState(() {
                                                            _tiles[index] = SensorTile.from(
                                                              _tiles[index],
                                                              height: value.round(),
                                                            );
                                                          });
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Hero(
                                                        tag: _tiles[index].hashCode,
                                                        child: Opacity(
                                                            opacity: dialogOpacity,
                                                            child: GestureDetector(
                                                              child: _tiles[index],
                                                              onTap: () {
                                                                dev.log("colorpicker bg");
                                                                setState(() {
                                                                  setDialogState(() {
                                                                    colorPicker = true;
                                                                    colorPickerInitialColor = _tiles[index].color;
                                                                    colorPickerCallback = (color) {
                                                                      _tiles[index] = SensorTile.from(_tiles[index], color: color);
                                                                      _saveToPreferences();
                                                                    };
                                                                  });
                                                                });
                                                              },
                                                              onDoubleTap: () {
                                                                dev.log("colorpicker textColor");
                                                                setState(() {
                                                                  setDialogState(() {
                                                                    colorPicker = true;
                                                                    colorPickerInitialColor = _tiles[index].textColor;
                                                                    colorPickerCallback = (color) {
                                                                      _tiles[index] = SensorTile.from(_tiles[index], textColor: color);
                                                                      _saveToPreferences();
                                                                    };
                                                                  });
                                                                });
                                                              },
                                                            )),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
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

class HeroDialogRoute<T> extends PageRoute<T> {
  HeroDialogRoute({required this.builder}) : super();

  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  bool get maintainState => true;

  @override
  Color get barrierColor => Colors.black54;

  @override
  String? get barrierLabel => "barrierLabel";

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child);
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return builder(context);
  }
}
