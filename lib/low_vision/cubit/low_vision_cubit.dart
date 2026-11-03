import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart' show bookIdentity;
import 'package:otzaria/low_vision/cubit/low_vision_state.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/models/books.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'low_vision_state_v1';
const _maxRecents = 30;
const _maxPositions = 300;

/// מצב ממשק הראייה הלקויה: ספרים קבועים, אחרונים, מיקומי קריאה והעדפות.
class LowVisionCubit extends Cubit<LowVisionState> {
  LowVisionCubit({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      super(const LowVisionState());

  final Future<SharedPreferences> Function() _prefs;
  final Map<String, LvReadingPosition> _positions = {};
  Timer? _saveTimer;

  Future<void> load() async {
    try {
      final raw = (await _prefs()).getString(_prefsKey);
      if (raw != null) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        _positions
          ..clear()
          ..addAll({
            for (final e
                in (json['positions'] as Map<String, dynamic>? ?? {}).entries)
              e.key: LvReadingPosition.fromJson(
                e.value as Map<String, dynamic>,
              ),
          });
        emit(
          state.copyWith(
            loaded: true,
            pinned: _decodeBooks(json['pinned']),
            recents: _decodeBooks(json['recents']),
            positions: Map.of(_positions),
            textScale: ((json['textScale'] as num?)?.toDouble() ?? 1.0).clamp(
              LowVisionState.minTextScale,
              LowVisionState.maxTextScale,
            ),
            palette: LvPalette.values.firstWhere(
              (p) => p.name == json['palette'],
              orElse: () => LvPalette.blackOnWhite,
            ),
            showNikud: json['showNikud'] as bool? ?? true,
            keyOverrides: {
              for (final e
                  in (json['keys'] as Map<String, dynamic>? ?? {}).entries)
                e.key: [for (final k in e.value as List) (k as num).toInt()],
            },
          ),
        );
        return;
      }
    } catch (error, stack) {
      debugPrint('low vision state load failed: $error\n$stack');
    }
    emit(state.copyWith(loaded: true));
  }

  static List<Book> _decodeBooks(Object? raw) {
    final books = <Book>[];
    for (final item in (raw as List? ?? const [])) {
      try {
        books.add(Book.fromJson(item as Map<String, dynamic>));
      } catch (_) {
        // רשומה פגומה אינה צריכה לחסום את שאר הרשימה.
      }
    }
    return books;
  }

  bool isPinned(Book book) {
    final id = bookIdentity(book);
    return state.pinned.any((b) => bookIdentity(b) == id);
  }

  void togglePin(Book book) {
    final id = bookIdentity(book);
    if (isPinned(book)) {
      emit(
        state.copyWith(
          pinned: [
            for (final b in state.pinned)
              if (bookIdentity(b) != id) b,
          ],
        ),
      );
    } else {
      emit(state.copyWith(pinned: [...state.pinned, book]));
    }
    _scheduleSave();
  }

  /// נקרא בפתיחת ספר: מעלה אותו לראש הרשימה האחרונים.
  void noteOpened(Book book) {
    final id = bookIdentity(book);
    final recents = [
      book,
      for (final b in state.recents)
        if (bookIdentity(b) != id) b,
    ].take(_maxRecents).toList();
    emit(state.copyWith(recents: recents));
    _scheduleSave();
  }

  void removeRecent(Book book) {
    final id = bookIdentity(book);
    emit(
      state.copyWith(
        recents: [
          for (final b in state.recents)
            if (bookIdentity(b) != id) b,
        ],
      ),
    );
    _scheduleSave();
  }

  /// הספרים לפי סדר התצוגה: קבועים ואז אחרונים (בלי כפילות).
  List<Book> get openBooks {
    final pinnedIds = {for (final b in state.pinned) bookIdentity(b)};
    return [
      ...state.pinned,
      for (final b in state.recents)
        if (!pinnedIds.contains(bookIdentity(b))) b,
    ];
  }

  LvReadingPosition? positionOf(Book book) => _positions[bookIdentity(book)];

  /// נשמר בלי לשדר מצב: גלילה מתעדכנת בקצב גבוה.
  void savePosition(Book book, LvReadingPosition position) {
    final id = bookIdentity(book);
    _positions.remove(id);
    _positions[id] = position;
    while (_positions.length > _maxPositions) {
      _positions.remove(_positions.keys.first);
    }
    _scheduleSave();
  }

  void setTextScale(double value) {
    emit(
      state.copyWith(
        textScale: value.clamp(
          LowVisionState.minTextScale,
          LowVisionState.maxTextScale,
        ),
      ),
    );
    _scheduleSave();
  }

  void zoomIn() => setTextScale(state.textScale * 1.2);
  void zoomOut() => setTextScale(state.textScale / 1.2);

  void setPalette(LvPalette palette) {
    emit(state.copyWith(palette: palette));
    _scheduleSave();
  }

  void cyclePalette() => setPalette(state.palette.next);

  void setShowNikud(bool value) {
    emit(state.copyWith(showNikud: value));
    _scheduleSave();
  }

  void setKeyOverride(String action, List<int> keys) {
    emit(state.copyWith(keyOverrides: {...state.keyOverrides, action: keys}));
    _scheduleSave();
  }

  void resetKeyOverrides() {
    emit(state.copyWith(keyOverrides: const {}));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  /// כותב מיד לדיסק; נקרא גם ביציאה מהקורא.
  Future<void> flush() async {
    _saveTimer?.cancel();
    try {
      final data = jsonEncode({
        'pinned': [for (final b in state.pinned) b.toJson()],
        'recents': [for (final b in state.recents) b.toJson()],
        'positions': {
          for (final e in _positions.entries) e.key: e.value.toJson(),
        },
        'textScale': state.textScale,
        'palette': state.palette.name,
        'showNikud': state.showNikud,
        'keys': state.keyOverrides,
      });
      await (await _prefs()).setString(_prefsKey, data);
    } catch (error, stack) {
      debugPrint('low vision state save failed: $error\n$stack');
    }
  }

  @override
  Future<void> close() async {
    await flush();
    return super.close();
  }
}
