import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/book_common/utils/commentary_search_utils.dart';
import 'package:otzaria/text_display/text_display_exports.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

import '../../support/search_engine_test_init.dart';

/// issue #1055 — מונה התאמות החיפוש במפרשים ספר מילים שלמות בעוד ההדגשה
/// חלקית: "אמר" נצבע בתוך "ויאמר" אך לא נספר. המונה חייב לקבל את אותו
/// דגל [partialWordMatch] שמגיע ל-RenderSettings.partialWordHighlight.
Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('countMatches — partialWordMatch (issue #1055)', () {
    test(
      'ברירת המחדל נשארת מילים שלמות — ההתנהגות הקיימת לא השתנתה',
      () {
        expect(utils.countMatches('ויאמר משה', 'אמר'), 0);
        expect(utils.countMatches('אמר רבי', 'אמר'), 1);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'עם הדגל — הופעה בתוך מילה נספרת, כמו שהיא נצבעת',
      () {
        expect(
          utils.countMatches('ויאמר משה', 'אמר', partialWordMatch: true),
          1,
        );
        expect(
          utils.countMatches('אמר ויאמר ונאמר', 'אמר', partialWordMatch: true),
          3,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  group('countCommentarySearchMatches — תואם את ההדגשה', () {
    test(
      'מפרש שמרונדר בהתאמה חלקית — המונה סופר גם הופעות בתוך מילה',
      () {
        expect(
          countCommentarySearchMatches(
            content: 'וַיֹּאמֶר משה אמר',
            query: 'אמר',
            displayProfile: TextDisplayProfile.defaults,
            partialWordMatch: true,
          ),
          2,
        );
        // אותו תוכן בספירת מילים-שלמות — רק ההופעה העצמאית.
        expect(
          countCommentarySearchMatches(
            content: 'וַיֹּאמֶר משה אמר',
            query: 'אמר',
            displayProfile: TextDisplayProfile.defaults,
            partialWordMatch: false,
          ),
          1,
        );
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  // הקפיצה לתוצאה מכוונת אל ההתאמה בתוך המפרש, לפי מקומה בטקסט הגלוי
  // (בלי תגיות HTML וניקוד), ובאותה ספירה של המונה (issue #2534).
  group('commentarySearchMatchTarget (issue #2534)', () {
    // פריט בלי טקסט מרונדר: המיקום הוא אותו חלק מגובה הפריט.
    final item = RenderConstrainedBox(
      additionalConstraints: BoxConstraints.tight(const Size(100, 2100)),
    )..layout(const BoxConstraints());

    double? targetTop(String? content, int matchIndex) =>
        commentarySearchMatchTarget(
          content: content,
          query: 'אמר',
          displayProfile: TextDisplayProfile.defaults,
          matchIndex: matchIndex,
        )?.call(0, item)?.top;

    // הטקסט הגלוי: "אמר בבב גגג ויאמר דדד" — 21 תווים.
    const content = '<b>אָמַר</b> בבב <i>גגג</i> וַיֹּאמֶר דדד';

    test(
      'המיקום הוא התו האחרון של ההתאמה בטקסט הגלוי, גם בתוך מילה',
      () {
        expect(targetTop(content, 0), closeTo(2100 * 2 / 21, 0.001));
        expect(targetTop(content, 1), closeTo(2100 * 16 / 21, 0.001));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'אינדקס מחוץ לטווח או תוכן שלא נטען — ראש הפריט',
      () {
        expect(targetTop(content, 2), isNull);
        expect(targetTop(content, -1), isNull);
        expect(targetTop(null, 0), isNull);
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });
}
