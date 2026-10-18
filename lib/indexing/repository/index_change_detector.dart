import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';

/// שלב הבדיקה של ריצת אינדוקס: אילו ספרים מאונדקסים התיישנו מול מקורם.
abstract interface class IndexChangeDetector {
  /// מחזיר את הספרים מתוך [candidates] שמסמכיהם באינדקס יש להחליף, או null
  /// כשהבדיקה בוטלה. ספר שאינו באינדקס אינו ענייננו — הוא מאונדקס כחדש.
  ///
  /// [waitWhilePaused] נקרא בין ספרים ו-[isCancelled] נבדק אחריו.
  /// [onProgress] מדווח (0, total) בתחילה, ואחריו על כל ספר.
  Future<List<Book>?> detectChanged(
    List<Book> candidates, {
    required Library library,
    required bool Function() isCancelled,
    required Future<void> Function() waitWhilePaused,
    void Function(int processed, int total)? onProgress,
  });
}
