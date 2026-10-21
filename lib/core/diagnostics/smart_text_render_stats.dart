import 'dart:developer' show Timeline;
import 'dart:typed_data';

import 'package:otzaria/widgets/smart_text/raised_markers.dart';

/// הסיבה ששורה נפלה מהמסלול המהיר של SmartTextWidget ל-HtmlWidget, לפי התג
/// הראשון שהמסלול המהיר אינו מקבל.
enum SmartTextFullPathReason {
  /// `<a class="link-anchor …">` — סמן-אות של מפרש.
  linkAnchor,

  /// `link-anchor-range` — טווח-ציטוט של הלינקר.
  linkAnchorRange,

  /// `<a>` אחר עם href (קישור פנימי, הערה, סמן-מספר).
  link,

  /// `<a>` בלי href.
  otherAnchor,

  /// `<span style=…>` שאינו הדגשת חיפוש מוכרת.
  styledSpan,

  /// `<span class=…>` שאינו סימון מורם או מקרא על פי המסורה.
  classSpan,

  /// `<sup>` / `<sub>` שנותרו אחרי processText.
  supSub,

  /// תג בלוק: div, p, רשימה, טבלה, ציטוט, pre, כותרת בתוך השורה.
  block,

  /// `<img>` / `<svg>`.
  image,

  /// ישות HTML שהמסלול המהיר אינו מפענח.
  entity,

  /// כל תג אחר.
  otherTag,

  /// כל התגים מוכרים: מבנה שבור או הדגשה בתוך הדגשה.
  structure,

  /// RenderMode שאינו column — המסלול המהיר לא נוסה.
  nonColumnMode,
}

/// מוני רינדור מצטברים של SmartTextWidget לאבחון מפתחים.
///
/// כשהאיסוף כבוי כל נקודת מדידה חוזרת מיד אחרי בדיקת [enabled], בלי הקצאות.
class SmartTextRenderStats {
  SmartTextRenderStats._();

  /// האם לספור; מופעל על-ידי DeveloperDiagnostics או בדיקת ביצועים.
  static bool enabled = false;

  static int _fastInline = 0;
  static int _fastHeading = 0;
  static int _fullHtml = 0;
  static final Int32List _reasons = Int32List(
    SmartTextFullPathReason.values.length,
  );
  static int _processHits = 0;
  static int _processMisses = 0;
  static int _processUncachedMicros = 0;
  static int _fwfhBuilds = 0;
  static int _fwfhBuildMicros = 0;

  /// זמן התחלה למדידה, או 0 כשהאיסוף כבוי.
  static int startMicros() => enabled ? Timeline.now : 0;

  static void fastLine({required bool heading}) {
    if (!enabled) return;
    if (heading) {
      _fastHeading++;
    } else {
      _fastInline++;
    }
  }

  /// שורה ב-HtmlWidget; בלי [columnMode] המסלול המהיר לא נוסה כלל.
  static void fullLine({required bool columnMode}) {
    if (!enabled) return;
    _fullHtml++;
    if (!columnMode) _reasons[SmartTextFullPathReason.nonColumnMode.index]++;
  }

  /// מסווג ורושם שורה שהמסלול המהיר דחה; נקרא רק בהחטאת מטמון.
  static void fullPathHtml(String html) {
    if (!enabled) return;
    _reasons[classifyFullPath(html).index]++;
  }

  static void processTextHit() {
    if (enabled) _processHits++;
  }

  static void processTextMiss(int startMicros) {
    if (!enabled) return;
    _processMisses++;
    if (startMicros > 0) _processUncachedMicros += Timeline.now - startMicros;
  }

  static void fwfhBuild(int startMicros) {
    if (!enabled || startMicros == 0) return;
    _fwfhBuilds++;
    _fwfhBuildMicros += Timeline.now - startMicros;
  }

