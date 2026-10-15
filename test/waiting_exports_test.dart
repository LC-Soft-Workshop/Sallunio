import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/plan_tools.dart';
import 'package:tableo/event_backup.dart';

void main() {
  test(
    'Waiting exports isolate waiting reservations and preserve contacts',
    () async {
      final p = demoProject();
      final waiting = rows(p, 'groups').first;
      waiting.addAll({
        'waiting': true,
        'name': 'Camille attente',
        'email': 'camille@example.test',
        'phone': '+32 470 12 34 56',
      });
      final before = clone(p);
      final csv = eventCsv(p, 'Liste d’attente');
      expect(csv, contains('Camille attente'));
      expect(csv, contains('camille@example.test'));
      expect(csv, contains('+32 470 12 34 56'));
      expect(csv, isNot(contains(rows(p, 'groups')[1]['name'])));
      expect(eventCsv(p, 'Réservations'), contains('camille@example.test'));
      await Directory('tmp/pdfs').create(recursive: true);
      await exportPdf(
        p,
        'tmp/pdfs/waiting-list.pdf',
        includePlan: false,
        includeSummary: false,
        includeCards: false,
        includeWaiting: true,
        overwriteConfirmed: true,
      );
      expect(File('tmp/pdfs/waiting-list.pdf').lengthSync(), greaterThan(1000));
      expect(p, before);
      final restored = readEventBackup(jsonEncode(eventBackup([p])));
      expect(
        rows(restored.first, 'groups').first['email'],
        'camille@example.test',
      );
      expect(rows(restored.first, 'groups').first['phone'], '+32 470 12 34 56');
    },
  );
}
