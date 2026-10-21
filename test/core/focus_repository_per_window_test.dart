import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';

/// שני חלונות באותו isolate לא חולקים צמתי פוקוס, טקסט איתור ומחסנית שחזור.
void main() {
  tearDown(AppWindowKeys.resetForTest);

  test('FocusRepository() הוא המופע של החלון הנוכחי, ויציב', () {
    expect(FocusRepository(), same(FocusRepository.current));
    expect(FocusRepository(), same(FocusRepository()));
    expect(
      FocusRepository.current,
      same(FocusRepository.forWindow(AppWindowKeys.current)),
    );
  });

  test('לכל חלון מופע נפרד ועצמאי', () {
    final a = AppWindowKeys();
    final b = AppWindowKeys(id: const AppWindowId('window-2'));
    final repoA = FocusRepository.forWindow(a);
    final repoB = FocusRepository.forWindow(b);
    expect(repoA, isNot(same(repoB)));
    expect(FocusRepository.forWindow(a), same(repoA));

    repoA.findRefSearchController.text = 'בראשית';
    expect(repoB.findRefSearchController.text, isEmpty);
    expect(
      repoA.findRefSearchFocusNode,
      isNot(same(repoB.findRefSearchFocusNode)),
    );

    var restoredA = 0, restoredB = 0;
    repoA.setScreenRestorer(restore: () => restoredA++, canRestore: () => true);
    repoB.setScreenRestorer(restore: () => restoredB++, canRestore: () => true);
    repoA.restoreNowForTesting();
    expect(restoredA, 1);
    expect(restoredB, 0);
  });

  test('current עוקב אחרי activateWindow', () {
    const id = AppWindowId('window-2');
    final keys = AppWindowKeys(id: id);
    AppWindowKeys.register(keys);
    final primary = FocusRepository();

    AppWindowKeys.activateWindow(id);
    expect(FocusRepository(), same(FocusRepository.forWindow(keys)));
    expect(FocusRepository(), isNot(same(primary)));

    AppWindowKeys.activateWindow(AppWindowId.primary);
    expect(FocusRepository(), same(primary));
  });

  testWidgets('of(context) — לפי ה-scope, ובלי scope — הנוכחי', (
    tester,
  ) async {
    final window = _FakeWindow();
    final a = AppWindowKeys();
    final b = AppWindowKeys(id: const AppWindowId('window-2'));
    late FocusRepository inA, inB, outside;
    Widget probe(void Function(FocusRepository) sink) => Builder(
      builder: (context) {
        sink(FocusRepository.of(context));
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      Column(
        children: [
          AppWindowScope(
            controller: window,
            geometry: window,
            keys: a,
            child: probe((r) => inA = r),
          ),
          AppWindowScope(
            controller: window,
            geometry: window,
            keys: b,
            child: probe((r) => inB = r),
          ),
          probe((r) => outside = r),
        ],
      ),
    );

    expect(inA, same(FocusRepository.forWindow(a)));
    expect(inB, same(FocusRepository.forWindow(b)));
    expect(inA, isNot(same(inB)));
    expect(outside, same(FocusRepository()));
  });
}

class _FakeWindow extends Fake
    implements AppWindowController, AppWindowGeometry {}
