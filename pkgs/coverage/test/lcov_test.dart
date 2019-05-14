// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coverage/coverage.dart';
import 'package:coverage/src/util.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _sampleAppPath = p.join('test', 'test_files', 'test_app.dart');
final _isolateLibPath = p.join('test', 'test_files', 'test_app_isolate.dart');

final _sampleAppFileUri = p.toUri(p.absolute(_sampleAppPath)).toString();
final _isolateLibFileUri = p.toUri(p.absolute(_isolateLibPath)).toString();

void main() {
  test('validate hitMap', () async {
    var hitmap = await _getHitMap();

    expect(hitmap, contains(_sampleAppFileUri));
    expect(hitmap, contains(_isolateLibFileUri));
    expect(hitmap, contains('package:coverage/src/util.dart'));

    Map<int, int> sampleAppHitMap = hitmap[_sampleAppFileUri];

    expect(sampleAppHitMap, containsPair(40, greaterThanOrEqualTo(1)),
        reason: 'be careful if you modify the test file');
    expect(sampleAppHitMap, containsPair(44, 0),
        reason: 'be careful if you modify the test file');
    expect(sampleAppHitMap, isNot(contains(29)),
        reason: 'be careful if you modify the test file');
  });

  group('LcovFormatter', () {
    test('format()', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter = LcovFormatter(resolver);

      String res = await formatter.format(hitmap);

      expect(res, contains(p.absolute(_sampleAppPath)));
      expect(res, contains(p.absolute(_isolateLibPath)));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));
    });

    test('format() includes files in reportOn list', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter = LcovFormatter(resolver, reportOn: ['lib/', 'test/']);

      String res = await formatter.format(hitmap);

      expect(res, contains(p.absolute(_sampleAppPath)));
      expect(res, contains(p.absolute(_isolateLibPath)));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));
    });

    test('format() excludes files not in reportOn list', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter = LcovFormatter(resolver, reportOn: ['lib/']);

      String res = await formatter.format(hitmap);

      expect(res, isNot(contains(p.absolute(_sampleAppPath))));
      expect(res, isNot(contains(p.absolute(_isolateLibPath))));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));
    });

    test('format() uses paths relative to basePath', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter = LcovFormatter(resolver, basePath: p.absolute('lib'));

      String res = await formatter.format(hitmap);

      expect(
          res, isNot(contains(p.absolute(p.join('lib', 'src', 'util.dart')))));
      expect(res, contains(p.join('src', 'util.dart')));
    });
  });

  group('PrettyPrintFormatter', () {
    test('format()', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter = PrettyPrintFormatter(resolver, Loader());

      String res = await formatter.format(hitmap);

      expect(res, contains(p.absolute(_sampleAppPath)));
      expect(res, contains(p.absolute(_isolateLibPath)));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));

      // be very careful if you change the test file
      expect(res, contains("      0|  return a - b;"));

      expect(res, contains('|  return _withTimeout(() async {'),
          reason: 'be careful if you change lib/src/util.dart');

      var hitLineRegexp = RegExp(r'\s+(\d+)\|  return a \+ b;');
      var match = hitLineRegexp.allMatches(res).single;

      var hitCount = int.parse(match[1]);
      expect(hitCount, greaterThanOrEqualTo(1));
    });

    test('format() includes files in reportOn list', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter =
          PrettyPrintFormatter(resolver, Loader(), reportOn: ['lib/', 'test/']);

      String res = await formatter.format(hitmap);

      expect(res, contains(p.absolute(_sampleAppPath)));
      expect(res, contains(p.absolute(_isolateLibPath)));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));
    });

    test('format() excludes files not in reportOn list', () async {
      var hitmap = await _getHitMap();

      var resolver = Resolver(packagesPath: '.packages');
      var formatter =
          PrettyPrintFormatter(resolver, Loader(), reportOn: ['lib/']);

      String res = await formatter.format(hitmap);

      expect(res, isNot(contains(p.absolute(_sampleAppPath))));
      expect(res, isNot(contains(p.absolute(_isolateLibPath))));
      expect(res, contains(p.absolute(p.join('lib', 'src', 'util.dart'))));
    });
  });
}

Future<Map> _getHitMap() async {
  expect(FileSystemEntity.isFileSync(_sampleAppPath), isTrue);

  // select service port.
  var port = await getOpenPort();

  // start sample app.
  var sampleAppArgs = [
    '--pause-isolates-on-exit',
    '--enable-vm-service=$port',
    _sampleAppPath
  ];
  var sampleProcess = await Process.start('dart', sampleAppArgs);

  // Capture the VM service URI.
  Completer<Uri> serviceUriCompleter = Completer<Uri>();
  sampleProcess.stdout
      .transform(utf8.decoder)
      .transform(LineSplitter())
      .listen((line) {
    if (!serviceUriCompleter.isCompleted) {
      Uri serviceUri = extractObservatoryUri(line);
      if (serviceUri != null) {
        serviceUriCompleter.complete(serviceUri);
      }
    }
  });
  Uri serviceUri = await serviceUriCompleter.future;

  // collect hit map.
  List<Map> coverageJson = (await collect(serviceUri, true, true))['coverage'];
  var hitMap = createHitmap(coverageJson);

  // wait for sample app to terminate.
  var exitCode = await sampleProcess.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
        'dart', sampleAppArgs, 'Fatal error. Exit code: $exitCode', exitCode);
  }
  sampleProcess.stderr.drain<List<int>>();
  return hitMap;
}
