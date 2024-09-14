import 'dart:async';
import 'dart:io';
import 'dart:math';
// import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
// import 'package:flutter_ble_lib/flutter_ble_lib.dart';
//import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:sprintf/sprintf.dart';
import 'package:listenable_stream/listenable_stream.dart';
import 'package:intl/intl.dart';
import 'package:mutex/mutex.dart';

import 'device.dart';
import 'api.dart';
import 'espcc_syncer.dart';
//import 'ble.dart';
import 'ble_characteristic.dart';
import 'ble_constants.dart';
import 'device_widgets.dart';

import 'util.dart';
import 'debug.dart';

class ESPCC extends Device with DeviceWithApi, DeviceWithWifi, DeviceWithPeers {
  late ESPCCSyncer syncer;
  final settings = AlwaysNotifier<ESPCCSettings>(ESPCCSettings());
  final files = AlwaysNotifier<ESPCCFileList>(ESPCCFileList());
  Stream<ESPCCSettings>? _settingsStream;

  @override
  int get defaultMtu => 512;

  @override
  int get largeMtu => 512;

  ESPCC(String id, String name) : super(id, name) {
    deviceWithApiConstruct(
      characteristic: EspccApiCharacteristic(this),
      handler: handleApiMessageSuccess,
      serviceUuid: BleConstants.ESPCC_API_SERVICE_UUID,
    );

    syncer = ESPCCSyncer(this);
    _settingsStream = settings.toValueStream().asBroadcastStream();
    tileStreams.addAll({
      "recording": DeviceTileStream(
        label: "Recording status",
        stream: _settingsStream?.map<Widget>((value) => Text(ESPCCRecordingState.getString(value.recording))),
        initialData: () => Text(ESPCCRecordingState.getString(settings.value.recording)),
      ),
    });
    tileActions.addAll({
      "startStop": DeviceTileAction(
        label: "Start/stop recording",
        action: (_, __) async {
          String action = "start";
          String succ = "Started";
          String fail = "Error starting";
          int expect = ESPCCRecordingState.RECORDING;
          if (ESPCCRecordingState.NOT_RECORDING < settings.value.recording) {
            action = "end";
            succ = "Stopped";
            fail = "Error stopping";
            expect = ESPCCRecordingState.NOT_RECORDING;
          }
          var state = await api.request<int>("rec=$action");
          snackbar((state == expect ? succ : fail) + " recording");
        },
      ),
    });
  }

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "";
    //logD("$tag $message");

    if (await wifiHandleApiMessageSuccess(message)) return true;
    if (await peerHandleApiMessageSuccess(message)) return true;

    if (await settings.value.handleApiMessageSuccess(message)) {
      settings.notifyListeners();
      return true;
    }

    if ("rec" == message.commandStr) {
      String? val = message.valueAsString;
      //logD("$tag rec: received val=$val");
      if (null == val) return true;
      if ("files:" == val.substring(0, min(6, val.length))) {
        List<String> names = val.substring(6).split(";");
        logD("$tag rec:files received names=$names");
        names.forEach((name) async {
          if (16 < name.length) {
            logD("$tag rec:files name too long: $name");
            return;
          }
          if (name.length <= 2) {
            logD("$tag rec:files name too short: $name");
            return;
          }
          ESPCCFile f = files.value.files.firstWhere(
            (file) => file.name == name,
            orElse: () {
              var file = syncer.getFromQueue(name: name);
              if (file == null) {
                file = ESPCCFile(name, this, remoteExists: ExtendedBool.True);
                file.updateLocalStatus();
              }
              files.value.files.add(file);
              files.notifyListeners();
              return file;
            },
          );
          if (f.remoteSize < 0) {
            api.requestResultCode("rec=info:${f.name}", expectValue: "info:${f.name}");
            await Future.delayed(Duration(milliseconds: 500));
          }
        });
        for (ESPCCFile f in files.value.files) {
          if (f.localExists == ExtendedBool.Unknown) {
            await f.updateLocalStatus();
            files.notifyListeners();
          }
        }
      } else if ("info:" == val.substring(0, min(5, val.length))) {
        List<String> tokens = val.substring(5).split(";");
        logD("$tag got info: $tokens");
        var f = ESPCCFile(tokens[0], this, remoteExists: ExtendedBool.True);
        if (8 <= f.name.length) {
          tokens.removeAt(0);
          tokens.forEach((token) {
            if ("size:" == token.substring(0, 5)) {
              int? s = int.tryParse(token.substring(5));
              if (s != null && 0 <= s) f.remoteSize = s;
            } else if ("distance:" == token.substring(0, 9)) {
              double? s = double.tryParse(token.substring(9));
              if (s != null && 0 <= s) f.distance = s.round();
            } else if ("altGain:" == token.substring(0, 8)) {
              int? s = int.tryParse(token.substring(8));
              if (s != null && 0 <= s) f.altGain = s;
            }
          });
          files.value.files.firstWhere(
            (file) => file.name == f.name,
            orElse: () {
              files.value.files.add(f);
              return f;
            },
          ).update(
            //name: f.name,
            remoteSize: f.remoteSize,
            distance: f.distance,
            altGain: f.altGain,
            //remoteExists: f.remoteExists,
          );
          files.notifyListeners();
        }
      }
      //logD("files.length=${files.value.files.length}");
      return true;
    }

