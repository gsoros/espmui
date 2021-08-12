import 'dart:async';
import 'dart:collection';

import 'ble_characteristic.dart';

enum ApiCommand {
  invalid,
  bootMode,
  hostName,
  reboot,
  passkey,
  secureApi,
}

enum ApiResult {
  success,
  error,
  unknownCommand,
  commandTooLong,
  argTooLong,
  bootModeInvalid,
  hostNameInvalid,
  passkeyInvalid,
  secureApiInvalid,
}

typedef void ApiCallback(ApiMessage message);

class ApiMessage {
  final tag = "[ApiMessage]";

  /// properties map
  Map<String, dynamic> _props = {};

  ApiMessage(
    String command,
    ApiCallback? onDone, {
    int maxAttempts = 3,
    int minDelay = 1000,
    int maxAge = 5000,
  }) {
    set("command", command);
    if (onDone != null) set("onDone", onDone);
    set("createdAt", DateTime.now().millisecondsSinceEpoch);
    set("maxAttempts", maxAttempts);
    set("minDelay", minDelay);
    set("maxAge", maxAge);
  }

  int? get resultCode => getInt("resultCode");

  void set(String key, dynamic value) {
    _props.update(key, (_) => value, ifAbsent: () => value);
  }

  void unset(String key) {
    _props.remove(key);
  }

  dynamic get(String key) {
    return _props[key];
  }

  int? getInt(String key) => int.tryParse(get(key).toString());

  /// Attempts to extract commandCode and commandStr from command
  void parseCommand() {
    var command = get("command");
    int eqSign = command.indexOf("=");
    String? arg;
    if (eqSign > 0) {
      arg = command.substring(eqSign + 1);
      if (arg!.length > 0) set("arg", arg.toString());
      command = command.substring(0, eqSign);
      if (command.length > 0) set("commandStr", command.toString());
    }
    var intParsed = int.tryParse(command);
    for (ApiCommand code in ApiCommand.values) {
      var valStr = code.toString().split('.').last;
      //print("$tag checking $valStr");
      if (code.index == intParsed || valStr == command) {
        set("commandCode", code.index);
        set("commandStr", command);
      }
    }
    if (get("commandCode") == null) {
      set("resultCode", -1);
      set("resultStr", "ClientError");
      set("info", "Unrecognized command");
      set("isDone", true);
    }
    print("$tag parsed: " + toString());
  }

  void destruct() {
    print("$tag destruct " + toString());
    set("isDone", true);
    set("info", get("info").toString() + " destructed");
  }

  String toString() {
    if (_props.isEmpty) return "$tag";
    String ret = "$tag (";
    List<String> propStrList = [];
    _props.forEach((key, value) => propStrList.add('$key: "$value"'));
    return ret + propStrList.join(", ") + ")";
  }
}

class Api {
  final tag = "[Api]";

  ApiCharacteristic _characteristic;
  late StreamSubscription<String> _subscription;
  final _queue = Queue<ApiMessage>();
  bool _running = false;
  Timer? _timer;
  int queueDelayMs;

  Api(this._characteristic, {this.queueDelayMs = 100}) {
    _characteristic.subscribe();
    _subscription = _characteristic.stream.listen((reply) => _onNotify(reply));
  }

  void _startQueueSchedule() {
    if (_timer != null) return;
    print("$tag queueSchedule start");
    _timer = Timer.periodic(
        Duration(milliseconds: queueDelayMs), (_) => _runQueue());
  }

  void _stopQueueSchedule() {
    if (_timer == null) return;
    print("$tag queueSchedule stop");
    _timer?.cancel();
    _timer = null;
  }

