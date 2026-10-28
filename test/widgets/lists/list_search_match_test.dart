import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/lists/list_search_match.dart';

int? rank(String query, String key, {List<String>? aliases}) {
  final k = ListSearchKey(key);
  if (aliases != null) {
    k.setAliases(aliases.map(normalizeForFindRefMatch).toList());
  }
  return listSearchRank(ListSearchQuery(query), k);
}

void main() {
  group('listSearchRank', () {
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
      expect(rank('רמבם', 'הרמב"ם על המשנה'), 0);
    });

    test('כל מילת שאילתה צריכה טוקן משלה', () {
      expect(rank('ברכות ב:', 'ברכות ב:'), 0);
      expect(rank('ברכות ב:', 'ברכות ז.'), isNull);
      expect(rank('ברכות ב:', 'ברכות'), isNull);
      expect(rank('ב ברכות', 'משנה ברכות ב'), 3);
    });

    test('הקלדה חלקית של "הרמב" תואמת "הרמב"ם"', () {
      expect(rank('הרמב', 'הרמב"ם הלכות שבת'), 2);
      expect(rank('הרמב', 'רמב"ם הלכות שבת'), 2);
      expect(rank('הלכ', 'הרמב"ם הלכות שבת'), 2);
    });

    test('כתיב מלא וחסר', () {
      expect(rank('מקואות', 'משנה מקוואות א'), 1);
      expect(rank('מקואות', 'מקוואות א'), 0);
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
