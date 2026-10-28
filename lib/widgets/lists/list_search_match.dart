import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

/// הצורה שבה משווים בחיפוש הרשימה — כמו באיתור מקורות.
String _matchForm(String text) =>
    bookNameMatchForm(normalizeForFindRefMatch(text));

List<String> _tokensOf(String form) =>
    form.isEmpty ? const [] : form.split(' ');

/// שאילתה מוכנה — נבנית פעם אחת לכל הקלדה.
class ListSearchQuery {
  ListSearchQuery(String raw)
    : rawLower = raw.toLowerCase(),
      form = _matchForm(raw) {
    tokens = _tokensOf(form);
    assignOrder = List.of(tokens)..sort((a, b) => b.length - a.length);
  }

  final String rawLower;
  final String form;
  late final List<String> tokens;

  /// הארוכות קודם — כדי ש"ב" לא יתפוס את "ברכות" לפני "ברכות" עצמה.
  late final List<String> assignOrder;
}

/// מפתח החיפוש של פריט, מוכן מראש ונשמר בין הקלדות.
class ListSearchKey {
  ListSearchKey(String raw)
    : rawLower = raw.toLowerCase(),
      form = _matchForm(raw) {
    tokens = _tokensOf(form);
  }

  final String rawLower;
  final String form;
  late final List<String> tokens;

  /// null — הכינויים עוד לא סופקו (למשל המטמון שלהם לא נטען).
  List<String>? aliasTokens;

  /// [aliases] כבר מנורמלים ב-[normalizeForFindRefMatch].
  void setAliases(List<String> aliases) {
    final out = <String>{};
    for (final alias in aliases) {
      out.addAll(_tokensOf(bookNameSpellingForm(alias)));
    }
    aliasTokens = out.toList(growable: false);
  }
}

/// דרגת ההתאמה של [key] ל-[query]: נמוך יותר — טוב יותר; null — אין התאמה.
int? listSearchRank(ListSearchQuery query, ListSearchKey key) {
  final q = query.tokens;
  if (q.isEmpty) {
    return key.rawLower.contains(query.rawLower) ? 5 : null;
  }
  final k = key.tokens;
  if (key.form.startsWith(query.form)) return 0;
  switch (_assignTokens(query.assignOrder, k, key.aliasTokens)) {
    case _Assigned.key:
      // דרגות 1-2 מוכלות ב-3, ולכן נבדקות רק כשהיא מתקיימת.
      if (_inOrder(q, k, exact: true)) return 1;
      if (_inOrder(q, k, exact: false)) return 2;
      return 3;
    case _Assigned.withAliases:
      return 4;
    case _Assigned.none:
      break;
  }
  if (key.rawLower.contains(query.rawLower) || key.form.contains(query.form)) {
    return 5;
  }
  return null;
}

/// דרגות [listSearchRank] האפשריות: 0..5.
const int listSearchRankCount = 6;

enum _Assigned { none, key, withAliases }

/// כל מילת שאילתה צריכה טוקן משלה — אחרת "ב" של "ברכות ב:" נבלע ב"ברכות".
/// מעבר ל-63 טוקנים הסימון לא נשמר, והם זמינים שוב.
_Assigned _assignTokens(List<String> q, List<String> k, List<String>? aliases) {
  var usedKey = 0;
  var usedAlias = 0;
  var needAliases = false;
  for (var i = 0; i < q.length; i++) {
    final t = q[i];
    final j = _claim(k, t, usedKey);
    if (j != -1) {
      if (j < 63) usedKey |= 1 << j;
      continue;
    }
    final a = aliases == null ? -1 : _claim(aliases, t, usedAlias);
    if (a == -1) return _Assigned.none;
    if (a < 63) usedAlias |= 1 << a;
    needAliases = true;
  }
  return needAliases ? _Assigned.withAliases : _Assigned.key;
}

/// הטוקן הפנוי הראשון שתואם את [t], עם עדיפות לזהה; -1 — אין.
int _claim(List<String> tokens, String t, int used) {
  var prefixAt = -1;
  for (var j = 0; j < tokens.length; j++) {
    if (j < 63 && used & (1 << j) != 0) continue;
    if (tokens[j] == t) return j;
    if (prefixAt == -1 && _tokenMatches(tokens[j], t)) prefixAt = j;
  }
  return prefixAt;
}

// התאמה חמדנית לטוקן המוקדם ביותר — מספיקה לבדיקת תת-סדרה.
bool _inOrder(List<String> q, List<String> k, {required bool exact}) {
  var j = 0;
  for (var i = 0; i < q.length; i++) {
    final t = q[i];
    while (j < k.length && !(exact ? k[j] == t : _tokenMatches(k[j], t))) {
      j++;
    }
    if (j == k.length) return false;
    j++;
  }
  return true;
}

/// תחילית; "הרמב" בהקלדה תואם גם "רמבם", שה"א הידיעה הוסרה ממנו במפתח.
bool _tokenMatches(String keyToken, String queryToken) {
  if (keyToken.startsWith(queryToken)) return true;
  final n = queryToken.length;
  if (n < 2 ||
      queryToken.codeUnitAt(0) != 0x05D4 ||
      keyToken.length < n - 1 ||
      !sagesTakingDefiniteArticle.contains(keyToken)) {
    return false;
  }
  for (var i = 1; i < n; i++) {
    if (keyToken.codeUnitAt(i - 1) != queryToken.codeUnitAt(i)) return false;
  }
  return true;
}
