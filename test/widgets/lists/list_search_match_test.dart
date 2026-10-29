import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/lists/list_search_match.dart';

int? rank(
  String query,
  String key, {
  List<String>? aliases,
  String? bookTitle,
}) {
  final k = ListSearchKey(key, bookTitle: bookTitle ?? key);
  if (aliases != null) {
    k.setAliases(aliases.map(normalizeForFindRefMatch).toList());
  }
  return listSearchRank(ListSearchQuery(query), k);
}

void main() {
  group('listSearchRank', () {
    test('התאמות מילוליות קודמות לכתיב חלופי', () {
      expect(rank('שרש', 'שורש'), greaterThan(rank('שרש', 'ספר א שרש')!));
      expect(rank('שרש', 'שורש'), greaterThan(rank('שרש', 'שרשראות')!));
      expect(rank('שרש', 'שורש'), greaterThan(rank('שרש', 'משרש')!));
    });

    test('כתיב חלופי מוגבל לכותרת ולא למיקום פנימי', () {
      expect(
        rank('דינים', 'משנה תורה הלכות דיינים', bookTitle: 'משנה תורה'),
        isNull,
      );
      expect(rank('דינים', 'דיינים הלכות שבת', bookTitle: 'דיינים'), isNotNull);
    });

    test('כינויים חלופיים אינם מתערבבים', () {
      expect(
        rank('אור שלום', 'הלכות שבת', aliases: ['אור חיים', 'דרכי שלום']),
        isNull,
      );
    });

    test('התאמה אפשרית אינה אובדת בהקצאה חמדנית', () {
      expect(rank('הרמב רמב', 'רמבם הרמבה'), isNotNull);
    });

    test('טוקנים מעבר למקום 63 אינם זמינים פעמיים', () {
      final key = '${List.filled(64, 'ראשון').join(' ')} אחרון';
      expect(rank('אחרון אחרון', key), isNull);
    });

    test('כינוי מרובה מילים שומר על מופעים חוזרים', () {
      expect(rank('אור אור', 'הלכות שבת', aliases: ['אור אור']), 4);
    });

    test('בלי כותרת מפורשת אין שינוי כתיב', () {
      expect(
        listSearchRank(ListSearchQuery('דינים'), ListSearchKey('דיינים')),
        isNull,
      );
      expect(
        listSearchRank(ListSearchQuery('שורש'), ListSearchKey('שרש')),
        isNull,
      );
    });

    test('כותרת מפורשת אינה מרחיבה מילים זהות במיקום', () {
      expect(rank('שרש שרש', 'שורש הלכות שורש', bookTitle: 'שורש'), isNull);
      expect(
        rank('מקואות', 'משנה תורה הלכות מקוואות', bookTitle: 'משנה תורה'),
        isNull,
      );
      expect(
        rank('דיינים', 'משנה תורה הלכות דיינים', bookTitle: 'משנה תורה'),
        1,
      );
    });

    test('כינוי מחליף כותרת ומתחבר רק למיקום', () {
      expect(rank('אור אור', 'אור', aliases: ['אור']), isNull);
      expect(
        rank(
          'רמבם שבת',
          'משנה תורה הלכות שבת',
          bookTitle: 'משנה תורה',
          aliases: ['רמבם'],
        ),
        4,
      );
      expect(
        rank(
          'רמבם תורה',
          'משנה תורה הלכות שבת',
          bookTitle: 'משנה תורה',
          aliases: ['רמבם'],
        ),
        isNull,
      );
    });

    test('כתיב חלופי מותר בכינוי בלבד ולא במיקום שמצטרף אליו', () {
      expect(rank('מקואות', 'שם הספר', aliases: ['מקוואות']), 6);
      expect(
        rank(
          'רמבם דינים',
          'משנה תורה הלכות דיינים',
          bookTitle: 'משנה תורה',
          aliases: ['רמבם'],
        ),
        isNull,
      );
    });

    test('סינון כינויים והקצאת מילים תואמים חיפוש ממצה', () {
      final random = Random(3436);
      const words = ['a', 'ab', 'abc', 'b', 'ba', 'c'];
      List<String> sample(int count) => [
        for (var i = 0; i < count; i++) words[random.nextInt(words.length)],
      ];
      bool exhaustive(List<String> query, List<String> tokens) {
        final used = List.filled(tokens.length, false);
        bool assign(int i) {
          if (i == query.length) return true;
          for (var j = 0; j < tokens.length; j++) {
            if (used[j] || !tokens[j].startsWith(query[i])) continue;
            used[j] = true;
            if (assign(i + 1)) return true;
            used[j] = false;
          }
          return false;
        }

        return assign(0);
      }

      for (var trial = 0; trial < 500; trial++) {
        final title = sample(1 + random.nextInt(3));
        final context = sample(random.nextInt(3));
        final aliases = [
          for (var i = 0; i < random.nextInt(5); i++)
            sample(1 + random.nextInt(3)),
        ];
        final query = sample(1 + random.nextInt(4));
        final raw = [...title, ...context].join(' ');
        final text = query.join(' ');
        final expected =
            raw.contains(text) ||
            exhaustive(query, [...title, ...context]) ||
            aliases.any((alias) => exhaustive(query, [...context, ...alias]));
        expect(
          rank(
                text,
                raw,
                bookTitle: title.join(' '),
                aliases: aliases.map((a) => a.join(' ')).toList(),
              ) !=
              null,
          expected,
          reason: 'query=$query title=$title context=$context aliases=$aliases',
        );
      }
    });

    test('דרגות ההתאמה', () {
      expect(rank('ברכות', 'ברכות ב.'), 0);
      expect(rank('ברכות ב', 'משנה ברכות ב'), 1);
      expect(rank('משנ ברכ', 'משנה ברכות א'), 2);
      expect(rank('ברכות משנה', 'משנה ברכות'), 3);
      expect(rank('רמבם', 'משנה תורה', aliases: ['רמב"ם']), 4);
      expect(rank('שית', 'בראשית'), 5);
      expect(rank('שבת', 'ברכות ב.'), isNull);
    });

    test('גרשיים וה"א הידיעה לפני ראשי-תיבות', () {
      expect(rank('רמבם', 'רמב"ם הלכות שבת'), 0);
      expect(rank('רמבם', 'הרמב"ם על המשנה'), 2);
    });

    test('כל מילת שאילתה צריכה טוקן משלה', () {
      expect(rank('ברכות ב:', 'ברכות ב:'), 0);
      expect(rank('ברכות ב:', 'ברכות ז.'), isNull);
      expect(rank('ברכות ב:', 'ברכות'), isNull);
      expect(rank('ב ברכות', 'משנה ברכות ב'), 3);
    });

    test('הקלדה חלקית של "הרמב" תואמת "הרמב"ם"', () {
      expect(rank('הרמב', 'הרמב"ם הלכות שבת'), 0);
      expect(rank('הרמב', 'רמב"ם הלכות שבת'), 2);
      expect(rank('הלכ', 'הרמב"ם הלכות שבת'), 2);
    });

    test('כתיב מלא וחסר', () {
      expect(rank('מקואות', 'משנה מקוואות א'), 6);
      expect(rank('מקואות', 'מקוואות א'), 6);
    });

    test('ו/י אחת נוספת בשם הספר — כולל באמצע הקלדה', () {
      expect(rank('ספר השורשים', 'ספר השרשים לרד"ק, שרש א'), 6);
      expect(rank('השורש', 'ספר השרשים לרד"ק'), 6);
      expect(rank('שלחן ערוך', 'שולחן ערוך, אורח חיים א'), 6);
      expect(rank('שולחן ערוך', 'שולחן ערוך, אורח חיים א'), 0);
    });

    test('מילים שונות אינן כתיב מלא/חסר', () {
      expect(rank('שבות', 'שבת א'), isNull);
      expect(rank('ברכות', 'ברכת אברהם'), isNull);
      expect(rank('חיות', 'חות יאיר'), isNull);
      expect(rank('מהריל', 'מהר"ל גבורות השם'), isNull);
    });

    test('כינוי משמש רק כשהמפתח עצמו אינו מתאים', () {
      expect(rank('משנה', 'משנה תורה', aliases: ['משנה']), 0);
      expect(rank('רמבם', 'משנה תורה'), isNull);
    });

    test('שאילתה שהנרמול מרוקן נופלת להכלה גולמית', () {
      expect(rank('(', 'שאילתה (ק)מילה'), 5);
      expect(rank('(', 'שאילתה מילה'), isNull);
    });
  });
}
