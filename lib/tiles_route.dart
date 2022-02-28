import 'dart:async';
//import 'dart:convert';
//import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_circle_color_picker/flutter_circle_color_picker.dart';

//import 'preferences.dart';
//import 'device.dart';
import 'device_list.dart';
import 'device_list_route.dart';
import 'device_widgets.dart';
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

  var _tileGrid = TileGrid();
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
      debugPrint("hideFab");
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
                                            _tileGrid = TileGrid(
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
                                      onPressed: () {
                                        setState(() {
                                          TileList().add(Tile());
                                          TileList().save();
                                        });
                                        Navigator.of(context).pop(); // close dialog
                                      },
                                      child: Text("Add tile")),
                                ),
                                Container(
                                  width: 150.0,
                                  height: 50.0,
                                  margin: EdgeInsets.only(top: 30),
                                  child: ElevatedButton(
                                      onPressed: () => setState(() {
                                            _tileGrid = TileGrid(
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
          child: _tileGrid,
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
    setState(() {
      _tiles.removeWhere((existing) => existing.hashCode == tile.hashCode);
      _tiles.insert(index, tile);
    });
  }

  @override
  Widget build(BuildContext context) {
    double sizeUnit = MediaQuery.of(context).size.width / 10;

/*
    Widget Function(int) sizeAndColor = (index) {
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
          Tile? tile = _tiles[index];
          if (null == tile) return Text("Cannot find tile");
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                children: [
                  Slider(
                    value: tile.colSpan.toDouble(),
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
                          tile,
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
                          value: tile.height.toDouble(),
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
                                tile,
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
                                      colorPickerInitialColor = tile.color;
                                      colorPickerCallback = (color) {
                                        _tiles[index] = Tile.from(tile, color: color);
                                        _tiles.save();
                                      };
                                    });
                                  },
                                  onDoubleTap: () {
                                    dev.log("colorpicker textColor");
                                    setStates(() {
                                      colorPicker = true;
                                      colorPickerInitialColor = tile.textColor;
                                      colorPickerCallback = (color) {
                                        _tiles[index] = Tile.from(tile, textColor: color);
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
*/

    Widget Function(int) sizeAndColor = (index) {
      return ValueListenableBuilder(
        valueListenable: _tiles.notifier,
        builder: (context, List<Tile> tiles, _) {
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
              if (tiles.length <= index || index < 0) return Text("Cannot find tile $index");
              Tile tile = tiles[index];
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    children: [
                      Slider(
                        value: tile.width.toDouble(),
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
                              tile,
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
                              value: tile.height.toDouble(),
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
                                  _tiles[index] = Tile.from(tile, height: value.round());
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
                                          colorPickerInitialColor = tile.color;
                                          colorPickerCallback = (color) {
                                            _tiles[index] = Tile.from(tile, color: color);
                                            _tiles.save();
                                          };
                                        });
                                      },
                                      onDoubleTap: () {
                                        dev.log("colorpicker textColor");
                                        setStates(() {
                                          colorPicker = true;
                                          colorPickerInitialColor = tile.textColor;
                                          colorPickerCallback = (color) {
                                            _tiles[index] = Tile.from(tile, textColor: color);
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
        },
      );
    };

    Widget Function(int) source = (index) {
      return ValueListenableBuilder(
          valueListenable: _tiles.notifier,
          builder: (context, List<Tile> tiles, _) {
            if (tiles.length <= index || index < 0) return Text("Cannot find tile $index");
            Tile tile = tiles[index];
            print("builder called: ${tile.stream}");
            String value = "${tile.device};${tile.stream}";
            bool valuePresent = false;
            var items = <DropdownMenuItem<String>>[];
            DeviceList().forEach((_, device) {
              if (device.tileStreams.length < 1) return;
              device.tileStreams.forEach((name, stream) {
                String itemValue = "${device.peripheral?.identifier};$name";
                if (itemValue == value) valuePresent = true;
                items.add(DropdownMenuItem(
                  value: itemValue,
                  child: Text("${stream.label} (${device.name ?? 'unnamed device'})"),
                ));
              });
            });
            if (items.length < 1)
              items.add(
                DropdownMenuItem(
                  value: value,
                  child: Text("No valid sources"),
                ),
              );
            else if (!valuePresent)
              items.insert(
                0,
                DropdownMenuItem(
                  value: value,
                  child: Text("Select Source"),
                ),
              );

            return EspmuiDropdown(
              value: value,
              items: items,
              onChanged: (value) {
                print("New source $value");
                var chunks = value?.split(";");
                if (chunks == null || chunks.length < 2 || chunks[0].length < 1 || chunks[1].length < 1) {
                  print("Wrong chunks: $chunks");
                  return;
                }
                _tiles[index] = Tile.from(
                  tile,
                  device: chunks[0],
                  stream: chunks[1],
                );
                _tiles.save();
              },
            );
          });
    };

    return ValueListenableBuilder<List<Tile>>(
        valueListenable: _tiles.notifier,
        builder: (context, tiles, __) {
          return StaggeredGridView.countBuilder(
            crossAxisCount: 10,
            //mainAxisSpacing: 4,
            //crossAxisSpacing: 4,
            shrinkWrap: true,
            itemCount: _tiles.length,
            staggeredTileBuilder: (index) {
              return StaggeredTile.extent(
                tiles[index].width,
                tiles[index].height * sizeUnit,
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
                  _tiles.save();
                },
                onWillAccept: (tile) {
                  if (tile == null) return false;
                  if (_tiles[index] == tile) return false;
                  _moveTile(tile, index);
                  return true;
                },
                onLeave: (tile) {},
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
                          onTap: () => print("tile $index tap"),
                          onDoubleTap: () {
                            print("tile $index doubleTap");

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
                                        child: Column(
                                          children: [
                                            sizeAndColor(index),
                                            source(index),
                                          ],
                                        ),
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
