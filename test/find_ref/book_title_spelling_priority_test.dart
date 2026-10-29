import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';

import 'support/seeded_reference_library.dart';

void main() {
  tearDown(resetSeededLibrary);

  test('מילה מילולית בכותרת נשארת לפני כתיב חלופי עד המיון הסופי', () async {
    seedLibrary(
      const [
        (id: 2786, title: 'מראית העין על ברכות', acronyms: []),
        (id: 6143, title: 'ספר העיון', acronyms: []),
      ],
      categoryPaths: const {
        2786: 'תלמוד בבלי, אחרונים, מראית העין, סדר זרעים',
        6143: 'קבלה, ספרי קבלה נוספים',
      },
    );
    final results = await buildFindRefRepo().findRefs('העיון');
    expect(results.first.title, 'ספר העיון');
  });

  for (final sample in [
    (
      query: 'שפר',
      variant: 'משנה תורה, הלכות שופר וסוכה ולולב',
      literal: 'אמרי שפר',
    ),
    (query: 'אלעזר', variant: 'משנת רבי אליעזר', literal: 'משמרת אלעזר'),
    (
      query: 'עניים',
      variant: 'פתח עינים על ברכות',
      literal: 'מעשה רקח על הלכות מתנות עניים',
    ),
  ]) {
    test(
      'התאמה מילולית ל-${sample.query} קודמת למילה אחרת בכתיב קרוב',
      () async {
        seedLibrary([
          (id: 1, title: sample.variant, acronyms: <String>[]),
          (id: 2, title: sample.literal, acronyms: <String>[]),
        ]);
        final results = await buildFindRefRepo().findRefs(sample.query);
        expect(results.first.title, sample.literal);
      },
    );
  }

  test('תקרת המטמון שומרת כותרת וכינויים מילוליים לפני כתיב חלופי', () {
    seedLibrary([
      for (var i = 1; i <= 205; i++)
        (id: i, title: 'מראית העין חלק $i', acronyms: <String>[]),
      (id: 300, title: 'ספר העיון', acronyms: <String>[]),
      (id: 301, title: 'כינוי ראשון', acronyms: ['העיון הארוך']),
      (id: 302, title: 'כינוי שני', acronyms: ['ספר העיון הארוך']),
    ]);
    final hits = ReferenceBooksCache.instance.search('העיון', limit: 3);
    expect(hits.map((hit) => hit.bookId), [300, 301, 302]);
  });

  test('התאמת כתיב אינה מוחקת כינוי מילולי חלקי של אותו הספר', () {
    seedLibrary(const [
      (id: 1, title: 'ספר העין', acronyms: ['העיון הארוך']),
      (id: 2, title: 'קיצור העין', acronyms: ['ספר העיון הארוך']),
    ]);
    final hits = ReferenceBooksCache.instance.search('העיון');
    expect(hits.map((hit) => hit.matchRank), [4, 5]);
    expect(hits.map((hit) => hit.matchedTerm), [
      'העיון הארוך',
      'ספר העיון הארוך',
    ]);
  });

  for (final title in ['ספר השרשים לרדק', 'שולחן ערוך']) {
    final query = title.startsWith('ספר') ? 'ספר השורשים' : 'שלחן ערוך';
    test(
      'הכתיב החלופי ב-$query משאיר רק את מיקום ההפניה לחיפוש הפנימי',
      () async {
        seedLibrary([
          (id: 1, title: title, acronyms: <String>[]),
        ]);
        final seen = <List<String>?>[];
        await buildFindRefRepo(tocQueryTokensSeen: seen).findRefs('$query א');
        expect(seen, isNotEmpty);
        expect(seen, everyElement(['א']));
      },
    );
  }

  test(
    'כינוי מילולי חלקי נשמר גם בפענוח סיומת אחרי כותרת בכתיב חלופי',
    () async {
      seedLibrary(const [
        (id: 1, title: 'ספר השרשים לרדק', acronyms: ['ספר השורשים לרדק']),
      ]);
      final seen = <List<String>?>[];
      await buildFindRefRepo(
        tocQueryTokensSeen: seen,
      ).findRefs('ספר השורשים א');
      expect(seen, isNotEmpty);
      expect(seen, everyElement(['א']));
    },
  );

  test('שם ספר בכתיב חלופי נמצא גם ללא כינויים', () async {
    seedLibrary(const [
      (id: 1, title: 'ספר יצירה', acronyms: []),
      (id: 2, title: 'ספר השרשים לרדק', acronyms: []),
    ]);
    expect(
      (await buildFindRefRepo().findRefs('ספר השורשים')).map((r) => r.title),
      ['ספר השרשים לרדק'],
    );
  });

  for (final literal in [
    (title: 'דובר בעניני צדק', author: '', acronyms: <String>[]),
    (title: 'ספר חדש', author: 'דובר בעניני צדק', acronyms: <String>[]),
    (title: 'ספר חדש', author: '', acronyms: ['דובר בעניני צדק']),
  ]) {
    test(
      'התאמה מילולית ב-${literal.title}/${literal.author}/${literal.acronyms} לפני כתיב חלופי מדור מוקדם',
      () {
        final results = filterBookSearchEntries(
          entries: [
            const BookSearchEntry(
              index: 0,
              title: 'דבר צדק',
              author: '',
              topics: '',
              eraOrder: 0,
            ),
            BookSearchEntry(
              index: 1,
              title: literal.title,
              author: literal.author,
              topics: '',
              acronyms: literal.acronyms,
              eraOrder: 5,
            ),
          ],
          queryWords: const ['דובר', 'צדק'],
          topics: const [],
          sortByRatio: true,
          normalizedQuery: 'דובר צדק',
        );
        expect(results, [1, 0]);
      },
    );
  }
}
