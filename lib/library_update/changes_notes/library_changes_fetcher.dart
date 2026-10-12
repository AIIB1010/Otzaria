import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:seforim_library_updater/seforim_library_updater.dart';

import 'library_changes_store.dart';

/// מוריד את `library-changes.md` של ה-releases שהוחלו, best-effort: כשל רשת,
/// 404 או timeout נבלעים — release בלי הקובץ (v32 ומטה) הוא מצב רגיל.
class LibraryChangesFetcher {
  LibraryChangesFetcher({
    required this.fetchReleases,
    required this.store,
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  static const assetName = 'library-changes.md';

  /// עדכון שמדלג על יותר גרסאות מזה מציג רק את האחרונות.
  static const maxReleases = 10;

  // קובץ ההערות של עדכון ענק הוא מאות KB; גדול מזה אינו הקובץ הצפוי.
  static const _maxAssetBytes = 4 << 20;

  final Future<List<LibraryRelease>> Function() fetchReleases;
  final LibraryChangesStore store;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  /// ה-releases היציבים בטווח ([fromVersion], [toVersion]] שיש להם קובץ הערות,
  /// החדש קודם, לכל היותר [maxReleases].
  @visibleForTesting
  static List<(LibraryRelease, ReleaseAsset)> releasesInRange(
    List<LibraryRelease> releases,
    int fromVersion,
    int toVersion,
  ) {
    final picked = <(LibraryRelease, ReleaseAsset, int)>[];
    for (final release in releases) {
      if (release.isDraft || release.isPrerelease) continue;
      if (!LibraryChangesStore.isSafeTag(release.tag)) continue;
      final version = LibraryUpdateDiscovery.parseVersionFromTag(release.tag);
      if (version == null || version <= fromVersion || version > toVersion) {
        continue;
      }
      final asset = release.assetByName(assetName);
      if (asset == null || asset.downloadUrl.isEmpty) continue;
      picked.add((release, asset, version));
    }
    picked.sort((a, b) {
      final byVersion = b.$3.compareTo(a.$3);
      return byVersion != 0 ? byVersion : b.$1.tag.compareTo(a.$1.tag);
    });
    return [for (final (r, a, _) in picked.take(maxReleases)) (r, a)];
  }

  /// מוריד את ההערות לטווח ומחזיר כמה נשמרו. לעולם אינו זורק.
  Future<int> fetch({required int fromVersion, required int toVersion}) async {
    // גרסה מקומית לא ידועה (0) הייתה מציגה את כל ההיסטוריה.
    if (fromVersion <= 0 || toVersion <= fromVersion) return 0;
    final List<(LibraryRelease, ReleaseAsset)> wanted;
    try {
      wanted = releasesInRange(
        await fetchReleases().timeout(timeout * 2),
        fromVersion,
        toVersion,
      );
    } catch (e) {
      debugPrint('[LibraryChanges] release list failed: $e');
      return 0;
    }
    if (wanted.isEmpty) return 0;
    var saved = 0;
    final client = _clientFactory();
    try {
      for (final (release, asset) in wanted) {
        try {
          if (await store.contains(release.tag)) continue;
          if (asset.size > _maxAssetBytes) continue;
          final response = await client
              .get(Uri.parse(asset.downloadUrl))
              .timeout(timeout);
          if (response.statusCode != 200) continue;
          if (response.bodyBytes.length > _maxAssetBytes) continue;
          final text = utf8.decode(response.bodyBytes, allowMalformed: true);
          if (text.trim().isEmpty) continue;
          await store.writePending(release.tag, text);
          saved++;
        } catch (e) {
          debugPrint('[LibraryChanges] ${release.tag} failed: $e');
        }
      }
    } finally {
      client.close();
    }
    return saved;
  }
}
