import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/core/diagnostics/process_tree_sampler.dart';
import 'package:otzaria/core/startup_timeline.dart';

class _BlockedFile extends Fake implements File {
  _BlockedFile(this.delegate);
  final File delegate;
  final started = Completer<void>();
  final release = Completer<void>();
  final recovered = Completer<void>();
  final secondWrite = Completer<void>();
  bool fail = false;
  int successfulWrites = 0;
  int concurrent = 0;
  int maximumConcurrent = 0;

  @override
  Directory get parent => delegate.parent;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    concurrent++;
    if (concurrent > maximumConcurrent) maximumConcurrent = concurrent;
    if (!started.isCompleted) started.complete();
    await release.future;
    if (fail) {
      concurrent--;
      throw FileSystemException('Blocked output');
    }
    await delegate.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    concurrent--;
    if (!recovered.isCompleted) recovered.complete();
    if (++successfulWrites == 2) secondWrite.complete();
    return this;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseDiagnosticsLaunchMode', () {
    DiagnosticsLaunchMode parse(
      List<String> args, [
      Map<String, String> env = const {},
    ]) => parseDiagnosticsLaunchMode(args, env);

    test('is off by default', () {
      expect(parse(const []), DiagnosticsLaunchMode.off);
      expect(parse(const ['otzaria://open']), DiagnosticsLaunchMode.off);
    });

    test('reads the command-line flag in its accepted spellings', () {
      for (final flag in [
        '--dev-diagnostics',
        '/dev-diagnostics',
        '--DEV_DIAGNOSTICS',
      ]) {
        expect(parse([flag]), DiagnosticsLaunchMode.panel, reason: flag);
      }
      expect(parse(['--dev-diagnostics=log']), DiagnosticsLaunchMode.logOnly);
    });

