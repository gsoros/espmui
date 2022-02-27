//import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';

import 'tile.dart';
//import 'preferences.dart';

class TileRoute extends StatefulWidget {
  final int index;
  final Map<String, dynamic> json;

  const TileRoute({Key? key, required this.index, required this.json}) : super(key: key);

  @override
  _TileRouteState createState() => _TileRouteState(index: index, json: json);
}

class _TileRouteState extends State<TileRoute> {
  /// position of the Tile in the TileList
  int index;
  late Tile tile;

  bool colorPicker = false;
  void Function(Color)? colorPickerCallback;
  Color? colorPickerInitialColor;

  _TileRouteState({required this.index, required Map<String, dynamic> json}) {
    tile = Tile.fromJson(json);
  }

  @override
  void initState() {
    dev.log("$runtimeType initState");
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            children: [
              Slider(
                value: tile.colSpan.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                onChangeEnd: (_) {
                  //TileList().save();
                },
                onChanged: (value) {
                  dev.log("colspan changed");
                  setState(() {
                    tile = Tile.from(tile, colSpan: value.round());
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
                      onChangeEnd: (_) {
                        //TileList().save();
                      },
                      onChanged: (value) {
                        dev.log("height changed");
                        setState(() {
                          tile = Tile.from(tile, height: value.round());
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Hero(
                        tag: tile.hashCode,
                        child: GestureDetector(
                          child: tile,
                          onTap: () {
                            dev.log("colorpicker bg");
                            setState(() {
                              colorPicker = true;
                              colorPickerInitialColor = tile.color;
                              colorPickerCallback = (color) {
                                tile = Tile.from(tile, color: color);
                                //TileList().save();
                              };
                            });
                          },
                          onDoubleTap: () {
                            dev.log("colorpicker textColor");
                            setState(() {
                              colorPicker = true;
                              colorPickerInitialColor = tile.textColor;
                              colorPickerCallback = (color) {
                                tile = Tile.from(tile, textColor: color);
                                //TileList().save();
                              };
                            });
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
