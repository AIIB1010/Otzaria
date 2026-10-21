/// תפקיד החלון בתהליך.
///
/// מופרד מ-`main.dart` כדי שקוד ליבה יוכל לשאול בלי לייבא את נקודת הכניסה.
class WindowRole {
  WindowRole._();

  /// האם החלון הזה נפתח מתוך חלון אחר.
  ///
  /// ⚠️ קובע דבר אחד בלבד: אילו אתחולים פר-**תהליך** מדולגים — בדיקת
  /// עדכוני ספרייה, רישום התראות המערכת, שטיפת תור הדיווחים, מיגרציית
  /// הנתיבים הניידים, אינדוקס. בלי הדילוג כל חלון הריץ אותם בנפרד — שתי
  /// בקשות מקבילות ל-GitHub החזירו 403 בכל פתיחת חלון.
  ///
  /// זה **אינו** "חלון ראשי": כל חלון שומר וטוען את המצב שלו בעצמו, ואין
  /// דבר שמותר רק בחלון הראשון מלבד עבודה שהיא של התהליך.
  static bool isSecondary = false;

  /// האם החלון נפתח עם כרטיסיה שהועברה אליו, כלומר ישר למסך הקריאה.
  ///
  /// ⚠️ במצב הזה אין טעם לבנות מראש את קטלוג הספרייה — 7,299 ספרים
  /// ו-1,341 קטגוריות, כ-700ms נמדדים — כי המשתמש רואה ספר ולא את
  /// הספרייה. `LibraryBrowser` טוען אותו ב-`initState` שלו ממילא, ולכן
  /// הדילוג אינו מוותר על שום דבר; הוא רק דוחה למי שבאמת צריך.
  static bool openedWithTab = false;
}

/// תפקיד חלון אחד, כפי שנחשף ב-`AppWindowScope.roleOf`. [AppWindowRole.current]
/// הוא מה ש-[WindowRole] אומר; חלון באותו isolate יעביר ערכים משלו.
class AppWindowRole {
  const AppWindowRole({
    required this.isPrimaryView,
    this.openedWithTab = false,
  });

  /// התפקיד מתוך [WindowRole], נקרא מחדש בכל גישה.
  static AppWindowRole get current => AppWindowRole(
    isPrimaryView: !WindowRole.isSecondary,
    openedWithTab: WindowRole.openedWithTab,
  );

  /// האם זה החלון הראשון ולא חלון שנפתח מתוך אחר ([WindowRole.isSecondary]).
  final bool isPrimaryView;

  /// האם החלון נפתח עם כרטיסיה שהועברה אליו ([WindowRole.openedWithTab]).
  final bool openedWithTab;

  @override
  bool operator ==(Object other) =>
      other is AppWindowRole &&
      other.isPrimaryView == isPrimaryView &&
      other.openedWithTab == openedWithTab;

  @override
  int get hashCode => Object.hash(isPrimaryView, openedWithTab);
}
