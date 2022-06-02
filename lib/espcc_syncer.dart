import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:developer' as dev;

import 'device.dart';
import 'util.dart';
import 'debug.dart';

class ESPCCSyncer with Debug {
  ESPCC device;
  final _queue = Queue<ESPCCFile>();
  ESPCCFile? _current;
  bool _running = false;
  Timer? _timer;
  final int queueDelayMs = 500;

  ESPCCSyncer(this.device);

  void start() {
    if (!_queue.isEmpty) _startQueueSchedule();
  }

  void queue(ESPCCFile f) {
    debugLog("queue ${f.name}");
    f.cancelDownload = false;
    if (!_queue.contains(f)) _queue.add(f);
    _startQueueSchedule();
  }

  void dequeue(ESPCCFile f) {
    debugLog("unqueue ${f.name}");
    var file = getFromQueue(file: f);
    if (null != file) file.cancelDownload = true;
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
    return _current == f && (_running || _timer != null);
  }

  Future<void> _runQueue() async {
    if (_running) {
      //debugLog("_runQueue: already _running");
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
      debugLog("cancelling download of $ef");
      // ef is not placed back into the queue
      device.files.notifyListeners();
      _running = false;
      return;
    }
    if (ef.remoteExists != ExtendedBool.True || ef.remoteSize <= 0) {
      debugLog("invalid remote $ef");
      // ef is not placed back into the queue
      _running = false;
      return;
    }
    await ef.updateLocalStatus();
    if (ef.localExists == ExtendedBool.Unknown) {
      debugLog("could not get local status for ${ef.name}");
      _queue.add(ef);
      _running = false;
      return;
    }
    if (ef.remoteSize <= ef.localSize) {
      debugLog("finished downloading ${ef.name}");
      device.files.notifyListeners();
      if (ef.remoteSize < ef.localSize) debugLog("!!! remote size ${ef.remoteSize} < local size ${ef.localSize}");
      _running = false;
      return;
    }
    File? f = await ef.getLocal();
    if (null == f) {
      debugLog("could not get local file for ${ef.name}");
      _queue.add(ef);
      _running = false;
      return;
    }
    if (!await device.connected) {
      debugLog("not connected");
      _queue.add(ef);
      _running = false;
      return;
    }
    int offset = ef.localSize <= 0 ? 0 : ef.localSize + 1;
    String request = "rec=get:${ef.name};offset:$offset";
    String expect = "get:${ef.name}:$offset;";
    debugLog("requesting: $request, expecting: $expect");
    String? reply = await device.api.request<String>(request, expectValue: expect);
    if (null == reply || reply.length < 1) {
      debugLog("empty reply for $request");
      _queue.add(ef);
      _running = false;
      return;
    }
    //debugLog("reply: $reply");
    int answerPos = reply.indexOf(";");
    if (answerPos < 0) {
      debugLog("invalid answer to $request");
      _queue.add(ef);
      _running = false;
      return;
    }
    String value = reply.substring(answerPos + 1);
    //debugLog("value: $value");
    if (!await f.exists()) {
      try {
        f = await f.create(recursive: true);
      } catch (e) {
        debugLog("could not create ${await ef.path}, error: $e");
        _queue.add(ef);
        _running = false;
        return;
      }
    }
    int localSize = await f.length();
    if (localSize != (offset <= 0 ? 0 : offset - 1)) {
      debugLog("local size is $localSize but offset is $offset");
      _queue.add(ef);
      _running = false;
      return;
    }
    f = await f.writeAsString(value, mode: FileMode.append, flush: true);
    await ef.updateLocalStatus();
    debugLog("Wrote ${value.length} bytes to ${ef.name} at offset $offset. Local: ${ef.localSize}, remote: ${ef.remoteSize}.");
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
