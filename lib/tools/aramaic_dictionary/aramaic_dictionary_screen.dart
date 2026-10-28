import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/core/messages/tools_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/tools/aramaic_dictionary/widgets/aramaic_result_card.dart';
import 'package:otzaria/tools/dictionary/repository/dictionary_lookup_repository.dart';
import 'package:otzaria/tools/tool_query.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/widgets/feedback/tool_empty_state.dart';
import 'package:otzaria/widgets/misc/tool_ui_helpers.dart';

/// מסנן ערכים ש-[field] שלהם מכיל את [query] וממיין: מדויק < מתחיל ב- < מילה שלמה < מכיל.
/// בכל רמת התאמה "פשיטא" קודם, ובשוויון נשמר סדר הקלט (המיון של Dart אינו יציב).
@visibleForTesting
List<Map<String, String>> rankAramaicMatches(
  List<Map<String, String>> entries,
  String field,
  String query,
) {
  final wholeWord = RegExp('(^|\\s)${RegExp.escape(query)}(\$|\\s)');
  final ranked =
      <
        ({int rank, bool other, int pos, int order, Map<String, String> entry})
      >[];
  for (final (order, entry) in entries.indexed) {
    final text = entry[field]!;
    final pos = text.indexOf(query);
    if (pos < 0) continue;
    final rank = text == query
        ? 0
        : pos == 0
        ? 1
        : wholeWord.hasMatch(text)
        ? 2
        : 3;
    final other =
        (entry['dictionary'] ?? AramaicDictionaryEntry.peshitaDictionary) !=
        AramaicDictionaryEntry.peshitaDictionary;
    ranked.add((
      rank: rank,
      other: other,
      pos: pos,
      order: order,
      entry: entry,
    ));
  }
  ranked.sort((a, b) {
    final rankCompare = a.rank.compareTo(b.rank);
    if (rankCompare != 0) return rankCompare;
    if (a.other != b.other) return a.other ? 1 : -1;
    final posCompare = a.pos.compareTo(b.pos);
    if (posCompare != 0) return posCompare;
    final lengthCompare = a.entry[field]!.length.compareTo(
      b.entry[field]!.length,
    );
    if (lengthCompare != 0) return lengthCompare;
    return a.order.compareTo(b.order);
  });
  return [for (final r in ranked) r.entry];
}

/// ממזג תוצאות בעלות אותו מפתח, גם ממילונים שונים, לכרטיס אחד עם כל הפירושים.
/// פירושי "פשיטא" קודמים; פירוש זהה שחוזר אינו מוצג פעמיים.
@visibleForTesting
List<Map<String, String>> mergeAramaicMatches(
  List<Map<String, String>> ranked,
) {
  final groups = <String, List<Map<String, String>>>{};
  for (final entry in ranked) {
    (groups[entry['aramaicPlain']!] ??= []).add(entry);
  }

  return [
    for (final group in groups.values)
      if (group.length == 1)
        group.single
      else
        _mergeGroup([
          ...group.where((e) => !_isOtherDictionary(e)),
          ...group.where(_isOtherDictionary),
        ]),
  ];
}

bool _isOtherDictionary(Map<String, String> entry) =>
    (entry['dictionary'] ?? AramaicDictionaryEntry.peshitaDictionary) !=
    AramaicDictionaryEntry.peshitaDictionary;

Map<String, String> _mergeGroup(List<Map<String, String>> group) {
  final seen = <String>{};
  final meanings = <String>[
    for (final entry in group)
      for (final part in entry['hebrew']!.split('***'))
        if (part.trim().isNotEmpty && seen.add(removeVolwels(part.trim())))
          part.trim(),
  ];

  return {
    ...group.first,
    'hebrew': meanings.join(' *** '),
    'hebrewPlain': group.map((e) => e['hebrewPlain']!).join(' '),
  };
}

// בלי גרשיים, כמו בתפריט ההקשר: "ב"ד" צריך למצוא גם את המפתח ב''ד.
String _stripQuotes(String text) => text.replaceAll(RegExp("[\"'״׳]"), '');

