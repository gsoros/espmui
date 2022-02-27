import 'dart:async';
//import 'dart:convert';
//import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_circle_color_picker/flutter_circle_color_picker.dart';

//import 'preferences.dart';
import 'device_list.dart';
import 'device_list_route.dart';
import 'tile.dart';
//import 'tile_route.dart';

class TilesRoute extends StatefulWidget {
  const TilesRoute({Key? key}) : super(key: key);

  @override
  _TilesRouteState createState() => _TilesRouteState();
}

class _TilesRouteState extends State<TilesRoute> {
  bool _fabVisible = false;
  Timer? _fabTimer;

  var _tiles = TileGrid();
  var devices = DeviceList();

  @override
  void initState() {
    dev.log("$runtimeType initState");
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
                                            dev.log('$runtimeType calling TileList(mode: fromPreferences)');
                                            _tiles = TileGrid(
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
                                            _tiles = TileGrid(
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
                                          child: DeviceListRoute(),
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

class TileGrid extends StatefulWidget {
  final String mode;

  const TileGrid({
    Key? key,
    this.mode = 'fromPreferences',
  }) : super(key: key);

  @override
  _TileGridState createState() {
    dev.log('$runtimeType createState()');
    _TileGridState state = _TileGridState();
    if (mode == 'fromPreferences')
      state._tiles.load();
    else if (mode == 'random') state._randomize();
    return state;
  }
}

class _TileGridState extends State<TileGrid> {
  late TileList _tiles;
  double dialogOpacity = 1;
  bool colorPicker = false;
  void Function(Color)? colorPickerCallback;
  Color? colorPickerInitialColor;

  _TileGridState() {
    _tiles = TileList();
  }

  @override
  void initState() {
    dev.log('$runtimeType initState');
    super.initState();
  }

  void _randomize() {
    dev.log('$runtimeType _randomize');
    _tiles.clear();
    for (var i = 0; i < 5; i++) _tiles.add(Tile.random());
  }

  void _moveTile(Tile tile, int index) {
    dev.log('$runtimeType reorder tile:${tile.name} newIndex:$index');
    setState(() {
      _tiles.removeWhere((existing) => existing.hashCode == tile.hashCode);
      _tiles.insert(index, tile);
    });
  }

  @override
  Widget build(BuildContext context) {
    double sizeUnit = MediaQuery.of(context).size.width / 10;
    Widget Function(int) tileSizeAndColor = (index) {
      return StatefulBuilder(
        builder: (context, setChildState) {
          void Function(void Function() f) setStates = (f) {
            setState(() {
              setChildState(() {
                f();
              });
            });
          };
          if (colorPicker && colorPickerInitialColor != null && colorPickerCallback != null) {
            var colorPickerController = CircleColorPickerController(initialColor: colorPickerInitialColor!);
            return CircleColorPicker(
              controller: colorPickerController,
              textStyle: TextStyle(color: Colors.transparent),
              onChanged: (color) {
                dev.log("colorpicker $color");
                colorPickerController.color = color;
                setStates(() {
                  colorPickerCallback!(color);
                });
              },
              onEnded: (color) {
                setStates(() {
                  colorPicker = false;
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
                      setChildState(() {
                        dialogOpacity = .5;
                      });
                    },
                    onChangeEnd: (_) {
                      setChildState(() {
                        dialogOpacity = 1;
                      });
                      _tiles.save();
                    },
                    onChanged: (value) {
                      dev.log("colspan changed");
                      setStates(() {
                        _tiles[index] = Tile.from(
                          _tiles[index],
                          colSpan: value.round(),
                        );
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
                            setChildState(() {
                              dialogOpacity = .5;
                            });
                          },
                          onChangeEnd: (_) {
                            setChildState(() {
                              dialogOpacity = 1;
                            });
                            _tiles.save();
                          },
                          onChanged: (value) {
                            dev.log("height changed");
                            setStates(() {
                              _tiles[index] = Tile.from(
                                _tiles[index],
                                height: value.round(),
                              );
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
                                    setStates(() {
                                      colorPicker = true;
                                      colorPickerInitialColor = _tiles[index].color;
                                      colorPickerCallback = (color) {
                                        _tiles[index] = Tile.from(_tiles[index], color: color);
                                        _tiles.save();
                                      };
                                    });
                                  },
                                  onDoubleTap: () {
                                    dev.log("colorpicker textColor");
                                    setStates(() {
                                      colorPicker = true;
                                      colorPickerInitialColor = _tiles[index].textColor;
                                      colorPickerCallback = (color) {
                                        _tiles[index] = Tile.from(_tiles[index], textColor: color);
                                        _tiles.save();
                                      };
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
      );
    };

    return ValueListenableBuilder<List<Tile>>(
        valueListenable: _tiles.notifier,
        builder: (context, tileList, widget) {
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
              return DragTarget<Tile>(
                onAccept: (tile) {
                  dev.log("onAccept $index ${tile.name}");
                  _tiles.save();
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
                  List<Tile?> accepted,
                  List<dynamic> rejected,
                ) {
                  return LongPressDraggable<Tile>(
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
                                        backgroundColor: Colors.black87,
                                        child: tileSizeAndColor(index),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );

                            /*
                            Navigator.push(
                              context,
                              PageTransition(
                                type: PageTransitionType.topToBottom,
                                child: TileRoute(index: index, json: _tiles[index].toJson()),
                              ),
                            );
                            */
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        });
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
