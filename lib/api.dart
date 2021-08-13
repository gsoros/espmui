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
  apiStrain,
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

  String command;
  String? commandStr;
  int? commandCode;
  String? arg;
  ApiCallback? onDone;
  int maxAttempts = 3;
  int minDelay = 500;
  int maxAge = 5000;
  int createdAt = 0;
  int? lastSentAt;
  int? attempts;
  int? resultCode;
  String? resultStr;
  String? info;
  String? value;
  bool? isDone;

  ApiMessage(
    this.command,
    this.onDone, {
    int? maxAttempts,
    int? minDelay,
    int? maxAge,
  }) {
    createdAt = DateTime.now().millisecondsSinceEpoch;
    this.maxAttempts = maxAttempts ?? this.maxAttempts;
    this.minDelay = minDelay ?? this.minDelay;
    this.maxAge = maxAge ?? this.maxAge;
    if (this.maxAttempts < 1) this.maxAttempts = 1;
    if (this.maxAttempts > 10) this.maxAttempts = 10;
    if (this.minDelay < 50) this.minDelay = 50;
    if (this.minDelay > 10000) this.minDelay = 10000;
    var maxAttemtsTotalTime = this.maxAttempts * this.minDelay;
    if (this.maxAge < maxAttemtsTotalTime)
      this.maxAge = maxAttemtsTotalTime + this.minDelay;
  }

  /// Attempts to extract commandCode and commandStr from command
  void parseCommand() {
    int eqSign = command.indexOf("=");
    String? parsedArg;
    if (eqSign > 0) {
      parsedArg = command.substring(eqSign + 1);
      if (parsedArg.length > 0) arg = parsedArg.toString();
      command = command.substring(0, eqSign);
      if (command.length > 0) commandStr = command.toString();
    }
    var intParsed = int.tryParse(command);
    for (ApiCommand code in ApiCommand.values) {
      var valStr = code.toString().split('.').last;
      //print("$tag checking $valStr");
      if (code.index == intParsed || valStr == command) {
        commandCode = code.index;
        commandStr = command;
      }
    }
    if (commandCode == null) {
      resultCode = -1;
      resultStr = "ClientError";
      info = "Unrecognized command";
      isDone = true;
    }
    print("$tag parsed: " + toString());
  }

  void destruct() {
    print("$tag destruct " + toString());
    isDone = true;
    //info = ((info == null) ? "" : info.toString()) + " destructed";
  }

  String toString() {
    return "$tag (" +
        "command: '$command'" +
        ((commandStr != null) ? ", commandStr='$commandStr'" : "") +
        ((commandCode != null) ? ", commandCode='$commandCode'" : "") +
        ((onDone != null) ? ", onDone='$onDone'" : "") +
        ", maxAttempts='$maxAttempts'" +
        ", minDelay='$minDelay'" +
        ", maxAge='$maxAge'" +
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
}

class Api {
  final tag = "[Api]";

  ApiCharacteristic _characteristic;
  late StreamSubscription<String> _subscription;
  final doneController = StreamController<ApiMessage>.broadcast();
  Stream<ApiMessage> get messageDoneStream => doneController.stream;
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
      if (message.commandCode == commandCode) {
        matches++;
        message.resultCode = resultCode;
        message.resultStr = resultStr;
        message.value = value;
        message.isDone = true;
        // don't return on the first match, process all matching messages
      }
    }
    if (matches == 0)
      print("$tag did not find a matching queued message for the reply $reply");
  }

  void _onDone(ApiMessage message) {
    doneController.add(message);
    var onDone = message.onDone;
    if (onDone == null) return;
    if (onDone is ApiCallback) {
      message.onDone = null;
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
  ApiMessage sendCommand(
    String command, {
    ApiCallback? onDone,
    int? maxAttempts,
    int? minDelay,
    int? maxAge,
  }) {
    var message = ApiMessage(
      command,
      onDone,
      maxAttempts: maxAttempts,
      minDelay: minDelay,
      maxAge: maxAge,
    );
    print("$tag adding to queue: $message");
    _queue.add(message);
    _runQueue();
    return message;
  }

  Future<String?> requestValue(
    String command, {
    int? maxAttempts,
    int? minDelay,
    int? maxAge,
  }) async {
    var message = sendCommand(
      command,
      maxAttempts: maxAttempts,
      minDelay: minDelay,
      maxAge: maxAge,
    );

    /// poll the message
    /// TODO use a Stream (each message could have an onChangeStream?)
    await Future.doWhile(() async {
      if (message.isDone != true && message.resultCode == null) {
        //print("$tag requestValue polling...");
        await Future.delayed(Duration(milliseconds: message.minDelay));
        return true;
      }
      //print("$tag requestValue poll end");
      return false;
    });
    return message.value.toString();
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
    if (message.commandCode == null) message.parseCommand();
    if (message.isDone == true) {
      message.isDone = null;
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
    if (now < (message.lastSentAt ?? 0) + message.minDelay) return;
    int attempts = message.attempts ?? 0;
    if (message.maxAttempts <= attempts) {
      print("$tag max attmpts reached: $message");
      message.resultCode = -1;
      message.resultStr = "ClientError";
      message.info = "Maximum attempts reached";
      message.isDone = true;
      return;
    }
    if (message.createdAt + message.maxAge <= now) {
      print("$tag max age reached: $message");
      message.resultCode = -1;
      message.resultStr = "ClientError";
      message.info = "Maximum age reached";
      message.isDone = true;
      return;
    }
    message.lastSentAt = now;
    message.attempts = attempts + 1;
    String toWrite = message.commandCode.toString();
    var arg = message.arg;
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
    doneController.close();
  }
}
