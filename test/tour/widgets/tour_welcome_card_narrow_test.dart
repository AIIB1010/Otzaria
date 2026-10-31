import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tour/widgets/tour_tooltip_card.dart';

/// issue #1318 — במסך טלפון שורת הכפתורים "דלג — אגלה לבד" / "בוא נתחיל"
/// גלשה מרוחב כרטיס הפתיחה (RIGHT OVERFLOWED). הכפתורים חייבים לרדת שורה.
void main() {
  Future<void> pumpNarrow(
    WidgetTester tester, {
    required SettingsLanguage language,
    double width = 320,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: SettingsTextScope(
            language: language,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: TourTooltipCard(
                    title: 'ברוכים הבאים לאוצריא',
                    body: 'ספרייה תורנית דיגיטלית חינמית ופתוחה.',
                    currentIndex: -1,
                    totalSteps: 3,
                    isLastStep: false,
                    isWelcomeStep: true,
                    onNext: () {},
                    onSkip: () {},
                    onToggleAutoPlay: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('כרטיס הפתיחה של הסיור במסך צר (issue #1318)', () {
    for (final language in [
      SettingsLanguage.hebrew,
      SettingsLanguage.english,
    ]) {
      testWidgets('כרטיס הפתיחה ברוחב 320 אינו גולש (${language.name})', (
        tester,
      ) async {
        await pumpNarrow(tester, language: language);
        expect(tester.takeException(), isNull);
        expect(find.byType(FilledButton), findsWidgets);
      });
    }

    testWidgets('בהגדלת HumanWare הגוף גולל והכפתור נשאר במסך', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.85)),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: SettingsTextScope(
                language: SettingsLanguage.hebrew,
                child: Scaffold(
                  body: Center(
                    child: TourTooltipCard(
                      title: 'ברוכים הבאים לאוצריא',
                      body:
                          'ספרייה תורנית דיגיטלית חינמית ופתוחה.\n\n'
                          'מאחר שעדיין לא טענת ספרייה, יוצג כעת סיור מקוצר. '
                          'לאחר טעינת הספרייה תוכל להפעיל שוב את הסיור המלא '
                          'מ: הגדרות ← מערכת.',
                      currentIndex: -1,
                      totalSteps: 3,
                      isLastStep: false,
                      isWelcomeStep: true,
                      onNext: () {},
                      onSkip: () {},
                      onToggleAutoPlay: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('בוא נתחיל'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });
}
