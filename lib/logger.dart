const LOG_PREFIX = 'PeerJS: ';

/*
Prints log messages depending on the debug level passed in. Defaults to 0.
0  Prints no logs.
1  Prints only errors.
2  Prints errors and warnings.
3  Prints all logs.
*/
class LogLevel {
  static const Disabled = 3;
  static const Errors = 2;
  static const Warnings = 1;
  static const All = 0;
}

class Logger {
  var logLevel = LogLevel.Disabled;

  log(dynamic message) {
    if (this.logLevel >= LogLevel.All) {
      this._print(LogLevel.All, message);
    }
  }

  warn(dynamic message) {
    if (this.logLevel >= LogLevel.Warnings) {
      this._print(LogLevel.Warnings, message);
    }
  }

  error(dynamic message) {
    if (this.logLevel >= LogLevel.Errors) {
      this._print(LogLevel.Errors, message);
    }
  }

  setLogFunction(Function fn) {
    this._print = fn;
  }

  Function _print = (int logLevel, dynamic message) {
    var msg = '$LOG_PREFIX ${message.toString()}';

    if (logLevel >= LogLevel.All) {
      print(msg);
    } else if (logLevel >= LogLevel.Warnings) {
      print("WARNING " + msg);
    } else if (logLevel >= LogLevel.Errors) {
      print("ERROR " + msg);
    }
  };
}

final logger = Logger();
