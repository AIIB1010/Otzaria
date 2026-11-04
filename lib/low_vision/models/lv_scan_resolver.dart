import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/page_converter.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:pdfrx/pdfrx.dart';

/// מוצא את הצילום המקורי (PDF) של ספר טקסט ואת הטקסט של ספר מצולם, ומתאים בין
/// המיקומים. כל התלויות ניתנות להחלפה לבדיקות.
class LvScanResolver {
  const LvScanResolver({
    this.pdfFor = _pdfFor,
    this.textFor = _textFor,
    this.pageFor = _pageFor,
    this.lineFor = _lineFor,
    this.talmudOpensAsScan = _talmudOpensAsScan,
  });

  /// הצילום של [book], או null.
  final Future<PdfBook?> Function(TextBook book) pdfFor;

  /// הטקסט של ספר מצולם, או null.
  final Future<TextBook?> Function(PdfBook pdf) textFor;

  /// העמוד בצילום שמתאים לשורה בטקסט, או null אם אין התאמה אמינה.
  final Future<int?> Function(TextBook text, PdfBook pdf, int line) pageFor;

  /// השורה בטקסט שמתאימה לעמוד בצילום, או null.
  final Future<int?> Function(
    PdfBook pdf,
    List<PdfOutlineNode> outline,
    int page,
  )
  lineFor;

  /// האם הגדרת אוצריא היא שמסכתות בבלי נפתחות כצילום.
  final bool Function(TextBook book) talmudOpensAsScan;

  static Future<PdfBook?> _pdfFor(TextBook book) async {
    try {
      // מסכת בבלי: הספרייה ממזגת טקסט וצילום לרשומה אחת, ואוצריא יודעת לאתר את הצילום.
      if (book.source.isOfficial && isTalmudBavliBook(book)) {
        final target = await resolveTalmudBavliPdfBook(book, forcePdf: true);
        if (target != null) return target.pdfBook;
      }
      final library = await DataRepository.instance.library;
      final pdf = library.getCompanionBook(book, PdfBook);
      return pdf is PdfBook ? pdf : null;
    } catch (_) {
      return null;
    }
  }

  static Future<TextBook?> _textFor(PdfBook pdf) async {
    try {
      final library = await DataRepository.instance.library;
      final text = library.getCompanionBook(pdf, TextBook);
      return text is TextBook ? text : null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _pageFor(TextBook text, PdfBook pdf, int line) async {
    try {
      return await textToPdfPage(text, line, pdfBook: pdf);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _lineFor(
    PdfBook pdf,
    List<PdfOutlineNode> outline,
    int page,
  ) async {
    try {
      return await pdfToTextPage(pdf, outline, page);
    } catch (_) {
      return null;
    }
  }

  static bool _talmudOpensAsScan(TextBook book) {
    try {
      return book.source.isOfficial &&
          isTalmudBavliBook(book) &&
          talmudBavliOpensInPdf();
    } catch (_) {
      return false;
    }
  }
}

/// הגדרת אוצריא לפתיחת מסכתות בבלי: 'pdf' (צילום מקורי) או 'text'.
bool lvTalmudOpensAsScan() {
  try {
    return talmudBavliOpensInPdf();
  } catch (_) {
    return false;
  }
}

String lvTalmudFormatKey() => SettingsRepository.keyTalmudBavliOpenFormat;

Future<void> lvSetTalmudOpensAsScan(bool scan) =>
    Settings.setValue<String>(lvTalmudFormatKey(), scan ? 'pdf' : 'text');
