import 'dart:async';
import 'dart:collection';
import 'dart:developer' as dev;

import 'device.dart';
//import 'util.dart';
import 'debug.dart';

class ESPCCSyncer with Debug {
  ESPCC device;
  final _queue = Queue<ESPCCFile>();

  ESPCCSyncer(this.device);

  void queue(ESPCCFile f) {
    if (!_queue.contains(f)) _queue.add(f);
    runQueue();
  }

  bool isQueued(ESPCCFile f) {
    for (ESPCCFile g in _queue) if (f.name == g.name) return true;
    return false;
  }

  Future<void> runQueue() async {
    if (_queue.isEmpty) return;
    ESPCCFile f = _queue.first;
    dev.log("TODO download ${f.name}");
  }
}
