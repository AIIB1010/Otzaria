import 'dart:async';

import 'package:http/http.dart' as http;

/// כותרת שכל תשובה מ-api.github.com נושאת — גם בשגיאה ובהגבלת קצב.
const _kGithubSignatureHeader = 'x-github-request-id';

const _kReachabilityTimeout = Duration(seconds: 5);

/// נתיב שעדכון הספרייה פונה אליו ממילא: ברשת מסוננת מאשרים את נתיבי
/// Otzaria בלבד ולא את כל api.github.com, ובדיקה מול השורש תיחסם.
const _kReachabilityProbeUrl =
    'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/latest';

/// האם שרת העדכונים (api.github.com) נגיש בפועל.
///
/// נבדקת חתימת GitHub בכותרות ולא סטטוס 200: רשת מסוננת מחזירה דף חסימה
/// תקין למראה, ובלעדיה כשל הסינון מוצג למשתמש כשגיאה של אוצריא.
Future<bool> isUpdateSourceReachable({
  Duration timeout = _kReachabilityTimeout,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(Uri.parse(_kReachabilityProbeUrl))
        .timeout(timeout);
    return response.headers.containsKey(_kGithubSignatureHeader);
  } catch (_) {
    return false;
  } finally {
    if (client == null) httpClient.close();
  }
}