    logD("unhandled: $message");
    return false;
  }

  Future<void> dispose() async {
    logD("$name dispose");
    await apiDispose();
    await wifiDispose();
    await peerDispose();
    super.dispose();
  }

  Future<void> onConnected() async {
    logD("_onConnected()");
    // api char can use values longer than 20 bytes
    await requestMtu(512);
    await super.onConnected();
    _requestInit();
  }

  Future<void> onDisconnected() async {
    logD("$name onDisconnected()");
    settings.value = ESPCCSettings();
    settings.notifyListeners();
    files.value = ESPCCFileList();
    files.notifyListeners();
    await apiOnDisconnected();
    await wifiOnDisconnected();
    await peerOnDisconnected();
    await super.onDisconnected();
  }

  /// request initial values, returned value is discarded
  /// because the message.done subscription will handle it
  void _requestInit() async {
    logD("Requesting init start");
    if (!await ready()) return;
    //await characteristic("api")?.write("init");

    await api.request<String>(
      "init",
      minDelayMs: 10000,
      maxAttempts: 3,
    );
    //await Future.delayed(Duration(milliseconds: 250));
  }

  Future<void> refreshFileList() async {
    if (files.value.syncing == ExtendedBool.True) {
      logD("refreshFileList() already refreshing");
      return;
    }
    files.value.syncing = ExtendedBool.True;
    files.notifyListeners();
    await api.requestResultCode("rec=files", expectValue: "files:");
    for (ESPCCFile f in files.value.files) f.updateLocalStatus();
    files.value.syncing = ExtendedBool.False;
    files.notifyListeners();
  }

  @override
  IconData get iconData => DeviceIcon("ESPCC").data();
}

class ESPCCFile with Debug {
  ESPCC device;
  String name;
  int remoteSize;
  int localSize;
  int distance;
  int altGain;
  ExtendedBool remoteExists;
  ExtendedBool localExists;
  bool _generatingGpx = false;
  Mutex _mutex = Mutex();

  /// flag for syncer queue
  bool cancelDownload = false;

  ESPCCFile(this.name, this.device,
      {this.remoteSize = -1,
      this.localSize = -1,
      this.distance = -1,
      this.altGain = -1,
      this.remoteExists = ExtendedBool.Unknown,
      this.localExists = ExtendedBool.Unknown});

  Future<void> updateLocalStatus() async {
    String? p = await path;
    if (null == p) return;
    final file = File(p);
    if (await file.exists()) {
      //logD("updateLocalStatus() local file $p exists");
      localExists = ExtendedBool.True;
      localSize = await file.length();
    } else {
      logD("updateLocalStatus() local file $p does not exist");
      localExists = ExtendedBool.False;
      localSize = -1;
    }
  }

  Future<String?> get path async {
    if (name.length < 1) return null;
    String? path = Platform.isAndroid ? await Path().external : await Path().documents;
    if (null == path) return null;
    String deviceName = "unnamedDevice";
    if (0 < device.name.length) deviceName = device.name;
    return "$path/${Path().sanitize(deviceName)}/rec/${Path().sanitize(name)}";
  }

  Future<File?> getLocal() async {
    String? p = await path;
    if (null == p) return null;
    return File(p);
  }

