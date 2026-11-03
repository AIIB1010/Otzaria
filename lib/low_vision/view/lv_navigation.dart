import 'package:flutter/widgets.dart';
import 'package:otzaria/low_vision/view/lv_reader_screen.dart';
import 'package:otzaria/models/books.dart';

/// מעבר מיידי בין מסכים: אנימציות מבלבלות מי שמסתכל מקרוב.
Route<T> lvRoute<T>(Widget page) => PageRouteBuilder<T>(
  pageBuilder: (_, _, _) => page,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
);

Future<T?> lvPush<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(lvRoute<T>(page));

/// פותח ספר בקורא. [replace] מחליף את הקורא הנוכחי (מעבר בין ספרים).
Future<void> lvOpenBook(
  BuildContext context,
  Book book, {
  bool replace = false,
}) {
  final page = LvReaderScreen(book: book);
  final navigator = Navigator.of(context);
  return replace
      ? navigator.pushReplacement(lvRoute<void>(page))
      : navigator.push(lvRoute<void>(page));
}
