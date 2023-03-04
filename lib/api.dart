import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'ble_characteristic.dart';
import 'device.dart';
import 'util.dart';
import 'debug.dart';

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

  /// generic local error
  static int get localError => 100;

  /// local filesystem error
  static int get localFsError => 110;

  /// local BT error
  static int get localBtError => 120;
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
      debugLog("parseCommand() failed: $command");
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
  ApiLogCharacteristic? get logCharacteristic => device.characteristic("apiLog") as ApiLogCharacteristic?;
  late StreamSubscription<String>? _subscription;
  final _doneController = StreamController<ApiMessage>.broadcast();
  Stream<ApiMessage> get messageSuccessStream => _doneController.stream;
  final _queue = Queue<ApiMessage>();
  bool _running = false;
  Timer? _timer;
  final int queueDelayMs;

  final Map<int, String> _initialCommands = {1: "init"};
  Map<int, String> commands = {};

  int? commandCode(String s, {bool logOnError = true}) {
    if (commands.containsValue(s)) return commands.keys.firstWhere((k) => commands[k] == s);
    if (logOnError) debugLog("${device.name} code not found for command $s");
    return null;
  }

  String? commandStr(int code) {
    if (commands.containsKey(code)) return commands[code];
    debugLog("str not found for command code $code");
    return null;
  }

  Api(this.device, {this.queueDelayMs = 200}) {
    commands.addAll(_initialCommands);
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

  /// format: resultCode[:resultStr];commandCode[]:commandStr][=[value]]
  void _onNotify(String reply) {
    String tag = "${device.name} Api._onNotify()";
    debugLog("$tag $reply");
    int resultEnd = reply.indexOf(";");
    if (resultEnd < 1) {
      debugLog("$tag Error parsing notification: $reply");
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
      debugLog("$tag Error parsing resultCode as int");
      return;
    }
    String commandWithValue = reply.substring(resultEnd + 1);
    int eq = commandWithValue.indexOf("=");
    if (eq < 1) {
      debugLog("$tag Error parsing commandWithValue: $commandWithValue");
      return;
    }
    String commandCodeStr = commandWithValue.substring(0, eq);
    int? commandCode = int.tryParse(commandCodeStr);
    if (commandCode == null) {
      debugLog("$tag Error parsing commandCode as int: $commandCodeStr");
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
        if (m.expectValue != null) {
          //debugLog("expected: '${m.expectValue}' got '${value.substring(0, min(m.expectValue!.length, value.length))}'");
          // no match if expected value is set and value does not begin with it
          if (m.expectValue != value.substring(0, min(m.expectValue!.length, value.length))) continue;
        }
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
        debugLog("$tag  commandStr is null");
        return;
      }
      var m = ApiMessage(this, cStr);
      m.commandStr = cStr;
      m.commandCode = commandCode;
      m.resultCode = resultCode;
      m.resultStr = resultStr;
      m.value = value;
      m.isDone = true;
      _onDone(m);
    }
  }

  Future<void> _onDone(ApiMessage message) async {
    //String tag = "${device.name} Api._onDone()";
    if (null != message.onDone) {
      var onDone = message.onDone;
      message.onDone = null;
      onDone!(message);
    }
    if (message.resultCode != ApiResult.success) return;
    if (await handleApiMessageSuccess(message)) return;
    streamSendIfNotClosed(_doneController, message);
  }

  /// returns true if the message does not need any further handling
  Future<bool> handleApiMessageSuccess(ApiMessage message) async {
    String tag = "${device.name} Api.handleApiMessageSuccess()";
    //debugLog("$tag handleApiMessageSuccess $message");

    if ("init" == message.commandStr) {
      if (null == message.value) {
        debugLog("$tag init value null");
        return true;
      }
      List<String> tokens = message.value!.split(";");
      tokens.forEach((token) {
        int? code;
        String? command;
        String? value;
        List<String> parts = token.split("=");
        if (parts.length == 1) {
          //debugLog("parts.length == 1; $parts");
          value = null;
        } else
          value = parts[1];
        List<String> c = parts[0].split(":");
        if (c.length != 2) {
          //debugLog("c.length != 2; $c");
          return;
        }
        code = int.tryParse(c[0]);
        command = c[1];
        //debugLog("handleApiMessageSuccess() init: $code:$command=$value");

        if (null == code) {
          debugLog("$tag code is null");
        } else if (commands.containsKey(code) && commands[code] == command) {
          // debugLog("skipping already existing command $command ($code)");
        } else if (commands.containsKey(code)) {
          debugLog("$tag command code already exists: $code");
        } else if (commands.containsValue(command)) {
          debugLog("$tag command already exists: $command");
        } else {
          debugLog("$tag adding command $command ($code)");
          commands.addAll({code: command});
        }

        if (null == value) {
          //debugLog("value is null");
          //} else if (value.length < 1) {
          //  //debugLog("value is empty");
        } else {
          // generate a message
          ApiMessage m = ApiMessage(this, command);
          m.resultCode = ApiResult.success;
          m.commandCode = code;
          m.commandStr = command;
          m.value = value;
          m.isDone = true;
          // call the message done processor
          _onDone(m);
        }
      });
      return true;
    }

    if ("system" == message.commandStr) {
      String? v = message.valueAsString;
      if (null == v) return false;

      if (0 == v.indexOf("hostname:")) {
        String name = v.substring("hostname:".length);
        if (0 < name.length) {
          device.name = name;
          debugLog("$tag device name: $name");
        }
        return true;
      }

      if (0 == v.indexOf("build:")) {
        debugLog("$tag $v");
        return true;
      }

      if (0 == v.indexOf("reboot")) {
        snackbar("Rebooting...");
        device.disconnect();
        await Future.delayed(Duration(seconds: 2));
        device.connect();
        return true;
      }

      return false;
    }

    if ("bat" == message.commandStr) {
      debugLog("$tag bat: ${message.valueAsString}");
      List<String>? chunks = message.valueAsString?.split("|");
      if (null == chunks || chunks.length < 2) return true;
      if ("charging" == chunks[1]) {
        bool wasntCharging = !device.isCharging.asBool;
        device.isCharging = ExtendedBool.True;
        if (wasntCharging) device.notifyCharging();
      } else if ("discharging" == chunks[1]) {
        bool wasCharging = device.isCharging.asBool;
        device.isCharging = ExtendedBool.False;
        if (wasCharging) device.notifyCharging();
      }
      return true;
    }

    return false;
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
    debugLog("adding to queue: $message");
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
    //debugLog("requestResultCode: $message");
    await isDone(message);
    return message.resultCode;
  }

  /// Polls the message while [isDone] != true && [resultCode] == null
  /// TODO use a stream (each message could have an onChangedStream?)
  Future<void> isDone(ApiMessage message) async {
    await Future.doWhile(() async {
      if (message.isDone != true && message.resultCode == null) {
        // debugLog("polling...");
        await Future.delayed(Duration(milliseconds: queueDelayMs));
        return true;
      }
      // debugLog("poll end");
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
    int now = uts();
    if (message.isDone == true) {
      message.isDone = null;
      _onDone(message);
      message.destruct();
    } else if (now < (message.lastSentAt ?? 0) + message.minDelayMs) {
      //debugLog("${device.name} Api delaying $message");
      _queue.addLast(message);
    } else {
      debugLog("${device.name} Api sending $message");
      if (!await device.ready()) {
        debugLog("${device.name} Api _send() device not ready");
      } else {
        message.lastSentAt = now;
        message.attempts = (message.attempts ?? 0) + 1;
        String toWrite = "${message.commandCode}" + (null != message.arg ? "=" + message.arg! : "");
        //debugLog("_send() calling char.write($toWrite)");
        characteristic?.write(toWrite);
      }
      _queue.addLast(message);
    }
    await Future.delayed(Duration(milliseconds: queueDelayMs));
    if (_queue.isNotEmpty) _startQueueSchedule();
    _running = false;
  }

  void reset() {
    _stopQueueSchedule();
    _queue.clear();
    commands.clear();
    commands.addAll(_initialCommands);
    debugLog("${device.name} reset() commands: $commands");
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