  Future<int> appendLocal({
    int? offset,
    String? data,
    Uint8List? byteData,
  }) async {
    String tag = "($name ef.hash $hashCode)";
    if (null != data && null != byteData) {
      logD("$tag both data and byteData present");
      return 0;
    }

    return _mutex.protect<int>(() async {
      File? f = await getLocal();
      if (null == f) {
        logD("$tag could not get local file");
        return 0;
      }
      if (!await f.exists()) {
        try {
          f = await f.create(recursive: true);
        } catch (e) {
          logE("$tag could not create ${await path}, error: $e");
          return 0;
        }
      }
      int sizeBefore = await f.length();
      if (null != offset && sizeBefore != (offset <= 0 ? 0 : offset - 1)) {
        logD("$tag local size is $sizeBefore but offset is $offset");
        return 0;
      }
      if (null != data && 0 < data.length)
        f = await f.writeAsString(
          data,
          mode: FileMode.append,
          flush: true,
        );
      else if (null != byteData && 0 < byteData.length)
        f = await f.writeAsBytes(
          byteData.toList(growable: false),
          mode: FileMode.append,
          flush: true,
        );
      else {
        logD("$tag need either data or byteData");
        return 0;
      }
      await updateLocalStatus();

      return localSize - sizeBefore;
    });
  }

  /// any file with a dot in the name is treated as non-binary :)
  bool get isBinary => name.indexOf(".") < 0;

  bool get isRec => isBinary;

  bool get isGpx => 0 < name.indexOf(".gpx");

  /// generates non-standard format for exporting to str%v#
  Future<bool> generateGpx({bool overwrite = false}) async {
    String tag = "$name";
    if (_generatingGpx) {
      logD("$tag already generating");
      return false;
    }
    _generatingGpx = true;
    if (!isRec) {
      logD("$tag not a rec file");
      _generatingGpx = false;
      return false;
    }
    File? f = await getLocal();
    if (null == f) {
      logD("$tag could not get local file");
      _generatingGpx = false;
      return false;
    }
    if (!await f.exists()) {
      logD("$tag local file does not exist");
      _generatingGpx = false;
      return false;
    }
    if (await f.length() <= 0) {
      logD("$tag local file has no size");
      _generatingGpx = false;
      return false;
    }
    String? p = await path;
    if (null == p || p.length < 5) {
      logD("$tag could not get path");
      _generatingGpx = false;
      return false;
    }
    String gpxPath = "$p-local.gpx";
    File g = File(gpxPath);
    if (await g.exists() && !overwrite) {
      logD("$tag $gpxPath already exists, not overwriting");
      _generatingGpx = false;
      return false;
    }
    int size = await f.length();
    var point = ESPCCDataPoint();
    var prevPoint = ESPCCDataPoint();
    int chunkSize = point.sizeInBytes;
    int toRead = 0;
    int cursor = 0;
    int pointsWritten = 0;
    bool done = false;
    // TODO lock file
    while (!done) {
      point = ESPCCDataPoint();
      toRead = chunkSize;
      if (size < cursor + chunkSize) {
        toRead = size - cursor;
        done = true;
      }
      if (toRead <= 0) {
        done = true;
        continue;
      }
      //logD("$tag size: $size, cursor: $cursor, toRead: $toRead");
      var raf = await f.open(mode: FileMode.read);
      raf = await raf.setPosition(cursor);
      point.fromList(await raf.read(toRead));
      await raf.close();
      if (0 == pointsWritten) {
        await g.writeAsString(
          _pointToGpxHeader(point),
          mode: FileMode.write, // truncate to zero
          flush: true,
        );
        logD("$tag header written");
      }
      if (prevPoint.time != 0 && (point.time < prevPoint.time || prevPoint.time + 7 * 86400 < point.time)) {
        // 7 days
        logD("$tag point #$pointsWritten: invalid time ${point.time} ${point.timeAsIso8601}");
        cursor += toRead;
        continue;
      }
      if (!point.hasLocation) {
        logD("$tag point #$pointsWritten: no location at  ${point.timeAsIso8601}");
        if (prevPoint.hasLocation) {
          logD("$tag copying location from prev point");
          point.lat = prevPoint.lat;
          point.lon = prevPoint.lon;
        } else {
          logD("$tag invalid point");
          cursor += toRead;
          continue;
        }
      }
      if (!point.hasAltitude && prevPoint.hasAltitude) {
        point.alt = prevPoint.alt;
        point.altitudeFlag = true;
      }
      if (!point.hasCadence && prevPoint.hasCadence) {
        point.cadence = prevPoint.cadence;
        point.cadenceFlag = true;
      }
      if (!point.hasPower && prevPoint.hasPower) {
        point.power = prevPoint.power;
        point.powerFlag = true;
      }
      if (!point.hasHeartrate && prevPoint.hasHeartrate) {
        point.heartrate = prevPoint.heartrate;
        point.heartrateFlag = true;
      }
      if (!point.hasTemperature && prevPoint.hasTemperature) {
        point.temperature = prevPoint.temperature;
        point.temperatureFlag = true;
      }
      await g.writeAsString(
        _pointToGpx(point),
        mode: FileMode.append,
        flush: true,
      );
      cursor += toRead;
      pointsWritten++;
      prevPoint.from(point);
    }
    logD("$tag $pointsWritten points written");
    if (0 < pointsWritten) {
      await g.writeAsString(
        _gpxFooter(),
        mode: FileMode.append,
        flush: true,
      );
      var size = await g.length();
      logD("$tag footer written, file size ${bytesToString(size)}");
    }
    _generatingGpx = false;
    return true;
  }

