import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'ble_characteristic.dart';
import 'device.dart';
import 'util.dart';
import 'debug.dart';

/*
enum ApiCommand {
  invalid,
  wifi,
  hostName,
  reboot,
  passkey,
  secureApi,
  weightService,
  calibrateStrain,
  tare,
  wifiApEnabled,
  wifiApSSID,
  wifiApPassword,
  wifiStaEnabled,
  wifiStaSSID,
  wifiStaPassword,
  crankLength,
  reverseStrain,
  doublePower,
  sleepDelay,
  hallChar,
  hallOffset,
  hallThreshold,
  hallThresLow,
  strainThreshold,
  strainThresLow,
  motionDetectionMethod,
  sleep,
  negativeTorqueMethod,
  autoTare,
  autoTareDelayMs,
  autoTareRangeG,
  config,
}
*/
/*
enum ApiResult {
  invalid,
  success,
  error,
  unknownCommand,
  commandTooLong,
  argTooLong,
  stringInvalid,
  passkeyInvalid,
  secureApiInvalid,
  calibrationFailed,
  tareFailed,
  argInvalid,
}
*/
class ApiResult {
  static int get success => 1;
}

typedef void ApiCallback(ApiMessage message);

class ApiMessage with Debug {
  Api api;

  /// the original unparsed command
  String command;

  /// parsed command string
  String? commandStr;

  /// parsed command code
  int? commandCode;

  /// parsed command arg
  String? arg;

  /// reply value expected to start with this string
  String? expectValue;

  /// callback when message is done
  ApiCallback? onDone;

  /// maximum number of resend attempts
  int maxAttempts = 3;

  /// minimum delay between resends (ms)
  int minDelayMs = 3000;

  /// maximum age before giving up (ms)
  int maxAgeMs = 10000;

  int createdAt = 0;
  int? lastSentAt;
  int? attempts;
  int? resultCode;
  String? resultStr;
  String? info;
  String? value;
  bool? isDone;

  ApiMessage(
    this.api,
    this.command, {
    this.expectValue,
    this.onDone,
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) {
    createdAt = uts();
    this.maxAttempts = maxAttempts ?? this.maxAttempts;
    this.minDelayMs = minDelayMs ?? this.minDelayMs;
    this.maxAgeMs = maxAgeMs ?? this.maxAgeMs;
    if (this.maxAttempts < 1) this.maxAttempts = 1;
    if (this.maxAttempts > 10) this.maxAttempts = 10;
    if (this.minDelayMs < 50) this.minDelayMs = 50;
    if (this.minDelayMs > 10000) this.minDelayMs = 10000;
    var maxAttemtsTotalTime = this.maxAttempts * this.minDelayMs;
    if (this.maxAgeMs < maxAttemtsTotalTime) this.maxAgeMs = maxAttemtsTotalTime + this.minDelayMs;
  }

  /// Attempts to create commandCode and commandStr from command
  void parseCommand() {
    if (commandCode != null) return; // already parsed
    //debugLog("parsing: $command");
    int eqSign = command.indexOf("=");
    String? parsedArg;
    if (eqSign > 0) {
      parsedArg = command.substring(eqSign + 1);
      if (parsedArg.length > 0) arg = parsedArg.toString();
      command = command.substring(0, eqSign);
      if (command.length > 0) commandStr = command.toString();
    }
    var intParsed = int.tryParse(command);
    for (int k in api.commands.keys) {
      if (k == intParsed || api.commands[k] == command) {
        commandCode = k;
        commandStr = api.commands[k];
        break;
      }
    }
    if (commandCode == null) {
      resultCode = -1;
      resultStr = "ClientError";
      info = "Unrecognized command";
      isDone = true;
    }
    //debugLog("parsed: " + toString());
  }

  void checkAge() {
    if (createdAt + maxAgeMs <= uts()) {
      debugLog("max age reached: " + toString());
      resultCode = -1;
      resultStr = "ClientError";
      info = "Maximum age reached";
      isDone = true;
    }
  }

  void checkAttempts() {
    if (maxAttempts <= (attempts ?? 0)) {
      debugLog("max attmpts reached: " + toString());
      resultCode = -1;
      resultStr = "ClientError";
      info = "Maximum attempts reached";
      isDone = true;
    }
  }

  void destruct() {
    //debugLog("destruct " + toString());
    isDone = true;
    //info = ((info == null) ? "" : info.toString()) + " destructed";
  }

  String toString() {
    return "$runtimeType (" +
        "command: '$command'" +
        ((commandStr != null) ? ", commandStr='$commandStr'" : "") +
        ((commandCode != null) ? ", commandCode='$commandCode'" : "") +
        ((expectValue != null) ? ", expectValue='$expectValue'" : "") +
        ((arg != null) ? ", arg='$arg'" : "") +
        ((onDone != null) ? ", onDone='$onDone'" : "") +
        ", maxAttempts='$maxAttempts'" +
        ", minDelayMs='$minDelayMs'" +
        ", maxAgeMs='$maxAgeMs'" +
        ", createdAt='$createdAt'" +
        ((lastSentAt != null) ? ", lastSentAt='$lastSentAt'" : "") +
        ((attempts != null) ? ", attempts='$attempts'" : "") +
        ((resultCode != null) ? ", resultCode='$resultCode'" : "") +
        ((resultStr != null) ? ", resultStr='$resultStr'" : "") +
        ((info != null) ? ", info='$info'" : "") +
        ((value != null) ? ", value='$value'" : "") +
        ((isDone != null) ? ", isDone='$isDone'" : "") +
        ")";
  }

  bool? get valueAsBool {
    if ("1:true" == value) return true;
    if ("0:false" == value) return false;
    if ("1" == value) return true;
    if ("0" == value) return false;
    if ("true" == value) return true;
    if ("false" == value) return false;
    return null;
  }

  int? get valueAsInt => int.tryParse(value ?? "");
  double? get valueAsDouble => double.tryParse(value ?? "");
  String? get valueAsString => value;
}

class Api with Debug {
  Device device;
  ApiCharacteristic? get characteristic => device.characteristic("api") as ApiCharacteristic?;
  late StreamSubscription<String>? _subscription;
  final _doneController = StreamController<ApiMessage>.broadcast();
  Stream<ApiMessage> get messageDoneStream => _doneController.stream;
  final _queue = Queue<ApiMessage>();
  bool _running = false;
  Timer? _timer;
  final int queueDelayMs;