  /// format: resultCode:resultStr;commandCode:commandStr=[value]
  void _onNotify(String reply) {
    print("$tag received $reply");
    int resultEnd = reply.indexOf(";");
    if (resultEnd < 1) {
      print("$tag Error parsing notification: $reply");
      return;
    }
    String result = reply.substring(0, resultEnd);
    int colon = result.indexOf(":");
    if (colon < 1) {
      print("$tag Error parsing result: $result");
      return;
    }
    String resultCodeStr = result.substring(0, colon);
    int? resultCode = int.tryParse(resultCodeStr);
    if (resultCode == null) {
      print("$tag Error parsing resultCode as int: $resultCode");
      return;
    }
    String resultStr = result.substring(colon + 1);
    String commandWithValue = reply.substring(resultEnd + 1);
    colon = commandWithValue.indexOf(":");
    if (colon < 1) {
      print("$tag Error parsing commandWithValue: $commandWithValue");
      return;
    }
    String commandCodeStr = commandWithValue.substring(0, colon);
    int? commandCode = int.tryParse(commandCodeStr);
    if (commandCode == null) {
      print("$tag Error parsing commandCode as int: $commandCodeStr");
      return;
    }
    String commandStrWithValue = commandWithValue.substring(colon + 1);
    int eq = commandStrWithValue.indexOf("=");
    if (eq < 1) {
      print("$tag Error parsing commandStrWithValue: $commandStrWithValue");
      return;
    }
    //String commandStr = commandStrWithValue.substring(0, eq);
    String value = commandStrWithValue.substring(eq + 1);
    int matches = 0;
    for (ApiMessage message in _queue) {
      if (message.getInt("commandCode") == commandCode) {
        matches++;
        message.set("resultCode", resultCode);
        message.set("resultStr", resultStr);
        message.set("value", value);
        message.set("isDone", true);
        // don't return on the first match, process all matching messages
      }
    }
    if (matches == 0)
      print("$tag did not find a matching queued message for the reply $reply");
  }

  void _onDone(ApiMessage message) {
    var onDone = message.get("onDone");
    if (onDone == null) return;
    if (onDone is ApiCallback) {
      message.unset("onDone");
      onDone(message);
      return;
    }
    print("$tag Incorrect callback type: $onDone");
  }

  /// Sends a command to the API.
  ///
  /// Command format: commandCode|commandStr[=[arg]]
  ///
  /// If supplied, [onDone] will be called with the [ApiMessage] containing the
  /// [resultCode] on completion.
  ///
  /// Note the returned [ApiMessage] does not yet contain the reply.
  ApiMessage sendCommand(String command, {ApiCallback? onDone}) {
    var message = ApiMessage(command, onDone);
    print("$tag adding to queue: $message");
    _queue.add(message);
    _runQueue();
    return message;
  }

  Future<String?> requestValue(String command) async {
    var message = sendCommand(command);
    // poll the message
    await Future.doWhile(() async {
      if (message.get("isDone") != true && message.resultCode == null) {
        //print("$tag requestValue polling...");
        await Future.delayed(Duration(milliseconds: queueDelayMs));
        return true;
      }
      //print("$tag requestValue poll end");
      return false;
    });
    var value = message.get("value");
    return (value == null) ? null : value.toString();
  }

  void _runQueue() {
    if (_running) {
      print("$tag _runQueue() already running");
      return;
    }
    _running = true;
    if (_queue.isEmpty) {
      _stopQueueSchedule();
      _running = false;
      return;
    }
    //print("$tag queue run");
    var message = _queue.removeFirst();
    if (message.get("commandCode") == null) message.parseCommand();
    if (message.get("isDone") == true) {
      message.unset("isDone");
      _onDone(message);
      message.destruct();
    } else {
      _send(message);
      _queue.addLast(message);
    }
    if (_queue.isNotEmpty) _startQueueSchedule();
    _running = false;
  }

  void _send(ApiMessage message) {
    int now = DateTime.now().millisecondsSinceEpoch;
    if (now <
        (message.getInt("lastSentAt") ?? 0) + (message.getInt("minDelay") ?? 0))
      return;
    int attempts = message.getInt("attempts") ?? 0;
    if ((message.getInt("maxAttempts") ?? 0) <= attempts) {
      print("$tag max attmpts reached: $message");
      message.set("resultCode", -1);
      message.set("resultStr", "ClientError");
      message.set("info", "Maximum attempts reached");
      message.set("isDone", true);
      return;
    }
    int maxAge = message.getInt("maxAge") ?? 0;
    if ((message.getInt("createdAt") ?? 0) + maxAge <= now) {
      print("$tag max age reached: $message");
      message.set("resultCode", -1);
      message.set("resultStr", "ClientError");
      message.set("info", "Maximum age reached");
      message.set("isDone", true);
      return;
    }
    message.set("lastSentAt", now);
    message.set("attempts", attempts + 1);
    String toWrite = message.get("commandCode").toString();
    var arg = message.get("arg");
    if (arg != null) toWrite += "=$arg";
    //print("$tag calling char.write($toWrite)");
    _characteristic.write(toWrite);
  }

  Future<void> destruct() async {
    print("$tag destruct");
    _stopQueueSchedule();
    await _subscription.cancel();
    while (_queue.isNotEmpty) {
      var message = _queue.removeFirst();
      message.destruct();
    }
  }
}