  String _pointToGpxHeader(ESPCCDataPoint p) {
    const String header = """<?xml version="1.0" encoding="UTF-8"?>
<gpx creator="espmui" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www.garmin.com/xmlschemas/GpxExtensionsv3.xsd http://www.garmin.com/xmlschemas/TrackPointExtension/v1 http://www.garmin.com/xmlschemas/TrackPointExtensionv1.xsd" version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1" xmlns:gpxx="http://www.garmin.com/xmlschemas/GpxExtensions/v3">
  <metadata>
    <time>%s</time>
  </metadata>
  <trk>
    <name>ride</name>
    <type>cycling</type>
    <trkseg>""";
    String s = sprintf(header, [p.timeAsIso8601]);
    //debugLog(s);
    return s;
  }

  String _pointToGpx(ESPCCDataPoint p) {
    if (!p.hasTime) return "";

    // TODO FIX sprintf strips the first newline
    const String pointFormat = """

      <trkpt%s>
        <time>%s</time>%s%s
      </trkpt>""";
    const String locationFormat = ' lat="%.7f" lon="%.7f"';
    const String altFormat = """

        <ele>%d</ele>""";
    const String extFormat = """

        <extensions>%s%s
        </extensions>""";
    const String powerFormat = """

          <power>%d</power>""";
    const String tpxFormat = """

          <gpxtpx:TrackPointExtension>%s%s%s
          </gpxtpx:TrackPointExtension>""";
    const String hrFormat = """

            <gpxtpx:hr>%d</gpxtpx:hr>""";
    const String cadFormat = """

            <gpxtpx:cad>%d</gpxtpx:cad>""";
    const String tempFormat = """

            <gpxtpx:atemp>%.1f</gpxtpx:atemp>""";

    bool hasTpx = p.hasHeartrate || p.hasCadence || p.hasTemperature;

    final String s = sprintf(pointFormat, [
      p.hasLocation ? sprintf(locationFormat, [p.lat, p.lon]) : "",
      p.timeAsIso8601,
      p.hasAltitude ? sprintf(altFormat, [p.alt]) : "",
      p.hasPower || hasTpx
          ? sprintf(extFormat, [
              p.hasPower ? sprintf(powerFormat, [p.power]) : "",
              hasTpx
                  ? sprintf(tpxFormat, [
                      p.hasHeartrate ? sprintf(hrFormat, [p.heartrate]) : "",
                      p.hasCadence ? sprintf(cadFormat, [p.cadence]) : "",
                      p.hasTemperature ? sprintf(tempFormat, [p.temperature]) : "",
                    ])
                  : "",
            ])
          : "",
    ]);
    //debugLog(s);
    return s;
  }

  String _gpxFooter() {
    const String s = """

    </trkseg>
  </trk>
</gpx>""";
    //debugLog(s);
    return s;
  }

  void update({
    String? name,
    ESPCC? device,
    int? remoteSize,
    int? localSize,
    int? distance,
    int? altGain,
    ExtendedBool? remoteExists,
    ExtendedBool? localExists,
  }) {
    if (null != name) this.name = name;
    if (null != device) this.device = device;
    if (null != remoteSize) this.remoteSize = remoteSize;
    if (null != localSize) this.localSize = localSize;
    if (null != distance) this.distance = distance;
    if (null != altGain) this.altGain = altGain;
    if (null != remoteExists) this.remoteExists = remoteExists;
    if (null != localExists) this.localExists = localExists;
  }

  @override
  bool operator ==(other) {
    return (other is ESPCCFile) &&
        other.device == device &&
        other.name == name &&
        other.remoteSize == remoteSize &&
        //other.localSize == localSize &&
        other.distance == distance &&
        other.altGain == altGain &&
        other.remoteExists == remoteExists &&
        other.localExists == localExists;
  }

