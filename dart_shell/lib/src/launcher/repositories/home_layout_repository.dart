import 'dart:convert';

import '../runtime_paths.dart';
import '../models/home_grid_item.dart';

class HomeLayoutRepository {
  const HomeLayoutRepository({required this._paths});

  final RuntimePaths _paths;

  Future<List<HomeLayoutSlot?>?> readSavedLayout() async {
    try {
      final file = await _paths.layoutFile();
      if (!await file.exists()) {
        return null;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }

      final rawSlots = decoded['slots'];
      if (rawSlots is! List) {
        return null;
      }

      return rawSlots.map(_decodeSlot).toList(growable: false);
    } on Object {
      return null;
    }
  }

  Future<Map<int, String>> readGroupNames() async {
    try {
      final file = await _paths.layoutFile();
      if (!await file.exists()) {
        return const <int, String>{};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return const <int, String>{};
      }
      final rawNames = decoded['groupNames'];
      if (rawNames is! Map) {
        return const <int, String>{};
      }
      final result = <int, String>{};
      for (final entry in rawNames.entries) {
        final page = int.tryParse(entry.key.toString());
        final name = entry.value;
        if (page == null || page < 0 || name is! String) {
          continue;
        }
        final normalized = name.trim();
        if (normalized.isNotEmpty) {
          result[page] = normalized.length <= 40
              ? normalized
              : normalized.substring(0, 40);
        }
      }
      return Map<int, String>.unmodifiable(result);
    } on Object {
      return const <int, String>{};
    }
  }

  Future<void> saveGroupNames(Map<int, String> groupNames) async {
    try {
      final file = await _paths.layoutFile();
      Map<String, Object?> document = <String, Object?>{
        'version': 5,
        'slots': const <Object?>[],
      };
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) {
          document = Map<String, Object?>.from(decoded);
        }
      }
      document['version'] = 5;
      document['groupNames'] = <String, String>{
        for (final entry in groupNames.entries)
          if (entry.key >= 0 && entry.value.trim().isNotEmpty)
            entry.key.toString(): entry.value.trim(),
      };
      await file.writeAsString('${jsonEncode(document)}\n', flush: true);
    } on Object {
      // Group metadata persistence is best effort.
    }
  }

  Future<void> saveLayout(List<HomeGridItem?> slots) async {
    try {
      final file = await _paths.layoutFile();
      Map<String, Object?> document = <String, Object?>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, Object?>) {
          document = Map<String, Object?>.from(decoded);
        }
      }
      document['version'] = 5;
      document['slots'] = slots.map(_encodeSlot).toList(growable: false);
      final payload = jsonEncode(document);
      await file.writeAsString('$payload\n', flush: true);
    } on Object {
      // Layout persistence is best effort; the in-memory layout remains valid.
    }
  }

  HomeLayoutSlot? _decodeSlot(Object? item) {
    if (item is String && item.isNotEmpty) {
      return HomeLayoutSlot(id: item);
    }

    if (item is Map) {
      final id = item['id'];
      if (id is! String || id.isEmpty) {
        return null;
      }
      final colSpan = item['colSpan'];
      final rowSpan = item['rowSpan'];
      final tileColorValue = item['tileColorValue'];
      final folderName = item['folderName'];
      final rawChildIds = item['childIds'];
      final childIds = rawChildIds is List
          ? rawChildIds
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toList()
          : null;
      return HomeLayoutSlot(
        id: id,
        colSpan: colSpan is int ? colSpan : null,
        rowSpan: rowSpan is int ? rowSpan : null,
        tileColorValue: tileColorValue is int ? tileColorValue : null,
        folderName: folderName is String ? folderName : null,
        childIds: childIds,
      );
    }

    return null;
  }

  Object? _encodeSlot(HomeGridItem? item) {
    if (item == null) {
      return null;
    }

    return <String, Object?>{
      'id': item.id,
      'colSpan': item.colSpan,
      'rowSpan': item.rowSpan,
      if (item.tileColorValue != null) 'tileColorValue': item.tileColorValue,
      if (item.isFolder) 'folderName': item.folderName,
      if (item.isFolder) 'childIds': item.folderItemIds,
    };
  }
}
