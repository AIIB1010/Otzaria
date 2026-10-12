import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/library_update/services/github_rate_limit.dart';
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'library_changes_dialog.dart';
import 'library_changes_fetcher.dart';
import 'library_changes_store.dart';

/// הורדת "מה חדש בספרים" אחרי עדכון והצגתו — פעם אחת לכל release.
class LibraryChangesNotes {
  LibraryChangesNotes({
    LibraryChangesStore? store,
    this._fetcher,
    Future<void> Function(BuildContext, List<LibraryChangesNote>)? showDialog,
    BuildContext? Function()? contextProvider,
  }) : store = store ?? LibraryChangesStore(),
       _showDialog = showDialog ?? showLibraryChangesDialog,
       _context = contextProvider ?? (() => navigatorKey.currentContext);

  static final instance = LibraryChangesNotes();

  final LibraryChangesStore store;
  final LibraryChangesFetcher? _fetcher;
  final Future<void> Function(BuildContext, List<LibraryChangesNote>)
  _showDialog;
  final BuildContext? Function() _context;

  bool _showing = false;
  bool _showAgain = false;

  LibraryChangesFetcher get _defaultFetcher => LibraryChangesFetcher(
    store: store,
    fetchReleases: () async {
      final client = GithubLibraryReleaseClient(
        httpClient: GithubRateLimitAwareClient(),
      );
      try {
        return await client.fetchReleases();
      } finally {
        client.dispose();
      }
    },
  );

  /// אחרי עדכון ספרייה מוצלח: מוריד את ההערות של הגרסאות שהוחלו ומציג את כל
  /// הממתינות. לעולם אינו זורק.
  Future<void> afterLibraryUpdate({
    required int fromVersion,
    required int toVersion,
  }) async {
    try {
      await (_fetcher ?? _defaultFetcher).fetch(
        fromVersion: fromVersion,
        toVersion: toVersion,
      );
      await showPending();
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    }
  }

  /// מציג את ההערות הממתינות (גם אלה שכתב המעדכן הלא-מקוון), ובסגירה מעביר
  /// אותן ל"נצפו". בלי Navigator הן נשארות לפעם הבאה.
  Future<void> showPending() async {
    if (_showing) {
      _showAgain = true;
      return;
    }
    _showing = true;
    try {
      do {
        _showAgain = false;
        final pending = await store.readPending();
        if (pending.isEmpty) return;
        final context = _context();
        if (context == null || !context.mounted) return;
        await _showDialog(context, pending);
        await store.markSeen(pending);
      } while (_showAgain);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    } finally {
      _showing = false;
    }
  }

  /// "מה חדש בגרסת הספרייה" ממסך ההגדרות: כל ההערות השמורות, החדשה קודם.
  Future<void> showAll(BuildContext context) async {
    try {
      final notes = await store.readAll();
      if (notes.isEmpty || !context.mounted) return;
      await _showDialog(context, notes);
      await store.markSeen(notes);
    } catch (error, stackTrace) {
      _log(error, stackTrace);
    }
  }

  void _log(Object error, StackTrace stackTrace) {
    debugPrint('[LibraryChanges] $error\n$stackTrace');
    try {
      ErrorLogFile.append(
        title: 'Library changes notes',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }
}
