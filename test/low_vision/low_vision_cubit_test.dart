import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/low_vision/input/lv_action.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/models/books.dart';
import 'package:shared_preferences/shared_preferences.dart';

TextBook _book(String title) => TextBook(title: title);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('קביעת ספר מציבה אותו ראשון, וביטול מסיר אותו', () async {
    final cubit = LowVisionCubit();
    await cubit.load();
    final a = _book('א');
    final b = _book('ב');
    cubit.noteOpened(a);
    cubit.noteOpened(b);
    expect(cubit.openBooks.map((e) => e.title), ['ב', 'א']);

    cubit.togglePin(a);
    expect(cubit.openBooks.map((e) => e.title), ['א', 'ב']);
    expect(cubit.isPinned(a), isTrue);

    cubit.togglePin(a);
    expect(cubit.isPinned(a), isFalse);
    await cubit.close();
  });

  test('ספר שנפתח שוב עובר לראש האחרונים בלי כפילות', () async {
    final cubit = LowVisionCubit();
    await cubit.load();
    final a = _book('א');
    cubit.noteOpened(a);
    cubit.noteOpened(_book('ב'));
    cubit.noteOpened(_book('א'));
    expect(cubit.state.recents.map((e) => e.title), ['א', 'ב']);
    await cubit.close();
  });

  test('ההעדפות והמיקומים נשמרים וחוזרים אחרי הפעלה מחדש', () async {
    final first = LowVisionCubit();
    await first.load();
    final book = _book('תנ"ך');
    first.togglePin(book);
    first.savePosition(book, const LvReadingPosition(42, -0.25));
    first.setTextScale(2.5);
    first.setPalette(LvPalette.whiteOnBlack);
    first.setShowNikud(false);
    first.setKeyOverride('next', [1234]);
    await first.close();

    final second = LowVisionCubit();
    await second.load();
    expect(second.state.pinned.single.title, 'תנ"ך');
    expect(second.positionOf(book)?.index, 42);
    expect(second.positionOf(book)?.fraction, -0.25);
    expect(second.state.textScale, 2.5);
    expect(second.state.palette, LvPalette.whiteOnBlack);
    expect(second.state.showNikud, isFalse);
    expect(second.state.keyOverrides['next'], [1234]);
    await second.close();
  });

  test('גודל הטקסט מוגבל לטווח', () async {
    final cubit = LowVisionCubit();
    await cubit.load();
    cubit.setTextScale(100);
    expect(cubit.state.textScale, LowVisionState.maxTextScale);
    cubit.setTextScale(0);
    expect(cubit.state.textScale, LowVisionState.minTextScale);
    await cubit.close();
  });

  test('נתונים פגומים ב-SharedPreferences אינם מונעים טעינה', () async {
    SharedPreferences.setMockInitialValues({
      'low_vision_state_v1': '{"pinned": [{"bad": 1}], "palette": "nope"}',
    });
    final cubit = LowVisionCubit();
    await cubit.load();
    expect(cubit.state.loaded, isTrue);
    expect(cubit.state.pinned, isEmpty);
    expect(cubit.state.palette, LvPalette.blackOnWhite);
    await cubit.close();
  });

  test('כל מקשי המאקרו F13–F22 משויכים לפעולה אחת בלבד', () {
    final seen = <int>{};
    for (final action in LvAction.values) {
      for (final key in action.defaultKeys) {
        expect(seen.add(key.keyId), isTrue, reason: '${key.keyLabel} כפול');
      }
    }
    for (final key in [
      LogicalKeyboardKey.f13,
      LogicalKeyboardKey.f14,
      LogicalKeyboardKey.f22,
    ]) {
      expect(seen, contains(key.keyId));
    }
  });

  test('מקשי זום סטנדרטיים (כולל חוגה שמדמה זום) מוגדרים כברירת מחדל', () {
    expect(
      LvAction.zoomIn.defaultKeys.map((k) => k.keyId),
      contains(LogicalKeyboardKey.zoomIn.keyId),
    );
    expect(
      LvAction.zoomOut.defaultKeys.map((k) => k.keyId),
      contains(LogicalKeyboardKey.zoomOut.keyId),
    );
  });

  test('שיוך מחוות, זמן החזקה והחלקה נשמרים וחוזרים', () async {
    final first = LowVisionCubit();
    await first.load();
    expect(
      first.state.actionFor(LvGesture.doubleTapLeft),
      LvTouchAction.nextPage,
    );
    first.setTouchBinding(LvGesture.threeFingerTap, LvTouchAction.colors);
    first.setHoldSeconds(2.5);
    first.setGlide(true);
    await first.close();

    final second = LowVisionCubit();
    await second.load();
    expect(
      second.state.actionFor(LvGesture.threeFingerTap),
      LvTouchAction.colors,
    );
    expect(second.state.actionFor(LvGesture.hold), LvTouchAction.back);
    expect(second.state.holdSeconds, 2.5);
    expect(second.state.glide, isTrue);
    await second.close();
  });
}
