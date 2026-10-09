import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';
import 'package:tableo/file_dialogs.dart';

class TestStore extends Store {
  Json project = demoProject();
  TestStore() {
    directory = 'Fictif';
  }
  @override
  Future<List<Json>> load() async => [project];
  @override
  Future<void> save(Json p) async {
    project = clone(p);
  }
}

class TestDialogs implements FileDialogs {
  final List<FileRequest> seen = [];
  String? result;
  bool error = false;
  @override
  Future<String?> choose(FileRequest r) async {
    seen.add(r);
    if (error) {
      throw const FileSystemException('Accès refusé au fichier fictif');
    }
    return result;
  }
}

void main() {
  test(
    'Save extensions support spaces and accents without doubling suffix',
    () {
      expect(withExtension('équipe été', 'csv'), 'équipe été.csv');
      expect(withExtension('équipe.PDF', 'pdf'), 'équipe.PDF');
      expect(withExtension('projet.json', 'tableo.json'), 'projet.json');
    },
  );
  testWidgets(
    'CSV Browse invokes open filter; cancellation and inaccessible file do not change data',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = TestStore(),
          picker = TestDialogs(),
          before = clone(store.project);
      await tester.pumpWidget(Tableo(store: store, fileDialogs: picker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('1. Importer les réservations (CSV)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcourir • Ouvrir'));
      await tester.pumpAndSettle();
      expect(picker.seen.single.extension, 'csv');
      expect(picker.seen.single.save, false);
      expect(store.project, before);
      picker.error = true;
      await tester.tap(find.text('Parcourir • Ouvrir'));
      await tester.pumpAndSettle();
      expect(find.text('Fichier inaccessible'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.project, before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Every existing file action has native navigation with correct save/open mode',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = TestDialogs();
      await tester.pumpWidget(Tableo(store: TestStore(), fileDialogs: picker));
      await tester.pumpAndSettle();
      for (final action in [
        'Importer projet',
        'Exporter projet',
        'Export PDF',
      ]) {
        await tester.tap(find.text('Fichiers ▾'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        if (action == 'Export PDF' || action == 'Exporter projet') {
          await tester.tap(find.text('Continuer'));
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.text(
            action == 'Importer projet'
                ? 'Parcourir • Ouvrir'
                : 'Parcourir • Enregistrer sous',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          picker.seen.last.extension,
          action == 'Export PDF' ? 'pdf' : 'tableo.json',
        );
        expect(picker.seen.last.save, action != 'Importer projet');
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Réservations').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV d’exemple'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer une copie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Parcourir • Enregistrer sous'));
      await tester.pumpAndSettle();
      expect(picker.seen.last.extension, 'csv');
      expect(picker.seen.last.save, true);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