  /// מחזיר את המונים מאז הקריאה הקודמת ומאפס; null כשלא נספר דבר.
  static Map<String, Object?>? takeAndReset() {
    final lines = _fastInline + _fastHeading + _fullHtml;
    if (lines == 0 &&
        _processHits + _processMisses == 0 &&
        _fwfhBuilds == 0 &&
        !_reasons.any((count) => count > 0)) {
      return null;
    }
    final result = <String, Object?>{
      'fastInline': _fastInline,
      'fastHeading': _fastHeading,
      'fullHtml': _fullHtml,
      'fullReasons': {
        for (final reason in SmartTextFullPathReason.values)
          if (_reasons[reason.index] > 0) reason.name: _reasons[reason.index],
      },
      'processHits': _processHits,
      'processMisses': _processMisses,
      'processUncachedMs': _microsToMs(_processUncachedMicros),
      'fwfhBuilds': _fwfhBuilds,
      'fwfhBuildMs': _microsToMs(_fwfhBuildMicros),
    };
    reset();
    return result;
  }

  static void reset() {
    _fastInline = 0;
    _fastHeading = 0;
    _fullHtml = 0;
    _reasons.fillRange(0, _reasons.length, 0);
    _processHits = 0;
    _processMisses = 0;
    _processUncachedMicros = 0;
    _fwfhBuilds = 0;
    _fwfhBuildMicros = 0;
  }

  static double _microsToMs(int micros) => (micros / 100).round() / 10;

  static final RegExp _tagRegex = RegExp(
    r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>',
  );
  static final RegExp _entityRegex = RegExp(
    r'&[a-zA-Z]{2,10};|&#x?[0-9a-fA-F]{1,6};',
  );
  static final RegExp _mamClassRegex = RegExp(r'^class="mam-[a-z-]+"$');
  static const Set<String> _simpleTags = {
    'b',
    'strong',
    'i',
    'em',
    'u',
    'big',
    'small',
    'br',
  };
  static const Set<String> _blockTags = {
    'div',
    'p',
    'ul',
    'ol',
    'li',
    'table',
    'tr',
    'td',
    'th',
    'blockquote',
    'pre',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'hr',
  };

  /// הסיבה לנפילה של [html] שהמסלול המהיר דחה, לפי התג הראשון שאינו מקבל.
  /// משקף את כללי SimpleInlineHtml בקירוב, לאבחון בלבד.
  static SmartTextFullPathReason classifyFullPath(String html) {
    for (final match in _tagRegex.allMatches(html)) {
      final name = match[2]!.toLowerCase();
      final attributes = match[3]!.trim();
      final closing = match[1] == '/';
      if (closing || attributes.isEmpty || attributes == '/') {
        if (_simpleTags.contains(name) || name == 'span') continue;
      }
      if (name == 'i' && attributes.startsWith('data-')) continue;
      switch (name) {
        case 'a':
          if (attributes.contains('link-anchor-range')) {
            return SmartTextFullPathReason.linkAnchorRange;
          }
          if (attributes.contains('link-anchor')) {
            return SmartTextFullPathReason.linkAnchor;
          }
          return attributes.contains('href')
              ? SmartTextFullPathReason.link
              : SmartTextFullPathReason.otherAnchor;
        case 'span':
          if (attributes.contains('link-anchor-range')) {
            return SmartTextFullPathReason.linkAnchorRange;
          }
          if (attributes.contains('link-anchor')) {
            return SmartTextFullPathReason.linkAnchor;
          }
          if (_isFastPathSpan(attributes)) continue;
          return attributes.startsWith('style')
              ? SmartTextFullPathReason.styledSpan
              : SmartTextFullPathReason.classSpan;
        case 'sup' || 'sub':
          return SmartTextFullPathReason.supSub;
        case 'img' || 'svg':
          return SmartTextFullPathReason.image;
      }
      return _blockTags.contains(name)
          ? SmartTextFullPathReason.block
          : SmartTextFullPathReason.otherTag;
    }
    final decoded = html.contains('&')
        ? html.replaceAll('&nbsp;', '').replaceAll('&thinsp;', '')
        : html;
    if (_entityRegex.hasMatch(decoded)) return SmartTextFullPathReason.entity;
    return SmartTextFullPathReason.structure;
  }

  static bool _isFastPathSpan(String attributes) =>
      attributes == 'class="$kFootnoteMarkerClass"' ||
      attributes == 'class="$kRaisedSupClass"' ||
      _mamClassRegex.hasMatch(attributes) ||
      (attributes.startsWith('style="') &&
          (attributes.contains('color: red') ||
              attributes.contains('rgba(255, 255, 0, 0.8)')));
}