    test('falls back to the environment variable', () {
      expect(
        parse(const [], {devDiagnosticsEnv: '1'}),
        DiagnosticsLaunchMode.panel,
      );
      expect(
        parse(const [], {devDiagnosticsEnv: 'log'}),
        DiagnosticsLaunchMode.logOnly,
      );
      expect(
        parse(const [], {devDiagnosticsEnv: '0'}),
        DiagnosticsLaunchMode.off,
      );
    });
  });

  test('computeFrameStats summarizes the window', () {
    final stats = computeFrameStats(
      const [
        FrameSample(2, 1, 5),
        FrameSample(4, 1, 8),
        FrameSample(30, 4, 40),
      ],
      window: const Duration(seconds: 2),
      slowTotal: 7,
    );
    expect(stats.framesPerSecond, 2);
    expect(stats.buildAvgMs, 12.0);
    expect(stats.buildMaxMs, 30.0);
    expect(stats.rasterMaxMs, 4.0);
    expect(stats.slowInWindow, 1);
    expect(stats.slowTotal, 7);
  });

  group('DeveloperDiagnostics', () {
    late File output;
    late List<String> errorLog;
    final diagnostics = DeveloperDiagnostics.instance;

    setUp(() {
      errorLog = [];
      output = File(
        '${Directory.systemTemp.createTempSync('diag').path}/out.jsonl',
      );
      diagnostics
        ..resetForTesting()
        ..outputPath = output.path
        ..errorLogWriter = errorLog.add;
    });

    tearDown(diagnostics.resetForTesting);

    List<Map<String, dynamic>> records() => [
      for (final line in output.readAsLinesSync())
        jsonDecode(line) as Map<String, dynamic>,
    ];

    test('nothing is collected or written while off', () {
      diagnostics.initFromLaunch(const [], environment: const {});
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(output.existsSync(), isFalse);
    });

    test('log-only launch collects without showing the panel', () async {
      diagnostics.initFromLaunch(const [
        '--dev-diagnostics=log',
      ], environment: const {});
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isFalse);

      await diagnostics.snapshot();
      final types = records().map((r) => r['type']).toList();
      expect(types, ['session', 'snapshot']);
    });

    test('toggling off a launch request stops collecting', () {
      diagnostics
        ..initFromLaunch(const ['--dev-diagnostics'], environment: const {})
        ..toggle();
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);

      diagnostics.toggle();
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isTrue);
    });

    test('snapshot includes the app context', () async {
      diagnostics.contextProvider = () => {'screen': 'reading', 'tabs': 3};
      diagnostics.toggle();
      await diagnostics.snapshot();

      final snapshot = records().firstWhere((r) => r['type'] == 'snapshot');
      expect(snapshot['context'], {'screen': 'reading', 'tabs': 3});
      expect(snapshot, contains('rssMb'));
      expect(errorLog.single, startsWith('=== Developer snapshot'));
    });

    testWidgets('stopping restores the paint flags present before collection', (
      tester,
    ) async {
      final color = debugCurrentRepaintColor;
      try {
        diagnostics.toggle();
        debugRepaintRainbowEnabled = true;
        debugPaintSizeEnabled = true;
        diagnostics.toggle();
        expect(debugRepaintRainbowEnabled, isFalse);
        expect(debugPaintSizeEnabled, isFalse);
        await tester.idle();
        debugPaintSizeEnabled = true;
        diagnostics.toggle();
        debugPaintSizeEnabled = false;
        diagnostics.toggle();
        expect(debugPaintSizeEnabled, isTrue);
        await tester.idle();
      } finally {
        debugRepaintRainbowEnabled = false;
        debugPaintSizeEnabled = false;
        debugCurrentRepaintColor = color;
      }
    });

    test('failed output is retained for one explicit snapshot retry', () async {
      final blocked = File('${output.parent.path}/blocked')
        ..writeAsStringSync('not a directory');
      diagnostics.outputPath = '${blocked.path}/out.jsonl';
      diagnostics.toggle();
      expect(await diagnostics.snapshot(), isNull);
      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(errorLog, isEmpty);
      await blocked.delete();
      expect(await diagnostics.snapshot(), diagnostics.outputPath);
      final restored = File(diagnostics.outputPath)
          .readAsLinesSync()
          .map((line) => jsonDecode(line) as Map<String, dynamic>)
          .toList();
      expect(
        restored.where((record) => record['type'] == 'session'),
        hasLength(1),
      );
      expect(
        restored.where((record) => record['type'] == 'snapshot'),
        hasLength(2),
      );
    });

    test('concurrent snapshots each persist once', () async {
      diagnostics.toggle();
      await Future.wait([diagnostics.snapshot(), diagnostics.snapshot()]);
      expect(
        records().where((record) => record['type'] == 'session'),
        hasLength(1),
      );
      expect(
        records().where((record) => record['type'] == 'snapshot'),
        hasLength(2),
      );
    });

    test(
      'blocked output serializes snapshots and persists stop once',
      () async {
        final blocked = _BlockedFile(output);
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final first = diagnostics.snapshot();
          await blocked.started.future;
          final second = diagnostics.snapshot();
          diagnostics.toggle();
          expect(diagnostics.isCollecting, isFalse);
          blocked.release.complete();
          await Future.wait([first, second]);
        }, createFile: (_) => blocked);
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'snapshot'),
          hasLength(2),
        );
        expect(
          records().where((record) => record['type'] == 'end'),
          hasLength(1),
        );
      },
    );

    test(
      'blocked output bounds pending slow frames and toggle recovers',
      () async {
        final blocked = _BlockedFile(output)..fail = true;
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final saving = diagnostics.snapshot();
          await blocked.started.future;
          final timing = FrameTiming(
            vsyncStart: 0,
            buildStart: 0,
            buildFinish: 100000,
            rasterStart: 100000,
            rasterFinish: 110000,
            rasterFinishWallTime: DateTime.now().microsecondsSinceEpoch,
          );
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(5000, timing),
          );
          expect(diagnostics.isCollecting, isFalse);
          var periodicTimers = 0;
          runZoned(
            diagnostics.toggle,
            zoneSpecification: ZoneSpecification(
              createPeriodicTimer: (self, parent, zone, duration, callback) {
                periodicTimers++;
                return parent.createPeriodicTimer(zone, duration, callback);
              },
            ),
          );
          expect(diagnostics.isCollecting, isFalse);
          expect(periodicTimers, 0);
          blocked.release.complete();
          expect(await saving, isNull);
          blocked.fail = false;
          diagnostics.toggle();
          await blocked.recovered.future;
          await Future<void>.delayed(Duration.zero);
          expect(diagnostics.isCollecting, isTrue);
          diagnostics.toggle();
          await diagnostics.snapshot();
        }, createFile: (_) => blocked);
        final slow = records().where(
          (record) => record['type'] == 'slow_frame',
        );
        expect(slow.length, inInclusiveRange(1000, 4999));
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'snapshot'),
          hasLength(2),
        );
      },
    );

    test(
      'cap drains remaining records after a blocked write succeeds',
      () async {
        final blocked = _BlockedFile(output);
        await IOOverrides.runZoned(() async {
          diagnostics.toggle();
          final saving = diagnostics.snapshot();
          await blocked.started.future;
          final timing = FrameTiming(
            vsyncStart: 0,
            buildStart: 0,
            buildFinish: 100000,
            rasterStart: 100000,
            rasterFinish: 110000,
            rasterFinishWallTime: DateTime.now().microsecondsSinceEpoch,
          );
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(10000, timing),
          );
          expect(diagnostics.isCollecting, isFalse);
          blocked.release.complete();
          await saving;
          await blocked.secondWrite.future.timeout(const Duration(seconds: 5));
          diagnostics.toggle();
          TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .onReportTimings!(
            List.filled(100, timing),
          );
          expect(diagnostics.isCollecting, isTrue);
          diagnostics.toggle();
          await diagnostics.snapshot();
        }, createFile: (_) => blocked);
        expect(blocked.maximumConcurrent, 1);
        expect(
          records().where((record) => record['type'] == 'slow_frame'),
          hasLength(4194),
        );
      },
    );

    test(
      'launch diagnostics runs after existing version initialization',
      () async {
        final source = File('lib/main.dart').readAsStringSync();
        final start = source.indexOf('void main(List<String> args) async {');
        final end = source.indexOf('void _installGlobalErrorHandlers()', start);
        final mainSource = source.substring(start, end);
        expect(
          mainSource.indexOf(
            'DeveloperDiagnostics.instance.initFromLaunch(args)',
          ),
          greaterThan(mainSource.indexOf('await _initializeLogMetadata()')),
        );
        ErrorLogFile.setAppVersion('1.2.3+45');
        diagnostics.initFromLaunch(const [
          '--dev-diagnostics=log',
        ], environment: const {});
        await diagnostics.snapshot();
        expect(records().first['version'], '1.2.3+45');
      },
    );

    group('process tree', () {
      const sample = ProcessTreeSample(
        hostPrivMb: 260,
        webview: {
          'RENDERER': (count: 2, privMb: 120, eachMb: [70, 50], pages: []),
        },
      );
      late int calls;

      setUp(() {
        calls = 0;
        diagnostics.processSampler = () async {
          calls++;
          return sample;
        };
      });

      Future<void> settle() => Future<void>.delayed(Duration.zero);

      // חייב לרוץ ראשון: אחריו ציר הזמן מסומן כחשוף לכל הקובץ.
      test('is not sampled before the window is revealed', () async {
        expect(StartupTimeline.instance.toJson()['revealMs'], isNull);
        diagnostics.toggle();
        for (var i = 0; i < 10; i++) {
          diagnostics.debugTick();
          await settle();
        }
        expect(calls, 0);
      });

      group('after reveal', () {
        setUpAll(StartupTimeline.instance.finishAtReveal);

        test('is sampled once every few ticks', () async {
          diagnostics.toggle();
          for (var i = 0; i < 11; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(calls, 3);
        });

        test('a slow sample is never overlapped', () async {
          final pending = Completer<ProcessTreeSample?>();
          diagnostics.processSampler = () {
            calls++;
            return pending.future;
          };
          diagnostics.toggle();
          for (var i = 0; i < 12; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(calls, 1);
          pending.complete(sample);
        });

        test(
          'a fresh sample writes a stats line even without frames',
          () async {
            diagnostics.toggle();
            diagnostics.debugTick();
            await settle();
            diagnostics.debugTick();
            diagnostics.debugTick();
            expect(diagnostics.stats.value.processes, sample);
            await diagnostics.snapshot();

            final stats = records().where((r) => r['type'] == 'stats');
            expect(stats, hasLength(1));
            expect(stats.single['processes'], sample.toJson());
            final snapshot = records().singleWhere(
              (r) => r['type'] == 'snapshot',
            );
            expect(snapshot['processes']['webviewPrivMb'], 120);
            expect(snapshot['processes'], contains('ageMs'));
          },
        );

        test('a failing sampler does not stop collection', () async {
          diagnostics.processSampler = () async {
            calls++;
            throw StateError('no access');
          };
          diagnostics.toggle();
          for (var i = 0; i < 6; i++) {
            diagnostics.debugTick();
            await settle();
          }
          expect(diagnostics.isCollecting, isTrue);
          expect(calls, 2);
          expect(diagnostics.stats.value.processes, isNull);
        });

        test('a sample that lands after stopping is dropped', () async {
          final pending = Completer<ProcessTreeSample?>();
          diagnostics.processSampler = () => pending.future;
          diagnostics.toggle();
          diagnostics.debugTick();
          diagnostics.toggle();
          pending.complete(sample);
          await settle();
          diagnostics.processSampler = () async => null;
          diagnostics.toggle();
          diagnostics.debugTick();
          await settle();
          expect(diagnostics.stats.value.processes, isNull);
        });

        test(
          'a sample from an earlier session is dropped after restart',
          () async {
            final pending = Completer<ProcessTreeSample?>();
            diagnostics.processSampler = () => pending.future;
            diagnostics.toggle();
            diagnostics.debugTick();
            diagnostics
              ..toggle()
              ..toggle();
            expect(diagnostics.isCollecting, isTrue);
            pending.complete(sample);
            await settle();
            diagnostics.debugTick();
            // הדגימה של ה-session הקודם לא נקלטה; ה-tick רק התחיל דגימה חדשה.
            expect(diagnostics.stats.value.processes, isNull);
          },
        );

        test(
          'the default sampler uses the registered WebView lister',
          () async {
            diagnostics.resetForTesting();
            var listed = 0;
            diagnostics.webViewProcessLister = () async {
              listed++;
              return const [];
            };
            diagnostics.toggle();
            diagnostics.debugTick();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            expect(listed, Platform.isWindows ? 1 : 0);
          },
        );
      });
    });

    test('toggling it off stops collecting', () {
      diagnostics.toggle();
      expect(diagnostics.isCollecting, isTrue);
      expect(diagnostics.panelVisible.value, isTrue);
      diagnostics.performanceOverlay.value = true;
      diagnostics.toggle();

      expect(diagnostics.isCollecting, isFalse);
      expect(diagnostics.panelVisible.value, isFalse);
      expect(diagnostics.performanceOverlay.value, isFalse);
    });
  });
}
