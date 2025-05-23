// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert' show json;
import 'dart:io';

import 'package:args/args.dart';
import 'package:coverage/src/collect.dart';
import 'package:coverage/src/coverage_options.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';

Future<void> main(List<String> arguments) async {
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  final defaultOptions = CoverageOptionsProvider().coverageOptions;
  final options = parseArgs(arguments, defaultOptions);

  final out = options.out == null ? stdout : File(options.out!).openWrite();

  await Chain.capture(() async {
    final coverage = await collect(options.serviceUri, options.resume,
        options.waitPaused, options.includeDart, options.scopedOutput,
        timeout: options.timeout,
        functionCoverage: options.functionCoverage,
        branchCoverage: options.branchCoverage);
    out.write(json.encode(coverage));
    await out.close();
  }, onError: (dynamic error, Chain chain) {
    stderr.writeln(error);
    stderr.writeln(chain.terse);
    // See http://www.retro11.de/ouxr/211bsd/usr/include/sysexits.h.html
    // EX_SOFTWARE
    exit(70);
  });
}

class Options {
  Options(
      this.serviceUri,
      this.out,
      this.timeout,
      this.waitPaused,
      this.resume,
      this.includeDart,
      this.functionCoverage,
      this.branchCoverage,
      this.scopedOutput);

  final Uri serviceUri;
  final String? out;
  final Duration? timeout;
  final bool waitPaused;
  final bool resume;
  final bool includeDart;
  final bool functionCoverage;
  final bool branchCoverage;
  final Set<String> scopedOutput;
}

@visibleForTesting
Options parseArgs(List<String> arguments, CoverageOptions defaultOptions) {
  final parser = ArgParser()
    ..addOption('host',
        abbr: 'H',
        help: 'remote VM host. DEPRECATED: use --uri',
        defaultsTo: '127.0.0.1')
    ..addOption('port',
        abbr: 'p',
        help: 'remote VM port. DEPRECATED: use --uri',
        defaultsTo: '8181')
    ..addOption('uri', abbr: 'u', help: 'VM observatory service URI')
    ..addOption('out', abbr: 'o', help: 'output: may be file or stdout')
    ..addOption('connect-timeout',
        abbr: 't', help: 'connect timeout in seconds')
    ..addMultiOption('scope-output',
        defaultsTo: defaultOptions.scopeOutput,
        help: 'restrict coverage results so that only scripts that start with '
            'the provided package path are considered')
    ..addFlag('wait-paused',
        abbr: 'w',
        defaultsTo: false,
        help: 'wait for all isolates to be paused before collecting coverage')
    ..addFlag('resume-isolates',
        abbr: 'r', defaultsTo: false, help: 'resume all isolates on exit')
    ..addFlag('include-dart',
        abbr: 'd', defaultsTo: false, help: 'include "dart:" libraries')
    ..addFlag('function-coverage',
        abbr: 'f',
        defaultsTo: defaultOptions.functionCoverage,
        help: 'Collect function coverage info')
    ..addFlag('branch-coverage',
        abbr: 'b',
        defaultsTo: defaultOptions.branchCoverage,
        help: 'Collect branch coverage info (Dart VM must also be run with '
            '--branch-coverage for this to work)')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'show this help');

  final args = parser.parse(arguments);

  void printUsage() {
    print('Usage: dart collect_coverage.dart --uri=http://... [OPTION...]\n');
    print(parser.usage);
  }

  Never fail(String message) {
    print('Error: $message\n');
    printUsage();
    exit(1);
  }

  if (args['help'] as bool) {
    printUsage();
    exit(0);
  }

  Uri serviceUri;
  if (args['uri'] == null) {
    // TODO(cbracken) eliminate --host and --port support when VM defaults to
    // requiring an auth token. Estimated for Dart SDK 1.22.
    serviceUri = Uri.parse('http://${args['host']}:${args['port']}/');
  } else {
    try {
      serviceUri = Uri.parse(args['uri'] as String);
    } on FormatException {
      fail('Invalid service URI specified: ${args['uri']}');
    }
  }

  final scopedOutput = args['scope-output'] as List<String>;
  String? out;
  final outPath = args['out'] as String?;
  if (outPath == 'stdout' ||
      (outPath == null && defaultOptions.outputDirectory == null)) {
    out = null;
  } else {
    final outFilePath = p.normalize(outPath ??
        p.absolute(defaultOptions.outputDirectory!, 'coverage.json'));

    final outFile = File(outFilePath);
    if (!FileSystemEntity.isDirectorySync(outFilePath) &&
        !FileSystemEntity.isFileSync(outFilePath)) {
      outFile.createSync(recursive: true);
    }

    out = outFile.path;
  }

  final timeout = (args['connect-timeout'] == null)
      ? null
      : Duration(seconds: int.parse(args['connect-timeout'] as String));
  return Options(
    serviceUri,
    out,
    timeout,
    args['wait-paused'] as bool,
    args['resume-isolates'] as bool,
    args['include-dart'] as bool,
    args['function-coverage'] as bool,
    args['branch-coverage'] as bool,
    scopedOutput.toSet(),
  );
}