  @override
  int get hashCode =>
      device.hashCode ^
      name.hashCode ^
      remoteSize.hashCode ^
      localSize.hashCode ^
      distance.hashCode ^
      altGain.hashCode ^
      remoteExists.hashCode ^
      localExists.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "name: $name, "
        "device: ${device.name}, "
        "remoteSize: $remoteSize, "
        "localSize: $localSize, "
        "distance: $distance, "
        "altGain: $altGain, "
        "remote: $remoteExists, "
        "local: $localExists "
        ")";
  }
}

class ESPCCSettings with Debug {
  Map<int, int> touchThres = {};
  Map<int, int> touchRead = {};
  bool touchEnabled = true;
  bool otaMode = false;
  int recording = ESPCCRecordingState.UNKNOWN;
  Map<String, TextEditingController> peerPasskeyEditingControllers = {};
  int vescBattNumSeries = -1;
  double vescBattCapacityWh = -1;
  int vescMaxPower = -1;
  double vescMinCurrent = -1;
  double vescMaxCurrent = -1;
  ExtendedBool vescRampUp = ExtendedBool.Unknown;
  ExtendedBool vescRampDown = ExtendedBool.Unknown;
  double vescRampMinCurrentDiff = -1;
  int vescRampNumSteps = -1;
  int vescRampTime = -1;
  int vescTempMotorWarning = -1;
  int vescTempMotorLimit = -1;
  int vescTempEscWarning = -1;
  int vescTempEscLimit = -1;

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "";
    //logD("$tag $message");
    //String? valueS = message.valueAsString;

    if ("touch" == message.commandStr) {
      String? v = message.valueAsString;
      if (null == v) return false;
      if (0 == v.indexOf("read:")) {
        List<String> values = v.substring("read:".length).split(",");
        int index = 0;
        Map<int, int> readings = {};
        values.forEach((value) {
          int? i = int.tryParse(value);
          if (null == i) return;
          readings[index] = i;
          index++;
        });
        touchRead = readings;
        logD("$tag touchRead=$touchRead");
        return true;
      }
      if (0 == v.indexOf("thresholds:")) {
        List<String> values = v.substring("thresholds:".length).split(",");
        int index = 0;
        Map<int, int> thresholds = {};
        values.forEach((value) {
          int? i = int.tryParse(value);
          if (null == i) return;
          thresholds[index] = i;
          index++;
        });
        touchThres = thresholds;
        logD("$tag touchThres=$touchThres");
        return true;
      }
      if (0 == v.indexOf("enabled:")) {
        int? i = int.tryParse(v.substring("enabled:".length));
        if (null != i) {
          touchEnabled = 0 < i;
          logD("$tag touchEnabled=$touchEnabled");
        }
      }
      return true;
    }

    if ("rec" == message.commandStr) {
      int? i = message.valueAsInt;
      String? s = message.valueAsString;
      if (null != i && null != s && 1 == s.length && int.tryParse(s) == i) {
        recording = (ESPCCRecordingState.MIN < i && i < ESPCCRecordingState.MAX) ? i : ESPCCRecordingState.UNKNOWN;
        //logD("$tag received rec=${message.value}, parsed recording=${ESPCCRecordingState.getString(recording)}");
        return true;
      }
      return false;
    }

