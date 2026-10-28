import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import 'support/seeded_reference_library.dart';

/// צורת ההשוואה של שמות ספרים: וו/יי כפולות, ה"א הידיעה לפני ראשי-תיבות,
/// והעדפת הכתיב שבגרשיים בשוויון.
void main() {
  tearDown(resetSeededLibrary);

  group('bookNameMatchToken', () {
    test('וו/יי כפולות כיחידה', () {
      expect(bookNameMatchToken('מקוואות'), 'מקואות');
      expect(bookNameMatchToken('חיים'), 'חים');
      expect(bookNameMatchToken('שבת'), 'שבת');
    });

    test('ה"א הידיעה נשמטת רק לפני ראשי-תיבות שברשימה', () {
      expect(bookNameMatchToken('הרמבם'), 'רמבם');
      expect(bookNameMatchToken('השס'), 'שס');
      // רש"י וחז"ל אינם מקבלים ה"א, ומילה רגילה אינה ראשי-תיבות
      expect(bookNameMatchToken('הרשי'), 'הרשי');
      expect(bookNameMatchToken('החזל'), 'החזל');
      expect(bookNameMatchToken('הלכות'), 'הלכות');
    });

    test('quotedWordsOf: רק גרשיים בתוך מילה', () {
      expect(
        quotedWordsOf('רמב"ם הל\' שבת', normalizeForFindRefMatch),
        {'רמבם'},
      );
      expect(quotedWordsOf('שו״ע או״ח', normalizeForFindRefMatch), {
        'שוע',
        'אוח',
      });
      expect(quotedWordsOf('רמבם שבת', normalizeForFindRefMatch), isEmpty);
    });
  });

  group('BookTitleIndex', () {
    test('"מקואות" מזהה כינוי בכתיב "מקוואות" כהתאמה מלאה ולא מקורבת', () {
      seedLibrary(const [
        (
          id: 1,
          title: 'בן אריה על משנה תורה, הלכות מקוואות',
          acronyms: ['בן אריה מקוואות'],
        ),
      ]);
      final hits = ReferenceBooksCache.instance.search('בן אריה מקואות');
      expect(hits.single.matchRank, 3);
      // התוצאה נושאת את הכינוי בצורתו הרגילה, כמו שהיה בלי צורת ההשוואה
      expect(hits.single.matchedTerm, 'בן אריה מקוואות');
    });

    test('"הרמב״ם הלכות שבת" מזהה את הכינוי "רמב״ם הלכות שבת"', () {
      seedLibrary(const [
        (
          id: 1,
          title: 'משנה תורה, הלכות שבת',
          acronyms: ['רמב"ם הלכות שבת'],
        ),
      ]);
      final hits = ReferenceBooksCache.instance.search('הרמב״ם הלכות שבת');
      expect(hits.single.matchRank, 3);
    });

    test('כינוי שגוי עם ה"א על מפרש אינו נעשה זהה לכינוי בלעדיה', () {
      // במסדים שכבר הופצו יש למגיד משנה כינויים "הרמב"ם הלכות X" — ה"א נשמטת
      // רק מהשאילתה ומהכותרת, ולכן "רמב"ם הלכות גירושין" מזהה רק את משנה תורה.
      seedLibrary(const [
        (
          id: 1,
          title: 'משנה תורה, הלכות גירושין',
          acronyms: ['רמב"ם הלכות גירושין'],
        ),
        (
          id: 2,
          title: 'מגיד משנה על משנה תורה, הלכות גירושין',
          acronyms: ['הרמב"ם הלכות גירושין'],
        ),
      ]);
      final hits = ReferenceBooksCache.instance.search('רמב"ם הלכות גירושין');
      expect(
        {for (final h in hits) h.bookId: h.matchRank},
        {1: 3, 2: 5},
      );
      // ועם ה"א בשאילתה — שני הכינויים מתאימים במלואם, כמו שנכתבו
      expect(
        ReferenceBooksCache.instance
            .search('הרמב"ם הלכות גירושין')
            .map((h) => h.matchRank),
        everyElement(3),
      );
    });

    test('כותרת עם ה"א נמצאת גם בלעדיה, ולהיפך', () {
      seedLibrary(const [
        (id: 1, title: 'השגות הראב"ד על בבא קמא', acronyms: []),
      ]);
      expect(
        ReferenceBooksCache.instance.search('השגות ראב"ד').single.matchRank,
        1,
      );
    });
  });

  group('findRefs — העדפת הכתיב שבגרשיים', () {
    test('בשוויון קודם ספר שכינויו כתוב בגרשיים כמו השאילתה', () async {
      // לשני הספרים כינוי זהה אחרי נרמול; בלי ההעדפה הראשון ברשימה קודם.
      seedLibrary(const [
        (id: 1, title: 'ספר ראשון', acronyms: ['רמבם']),
        (id: 2, title: 'ספר שני', acronyms: ['רמב"ם']),
      ]);
      final quoted = (await buildFindRefRepo().findRefs(
        'רמב"ם',
      )).map((r) => r.title).toList();
      expect(quoted.indexOf('ספר שני'), lessThan(quoted.indexOf('ספר ראשון')));

      final plain = (await buildFindRefRepo().findRefs(
        'רמבם',
      )).map((r) => r.title).toList();
      expect(plain.indexOf('ספר ראשון'), lessThan(plain.indexOf('ספר שני')));
    });
  });

  group('isBookTitleSpellingVariant', () {
    const same = [
      ('מדות', 'מידות'),
      ('תפלה', 'תפילה'),
      ('חדושי', 'חידושי'),
      ('באור', 'ביאור'),
      ('מגלה', 'מגילה'),
      ('שלחן', 'שולחן'),
      ('תהלים', 'תהילים'),
      ('רבנו', 'רבינו'),
      ('עדיות', 'עדויות'),
      ('שרשים', 'שורשים'),
      ('השרשים', 'השורשים'),
      ('שרש', 'שורש'),
      ('כהן', 'כוהן'),
      ('קצור', 'קיצור'),
      ('עוקצין', 'עוקצים'),
      ('ביכורים', 'בכורים'),
      ('עירובין', 'ערובין'),
      ('קידושין', 'קדושין'),
      ('תפילין', 'תפלין'),
      ('מגילת', 'מגלת'),
      ('הזוהר', 'הזהר'),
      ('מקוואות', 'מקואות'),
      ('דינין', 'דינים'),
    ];
    for (final (a, b) in same) {
      test('$a = $b', () {
        expect(isBookTitleSpellingVariant(a, b), isTrue);
        expect(isBookTitleSpellingVariant(b, a), isTrue);
      });
    }

    const different = [
      ('שבת', 'שבות'),
      ('חות', 'חיות'),
      ('ברכת', 'ברכות'),
      ('תלמוד', 'תלמיד'),
      ('שבועות', 'שביעית'),
      ('הושע', 'יהושע'),
      ('דברי', 'דבריו'),
      ('ותורה', 'תורה'),
      ('רב', 'רוב'),
      ('מצה', 'מצוה'),
      ('מדות', 'מהדורות'),
      ('עקר', 'עיקר'),
      ('קצר', 'קיצור'),
      ('מהרל', 'מהריל'),
      ('רדבז', 'רידבז'),
      ('מהרם', 'מהרים'),
      ('המהרל', 'המהריל'),
      ('אדם', 'אדום'),
      ('שלם', 'שלום'),
      ('פרש', 'פירש'),
      ('תקן', 'תיקן'),
      ('בנין', 'בנים'),
      ('מנחת', 'מנחות'),
      ('מקור', 'מקורי'),
    ];
    for (final (a, b) in different) {
      test('$a ≠ $b', () {
        expect(isBookTitleSpellingVariant(a, b), isFalse);
        expect(isBookTitleSpellingVariant(b, a), isFalse);
      });
    }

    test('בתחילת מילה, אולי אחרי אות שימוש — לא באמצעה', () {
      expect(startsWithBookTitleSpellingVariant('השרשים', 'שורש'), isTrue);
      expect(startsWithBookTitleSpellingVariant('שרשי', 'שורש'), isTrue);
      expect(startsWithBookTitleSpellingVariant('השורשים', 'שרשים'), isTrue);
      expect(startsWithBookTitleSpellingVariant('תשובות', 'שבות'), isFalse);
      expect(startsWithBookTitleSpellingVariant('החיות', 'חות'), isFalse);
      expect(startsWithBookTitleSpellingVariant('המהריל', 'מהרל'), isFalse);
      expect(startsWithBookTitleSpellingVariant('רידבז', 'רדבז'), isFalse);
    });
  });

  group('findRefs — כתיב מלא/חסר בשם הספר', () {
    test(
      '"ספר השורשים" מוצא את "ספר השרשים לרדק" ולא נקבר תחת "ספר"',
      () async {
        seedLibrary(const [
          (id: 3052, title: 'ספר יצירה', acronyms: []),
          (id: 3891, title: 'ספר החינוך', acronyms: []),
          (id: 3922, title: 'ספר חסידים', acronyms: []),
          (
            id: 6063,
            title: 'ספר השרשים לרדק',
            acronyms: [
              'ספר השורשים לרדק',
              'ספר השרשים רדק',
              'ספר שרשים לרדק',
              'רדק',
            ],
          ),
        ]);
        final results = await buildFindRefRepo().findRefs('ספר השורשים');
        expect(results.first.title, 'ספר השרשים לרדק');
        expect(results.first.reference, 'ספר השרשים לרדק');
      },
    );

    test('"שלחן ערוך" מזהה את "שולחן ערוך" כהתאמת כותרת ולא כמקורבת', () {
      seedLibrary(const [
        (id: 3813, title: 'חתם סופר על שלחן ערוך אורח חיים', acronyms: []),
        (id: 382, title: 'שולחן ערוך, אורח חיים', acronyms: []),
      ]);
      final hit = ReferenceBooksCache.instance
          .search('שלחן ערוך')
          .singleWhere((h) => h.bookId == 382);
      expect(hit.matchRank, 2);
      expect(hit.spellingVariantTitleIndex, 0);
    });

    test('כתיב שונה של מילה אחרת אינו התאמת כותרת', () {
      seedLibrary(const [
        (id: 1, title: 'שות שבות יעקב', acronyms: []),
        (id: 2, title: 'תשובות רשי', acronyms: []),
      ]);
      final hits = ReferenceBooksCache.instance.search('שבת');
      expect(hits, isEmpty);
    });
  });

  group('findRefs — כינוי מדויק גובר על כתיב מלא/חסר של הכותרת', () {
    void seedYerushalmiAndGershom() => seedLibrary(const [
      (
        id: 140,
        title: 'תלמוד ירושלמי ברכות',
        acronyms: ['ירושלמי ברכות', 'ירושלמי'],
      ),
      (
        id: 150,
        title: 'תלמוד ירושלמי בכורים',
        acronyms: ['ירושלמי ביכורים', 'ירושלמי בכורים', 'ירושלמי'],
      ),
      (
        id: 2094,
        title: 'רבינו גרשום על תענית',
        acronyms: ['רבינו גרשום תענית', 'רגש תענית'],
      ),
      (
        id: 2104,
        title: 'רבינו גרשום על תמורה',
        acronyms: ['גרשום על תמורה', 'גרשם על תמורה', 'גרשם תמורה'],
      ),
    ]);

    test('הכינוי "ירושלמי ביכורים" נשאר דירוג 3 עם המונח', () {
      seedYerushalmiAndGershom();
      final hit = ReferenceBooksCache.instance
          .search('ירושלמי ביכורים')
          .singleWhere((h) => h.bookId == 150);
      expect(hit.matchRank, 3);
      expect(hit.matchedTerm, 'ירושלמי ביכורים');
    });

    test('הכינוי "גרשם על תמורה" נשאר דירוג 3 עם המונח', () {
      seedYerushalmiAndGershom();
      final hits = ReferenceBooksCache.instance.search('גרשם על תמורה');
      final hit = hits.singleWhere((h) => h.bookId == 2104);
      expect(hit.matchRank, 3);
      expect(hit.matchedTerm, 'גרשם על תמורה');
      expect(hits.where((h) => h.bookId == 2094), isEmpty);
    });

    test('"מהרל" אינו מזהה את ספרי המהרי"ל כהתאמת כותרת', () {
      seedLibrary(const [
        (id: 5948, title: 'מהריל (מנהגים)', acronyms: []),
        (id: 6952, title: 'ליקוטי מהריל על התורה', acronyms: []),
      ]);
      expect(ReferenceBooksCache.instance.search('מהרל גבורות'), isEmpty);
      // מרחק עריכה 1 (התאמה מקורבת) נשאר כמו קודם — רק לא כתיב מלא/חסר.
      expect(
        ReferenceBooksCache.instance.search('מהרל').map((h) => h.matchRank),
        everyElement(ReferenceBooksCache.fuzzyMatchRank),
      );
    });
  });

  group('findRefs — כתיב מלא/חסר של ספר אחר מול כינוי מדויק', () {
    void seedGittin() => seedLibrary(const [
      (id: 206, title: 'תוספתא גיטין', acronyms: []),
      (id: 120, title: 'גיטין', acronyms: ['גיט', 'גיטן', 'מסכת גיטין']),
    ]);

    test('"גיטן" — הכינוי המדויק קודם בבחירת הספרים', () {
      seedGittin();
      final hits = ReferenceBooksCache.instance.search('גיטן');
      expect(hits.map((h) => h.bookId), [120, 206]);
      expect(hits.last.spellingVariantTitleIndex, 1);
    });

    test('"גיטן" — גיטין ראשון בתוצאות', () async {
      seedGittin();
      final results = await buildFindRefRepo().findRefs('גיטן');
      expect(results.first.title, 'גיטין');
    });

    test('"שולחנו של" — "של" אינו נבלע בתחילית של "שלחנו"', () async {
      seedLibrary(const [
        (id: 7651, title: 'שלחנו של אברהם', acronyms: []),
      ]);
      final results = await buildFindRefRepo().findRefs('שולחנו של');
      expect(results.map((r) => r.title), ['שלחנו של אברהם']);
    });
  });

  group('כתיב מלא/חסר — גבולות', () {
    test('מילים קצרות וריקות אינן זורקות ואינן מותאמות', () {
      const words = ['', 'ו', 'י', 'או', 'בו', 'שב', 'שבו'];
      for (final a in words) {
        for (final b in words) {
          expect(isBookTitleSpellingVariant(a, b), isFalse, reason: '$a/$b');
          expect(startsWithBookTitleSpellingVariant(a, b), isFalse);
        }
      }
    });

    test('הנרמול הכללי (גם של הכותרות הפנימיות) אינו מאחד כתיב', () {
      expect(
        normalizeForFindRefMatch('ספר השורשים'),
        isNot(normalizeForFindRefMatch('ספר השרשים')),
      );
      expect(bookNameMatchToken('השורשים'), 'השורשים');
      expect(normalizeForFindRefMatch('דיינים'), 'דיינים');
    });

    test('שאילתה בכתיב הכותרת עצמו אינה מסומנת ככתיב מלא/חסר', () {
      seedLibrary(const [(id: 6063, title: 'ספר השרשים לרדק', acronyms: [])]);
      final hit = ReferenceBooksCache.instance
          .search('ספר השרשים')
          .singleWhere((h) => h.bookId == 6063);
      expect(hit.matchRank, 1);
      expect(hit.spellingVariantTitleIndex, isNull);
    });

    test('נסמך ורבים (ברכת/ברכות) אינם התאמת כתיב', () {
      seedLibrary(const [
        (id: 1, title: 'ברכות', acronyms: []),
        (id: 2, title: 'ברכת אברהם', acronyms: []),
      ]);
      expect(
        ReferenceBooksCache.instance
            .search('ברכת')
            .where((h) => h.spellingVariantTitleIndex != null),
        isEmpty,
      );
    });

    test('"מגילה": המסכת ראשונה, וכותרת מילולית לפני "מגלה עמוקות"', () async {
      seedLibrary(const [
        (id: 1, title: 'מגלה עמוקות על התורה', acronyms: []),
        (id: 2, title: 'תוספתא מגילה', acronyms: []),
        (id: 3, title: 'מגילה', acronyms: ['מסכת מגילה']),
      ]);
      final titles = (await buildFindRefRepo().findRefs(
        'מגילה',
      )).map((r) => r.title).toList();
      expect(titles.first, 'מגילה');
      final deep = titles.indexOf('מגלה עמוקות על התורה');
      if (deep != -1) {
        expect(titles.indexOf('תוספתא מגילה'), lessThan(deep));
      }
    });

    test('שתי מילים בכתיב מלא באותה שאילתה', () {
      seedLibrary(const [(id: 1, title: 'חדושי תפלה', acronyms: [])]);
      final hit = ReferenceBooksCache.instance
          .search('חידושי תפילה')
          .singleWhere((h) => h.bookId == 1);
      expect(hit.matchRank, 2);
      expect(hit.spellingVariantTitleIndex, 0);
    });

    test('כתיב מלא של מילה אחת אינו מכסה מילה אחרת שאינה תואמת', () {
      seedLibrary(const [(id: 1, title: 'ספר השרשים לרדק', acronyms: [])]);
      expect(
        ReferenceBooksCache.instance
            .search('ספור השורשים')
            .where((h) => h.spellingVariantTitleIndex != null),
        isEmpty,
      );
    });
  });
}
