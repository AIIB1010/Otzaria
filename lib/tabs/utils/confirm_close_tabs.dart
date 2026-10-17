import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// כרטיסיה שיש בה שינויים שלא נשמרו, עם ההודעה שצורפה (אם צורפה).
typedef UnsavedTabEntry = ({OpenedTab tab, String? message});

/// חלוניות התוסף מתוך [tabs] (כולל צדדי כרטיסיה מפוצלת) שיש בהן שינויים
/// שלא נשמרו, לפי [PluginUnsavedChangesRegistry].
List<UnsavedTabEntry> unsavedPluginTabs(
  Iterable<OpenedTab> tabs, {
  PluginUnsavedChangesRegistry? registry,
}) {
  final reg = registry ?? PluginUnsavedChangesRegistry.instance;
  return [
    for (final tab in tabs)
      for (final pane in leafPanes(tab))
        if (pane is ToolTab && pane.isPlugin)
          if (reg.hasUnsavedChanges((
            pluginId: pane.toolId,
            instanceId: pane.instanceId,
          )))
            (
              tab: pane,
              message: reg.messageFor((
                pluginId: pane.toolId,
                instanceId: pane.instanceId,
              )),
            ),
  ];
}

String unsavedCorrectionsMessage(String pluginName) =>
    'תיקוני התוסף ‹$pluginName› עדיין לא נשמרו לטיוטת ההתאוששות.';

/// לשוניות קורא שתיקוני התוסף בהן לא נשמרו לטיוטה גם אחרי ניסיון שמירה.
/// טיוטה שנשמרה אינה אובדת בסגירה, ולכן אינה מוחזרת.
Future<List<UnsavedTabEntry>> unpersistedCorrectionTabs(
  Iterable<OpenedTab> tabs, {
  PluginCorrectionSessionService? service,
}) async {
  final sessions = service ?? PluginCorrectionSessionService.instance;
  final panes = <String, ({TextBookTab tab, String name})>{};
  for (final tab in tabs) {
    for (final pane in leafPanes(tab)) {
      if (pane is! TextBookTab) continue;
      final tabId = PluginCorrectionSessionService.knownTabIdFor(pane);
      final name = tabId == null ? null : sessions.ownerNameForTab(tabId);
      if (name != null) panes[tabId!] = (tab: pane, name: name);
    }
  }
  if (panes.isEmpty) return const [];
  final unpersisted = await sessions.unpersistedTabIds(panes.keys);
  return [
    for (final MapEntry(key: tabId, value: pane) in panes.entries)
      if (unpersisted.contains(tabId))
        (tab: pane.tab, message: unsavedCorrectionsMessage(pane.name)),
  ];
}

const String unsavedChangesDialogTitle = 'שינויים שלא נשמרו';
const String unsavedChangesDialogSubtitle = 'הסגירה תמחק את השינויים שלא נשמרו';
const String unsavedChangesAppCloseSubtitle =
    'סגירת התוכנה תמחק את השינויים שלא נשמרו';
const String unsavedChangesWindowCloseSubtitle =
    'סגירת החלון תמחק את השינויים שלא נשמרו';
const String unsavedChangesCloseAnyway = 'סגור בכל זאת';

/// גוף הדיאלוג: שורה לכל כרטיסיה, ואחריה ההודעה שהתוסף צירף.
String unsavedChangesDialogContent(List<UnsavedTabEntry> entries) {
  final lines = <String>[];
  for (final entry in entries) {
    lines.add('ב"${entry.tab.title}" יש שינויים שלא נשמרו.');
    final message = entry.message;
    if (message != null) lines.add(message);
  }
  return lines.join('\n');
}

/// מאשר סגירה של [tabs]: אם אין בהן שינויים שלא נשמרו מחזיר `true`, אחרת
/// מציג דיאלוג אזהרה ומחזיר את בחירת המשתמש. תיקוני קורא נשמרים קודם לטיוטה.
Future<bool> confirmCloseTabs(
  BuildContext context,
  Iterable<OpenedTab> tabs, {
  String subtitle = unsavedChangesDialogSubtitle,
  PluginCorrectionSessionService? corrections,
}) async {
  final entries = [
    ...unsavedPluginTabs(tabs),
    ...await unpersistedCorrectionTabs(tabs, service: corrections),
  ];
  if (entries.isEmpty || !context.mounted) return entries.isEmpty;
  final confirmed = await showWarningDialog(
    context: context,
    title: unsavedChangesDialogTitle,
    content: unsavedChangesDialogContent(entries),
    subtitle: subtitle,
    confirmText: unsavedChangesCloseAnyway,
  );
  return confirmed == true;
}

Future<bool>? _pendingAppClose;

/// אישור סגירת התוכנה כשיש בכרטיסיות תוסף שינויים שלא נשמרו.
///
/// כמה מאזיני סגירת-חלון (הראשי, ושל העדכון) שואלים כל אחד בנפרד; הבטחה
/// משותפת מבטיחה דיאלוג אחד ותשובה אחת לכולם, גם בלחיצה כפולה על ה-X.
Future<bool> confirmAppCloseWithUnsavedChanges() {
  final pending = _pendingAppClose;
  if (pending != null) return pending;
  final context = navigatorKey.currentContext;
  if (context == null) return Future.value(true);
  final future = confirmCloseTabs(
    context,
    context.read<TabsBloc>().state.tabs,
    // ⚠️ סינכרוני ולא שאלה ל-runner: שני מאזינים קוראים לכאן, והראשון
    // שמגיע קובע את הנוסח — נוסח שנגזר מ-`await` היה תלוי בסדר ביניהם.
    subtitle: WindowBus.instance.hasOtherWindows
        ? unsavedChangesWindowCloseSubtitle
        : unsavedChangesAppCloseSubtitle,
  ).whenComplete(() => _pendingAppClose = null);
  _pendingAppClose = future;
  return future;
}
