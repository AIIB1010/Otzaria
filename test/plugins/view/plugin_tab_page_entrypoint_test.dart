import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/view/plugin_tab_page.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:provider/provider.dart';

import '../../helpers/memory_settings_cache.dart';

class _MockPluginSystemBloc extends Mock implements PluginSystemBloc {}

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockLibraryBloc extends Mock implements LibraryBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockBookmarkBloc extends Mock implements BookmarkBloc {}

class _MockCustomFoldersBloc extends Mock implements CustomFoldersBloc {}

class _SettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _SettingsBloc() : super(SettingsState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// רושם בדיקות קיום של קבצים תחת [prefix]; כל קובץ אחר הוא קובץ אמיתי.
final class _EntryFileSpy extends IOOverrides {
  _EntryFileSpy(this.prefix);
  final String prefix;
  final existsCalls = <String>[];
  final existsSyncCalls = <String>[];

  @override
  File createFile(String path) => path.replaceAll(r'\', '/').startsWith(prefix)
      ? _SpyFile(path, this)
      : super.createFile(path);
}

class _SpyFile implements File {
  _SpyFile(this.path, this._spy);
  @override
  final String path;
  final _EntryFileSpy _spy;

  @override
  Future<bool> exists() async {
    _spy.existsCalls.add(path.replaceAll(r'\', '/'));
    return false;
  }

  @override
  bool existsSync() {
    _spy.existsSyncCalls.add(path);
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/install/path',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: false,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '0.0.0',
    sdkVersion: '1.0.0',
    permissions: const [],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Tab',
    toolTabOrder: 0,
    defaultPinned: false,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2025),
  updatedAt: DateTime(2025),
);

void main() {
  setUp(() => Settings.init(cacheProvider: MemorySettingsCache()));

  testWidgets(
    'טאב תוסף בודק את קובץ הכניסה אסינכרונית — בלי existsSync (#3380)',
    (tester) async {
      final io = _EntryFileSpy('/install/');
      final settings = _SettingsBloc();
      addTearDown(settings.close);

      await IOOverrides.runWithIOOverrides(() async {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<PluginSystemBloc>.value(value: _MockPluginSystemBloc()),
              Provider<HistoryBloc>.value(value: _MockHistoryBloc()),
              Provider<TabsBloc>.value(value: _MockTabsBloc()),
              Provider<NavigationBloc>.value(value: _MockNavigationBloc()),
              Provider<LibraryBloc>.value(value: _MockLibraryBloc()),
              Provider<CalendarCubit>.value(value: _MockCalendarCubit()),
              Provider<WorkspaceBloc>.value(value: _MockWorkspaceBloc()),
              Provider<BookmarkBloc>.value(value: _MockBookmarkBloc()),
              Provider<CustomFoldersBloc>.value(
                value: _MockCustomFoldersBloc(),
              ),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: PluginTabPage(plugin: _plugin(), instanceId: 'tab-1'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }, io);

      expect(io.existsSyncCalls, isEmpty);
      expect(io.existsCalls, ['/install/path/index.html']);
      // קובץ כניסה חסר — לא נבנה WebView.
      expect(find.byType(InAppWebView), findsNothing);

      await tester.pumpWidget(const SizedBox());
    },
  );
}
