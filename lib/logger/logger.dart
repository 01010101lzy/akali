import 'dart:io';
import 'dart:developer';
import 'dart:isolate';
import 'dart:convert';

import 'package:aqueduct/aqueduct.dart';

Function logHandlerFactory(Level verbosity) {
  return (LogRecord rec) {
    if (rec.level >= verbosity) {
      print('$rec');
      if (rec.error != null) print(rec.error);
      if (rec.stackTrace != null) print(rec.stackTrace);
    }
  };
}

// class AkaliLogger {
//   List<LogFile> logFileEndpoints;
//   LogLevel commandLineLogLevel;

//   AkaliLogger({this.commandLineLogLevel}) {
//     logFileEndpoints ??= [];
//   }

//   log(dynamic object, [LogLevel level = LogLevel.info, String source]) {
//     this.logFileEndpoints.forEach((file) => file.log(object, level, source));
//   }
// }

// enum LogLevel {
//   silly,
//   info,
//   warning,
//   error,
//   silent,
// }

// class LogFile {
//   LogLevel level;
//   File logFile;
//   IOSink logFileSink;

//   bool useJson = false;
//   bool includeTimeStamp = true;
//   bool includeSource = true;

//   LogFile(
//     this.level,
//     this.logFile, {
//     this.useJson,
//     this.includeSource,
//     this.includeTimeStamp,
//   }) {
//     logFileSink = logFile.openWrite(mode: FileMode.writeOnlyAppend);
//     if (useJson) logFileSink.write("{");
//   }

//   close() {
//     if (this.useJson) logFileSink.write("}");
//     logFileSink.close();
//   }

//   log(dynamic object, [LogLevel level = LogLevel.info, String source]) {
//     if (level.index < this.level.index) return;
//     if (!useJson) {
//       if (includeTimeStamp) logFileSink.write("${DateTime.now().toIso8601String()} ");
//       if (includeSource) logFileSink.write("${source.padRight(10)} ");
//       logFileSink.write("${level.toString().padRight(6)} ");
//       logFileSink.writeln(object);
//     } else {
//       Map<String, dynamic> stuff;
//       stuff['content'] = object;
//       if (includeTimeStamp) stuff['time'] = DateTime.now();
//       if (includeSource) stuff['source'] = source;
//       stuff['level'] = level;
//       logFileSink.writeln("," + jsonEncode(stuff));
//     }
//   }
// }
