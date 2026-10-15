import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/main.dart';

import 'file_dialogs_test.dart' show TestStore, TestDialogs;

void main() {
  test(
    'PDF plan can omit legend without changing reservations or source',
    () async {
      final p = demoProject();
      allocate(p);
      await Directory('tmp/pdfs').create(recursive: true);
      for (final legend in [true, false]) {
        await exportPdf(
          p,
          'tmp/pdfs/optional-legend-$legend.pdf',
          overwriteConfirmed: true,
          includePlan: true,
          includeSummary: false,
          includeCards: false,
          includeLegend: legend,
        );
      }
    },
  );

  test(
    'Export all seven nonempty combinations for content verification',
    () async {
      final p = demoProject();
      p['groups'] = [rows(p, 'groups').first];
      rows(p, 'groups').first['alloc'] = [
        {'table': tables(p).first['id'], 'count': 6},
      ];
      await Directory('tmp/pdfs').create(recursive: true);
      for (var mask = 1; mask <= 7; mask++) {
        await exportPdf(
          p,
          'tmp/pdfs/selection-$mask.pdf',
          includePlan: mask & 1 != 0,
          includeSummary: mask & 2 != 0,
          includeCards: mask & 4 != 0,
          overwriteConfirmed: true,
        );
      }
      await expectLater(
        exportPdf(
          p,
          'tmp/pdfs/selection-empty.pdf',
          includePlan: false,
          includeSummary: false,
          includeCards: false,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
  testWidgets(
    'PDF selector requires a section and cancel does not invoke file picker',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = TestDialogs();
      await tester.pumpWidget(Tableo(store: TestStore(), fileDialogs: picker));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fichiers ▾'));
      await tester.pumpAndSettle();
      expect(find.text('Fiches tables (PDF)'), findsNothing);
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Fiches de table'),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Afficher la légende sur le plan',
              ),
            )
            .value,
        true,
      );
      await tester.tap(
        find.widgetWithText(
          CheckboxListTile,
          'Afficher la légende sur le plan',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Afficher la légende sur le plan',
              ),
            )
            .value,
        false,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Plan de salle'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(
                CheckboxListTile,
                'Afficher la légende sur le plan',
              ),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(
        find.widgetWithText(CheckboxListTile, 'Récapitulatif de l’événement'),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuer'),
            )
            .onPressed,
        isNull,
      );
      final waiting = find.widgetWithText(CheckboxListTile, 'Liste d’attente');
      await tester.ensureVisible(waiting);
      await tester.tap(waiting);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Continuer'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(picker.seen, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
