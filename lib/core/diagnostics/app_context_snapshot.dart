import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';

/// מה החלון מציג: מסך, כרטיסייה נוכחית, ספירה לפי סוג ותוסף פעיל.
/// משמש את רשומות ה-context של אבחון המפתחים ואת הדיווח על התוכנה.
Map<String, Object?> describeAppContext({
  required Screen screen,
  required TabsState tabs,
  required PluginSystemState pluginState,
}) {
  final current = tabs.currentTab;
  final tabsByType = <String, int>{};
  for (final tab in tabs.tabs) {
    tabsByType.update(
      tab.runtimeType.toString(),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  return {
    'screen': screen.name,
    'tabs': tabs.tabs.length,
    'tabsByType': tabsByType,
    'currentTab': current?.runtimeType.toString(),
    // כותרת כרטיסיית חיפוש היא השאילתה שהמשתמש הקליד; היא לא יוצאת בדיווח.
    'currentTitle': current is SearchingTab ? null : current?.title,
    if (current is ToolTab && current.isPlugin)
      'plugin': _pluginContext(current.toolId, pluginState),
  };
}

Map<String, Object?> _pluginContext(String pluginId, PluginSystemState state) {
  final plugins = state is PluginSystemLoaded
      ? state.plugins
      : const <InstalledPlugin>[];
  for (final plugin in plugins) {
    if (plugin.pluginId != pluginId) continue;
    return {
      'id': pluginId,
      'version': plugin.version,
      'source': plugin.sourceType,
      'enabled': plugin.enabled,
    };
  }
  return {'id': pluginId};
}
