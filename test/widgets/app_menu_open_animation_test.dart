import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tool_catalog_entry.dart';
import 'package:otzaria/tools/view/tools_launcher_panel.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

/// תפריט מעוגן גדל מהכפתור והלאה: למטה כשהוא נפתח מתחתיו, ולמעלה כשאין
/// מקום והוא נפתח מעליו (issue #2463).
void main() {
  const actionLabels = ['הגדרות התוסף', 'הסתר מהממשק', 'הסר את התוסף'];

  Widget host(Alignment alignment, Widget child) => MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Align(alignment: alignment, child: child),
      ),
    ),
  );

  Widget pluginCard() => SizedBox(
    width: 140,
    height: 140,
    child: ToolTile(
      entry: ToolCatalogEntry(
        toolId: 'plugin.sample',
        label: 'תוסף לדוגמה',
        order: 900,
        icon: FluentIcons.puzzle_piece_24_regular,
      ),
      isOpen: false,
      isHighlighted: false,
      onTap: () {},
      actions: [
        for (final label in actionLabels)
          ToolTileAction(
            icon: FluentIcons.settings_24_regular,
            label: label,
            onTap: () {},
          ),
      ],
    ),
  );

  Finder menuBox(String itemLabel) => find
      .ancestor(
        of: find.text(itemLabel),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.type == MaterialType.card,
        ),
      )
      .first;

  double itemOpacity(WidgetTester tester, String itemLabel) => tester
      .widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(itemLabel),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  /// פותח את התפריט ומחזיר את מלבן התפריט באמצע האנימציה ובסופה.
  Future<({Rect anchor, Rect middle, Rect end})> openAndMeasure(
    WidgetTester tester,
    Finder trigger,
    String itemLabel, {
    void Function()? atMiddle,
  }) async {
    final anchor = tester.getRect(trigger);
    await tester.tap(trigger);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final middle = tester.getRect(menuBox(itemLabel));
    atMiddle?.call();
    await tester.pumpAndSettle();
    final end = tester.getRect(menuBox(itemLabel));
    return (anchor: anchor, middle: middle, end: end);
  }

  final menuButton = find.byIcon(FluentIcons.more_vertical_24_regular);

  group('תפריט כרטיס תוסף בפאנל הכלים (issue #2463)', () {
    testWidgets('אין מקום למטה — התפריט נפתח מעל הכפתור וגדל כלפי מעלה', (
      tester,
    ) async {
      await tester.pumpWidget(host(Alignment.bottomCenter, pluginCard()));

      final rects = await openAndMeasure(
        tester,
        menuButton,
        actionLabels.first,
        atMiddle: () {
          // הפריט הקרוב לכפתור (התחתון) מופיע לפני העליון.
          expect(
            itemOpacity(tester, actionLabels.last),
            greaterThan(itemOpacity(tester, actionLabels.first)),
          );
        },
      );

      expect(rects.end.bottom, lessThanOrEqualTo(rects.anchor.top));
      expect(rects.middle.height, lessThan(rects.end.height));
      // הקצה הצמוד לכפתור קבוע, והקצה הרחוק נע כלפי מעלה.
      expect(rects.middle.bottom, moreOrLessEquals(rects.end.bottom));
      expect(rects.middle.top, greaterThan(rects.end.top));
    });

    testWidgets('יש מקום למטה — התפריט נפתח מתחת לכפתור וגדל כלפי מטה', (
      tester,
    ) async {
      await tester.pumpWidget(host(Alignment.topCenter, pluginCard()));

      final rects = await openAndMeasure(
        tester,
        menuButton,
        actionLabels.first,
        atMiddle: () {
          expect(
            itemOpacity(tester, actionLabels.first),
            greaterThan(itemOpacity(tester, actionLabels.last)),
          );
        },
      );

      expect(rects.end.top, greaterThanOrEqualTo(rects.anchor.bottom));
      expect(rects.middle.height, lessThan(rects.end.height));
      expect(rects.middle.top, moreOrLessEquals(rects.end.top));
      expect(rects.middle.bottom, lessThan(rects.end.bottom));
    });
  });

  // כל התפריטים המעוגנים עוברים דרך showAnchoredAppMenu — גם שדה בחירה
  // בתחתית מסך (למשל בהגדרות), עם הערך הנוכחי מסומן.
  testWidgets('שדה בחירה בתחתית המסך — התפריט גדל כלפי מעלה (issue #2463)', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        Alignment.bottomCenter,
        SizedBox(
          width: 240,
          child: AppDropdownField<int>(
            value: 2,
            entries: const [
              AppMenuEntry(value: 1, label: 'אפשרות ראשונה'),
              AppMenuEntry(value: 2, label: 'אפשרות שנייה'),
              AppMenuEntry(value: 3, label: 'אפשרות שלישית'),
            ],
            onSelected: (_) {},
          ),
        ),
      ),
    );

    final rects = await openAndMeasure(
      tester,
      find.byType(AppDropdownField<int>),
      'אפשרות ראשונה',
    );

    expect(rects.end.bottom, lessThanOrEqualTo(rects.anchor.top));
    expect(rects.middle.bottom, moreOrLessEquals(rects.end.bottom));
    expect(rects.middle.top, greaterThan(rects.end.top));
  });

  for (final alignment in [
    Alignment.topRight,
    Alignment.bottomRight,
    Alignment.topLeft,
    Alignment.bottomLeft,
  ]) {
    for (final direction in TextDirection.values) {
      testWidgets('תפריט נשאר צמוד לעוגן לאחר resize: $alignment $direction', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Align(
                    alignment: alignment,
                    child: AppPopupMenuButton<int>(
                      entries: const [
                        AppMenuEntry(value: 1, label: 'פריט בתפריט'),
                      ],
                      child: const SizedBox(
                        width: 80,
                        height: 40,
                        child: Text('פתח תפריט'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('פתח תפריט'));
        await tester.pumpAndSettle();
        final alignRight = alignment.x > 0;
        final originalAnchor = tester.getRect(find.text('פתח תפריט'));
        final originalMenu = tester.getRect(menuBox('פריט בתפריט'));

        for (final size in [const Size(1000, 800), const Size(700, 500)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final anchor = tester.getRect(find.text('פתח תפריט'));
          final menu = tester.getRect(menuBox('פריט בתפריט'));
          expect(
            alignRight ? menu.right - anchor.right : menu.left - anchor.left,
            moreOrLessEquals(
              alignRight
                  ? originalMenu.right - originalAnchor.right
                  : originalMenu.left - originalAnchor.left,
            ),
          );
          final gap = alignment.y < 0
              ? menu.top - anchor.bottom
              : anchor.top - menu.bottom;
          expect(gap, moreOrLessEquals(4));
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