    if ("vesc" == message.commandStr) {
      if (null == message.valueAsString) return false;
      List<String> tokens = message.valueAsString!.split("|");
      tokens.forEach((token) {
        List<String> pair = token.split(":");
        if (2 != pair.length) {
          logD("$tag invalid token: $token");
          return;
        }
        switch (pair[0]) {
          case "BNS":
            vescBattNumSeries = int.tryParse(pair[1]) ?? vescBattNumSeries;
            break;
          case "BC":
            vescBattCapacityWh = double.tryParse(pair[1]) ?? vescBattCapacityWh;
            break;
          case "MP":
            vescMaxPower = int.tryParse(pair[1]) ?? vescMaxPower;
            break;
          case "MiC":
            vescMinCurrent = double.tryParse(pair[1]) ?? vescMinCurrent;
            break;
          case "MaC":
            vescMaxCurrent = double.tryParse(pair[1]) ?? vescMaxCurrent;
            break;
          case "RU":
            vescRampUp = ExtendedBool.fromString(pair[1]);
            break;
          case "RD":
            vescRampDown = ExtendedBool.fromString(pair[1]);
            break;
          case "RMCD":
            vescRampMinCurrentDiff = double.tryParse(pair[1]) ?? vescRampMinCurrentDiff;
            break;
          case "RNS":
            vescRampNumSteps = int.tryParse(pair[1]) ?? vescRampNumSteps;
            break;
          case "RT":
            vescRampTime = int.tryParse(pair[1]) ?? vescRampTime;
            break;
          case "TMW":
            vescTempMotorWarning = int.tryParse(pair[1]) ?? vescTempMotorWarning;
            break;
          case "TML":
            vescTempMotorLimit = int.tryParse(pair[1]) ?? vescTempMotorLimit;
            break;
          case "TEW":
            vescTempEscWarning = int.tryParse(pair[1]) ?? vescTempEscWarning;
            break;
          case "TEL":
            vescTempEscLimit = int.tryParse(pair[1]) ?? vescTempEscLimit;
            break;
          default:
            logD("$tag unknown name: token: $token, name: ${pair[0]}, value: ${pair[1]}");
        }
      });
      logD("$tag updated settings: $this");
      return true;
    }

    if ("system" == message.commandStr) {
      if ("ota" == message.valueAsString) {
        otaMode = true;
        return true;
      }
      return false;
    }

    return false;
  }

  @override
  bool operator ==(other) {
    return (other is ESPCCSettings) &&
        other.touchThres == touchThres &&
        other.touchEnabled == touchEnabled &&
        other.otaMode == otaMode &&
        other.recording == recording &&
        other.vescBattNumSeries == vescBattNumSeries &&
        other.vescBattCapacityWh == vescBattCapacityWh &&
        other.vescMaxPower == vescMaxPower &&
        other.vescMinCurrent == vescMinCurrent &&
        other.vescMaxCurrent == vescMaxCurrent &&
        other.vescRampUp == vescRampUp &&
        other.vescRampDown == vescRampDown &&
        other.vescRampMinCurrentDiff == vescRampMinCurrentDiff &&
        other.vescRampNumSteps == vescRampNumSteps &&
        other.vescRampTime == vescRampTime;
  }

  @override
  int get hashCode =>
      touchThres.hashCode ^
      touchEnabled.hashCode ^
      otaMode.hashCode ^
      recording.hashCode ^
      vescBattNumSeries.hashCode ^
      vescBattCapacityWh.hashCode ^
      vescMaxPower.hashCode ^
      vescMinCurrent.hashCode ^
      vescMaxCurrent.hashCode ^
      vescRampUp.hashCode ^
      vescRampDown.hashCode ^
      vescRampMinCurrentDiff.hashCode ^
      vescRampNumSteps.hashCode ^
      vescRampTime.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "touchThres: $touchThres, "
        "touchEnabled: $touchEnabled, "
        "otaMode: $otaMode, "
        "recording: $recording, "
        "vescBattNumSeries: $vescBattNumSeries, "
        "vescBattCapacityWh: $vescBattCapacityWh, "
        "vescMaxPower: $vescMaxPower, "
        "vescMinCurrent: $vescMinCurrent, "
        "vescMaxCurrent: $vescMaxCurrent, "
        "vescRampUp: $vescRampUp, "
        "vescRampDown: $vescRampDown, "
        "vescRampMinCurrentDiff: $vescRampMinCurrentDiff, "
        "vescRampNumSteps: $vescRampNumSteps, "
        "vescRampTime: $vescRampTime"
        ")";
  }
}

class ESPCCRecordingState {
  static const int MIN = -2;
  static const int UNKNOWN = -1;
  static const int NOT_RECORDING = 0;
  static const int RECORDING = 1;
  static const int PAUSED = 2; // TODO
  static const int MAX = 3;

  static String getString(int value) {
    if (value <= MIN || MAX <= value) return "invalid";
    if (value == NOT_RECORDING) return "stopped";
    if (value == RECORDING) return "recording";
    if (value == PAUSED) return "paused";
    return "...";
  }
}

/*
    struct DataPoint {
        byte flags = 0;           // length: 1;
        time_t time = 0;          // length: 4; unit: seconds; UTS
        double lat = 0.0;         // length: 8; GCS latitude 0°... 90˚
        double lon = 0.0;         // length: 8; GCS longitude 0°... 180˚
        int16_t altitude = 0;     // length: 2; unit: m
        uint16_t power = 0;       // length: 2; unit: W
        uint8_t cadence = 0;      // length: 1; unit: rpm
        uint8_t heartrate = 0;    // length: 1; unit: bpm
        int16_t temperature = 0;  // length: 2; unit: ˚C / 10; unused
    };
*/
class ESPCCDataPoint with Debug {
  static const String _tag = "ESPCCDataPoint";
  static const Endian _endian = Endian.little;

