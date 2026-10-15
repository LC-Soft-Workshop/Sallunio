import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'domain.dart';

String defaultDataDirectory({Map<String, String>? environment}) {
  final values = environment ?? Platform.environment;
  final roaming = values['APPDATA'],
      local = values['LOCALAPPDATA'],
      profile = values['USERPROFILE'];
  final root = roaming != null && roaming.isNotEmpty
      ? roaming
      : local != null && local.isNotEmpty
      ? local
      : profile != null && profile.isNotEmpty
      ? '$profile${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming'
      : null;
  if (root == null) {
    throw const FileSystemException(
      'Dossier personnel Windows introuvable. Aucun fichier de données n’a été remplacé.',
    );
  }
  return '$root${Platform.pathSeparator}Tableo';
}

class Store {
  bool demoOnEmpty = true;
  bool darkMode = false;
  List<String> eventOrder = [];
  bool _opened = false;
  late Database db;
  late String directory;
  Future<void> open({String? path}) async {
    sqfliteFfiInit();
    directory = path ?? defaultDataDirectory();
    await Directory(directory).create(recursive: true);
    db = await databaseFactoryFfi.openDatabase(
      '$directory${Platform.pathSeparator}tableo.sqlite',
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE projects (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated TEXT NOT NULL)',
          );
        },
      ),
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    final state = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: ['demo_on_empty'],
    );
    demoOnEmpty = state.isEmpty || state.first['value'] != '0';
    final theme = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: ['dark_mode'],
    );
    darkMode = theme.isNotEmpty && theme.first['value'] == '1';
    final order = await db.query(
      'app_state',
      where: 'key = ?',
      whereArgs: ['event_order'],
    );
    if (order.isNotEmpty) {
      try {
        final parsed = jsonDecode(order.first['value'] as String);
        if (parsed is List && parsed.every((id) => id is String)) {
          eventOrder = parsed.cast<String>();
        }
      } on FormatException {
        eventOrder = [];
      }
    }
    _opened = true;
  }

  List<Json> orderedEvents(List<Json> events) {
    final ranks = {
      for (var i = 0; i < eventOrder.length; i++) eventOrder[i]: i,
    };
    final original = {
      for (var i = 0; i < events.length; i++) events[i]['id']: i,
    };
    return [...events]..sort((a, b) {
      final rank = (ranks[a['id']] ?? eventOrder.length).compareTo(
        ranks[b['id']] ?? eventOrder.length,
      );
      return rank != 0
          ? rank
          : original[a['id']]!.compareTo(original[b['id']]!);
    });
  }

  Future<void> saveEventOrder(List<String> ids) async {
    if (_opened) {
      await db.insert('app_state', {
        'key': 'event_order',
        'value': jsonEncode(ids),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    eventOrder = [...ids];
  }

  Future<void> saveDarkMode(bool value) async {
    if (_opened) {
      await db.insert('app_state', {
        'key': 'dark_mode',
        'value': value ? '1' : '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    darkMode = value;
  }

  Future<List<Json>> load() async => (await db.query(
    'projects',
    orderBy: 'updated DESC',
  )).map((r) => jsonDecode(r['data'] as String) as Json).toList();
  Future<void> save(Json p) async => db.insert('projects', {
    'id': p['id'],
    'data': jsonEncode(p),
    'updated': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> delete(String id) async {
    await db.transaction((transaction) async {
      final deleted = await transaction.delete(
        'projects',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted > 0) {
        await transaction.insert('app_state', {
          'key': 'demo_on_empty',
          'value': '0',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        demoOnEmpty = false;
      }
    });
  }

  Future<void> saveEvents(List<Json> events) =>
      db.transaction((transaction) async {
        for (final event in events) {
          await transaction.insert('projects', {
            'id': event['id'],
            'data': jsonEncode(event),
            'updated': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> close() async {
    await db.close();
    _opened = false;
  }
}
