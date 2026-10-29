import 'package:flutter/foundation.dart';
import 'package:otzaria/find_ref/book_name_match.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

String _matchForm(String text) => normalizeForFindRefMatch(text);

List<String> _tokensOf(String form) =>
    form.isEmpty ? const [] : form.split(' ');

/// שאילתה מוכנה — נבנית פעם אחת לכל הקלדה.
class ListSearchQuery {
  ListSearchQuery(String raw)
    : rawLower = raw.toLowerCase(),
      form = _matchForm(raw) {
    tokens = _tokensOf(form);
  }

  final String rawLower;
  final String form;
  late final List<String> tokens;
  late final List<String> _spellingTokens = tokens
      .map(bookNameMatchToken)
      .toList();
  final Map<String, List<bool>> _literalMatches = {};
  final Map<String, List<bool>> _variantMatches = {};

  bool matches(String token, int index, {bool spelling = false}) {
    final literal = _literalMatches.putIfAbsent(
      token,
      () => [for (final word in tokens) _tokenMatches(token, word)],
    );
    if (literal[index] || !spelling) return literal[index];
    return _variantMatches.putIfAbsent(token, () {
      final key = bookNameMatchToken(token);
      return [
        for (final word in _spellingTokens)
          key.startsWith(word) || startsWithBookTitleSpellingVariant(key, word),
      ];
    })[index];
  }
}

/// מפתח מוכן; כתיב חלופי מותר רק במילות [bookTitle] המופיעות בו כרצף.
class ListSearchKey {
  ListSearchKey(this.raw, {this.bookTitle})
    : rawLower = raw.toLowerCase(),
      form = _matchForm(raw) {
    tokens = _tokensOf(form);
    final title = bookTitle == null
        ? const <String>[]
        : _tokensOf(_matchForm(bookTitle!));
    if (title.isEmpty) return;
    for (var start = 0; start + title.length <= tokens.length; start++) {
      if (listEquals(tokens.sublist(start, start + title.length), title)) {
        titlePositions.addAll(List.generate(title.length, (i) => start + i));
        break;
      }
    }
  }

  final String raw;
  final String? bookTitle;
  final String rawLower;
  final String form;
  late final List<String> tokens;
  final Set<int> titlePositions = {};
  late final List<String> contextTokens = [
    for (var i = 0; i < tokens.length; i++)
      if (!titlePositions.contains(i)) tokens[i],
  ];
  List<List<String>> aliasTokens = const [];
  List<String>? _aliases;
  final Map<String, List<int>> _aliasIndicesByToken = {};

  Iterable<List<String>> aliasesFor(
    ListSearchQuery query, {
    bool spelling = false,
  }) {
    Set<int>? candidates;
    for (var i = 0; i < query.tokens.length; i++) {
      if (contextTokens.any((token) => query.matches(token, i))) continue;
      final matching = <int>{};
      for (final entry in _aliasIndicesByToken.entries) {
        if (query.matches(entry.key, i, spelling: spelling)) {
          matching.addAll(entry.value);
        }
      }
      if (matching.isEmpty) return const [];
      candidates = candidates == null
          ? matching
          : candidates.intersection(matching);
      if (candidates.isEmpty) return const [];
    }
    return candidates == null
        ? aliasTokens
        : candidates.map((i) => aliasTokens[i]);
  }

  /// הכינויים כבר מנורמלים; כל כינוי נשאר חלופה עצמאית לשם הספר.
  void setAliases(List<String>? aliases) {
    if (listEquals(_aliases, aliases)) return;
    _aliases = aliases == null ? null : List.of(aliases);
    aliasTokens = [
      for (final alias in aliases ?? const <String>[]) _tokensOf(alias),
    ];
    _aliasIndicesByToken.clear();
    for (var i = 0; i < aliasTokens.length; i++) {
      for (final token in aliasTokens[i].toSet()) {
        (_aliasIndicesByToken[token] ??= []).add(i);
      }
    }
  }
}

/// דרגת ההתאמה: כל התאמה מילולית קודמת לכתיב חלופי של שם הספר.
int? listSearchRank(ListSearchQuery query, ListSearchKey key) {
  final q = query.tokens;
  if (q.isEmpty) {
    return key.rawLower.contains(query.rawLower) ? 5 : null;
  }
  final k = key.tokens;
  if (key.form.startsWith(query.form)) return 0;
  if (_inOrder(query, k, exact: true)) return 1;
  if (_inOrder(query, k, exact: false)) return 2;
  if (_assignTokens(query, k)) return 3;
  for (final alias in key.aliasesFor(query)) {
    if (_assignTokens(query, key.contextTokens, extra: alias)) return 4;
  }
  if (key.rawLower.contains(query.rawLower) || key.form.contains(query.form)) {
    return 5;
  }
  if (key.titlePositions.isNotEmpty &&
      _assignTokens(query, k, spellingPositions: key.titlePositions)) {
    return 6;
  }
  for (final alias in key.aliasesFor(query, spelling: true)) {
    if (_assignTokens(
      query,
      key.contextTokens,
      extra: alias,
      spellingExtra: true,
    )) {
      return 6;
    }
  }
  return null;
}

const int listSearchRankCount = 7;

/// התאמה חד-חד-ערכית; הקצאה חמדנית עלולה לתפוס מילה שדרושה למילת שאילתה אחרת.
bool _assignTokens(
  ListSearchQuery query,
  List<String> k, {
  Set<int>? spellingPositions,
  List<String> extra = const [],
  bool spellingExtra = false,
}) {
  final length = k.length + extra.length;
  if (query.tokens.length > length) return false;
  bool matches(int j, int i) {
    final token = j < k.length ? k[j] : extra[j - k.length];
    return query.matches(
      token,
      i,
      spelling: j < k.length
          ? spellingPositions?.contains(j) == true
          : spellingExtra,
    );
  }

  if (query.tokens.length == 1) {
    for (var j = 0; j < length; j++) {
      if (matches(j, 0)) return true;
    }
    return false;
  }
  final owners = List.filled(length, -1);
  bool claim(int queryIndex, List<bool> seen) {
    for (var j = 0; j < length; j++) {
      if (seen[j] || !matches(j, queryIndex)) continue;
      seen[j] = true;
      if (owners[j] == -1 || claim(owners[j], seen)) {
        owners[j] = queryIndex;
        return true;
      }
    }
    return false;
  }

  for (var i = 0; i < query.tokens.length; i++) {
    if (!claim(i, List.filled(length, false))) return false;
  }
  return true;
}

bool _inOrder(ListSearchQuery query, List<String> k, {required bool exact}) {
  var j = 0;
  for (var i = 0; i < query.tokens.length; i++) {
    while (j < k.length &&
        !(exact ? k[j] == query.tokens[i] : query.matches(k[j], i))) {
      j++;
    }
    if (j == k.length) return false;
    j++;
  }
  return true;
}

/// ה"א הידיעה לפני ראשי תיבות מוכרים תואמת גם בהקלדה חלקית ("הרמב").
bool _tokenMatches(String keyToken, String queryToken) {
  if (keyToken.startsWith(queryToken)) return true;
  if (keyToken.startsWith('ה') &&
      sagesTakingDefiniteArticle.contains(keyToken.substring(1)) &&
      keyToken.substring(1).startsWith(queryToken)) {
    return true;
  }
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