  var _flags = Uint8List(1);
  var _time = Uint8List(4);
  var _lat = Uint8List(8);
  var _lon = Uint8List(8);
  var _alt = Uint8List(2);
  var _power = Uint8List(2);
  var _cadence = Uint8List(1);
  var _heartrate = Uint8List(1);
  var _temperature = Uint8List(2);

  bool fromList(Uint8List bytes) {
    String tag = "$_tag";
    if (bytes.length < sizeInBytes) {
      logD("$tag incorrect length: ${bytes.length}, need at least $sizeInBytes");
      return false;
    }
    //logD("$tag $bytes");
    int cursor = 0;
    _flags = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    _time = bytes.sublist(cursor, cursor + 4);
    cursor += 4;
    if (locationFlag) _lat = bytes.sublist(cursor, cursor + 8);
    cursor += 8;
    if (locationFlag) _lon = bytes.sublist(cursor, cursor + 8);
    cursor += 8;
    if (altitudeFlag) _alt = bytes.sublist(cursor, cursor + 2);
    cursor += 2;
    if (powerFlag) _power = bytes.sublist(cursor, cursor + 2);
    cursor += 2;
    if (cadenceFlag) _cadence = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    if (heartrateFlag) _heartrate = bytes.sublist(cursor, cursor + 1);
    cursor += 1;
    if (temperatureFlag) _temperature = bytes.sublist(cursor, cursor + 2);
    return true;
  }

  bool from(ESPCCDataPoint p) {
    _flags = Uint8List.fromList(p.flagsList);
    _time = Uint8List.fromList(p.timeList);
    _lat = Uint8List.fromList(p.latList);
    _lon = Uint8List.fromList(p.lonList);
    _alt = Uint8List.fromList(p.altList);
    _power = Uint8List.fromList(p.powerList);
    _cadence = Uint8List.fromList(p.cadenceList);
    _heartrate = Uint8List.fromList(p.heartrateList);
    _temperature = Uint8List.fromList(p.temperatureList);
    return true;
  }

  /// 2022-01-01 00:00:00 < time < 2122-01-01 00:00:00
  bool get hasTime {
    int t = time;
    return 1640995200 < t && t < 4796668800;
  }

  bool get locationFlag => 0 < _flags[0] & ESPCCDataPointFlags.location;
  bool get hasLocation {
    if (!locationFlag) return false;
    double d = lat;
    if (d < 0 || 90 < d) return false;
    d = lon;
    if (d < 0 || 180 < d) return false;
    return true;
  }

  bool get altitudeFlag => 0 < _flags[0] & ESPCCDataPointFlags.altitude;
  set altitudeFlag(bool b) => _flags[0] |= b ? ESPCCDataPointFlags.altitude : ~ESPCCDataPointFlags.altitude;
  bool get hasAltitude {
    if (!altitudeFlag) return false;
    int i = alt;
    return (-500 < i && i < 10000);
  }

  bool get powerFlag => 0 < _flags[0] & ESPCCDataPointFlags.power;
  set powerFlag(bool b) => _flags[0] |= b ? ESPCCDataPointFlags.power : ~ESPCCDataPointFlags.power;
  bool get hasPower {
    if (!powerFlag) return false;
    int i = power;
    return (0 <= i && i < 3000);
  }

  bool get cadenceFlag => 0 < _flags[0] & ESPCCDataPointFlags.cadence;
  set cadenceFlag(bool b) => _flags[0] |= b ? ESPCCDataPointFlags.cadence : ~ESPCCDataPointFlags.cadence;
  bool get hasCadence {
    if (!cadenceFlag) return false;
    int i = cadence;
    return (0 <= i && i < 200);
  }

  bool get heartrateFlag => 0 < _flags[0] & ESPCCDataPointFlags.heartrate;
  set heartrateFlag(bool b) => _flags[0] |= b ? ESPCCDataPointFlags.heartrate : ~ESPCCDataPointFlags.heartrate;
  bool get hasHeartrate {
    //String tag = "$_tag";
    //logD("$tag flags: ${_flags[0]}");
    if (!heartrateFlag) return false;
    int i = heartrate;
    //logD("$tag heartrate: $i");
    return (30 <= i && i < 230);
  }

