import 'dart:async';
//import 'dart:convert';
import 'dart:math';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import 'tile.dart';
import 'device.dart';
//import 'ble_characteristic.dart';
import 'device_list.dart';
import 'device_list_route.dart';
import 'device_widgets.dart';
import 'util.dart';
import 'debug.dart';

class TilesRoute extends StatefulWidget {
  const TilesRoute({super.key});

  @override
  TilesRouteState createState() => TilesRouteState();
}

class TilesRouteState extends State<TilesRoute> with Debug {
  bool _fabVisible = false;
  Timer? _fabTimer;

  final _tileGrid = const TileGrid();
  // var devices = DeviceList();

  @override
  void initState() {
    dev.log("$runtimeType initState");
    super.initState();
  }

  Future<void> showFab(dynamic _) async {
    logD("showFab");
    setState(() {
      _fabVisible = true;
    });
    _fabTimer?.cancel();
    _fabTimer = Timer(const Duration(seconds: 3), () {
      logD("hideFab");
      setState(() {
        _fabVisible = false;
      });
    });
  }

  Widget fab() {
    if (!_fabVisible) return Container();
    return FloatingActionButton(
      onPressed: () {
        logD("fab pressed");
        Navigator.push(
          context,
          HeroDialogRoute(
            builder: (BuildContext context) {
              return Center(
                child: AlertDialog(
                  title: const Hero(tag: 'fab', child: Icon(Icons.settings)),
                  contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                          onPressed: () {
                            setState(() {
                              TileList().add(Tile());
                              TileList().save();
                            });
                            Navigator.of(context).pop(); // close dialog
                          },
                          child: const Text("Add tile")),
                      const SizedBox(width: 10, height: 20, child: Empty()),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(); // close dialog
                          Navigator.push(
                            context,
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              child: const DeviceListRoute(),
                            ),
                          );
                        },
                        child: const Text("Devices"),
                      ),
                    ],
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: Navigator.of(context).pop,
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
      backgroundColor: Colors.red,
      heroTag: "fab",
      child: const Icon(
        Icons.settings,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: showFab,
      onVerticalDragDown: showFab,
      child: Scaffold(
        floatingActionButton: fab(),
        body: SafeArea(
          child: _tileGrid,
        ),
      ),
    );
  }
}

class TileGrid extends StatefulWidget with Debug {
  final String mode;

  const TileGrid({
    super.key,
    this.mode = 'fromPreferences',
  });

  @override
  TileGridState createState() {
    //logD('createState()');
    return TileGridState();
  }
}

class TileGridState extends State<TileGrid> with Debug {
  late TileList _tiles;
  double dialogOpacity = 1;
  bool showColorPicker = false;
  void Function(Color)? colorPickerCallback;
  String? colorPickerTarget;
  Color? colorPickerColor;

  TileGridState() {
    _tiles = TileList();
  }

  @override
  void initState() {
    logD('initState');
    super.initState();
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

    Widget sizeAndColor(int index) {
      return ValueListenableBuilder(
        valueListenable: _tiles.notifier,
        builder: (context, List<Tile> tiles, _) {
          return StatefulBuilder(
            builder: (context, setChildState) {
              setStates(f) {
                setState(() {
                  setChildState(() {
                    f();
                  });
                });
              }

              if (showColorPicker && colorPickerColor != null && colorPickerCallback != null) {
                return Column(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Text("$colorPickerTarget Color"),
                    ),
                    SlidePicker(
                      pickerColor: colorPickerColor!,
                      colorModel: ColorModel.rgb,
                      enableAlpha: true,
                      displayThumbColor: true,
                      showParams: false,
                      showIndicator: true,
                      //indicatorBorderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                      //indicatorAlignmentBegin: const Alignment(-1.0, -3.0),
                      //indicatorAlignmentEnd: const Alignment(1.0, 3.0),
                      onColorChanged: (color) {
                        dev.log("colorpicker $color");
                        setStates(() {
                          colorPickerColor = color;
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 4,
                          child: EspmuiElevatedButton(
                            child: const Text("Cancel"),
                            onPressed: () {
                              setStates(() {
                                showColorPicker = false;
                              });
                            },
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: EspmuiElevatedButton(
                              child: const Text("Set Color"),
                              onPressed: () {
                                setStates(() {
                                  if (null != colorPickerColor) colorPickerCallback!(colorPickerColor!);
                                  showColorPicker = false;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                                          showColorPicker = true;
                                          colorPickerColor = tile.color;
                                          colorPickerTarget = "Background";
                                          colorPickerCallback = (color) {
                                            _tiles[index] = Tile.from(tile, color: color);
                                            _tiles.save();
                                          };
                                        });
                                      },
                                      onDoubleTap: () {
                                        dev.log("colorpicker textColor");
                                        setStates(() {
                                          showColorPicker = true;
                                          colorPickerColor = tile.textColor;
                                          colorPickerTarget = "Text";
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
    }

    Widget source(int index) {
      return ValueListenableBuilder(
          valueListenable: _tiles.notifier,
          builder: (context, List<Tile> tiles, _) {
            if (tiles.length <= index || index < 0) return Text("Cannot find tile $index");
            Tile tile = tiles[index];
            //logD("source builder called: ${tile.stream}");
            String value = "${tile.device};${tile.stream}";
            bool valuePresent = false;
            var items = <DropdownMenuItem<String>>[];
            DeviceList().forEach((_, device) {
              if (device.tileStreams.isEmpty) return;
              device.tileStreams.forEach((name, stream) {
                String itemValue = '${device.id};$name';
                if (itemValue == value) valuePresent = true;
                items.add(DropdownMenuItem(
                  value: itemValue,
                  child: Text("${device.name.isNotEmpty ? device.name : 'unnamed device'} ${stream.label}"),
                ));
              });
            });
            if (items.isEmpty) {
              items.add(
                DropdownMenuItem(
                  value: value,
                  child: const Text("No valid sources"),
                ),
              );
            }
            items.sort((a, b) => a.child.toString().compareTo(b.child.toString()));
            if (!valuePresent) {
              items.insert(
                0,
                const DropdownMenuItem(
                  value: "",
                  child: Text("Select Source"),
                ),
              );
            }

            var sourceDropdown = EspmuiDropdownWidget(
              value: valuePresent ? value : "",
              items: items,
              onChanged: (value) {
                logD("New source $value");
                var chunks = value?.split(";");
                if (chunks == null || chunks.length < 2 || chunks[0].isEmpty || chunks[1].isEmpty) {
                  logD("Wrong chunks: $chunks");
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
            History? charHistory = DeviceList().byIdentifier(tile.device)?.tileStreams[tile.stream]?.history;
            if (null == charHistory) return sourceDropdown;
            logD("this stream supports history");
            double max = charHistory.maxAge.toDouble();

            /// Slider power curve
            /// https://stackoverflow.com/a/17102320/7195990

            /// desired curve value at start
            double cX = 0;

            /// desired curve value at midpoint
            double cY = max / 10;

            /// desired curve value at end
            double cZ = max;

            /// special case: linear curve
            if ((cX - 2 * cY + cZ) == 0) {
              logD("linear curve");
              cY += 1;
            }

            ///
            double curveA = (cX * cZ - cY * cY) / (cX - 2 * cY + cZ);
            double curveB = pow(cY - cX, 2) / (cX - 2 * cY + cZ);
            double curveC = 2 * log((cZ - cY) / (cY - cX));

            double valueToSlider(double value) {
              return log((value - curveA) / curveB) / curveC;
            }

            double sliderToValue(double value) {
              return curveA + curveB * exp(curveC * value);
            }

            double currentValue = tile.history.toDouble();
            if (max < currentValue) currentValue = max;
            if (currentValue < 0) currentValue = 0;
            var historySlider = Slider(
              label: "History: ${currentValue.round()} seconds",
              value: valueToSlider(currentValue),
              min: 0,
              max: 1,
              divisions: 100,
              onChangeStart: null,
              onChangeEnd: (value) {
                _tiles.save();
                snackbar("History: ${sliderToValue(value).round()} seconds", context);
              },
              onChanged: tile.history < 0
                  ? null
                  : (value) {
                      //logD("v: $value s2v(v): ${sliderToValue(value)} v2s(s2v(v)): ${valueToSlider(sliderToValue(value))}");
                      _tiles[index] = Tile.from(
                        tile,
                        history: sliderToValue(value).round(),
                      );
                    },
            );
            return Column(
              children: [
                sourceDropdown,
                Row(
                  children: [
                    historySlider,
                    Checkbox(
                      value: tile.history < 0,
                      onChanged: (value) {
                        if (value == true) {
                          _tiles[index] = Tile.from(
                            tile,
                            history: -1,
                          );
                          return;
                        }
                        _tiles[index] = Tile.from(
                          tile,
                          history: 0,
                        );
                      },
                    ),
                    Text('∞'),
                  ],
                ),
              ],
            );
          });
    }

    Widget tapAction(int index) {
      return ValueListenableBuilder(
          valueListenable: _tiles.notifier,
          builder: (context, List<Tile> tiles, _) {
            if (tiles.length <= index || index < 0) return Text("Cannot find tile $index");
            Tile tile = tiles[index];
            //logD("tapAction builder called: ${tile.tap}");
            bool valuePresent = false;
            var items = <DropdownMenuItem<String>>[];
            DeviceList().forEach((_, device) {
              if (device.tileActions.isEmpty) return;
              device.tileActions.forEach((name, action) {
                String itemValue = "${device.id};$name";
                //logD("${device.name ?? 'unnamed device'} ${action.label} $itemValue");
                if (itemValue == tile.tap) valuePresent = true;
                items.add(DropdownMenuItem(
                  value: itemValue,
                  child: Text("${device.name.isNotEmpty ? device.name : 'unnamed device'} ${action.label}"),
                ));
              });
            });
            items.sort((a, b) => a.child.toString().compareTo(b.child.toString()));
            items.insert(
              0,
              const DropdownMenuItem(
                value: "",
                child: Text("No Tap Action"),
              ),
            );
            return EspmuiDropdownWidget(
              value: valuePresent ? tile.tap : "",
              items: items,
              onChanged: (value) {
                logD("New tapAction $value");
                _tiles[index] = Tile.from(
                  tile,
                  tap: value ?? "",
                );
                _tiles.save();
              },
            );
          });
    }

    void onTap(Tile? tile) {
      if (null == tile) return;
      logD("onTap: ${tile.tap}");
      if (tile.tap.length < 3) return;
      var chunks = tile.tap.split(";");
      if (chunks.length != 2) return;
      Device? device = DeviceList().byIdentifier(chunks[0]);
      if (null == device) return;
      DeviceTileAction? action = device.tileActions[chunks[1]];
      if (null == action) return;
      action.call(context);
    }

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
                onAcceptWithDetails: (tile) {
                  _tiles.save();
                },
                onWillAcceptWithDetails: (details) {
                  if (tiles[index] == details.data) return false;
                  _moveTile(details.data, index);
                  return true;
                },
                onLeave: (tile) {},
                builder: (
                  BuildContext context,
                  List<Tile?> accepted,
                  List<dynamic> rejected,
                ) {
                  return LongPressDraggable<Tile>(
                    data: tiles[index],
                    feedback: Opacity(
                      opacity: .5,
                      child: Material(
                        color: Colors.transparent,
                        child: _tiles[index],
                      ),
                    ),
                    child: Hero(
                      placeholderBuilder: (_, __, child) => child,
                      tag: tiles[index].hashCode,
                      child: Card(
                        shadowColor: Colors.black26,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5.0),
                        ),
                        elevation: 3,
                        color: Colors.transparent, // debug
                        child: Material(
                          child: InkWell(
                            child: tiles[index],
                            onTap: () {
                              logD("tile $index tap");
                              onTap(tiles[index]);
                            },
                            onDoubleTap: () {
                              logD("tile $index doubleTap");
                              Navigator.push(
                                context,
                                HeroDialogRoute(
                                  builder: (context) {
                                    return PopScope(
                                      onPopInvokedWithResult: (didPop, result) async {
                                        if (didPop) {
                                          setState(() {
                                            showColorPicker = false;
                                          });
                                        }
                                      },
                                      child: Center(
                                        child: AlertDialog(
                                          scrollable: true,
                                          backgroundColor: Colors.black87,
                                          content: Column(
                                            children: [
                                              sizeAndColor(index),
                                              source(index),
                                              tapAction(index),
                                            ],
                                          ),
                                          actions: [
                                            EspmuiElevatedButton(
                                              child: const Text("Delete Tile"),
                                              onPressed: () {
                                                logD("delete tile $index");
                                                setState(() {
                                                  tiles.removeAt(index);
                                                  _tiles.tiles = tiles;
                                                  _tiles.save();
                                                });
                                                Navigator.of(context).pop();
                                              },
                                            ),
                                            EspmuiElevatedButton(
                                              onPressed: Navigator.of(context).pop,
                                              child: const Text("Close"),
                                            ),
                                          ],
                                          actionsAlignment: MainAxisAlignment.spaceBetween,
                                          buttonPadding: EdgeInsets.zero,
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
                    ),
                  );
                },
              );
            },
          );
        });
  }
}