// הביטוי הארמי בסוגריים מסולסלים ובהרחבה (=...) אינו עברית לחיפוש.
String _stripAramaicMarkup(String text) => text
    .replaceAll(RegExp(r'\{[^{}]*\}|\(=[^)]*\)'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ');

class AramaicDictionaryScreen extends StatefulWidget {
  const AramaicDictionaryScreen({super.key, this.repository, this.queryInbox});

  final DictionaryLookupRepository? repository;
  final ToolQueryInbox? queryInbox;

  @override
  State<AramaicDictionaryScreen> createState() =>
      _AramaicDictionaryScreenState();
}

class _AramaicDictionaryScreenState extends State<AramaicDictionaryScreen>
    with ToolQueryConsumer {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final DictionaryLookupRepository _dictionaryRepository =
      widget.repository ?? DictionaryLookupRepository.instance;
  List<Map<String, String>> _dictionaryData = [];
  List<Map<String, String>> _filteredResults = [];
  bool _isLoading = true;
  bool _isHebrewToAramaic = false;

  @override
  ToolQueryInbox? get toolQueryInbox => widget.queryInbox;

  @override
  bool get canApplyToolQuery => !_isLoading;

  @override
  void applyToolQuery(ToolQuery query) {
    _isHebrewToAramaic = query.hebrewToAramaic;
    fillSearchField(_searchController, query.text);
    _performSearch(query.text);
  }

  @override
  void initState() {
    super.initState();
    _loadDictionary();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadDictionary() async {
    try {
      await _dictionaryRepository.ensureAramaicLoaded();
      final entries = _dictionaryRepository.getAllAramaicEntries();

      if (!mounted) return;

      setState(() {
        _dictionaryData = entries.map((entry) {
          return <String, String>{
            'aramaic': entry.aramaic,
            'hebrew': entry.hebrew,
            'dictionary': entry.dictionary,
            // שדות החיפוש בלי ניקוד, כדי שהקלדה רגילה תמצא ערכים מנוקדים.
            'aramaicPlain': _stripQuotes(removeVolwels(entry.aramaic)),
            'hebrewPlain': removeVolwels(_stripAramaicMarkup(entry.hebrew)),
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
      UiSnack.showError(ToolsMessages.dictionaryLoadError(e));
    }
    consumeToolQuery();
  }

  void _performSearch(String query) {
    query = removeVolwels(query.trim());
    if (!_isHebrewToAramaic) query = _stripQuotes(query);

    if (query.isEmpty) {
      setState(() {
        _filteredResults = [];
      });
      return;
    }

    final field = _isHebrewToAramaic ? 'hebrewPlain' : 'aramaicPlain';
    setState(() {
      _filteredResults = mergeAramaicMatches(
        rankAramaicMatches(_dictionaryData, field, query),
      );
    });
  }

  void _toggleDirection() {
    setState(() => _isHebrewToAramaic = !_isHebrewToAramaic);
    _performSearch(_searchController.text);
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CallbackShortcuts(
      bindings: {
        currentWindowSearchActivator(context): () {
          _searchFocusNode.requestFocus();
        },
      },
      child: Column(
        children: [
          AppTopBar(
            center: OtzariaSearchField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              icon: OtzariaIcons.search_in_text_24_regular,
              hintText: _isHebrewToAramaic
                  ? 'חפש מילה בעברית...'
                  : 'חפש מילה בארמית...',
              autofocus: true,
              onChanged: _performSearch,
              onClear: () => setState(() => _filteredResults = []),
            ),
          ),
          Expanded(
            child: ToolPanelWrapper(
              child: Column(
                children: [
                  _buildDirectionToggle(),
                  Expanded(child: _buildResultsList()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionToggle() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.spaceMD,
        vertical: AppTokens.spaceSM,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'עברית',
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight: _isHebrewToAramaic
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: _isHebrewToAramaic ? cs.primary : cs.onSurface,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD - 4),
          IconButton(
            icon: Icon(
              _isHebrewToAramaic
                  ? FluentIcons.arrow_right_24_regular
                  : FluentIcons.arrow_left_24_regular,
            ),
            onPressed: _toggleDirection,
            tooltip: 'החלף כיוון',
            style: IconButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD - 4),
          Text(
            'ארמית',
            style: TextStyle(
              fontSize: AppTokens.fontLG,
              fontWeight: !_isHebrewToAramaic
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: !_isHebrewToAramaic ? cs.primary : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchController.text.isEmpty) {
      return const ToolEmptyState(
        icon: OtzariaIcons.alef_near_alef_stam_24_filled,
        message: 'הזן מילה לחיפוש במילון',
      );
    }

    if (_filteredResults.isEmpty) {
      return const ToolEmptyState(
        icon: OtzariaIcons.search_24_regular,
        message: 'לא נמצאו תוצאות',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final entry = _filteredResults[index];
        return AramaicResultCard(
          aramaic: entry['aramaic']!,
          hebrew: entry['hebrew']!,
          isHebrewToAramaic: _isHebrewToAramaic,
        );
      },
    );
  }
}