  bool get temperatureFlag => 0 < _flags[0] & ESPCCDataPointFlags.temperature;
  set temperatureFlag(bool b) => _flags[0] |= b ? ESPCCDataPointFlags.temperature : ~ESPCCDataPointFlags.temperature;
  bool get hasTemperature {
    if (!temperatureFlag) return false;
    double f = temperature;
    return (-50 <= f && f < 70);
  }

  bool get hasLap => 0 < _flags[0] & ESPCCDataPointFlags.lap;

  int get flags => _flags.buffer.asByteData().getUint8(0);
  Uint8List get flagsList => _flags;
  int get time => _time.buffer.asByteData().getInt32(0, _endian);
  Uint8List get timeList => _time;
  double get lat => _lat.buffer.asByteData().getFloat64(0, _endian);
  Uint8List get latList => _lat;
  set lat(double f) => _lat.buffer.asByteData().setFloat64(0, f, _endian);
  double get lon => _lon.buffer.asByteData().getFloat64(0, _endian);
  Uint8List get lonList => _lon;
  set lon(double f) => _lon.buffer.asByteData().setFloat64(0, f, _endian);
  int get alt => _alt.buffer.asByteData().getInt16(0, _endian);
  Uint8List get altList => _alt;
  set alt(int i) => _alt.buffer.asByteData().setInt16(0, i, _endian);
  int get power => _power.buffer.asByteData().getUint16(0, _endian);
  Uint8List get powerList => _power;
  set power(int i) => _power.buffer.asByteData().setUint16(0, i, _endian);
  int get cadence => _cadence.buffer.asByteData().getUint8(0);
  Uint8List get cadenceList => _cadence;
  set cadence(int i) => _cadence.buffer.asByteData().setUint8(0, i);
  int get heartrate => _heartrate.buffer.asByteData().getUint8(0);
  Uint8List get heartrateList => _heartrate;
  set heartrate(int i) => _heartrate.buffer.asByteData().setUint8(0, i);
  double get temperature => _temperature.buffer.asByteData().getInt16(0, _endian) / 100;
  Uint8List get temperatureList => _temperature;
  set temperature(double f) => _temperature.buffer.asByteData().setInt16(0, (f * 100).toInt(), _endian);

  /// example: 2022-03-25T12:58:13Z
  String get timeAsIso8601 => DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'").format(DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true));

  /// example: 2022-03-25T12:58:13.000Z
  //String get timeAsIso8601 => DateTime.fromMillisecondsSinceEpoch(time * 1000, isUtc: true).toIso8601String();

  String get debug => "flags: ${_flags.toList()}, time: ${_time.toList()}, ";

  /*
  set flags(int v) {
    if (v < 0 || 255 < v) {
      logD("$_tag set flags out of range: $v");
      return;
    }
    _flags.buffer.asByteData().setUint8(0, v);
  }
  set time(int v) {
    if (v < -2147483648 || 2147483647 < v) {
      logD("$_tag set time out of range: $v");
      return;
    }
    _time.buffer.asByteData().setInt32(0, v, _endian);
  }
  ...
  */

  int get sizeInBytes =>
      _flags.length + //
      _time.length +
      _lat.length +
      _lon.length +
      _alt.length +
      _power.length +
      _cadence.length +
      _heartrate.length +
      _temperature.length;
}

/*
    struct Flags {
        const byte location = 1;
        const byte altitude = 2;
        const byte power = 4;
        const byte cadence = 8;
        const byte heartrate = 16;
        const byte temperature = 32;  
        const byte lap = 64;          // unused
    } const Flags;
*/
class ESPCCDataPointFlags {
  static const int location = 1;
  static const int altitude = 2;
  static const int power = 4;
  static const int cadence = 8;
  static const int heartrate = 16;
  static const int temperature = 32;
  static const int lap = 64;
}

class ESPCCFileList {
  List<ESPCCFile> files = [];
  var syncing = ExtendedBool.Unknown;

  bool has(String name) {
    bool exists = false;
    for (ESPCCFile f in files) {
      if (f.name == name) {
        exists = true;
        break;
      }
    }
    return exists;
  }

  @override
  bool operator ==(other) {
    return (other is ESPCCFileList) && other.files == files;
  }

  @override
  int get hashCode => files.hashCode;

  String toString() {
    return "${describeIdentity(this)} ("
        "files: $files"
        ")";
  }
}
