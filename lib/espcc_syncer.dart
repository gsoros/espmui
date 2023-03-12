import 'dart:async';
import 'dart:collection';
//import 'dart:io';
//import 'dart:developer' as dev;

import 'espcc.dart';
import 'util.dart';
import 'debug.dart';

class ESPCCSyncer with Debug {
  ESPCC device;
  final _queue = Queue<ESPCCFile>();
  ESPCCFile? _current;
  bool _running = false;
  Timer? _timer;
  final int queueDelayMs = 100;

  ESPCCSyncer(this.device);

  void start() {
    if (_queue.isNotEmpty) _startQueueSchedule();
  }

  void queue(ESPCCFile f) async {
    debugLog("queue ${f.name}");
    f.cancelDownload = false;
    if (!_queue.contains(f)) _queue.add(f);
    int? mtu = await device.peripheral?.requestMtu(512).catchError((e) {
      debugLog(e);
    });
    if (null != mtu) debugLog("got mtu=$mtu");
    _startQueueSchedule();
  }

  void dequeue(ESPCCFile f) {
    debugLog("dequeue ${f.name}");
    f.cancelDownload = true;
    var file = getFromQueue(file: f);
    if (null != file) file.cancelDownload = true;
    device.files.notifyListeners();
  }

  bool isQueued(ESPCCFile f) {
    var file = getFromQueue(file: f);
    if (null != file && !file.cancelDownload) return true;
    return false;
  }

  ESPCCFile? getFromQueue({
    ESPCCFile? file,
    String? name,
  }) {
    if (null == file && null == name) return null;
    for (ESPCCFile g in _queue) if (file?.name == g.name || (name != null && name == g.name)) return g;
    return null;
  }

  bool isDownloading(ESPCCFile f) {
    //if (f.name == _current?.name) debugLog("f: $f _current: $_current");
    return !f.cancelDownload && _current == f && (_running || _timer != null);
  }

  Future<void> _runQueue() async {
    String tag = "_runQueue()";

    if (_running) {
      // debugLog("$tag already _running");
      return;
    }
    _running = true;
    if (_queue.isEmpty) {
      _running = false;
      _stopQueueSchedule();
      return;
    }
    ESPCCFile ef = _queue.removeFirst();
    _current = ef;
    if (ef.cancelDownload) {
      debugLog("$tag cancelling download of $ef");
      // ef is not placed back into the queue
      device.files.notifyListeners();
      _running = false;
      return;
    }
    if (ef.remoteExists != ExtendedBool.True || ef.remoteSize <= 0) {
      debugLog("$tag invalid remote $ef");
      // ef is not placed back into the queue
      _running = false;
      return;
    }
    await ef.updateLocalStatus();
    if (ef.localExists == ExtendedBool.Unknown) {
      debugLog("$tag could not get local status for ${ef.name}");
      _queue.add(ef);
      _running = false;
      return;
    }
    if (ef.remoteSize <= ef.localSize) {
      debugLog("$tag finished downloading ${ef.name}");
      device.files.notifyListeners();
      if (ef.remoteSize < ef.localSize) debugLog("!!! remote size ${ef.remoteSize} < local size ${ef.localSize}");
      if (ef.isRec) {
        String msg = "generating ${ef.name}-local.gpx";
        snackbar(msg);
        await ef.generateGpx();
        snackbar("done $msg");
      }
      _running = false;
      return;
    }
    if (!await device.connected) {
      debugLog("$tag not connected");
      _queue.add(ef);
      _running = false;
      return;
    }
    await ef.updateLocalStatus();
    int offset = ef.localSize <= 0 ? 0 : ef.localSize + 1;
    String request = "rec=get:${ef.name};offset:$offset";
    String expect = "get:${ef.name}:$offset;";
    // debugLog("$tag (ef.hash: ${ef.hashCode}) requesting: $request, expecting: $expect");
    String? reply = await device.api.request<String>(
      request,
      expectValue: expect,
      minDelayMs: 1000,
      maxAgeMs: 3000,
      maxAttempts: 3,
    );
    if (null == reply || reply.length < 1) {
      debugLog("$tag empty reply for $request");
      _queue.add(ef);
      _running = false;
      return;
    }
    // debugLog("$ef reply: $reply");
    int answerPos = reply.indexOf(";");
    if (answerPos < 0) {
      debugLog("$tag invalid answer to $request");
      _queue.add(ef);
      _running = false;
      return;
    }
    if (!ef.isBinary) {
      String value = reply.substring(answerPos + 1);
      // debugLog("$tag $ef got ${value.length}B");
      int written = await ef.appendLocal(offset: offset, data: value);
      if (written != value.length) {
        debugLog("$ef, received: ${value.length}, written: $written");
      }
    }
    // in case of a binary (rec) file, at this point the local file should be
    // updated by EspccApiCharacteristic::onNotify()
    await ef.updateLocalStatus();
    //debugLog("$tag ef.hash ${ef.hashCode} local size is now ${ef.localSize}");
    device.files.notifyListeners();
    _queue.addFirst(ef);
    _running = false;
  }

  void _startQueueSchedule() {
    debugLog("queueSchedule already running");
    if (_timer != null) return;
    debugLog("queueSchedule start");
    _timer = Timer.periodic(Duration(milliseconds: queueDelayMs), (_) => _runQueue());
  }

  void _stopQueueSchedule() {
    if (_timer == null) return;
    debugLog("queueSchedule stop");
    _timer?.cancel();
    _timer = null;
  }
}
