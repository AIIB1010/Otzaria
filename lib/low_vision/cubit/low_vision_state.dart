import 'package:equatable/equatable.dart';
import 'package:otzaria/low_vision/input/lv_touch_gesture.dart';
import 'package:otzaria/low_vision/theme/lv_palette.dart';
import 'package:otzaria/models/books.dart';

/// מיקום קריאה שמור בספר: שורה בטקסט (או עמוד ב-PDF) והמיקום בתוכה.
class LvReadingPosition extends Equatable {
  const LvReadingPosition(this.index, [this.fraction = 0]);

  final int index;
  final double fraction;

  Map<String, dynamic> toJson() => {'i': index, 'f': fraction};

  factory LvReadingPosition.fromJson(Map<String, dynamic> json) =>
      LvReadingPosition(
        (json['i'] as num?)?.toInt() ?? 0,
        (json['f'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [index, fraction];
}

class LowVisionState extends Equatable {
  const LowVisionState({
    this.loaded = false,
    this.pinned = const [],
    this.recents = const [],
    this.positions = const {},
    this.textScale = 1.0,
    this.palette = LvPalette.blackOnWhite,
    this.showNikud = true,
    this.touchBindings = const {},
    this.holdSeconds = 1.2,
    this.glide = false,
    this.keyOverrides = const {},
  });

  final bool loaded;

  /// ספרים שהמשתמש קבע לפתוח תמיד.
  final List<Book> pinned;

  /// ספרים שנפתחו לאחרונה, החדש בראש.
  final List<Book> recents;

  /// מפתח: זהות הספר (`bookIdentity`).
  final Map<String, LvReadingPosition> positions;

  /// מכפיל גודל הטקסט בקורא.
  final double textScale;
  final LvPalette palette;
  final bool showNikud;

  /// שיוך מחוות לפעולות (שם מחווה ← שם פעולה). מה שחסר: ברירת המחדל.
  final Map<String, String> touchBindings;

  /// כמה שניות מחזיקים אצבע במקום אחד כדי להפעיל את "החזקה ארוכה".
  final double holdSeconds;

  /// האם עמוד ה-PDF ממשיך להחליק אחרי שחרור האצבע (false = נעצר מיד).
  final bool glide;

  static const List<double> holdSecondsOptions = [0.8, 1.2, 1.8, 2.5];

  /// הפעולה המשויכת למחווה.
  LvTouchAction actionFor(LvGesture gesture) {
    final name = touchBindings[gesture.name];
    return LvTouchAction.values.firstWhere(
      (a) => a.name == name,
      orElse: () => gesture.defaultAction,
    );
  }

  /// שיוך מקשים מותאם: שם הפעולה ← מזהי מקשים לוגיים.
  final Map<String, List<int>> keyOverrides;

  static const double minTextScale = 0.6;
  static const double maxTextScale = 6.0;

  LowVisionState copyWith({
    bool? loaded,
    List<Book>? pinned,
    List<Book>? recents,
    Map<String, LvReadingPosition>? positions,
    double? textScale,
    LvPalette? palette,
    bool? showNikud,
    Map<String, String>? touchBindings,
    double? holdSeconds,
    bool? glide,
    Map<String, List<int>>? keyOverrides,
  }) => LowVisionState(
    loaded: loaded ?? this.loaded,
    pinned: pinned ?? this.pinned,
    recents: recents ?? this.recents,
    positions: positions ?? this.positions,
    textScale: textScale ?? this.textScale,
    palette: palette ?? this.palette,
    showNikud: showNikud ?? this.showNikud,
    touchBindings: touchBindings ?? this.touchBindings,
    holdSeconds: holdSeconds ?? this.holdSeconds,
    glide: glide ?? this.glide,
    keyOverrides: keyOverrides ?? this.keyOverrides,
  );

  @override
  List<Object?> get props => [
    loaded,
    pinned,
    recents,
    positions,
    textScale,
    palette,
    showNikud,
    touchBindings,
    holdSeconds,
    glide,
    keyOverrides,
  ];
}
