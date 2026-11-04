import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/models/lv_scan_resolver.dart';
import 'package:otzaria/low_vision/view/lv_pdf_reader.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

/// בוחר את הקורא המתאים לסוג הספר, ורושם אותו ברשימת "הספרים שלי".
class LvReaderScreen extends StatefulWidget {
  const LvReaderScreen({
    super.key,
    required this.book,
    this.forceText = false,
    this.initialPage,
    this.initialLine,
    this.resolver = const LvScanResolver(),
  });

  final Book book;

  /// לבדיקות.
  final LvScanResolver resolver;

  /// פותח את הטקסט גם לספר שיש לו גרסת צילום.
  final bool forceText;

  /// עמוד פתיחה בצילום (PDF), ושורת פתיחה בטקסט.
  final int? initialPage;
  final int? initialLine;

  @override
  State<LvReaderScreen> createState() => _LvReaderScreenState();
}

class _LvReaderScreenState extends State<LvReaderScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LowVisionCubit>().noteOpened(widget.book);
  }

  /// לספר טקסט שיש לו צילום: הצילום ועמוד הפתיחה שמתאים למקום שבו היית בטקסט.
  Future<({PdfBook pdf, int? page})?> _scanFor(TextBook book) async {
    final saved = context.read<LowVisionCubit>().positionOf(book)?.index;
    final pdf = await widget.resolver.pdfFor(book);
    if (pdf == null) return null;
    var page = widget.initialPage;
    final line = widget.initialLine ?? saved;
    if (page == null && line != null) {
      page = await widget.resolver.pageFor(book, pdf, line);
    }
    return (pdf: pdf, page: page);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    if (book is PdfBook) {
      return LvPdfReader(book: book, initialPage: widget.initialPage);
    }
    if (book is TextBook) {
      final wantsScan =
          !widget.forceText &&
          (book.isUserBook ||
              context.read<LowVisionCubit>().state.preferScan ||
              widget.resolver.talmudOpensAsScan(book));
      if (wantsScan) {
        return FutureBuilder<({PdfBook pdf, int? page})?>(
          future: _scanFor(book),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return LvScaffold(
                title: book.title,
                onBack: () => Navigator.of(context).maybePop(),
                body: const LvMessage('הספר נטען…', busy: true),
              );
            }
            final scan = snapshot.data;
            return scan != null
                ? LvPdfReader(book: scan.pdf, initialPage: scan.page)
                : LvTextReader(book: book, initialLine: widget.initialLine);
          },
        );
      }
      return LvTextReader(book: book, initialLine: widget.initialLine);
    }
    if (book is ConvertibleDocumentBook) {
      return LvTextReader(book: book.toTextBook(), source: book);
    }
    return LvScaffold(
      title: book.title,
      onBack: () => Navigator.of(context).maybePop(),
      body: const LvMessage('הספר הזה אינו זמין לקריאה במכשיר'),
    );
  }
}
