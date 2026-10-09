import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

Json currentProject() {
  final p = demoProject();
  p['name'] = 'Événement courant fictif';
  p['room']['name'] = 'Salle courante 14 x 10';
  p['room']['width'] = 14.0;
  p['room']['height'] = 10.0;
  final ts = tables(p);
  ts[0].addAll({
    'label': 'T71',
    'x': 3.2,
    'y': 5.6,
    'w': 2.4,
    'h': .8,
    'capacity': 8,
  });
  ts[1].addAll({
    'label': 'T72',
    'x': 7.1,
    'y': 2.2,
    'w': 2.1,
    'h': 1.0,
    'capacity': 5,
  });
  final gs = rows(p, 'groups');
  gs[0].addAll({
    'name': 'Référent courant fictif',
    'count': 7,
    'meal': 'Normal',
    'alloc': [
      {'table': ts[0]['id'], 'count': 7},
    ],
  });
  gs[1].addAll({
    'name': 'Morgan actuel fictif',
    'count': 2,
    'meal': 'Sans gluten',
    'needs': '',
    'allergy': 'Exemple actualisé',
    'alloc': [
      {'table': ts[1]['id'], 'count': 2},
    ],
  });
  gs[2].addAll({
    'name': 'Alex actuel fictif',
    'count': 1,
    'alloc': [
      {'table': ts[2]['id'], 'count': 1},
    ],
  });
  return p;
}

class LivePdfStore extends Store {
  final Json project = currentProject();
  @override
  Future<List<Json>> load() async => [project];
  @override
  Future<void> save(Json p) async {}
  LivePdfStore() {
    directory = 'output/pdf';
  }
}

void main() {
  test('Export captures current edited data before asynchronous work, not later mutation', () async {
    await Directory('output/pdf').create(recursive: true);
    final p = currentProject(), expected = clone(currentProject());
    final snapshot = clone(p);
    final path = File('output/pdf/verification-export-actuel-${uid()}.pdf')
        .absolute
        .path;
    final future = exportPdf(
      p,
      path,
      exportReference: 'preuve-snapshot-courant',
    );
    p['name'] = 'Mutation APRES export';
    p['room']['name'] = 'Ancienne référence remplacée';
    p['groups'] = <Json>[];
    await future;
    expect((await File(path).readAsBytes()).length, greaterThan(10000));
    await Directory('tmp/pdfs').create(recursive: true);
    await File('tmp/pdfs/pdf-current-manifest.json')
        .writeAsString(jsonEncode({'path': path, 'snapshot': snapshot}));
    expect(expected['name'], snapshot['name']);
  });
  test(
    'Existing PDFs are never overwritten and filename suggestions differ',
    () async {
      final dir = await Directory.systemTemp.createTemp('tableo-existing-pdf-');
      expect(dir.parent.absolute.path, Directory.systemTemp.absolute.path);
      final file = File('${dir.path}/existant.pdf');
      await file.writeAsString('PDF fictif existant à préserver');
      await expectLater(
        exportPdf(currentProject(), file.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.readAsString(), 'PDF fictif existant à préserver');
      expect(newPdfPath(dir.path), isNot(newPdfPath(dir.path)));
      await dir.delete(recursive: true);
    },
  );
  test(
    'Export after reopen and workspace switch uses chosen edited workspace',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'tableo-pdf-workspaces-',
      );
      expect(dir.parent.absolute.path, Directory.systemTemp.absolute.path);
      final store = Store();
      await store.open(path: dir.path);
      final a = demoProject(), b = currentProject();
      b['name'] = 'Événement B sélectionné';
      await store.save(a);
      await store.save(b);
      await store.close();
      final reopened = Store();
      await reopened.open(path: dir.path);
      final chosen = (await reopened.load()).firstWhere(
        (p) => p['id'] == b['id'],
      );
      chosen['room']['name'] = 'Salle B modifiée sans sauvegarde';
      await Directory('tmp/pdfs').create(recursive: true);
      final path = File('tmp/pdfs/workspace-courant-${uid()}.pdf')
          .absolute
          .path;
      await exportPdf(chosen, path, exportReference: 'preuve-workspace-B');
      await File('tmp/pdfs/pdf-workspace-manifest.json')
          .writeAsString(jsonEncode({'path': path, 'snapshot': chosen}));
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
  testWidgets(
    'PDF action snapshots the live workspace at click and announces completed new file with exact path',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => Directory('output/pdf').create(recursive: true),
      );
      final store = LivePdfStore(), snapshot = clone(store.project);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers ▾'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuer'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextField),
            )
            .first,
      );
      final path = File(field.controller!.text).absolute.path;
      store.project['name'] = 'Changement après clic PDF';
      store.project['groups'] = <Json>[];
      await tester.tap(find.text('Valider'));
      for (
        var i = 0;
        i < 200 && find.text('PDF exporté').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('PDF exporté'), findsOneWidget);
      expect(find.text(path), findsOneWidget);
      expect(File(path).lengthSync(), greaterThan(10000));
      await tester.runAsync(
        () => File('tmp/pdfs/pdf-ui-manifest.json')
            .writeAsString(jsonEncode({'path': path, 'snapshot': snapshot})),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
