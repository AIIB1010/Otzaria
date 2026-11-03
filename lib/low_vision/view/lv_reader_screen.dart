import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/low_vision/cubit/low_vision_cubit.dart';
import 'package:otzaria/low_vision/view/lv_pdf_reader.dart';
import 'package:otzaria/low_vision/view/lv_text_reader.dart';
import 'package:otzaria/low_vision/view/widgets/lv_widgets.dart';
import 'package:otzaria/models/books.dart';

/// בוחר את הקורא המתאים לסוג הספר, ורושם אותו ברשימת "הספרים שלי".
class LvReaderScreen extends StatefulWidget {
  const LvReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<LvReaderScreen> createState() => _LvReaderScreenState();
}

class _LvReaderScreenState extends State<LvReaderScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LowVisionCubit>().noteOpened(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    if (book is PdfBook) return LvPdfReader(book: book);
    if (book is TextBook) return LvTextReader(book: book);
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