  Map<int, String> commands = {1: "init"};
  int? commandCode(String s) => commands.containsValue(s) ? commands.keys.firstWhere((k) => commands[k] == s) : null;
  String? commandStr(int commandCode) => commands.containsKey(commandCode) ? commands[commandCode] : null;

  Api(this.device, {this.queueDelayMs = 200}) {
    //_characteristic?.subscribe();
    _subscription = characteristic?.defaultStream.listen((reply) => _onNotify(reply));
  }

  void _startQueueSchedule() {
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

  /// format: resultCode:resultStr;commandCode:commandStr=[value]
  void _onNotify(String reply) {
    //debugLog("_onNotify() $reply");
    int resultEnd = reply.indexOf(";");
    if (resultEnd < 1) {
      debugLog("Error parsing notification: $reply");
      return;
    }
    String result = reply.substring(0, resultEnd);
    int colon = result.indexOf(":");
    int? resultCode = -1;
    String resultCodeStr = "";
    String resultStr = "";
    if (0 < colon) {
      resultCodeStr = result.substring(0, colon);
      resultStr = result.substring(colon + 1);
      resultCode = int.tryParse(resultCodeStr);
    } else
      resultCode = int.tryParse(result);
    if (resultCode == null) {
      debugLog("Error parsing resultCode as int");
      return;
    }
    String commandWithValue = reply.substring(resultEnd + 1);
    int eq = commandWithValue.indexOf("=");
    if (eq < 1) {
      debugLog("Error parsing commandWithValue: $commandWithValue");
      return;
    }
    String commandCodeStr = commandWithValue.substring(0, eq);
    int? commandCode = int.tryParse(commandCodeStr);
    if (commandCode == null) {
      debugLog("Error parsing commandCode as int: $commandCodeStr");
      return;
    }
    // String commandStrWithValue = commandWithValue.substring(colon + 1);
    // int eq = commandStrWithValue.indexOf("=");
    // if (eq < 1) {
    //   debugLog("Error parsing commandStrWithValue: $commandStrWithValue");
    //   return;
    // }
    //String commandStr = commandStrWithValue.substring(0, eq);
    String value = commandWithValue.substring(eq + 1);
    int matches = 0;
    for (ApiMessage m in _queue) {
      if (m.commandCode == commandCode) {
        //debugLog("expected: '${m.expectValue}' got '${value.substring(0, min(m.expectValue!.length, value.length))}'");
        // no match if expected value is set and value does not begin with it
        if (m.expectValue != null && m.expectValue != value.substring(0, min(m.expectValue!.length, value.length))) continue;
        matches++;
        m.resultCode = resultCode;
        m.resultStr = resultStr;
        m.value = value;
        m.isDone = true;
        // don't return on the first match, process all matching messages
      }
    }
    if (matches == 0) {
      // debugLog("_onNotify() No matching queued message for the reply $reply, generating new one");
      var cStr = commandStr(commandCode);
      if (null == cStr) {
        debugLog("_onNotify() commandStr is null");
        return;
      }
      var m = ApiMessage(
        this,
        cStr,
      );
      m.commandStr = cStr;
      m.commandCode = commandCode;
      m.resultCode = resultCode;
      m.resultStr = resultStr;
      m.value = value;
      m.isDone = true;
      _onDone(m);
    }
  }

  void _onDone(ApiMessage message) {
    //debugLog("_onDone $message");
    streamSendIfNotClosed(_doneController, message);
    if (null == message.onDone) return;
    var onDone = message.onDone;
    message.onDone = null;
    onDone!(message);
  }

  /// Sends a command to the API.
  ///
  /// Command format: commandCode|commandStr[=[arg]]
  ///
  /// If supplied, [onDone] will be called with the [ApiMessage] containing the
  /// [resultCode] on completion.
  ///
  /// Note the returned [ApiMessage] does not yet contain the reply.
  ApiMessage sendCommand(
    String command, {
    String? expectValue,
    ApiCallback? onDone,
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) {
    var message = ApiMessage(
      this,
      command,
      expectValue: expectValue,
      onDone: onDone,
      maxAttempts: maxAttempts,
      minDelayMs: minDelayMs,
      maxAgeMs: maxAgeMs,
    );
    // check queue for duplicate commands and remove them as this one will be newer
    int before = _queue.length;
    _queue.removeWhere((queued) => queued.command == message.command);
    int removed = before - _queue.length;
    if (removed > 0) debugLog("removed $removed duplicate messages");
    //debugLog("adding to queue: $message");
    _queue.add(message);
    _runQueue();
    return message;
  }

  /// Requests a value from the device API
  Future<T?> request<T>(
    String command, {
    String? expectValue,
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) async {
    var message = sendCommand(
      command,
      expectValue: expectValue,
      maxAttempts: maxAttempts,
      minDelayMs: minDelayMs,
      maxAgeMs: maxAgeMs,
    );
    await isDone(message);
    if (T == ApiMessage) return message as T?;
    if (T == String) return message.valueAsString as T?;
    if (T == double) return message.valueAsDouble as T?;
    if (T == int) return message.valueAsInt as T?;
    if (T == bool) return message.valueAsBool as T?;
    debugLog("request() error: type $T is not handled");
    return message as T?;
  }

  /// Requests a result from the device API
  Future<int?> requestResultCode(
    String command, {
    String? expectValue,
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) async {
    var message = sendCommand(
      command,
      expectValue: expectValue,
      maxAttempts: maxAttempts,
      minDelayMs: minDelayMs,
      maxAgeMs: maxAgeMs,
    );
    await isDone(message);
    return message.resultCode;
  }

  /// Polls the message while [isDone] != true && [resultCode] == null
  /// TODO use a stream (each message could have an onChangedStream?)
  Future<void> isDone(ApiMessage message) async {
    await Future.doWhile(() async {
      if (message.isDone != true && message.resultCode == null) {
        //debugLog("polling...");
        // TODO milliseconds: [message.minDelay, queueDelayMs].max
        await Future.delayed(Duration(milliseconds: queueDelayMs));
        return true;
      }
      //debugLog("poll end");
      return false;
    });
  }

  bool queueContainsCommand({String? commandStr, int? command}) {
    for (ApiMessage message in _queue)
      if ((null != commandStr && message.commandStr == commandStr) //
          ||
          (null != command && message.commandCode == command)) return true;
    return false;
  }

  void _runQueue() async {
    if (_running) {
      //debugLog("_runQueue() already running");
      return;
    }
    _running = true;
    if (_queue.isEmpty) {
      _stopQueueSchedule();
      _running = false;
      return;
    }
    //debugLog("queue run");
    var message = _queue.removeFirst();
    message.parseCommand();
    message.checkAge();
    message.checkAttempts();
    if (message.isDone == true) {
      message.isDone = null;
      _onDone(message);
      message.destruct();
    } else {
      _send(message);
      _queue.addLast(message);
    }
    await Future.delayed(Duration(milliseconds: queueDelayMs));
    if (_queue.isNotEmpty) _startQueueSchedule();
    _running = false;
  }

  void _send(ApiMessage message) async {
    int now = uts();
    if (now < (message.lastSentAt ?? 0) + message.minDelayMs) return;
    if (!await device.ready()) {
      debugLog("_send() not ready");
      return;
    }
    message.lastSentAt = now;
    message.attempts = (message.attempts ?? 0) + 1;
    String toWrite = message.commandCode.toString();
    var arg = message.arg;
    if (arg != null) toWrite += "=$arg";
    //debugLog("_send() calling char.write($toWrite)");
    characteristic?.write(toWrite);
  }

  Future<void> destruct() async {
    debugLog("destruct");
    _stopQueueSchedule();
    await _subscription?.cancel();
    while (_queue.isNotEmpty) {
      var message = _queue.removeFirst();
      message.destruct();
    }
    _doneController.close();
  }
}
