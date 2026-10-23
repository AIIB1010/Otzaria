import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:window_manager/window_manager.dart' show ResizeEdge;

/// ה-runner של macOS לפי החוזה של `otzaria/view_window` (ViewWindowChannel.swift).
class _FakeRunner {
  final List<MethodCall> calls = [];
  Map<String, Object?>? frame = {'x': 100.0, 'y': 50.0, 'width': 800.0};
  Map<String, Object?>? visibleFrame = {
    'x': 0.0,
    'y': 25.0,
    'width': 1440.0,
    'height': 875.0,
    'scale': 2.0,
  };
  bool ready = true;
  bool cloakResult = false;
  Set<int> knownHandles = {7};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'multiViewReady':
        return ready;
      case 'multiViewStatus':
        return 'ivar _multiViewEnabled not found';
      case 'keyWindow':
        return 7;
      case 'enableReopenHandling':
        return null;
    }
    final handle = (call.arguments as Map)['handle'];
    if (!knownHandles.contains(handle)) {
      throw PlatformException(code: 'unknown_window');
    }
    return switch (call.method) {
      'frame' => frame == null ? null : {...frame!, 'height': 600.0},
      'visibleFrame' => visibleFrame,
      'isVisible' => true,
      'cloak' => cloakResult,
      'reveal' => true,
      _ => null,
    };
  }

  List<String> get methods => [for (final c in calls) c.method];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = CocoaViewWindowNative.defaultChannel;
  const native = CocoaViewWindowNative();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeRunner runner;

  setUp(() {
    runner = _FakeRunner();
    messenger.setMockMethodCallHandler(channel, runner.handle);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('מסגרת: נקודות מה-runner כפול קנה המידה של המסך, לפי ידית', () async {
    expect(
      await native.windowRect(7),
      const Rect.fromLTWH(200, 100, 1600, 1200),
    );
    expect(runner.methods, ['frame', 'visibleFrame']);
    expect(runner.calls.first.arguments, {'handle': 7});
  });

  test(
    'setWindowRect: פיזי חלקי קנה המידה, בצורת הארגומנטים של setFrame',
    () async {
      await native.setWindowRect(7, const Rect.fromLTWH(200, 100, 1600, 1200));
      final setFrame = runner.calls.last;
      expect(setFrame.method, 'setFrame');
      expect(setFrame.arguments, {
        'handle': 7,
        'x': 100.0,
        'y': 50.0,
        'width': 800.0,
        'height': 600.0,
      });
    },
  );

  test('אזור עבודה ומיקום: לפי visibleFrame, DPI 96 לכל 1x', () async {
    expect(await native.workArea(7), const Rect.fromLTWH(0, 50, 2880, 1750));
    final placement = (await native.placement(7))!;
    expect(placement.normal, const Rect.fromLTWH(200, 100, 1600, 1200));
    expect(placement.maximized, isFalse);
    expect(placement.dpi, 192);
  });

  test('visibleFrame null (אין מסך): אין אזור עבודה, וקנה המידה 1', () async {
    runner.visibleFrame = null;
    expect(await native.workArea(7), isNull);
    expect(await native.windowRect(7), const Rect.fromLTWH(100, 50, 800, 600));
    expect((await native.placement(7))!.dpi, 96);
    await native.setWindowRect(7, const Rect.fromLTWH(10, 20, 300, 400));
    expect(runner.calls.last.arguments, {
      'handle': 7,
      'x': 10.0,
      'y': 20.0,
      'width': 300.0,
      'height': 400.0,
    });
  });

  test(
    'ידית שאינה מוכרת (unknown_window): ערכי ברירת מחדל, בלי חריגה',
    () async {
      expect(await native.windowRect(99), isNull);
      expect(await native.workArea(99), isNull);
      expect(await native.placement(99), isNull);
      expect(await native.isVisible(99), isFalse);
      await native.focus(99);
      await native.setWindowRect(99, const Rect.fromLTWH(0, 0, 10, 10));
    },
  );

  test('פעולות החלון: שמות המתודות של ה-runner', () async {
    await native.show(7);
    await native.focus(7);
    await native.startDragging(7);
    expect(await native.isVisible(7), isTrue);
    expect(await native.foregroundWindow(), 7);
    expect(runner.methods, [
      'orderFront',
      'makeKey',
      'startDragging',
      'isVisible',
      'keyWindow',
    ]);
    expect(runner.calls.last.arguments, isNull);
  });

  test('אין בערוץ: הסתרה, שינוי גודל מקצה, הגדלה אנכית ותיקוני קלט', () async {
    await native.hide(7);
    await native.startResizing(7, ResizeEdge.left);
    await native.maximizeVertically(7);
    await native.installViewHooks(7);
    expect(runner.calls, isEmpty);
  });

  test(
    'makeFrameless: cloak ואז makeFrameless, גם כש-cloak מחזיר false',
    () async {
      // false הוא גם "כבר מוסתר" (ה-hook תפס את החלון), ולא "אינו חלון Dart".
      runner.cloakResult = false;
      await native.makeFrameless(7);
      expect(runner.methods, ['cloak', 'makeFrameless']);
      expect(
        runner.calls.every((c) => (c.arguments as Map)['handle'] == 7),
        isTrue,
      );
    },
  );

  test('reveal: עם הפעלה', () async {
    await native.reveal(7);
    expect(runner.calls.single.method, 'reveal');
    expect(runner.calls.single.arguments, {'handle': 7, 'activate': true});
  });

  group('handshake', () {
    test('מוכן: null, בלי שאלת סטטוס', () async {
      expect(await native.multiViewUnavailableReason(), isNull);
      expect(runner.methods, ['multiViewReady']);
    });

    test('לא מוכן: הסיבה מ-multiViewStatus', () async {
      runner.ready = false;
      expect(
        await native.multiViewUnavailableReason(),
        'ivar _multiViewEnabled not found',
      );
      expect(runner.methods, ['multiViewReady', 'multiViewStatus']);
    });

    test('runner בלי הערוץ: סיבה, בלי חריגה', () async {
      messenger.setMockMethodCallHandler(channel, null);
      expect(
        await native.multiViewUnavailableReason(),
        'runner without otzaria/view_window',
      );
    });

    test('runner שאינו עונה: timeout', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      expect(
        await native.multiViewUnavailableReason(
          timeout: const Duration(milliseconds: 10),
        ),
        startsWith('no answer'),
      );
    });
  });

  group('Dock', () {
    Future<Object?> reopenRequested() async {
      final reply = await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('reopenRequested')),
        null,
      );
      return reply == null ? null : channel.codec.decodeEnvelope(reply);
    }

    tearDown(() => channel.setMethodCallHandler(null));

    test('ה-handler מותקן לפני enableReopenHandling, ותשובתו חוזרת', () async {
      var reopens = 0;
      var handlerReadyAtEnable = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'enableReopenHandling') {
          handlerReadyAtEnable = await reopenRequested() == true;
          reopens = 0;
        }
        return runner.handle(call);
      });

      await native.handleDockReopen(() async {
        reopens++;
        return true;
      });

      expect(handlerReadyAtEnable, isTrue);
      expect(await reopenRequested(), isTrue);
      expect(reopens, 1);
    });

    test('שחזור שנכשל: false, וה-runner משחזר בעצמו', () async {
      await native.handleDockReopen(() async => throw StateError('db'));
      expect(await reopenRequested(), isFalse);
    });
  });
}
