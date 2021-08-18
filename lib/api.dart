import 'dart:async';
import 'dart:collection';

import 'ble_characteristic.dart';
import 'util.dart';
import 'device.dart';

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
}

enum ApiResult {
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
  int minDelayMs = 1000;
  int maxAgeMs = 5000;
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
    if (this.maxAgeMs < maxAttemtsTotalTime)
      this.maxAgeMs = maxAttemtsTotalTime + this.minDelayMs;
  }

  /// Attempts to create commandCode and commandStr from command
  void parseCommand() {
    if (commandCode != null) return; // already parsed
    //print("$tag parsing: $command");
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
    //print("$tag parsed: " + toString());
  }

  void checkAge() {
    if (createdAt + maxAgeMs <= uts()) {
      print("$tag max age reached: " + toString());
      resultCode = -1;
      resultStr = "ClientError";
      info = "Maximum age reached";
      isDone = true;
    }
  }

  void checkAttempts() {
    if (maxAttempts <= (attempts ?? 0)) {
      print("$tag max attmpts reached: " + toString());
      resultCode = -1;
      resultStr = "ClientError";
      info = "Maximum attempts reached";
      isDone = true;
    }
  }

  void destruct() {
    //print("$tag destruct " + toString());
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
    return null;
  }

  int? get valueAsInt => int.tryParse(value ?? "");
  double? get valueAsDouble => double.tryParse(value ?? "");
  String? get valueAsString => value;
}

class Api {
  final tag = "[Api]";

  Device device;
  ApiCharacteristic? get _characteristic => device.apiCharacteristic;
  late StreamSubscription<String>? _subscription;
  final _doneController = StreamController<ApiMessage>.broadcast();
  Stream<ApiMessage> get messageDoneStream => _doneController.stream;
  final _queue = Queue<ApiMessage>();
  bool _running = false;
  Timer? _timer;
  final int queueDelayMs;

  Api(this.device, {this.queueDelayMs = 200}) {
    _characteristic?.subscribe();
    _subscription = _characteristic?.stream.listen((reply) => _onNotify(reply));
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
    //print("$tag _onNotify() $reply");
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
    //print("$tag onDone $message");
    streamSendIfNotClosed(_doneController, message);
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
    int? minDelayMs,
    int? maxAgeMs,
  }) {
    var message = ApiMessage(
      command,
      onDone,
      maxAttempts: maxAttempts,
      minDelayMs: minDelayMs,
      maxAgeMs: maxAgeMs,
    );
    // check queue for duplicate commands and remove them as this one will be newer
    int before = _queue.length;
    _queue.removeWhere((queued) => queued.command == message.command);
    int removed = before - _queue.length;
    if (removed > 0) print("$tag removed $removed duplicate messages");
    //print("$tag adding to queue: $message");
    _queue.add(message);
    _runQueue();
    return message;
  }

  /// Requests a value from the device API
  Future<T?> request<T>(
    String command, {
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) async {
    var message = sendCommand(
      command,
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
    print("$tag request() error: type $T is not handled");
    return message as T?;
  }

  /// Requests a result from the device API
  Future<int?> requestResultCode(
    String command, {
    int? maxAttempts,
    int? minDelayMs,
    int? maxAgeMs,
  }) async {
    var message = sendCommand(
      command,
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
        //print("$tag polling...");
        // TODO milliseconds: [message.minDelay, queueDelayMs].max
        await Future.delayed(Duration(milliseconds: message.minDelayMs));
        return true;
      }
      //print("$tag poll end");
      return false;
    });
  }

  bool queueContainsCommand({String? commandStr, ApiCommand? command}) {
    for (ApiMessage message in _queue)
      if (message.commandStr == commandStr ||
          message.commandCode == command?.index) return true;
    return false;
  }

  void _runQueue() async {
    if (_running) {
      //print("$tag _runQueue() already running");
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
    //var device = Scanner().selected;
    if (!await device.connected) {
      print("$tag _send() not connected");
      return;
    }
    message.lastSentAt = now;
    message.attempts = (message.attempts ?? 0) + 1;
    String toWrite = message.commandCode.toString();
    var arg = message.arg;
    if (arg != null) toWrite += "=$arg";
    //print("$tag _send() calling char.write($toWrite)");
    _characteristic?.write(toWrite);
  }

  Future<void> destruct() async {
    print("$tag destruct");
    _stopQueueSchedule();
    await _subscription?.cancel();
    while (_queue.isNotEmpty) {
      var message = _queue.removeFirst();
      message.destruct();
    }
    _doneController.close();
  }
}
