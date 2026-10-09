import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/exports.dart';
import 'package:tableo/file_dialogs.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

class LogoDialog extends FileDialogs {
  @override
  Future<String?> choose(FileRequest request) async {
    expect(request.extension, 'image');
    expect(request.save, false);
    return File('test/fixtures/logo-fiches.png').absolute.path;
  }
}

void main() {
  test('Personalized PDF repeats logo and message on occupied cards', () async {
    final p = demoProject();
    allocate(p);
    p['tableCards'] = {
      'message': 'Bienvenue et merci pour votre présence !',
      'logo': base64Encode(
        await File('test/fixtures/logo-fiches.png').readAsBytes(),
      ),
    };
    validateProject(clone(p));
    await Directory('output/pdf').create(recursive: true);
    await exportPdf(
      p,
      'output/pdf/exemple-fiches-personnalisees.pdf',
      cardsOnly: true,
      overwriteConfirmed: true,
    );
    expect(
      await File('output/pdf/exemple-fiches-personnalisees.pdf').length(),
      greaterThan(1000),
    );
  });
  testWidgets(
    'Properties save phrase and logo, cancel safely and remove only the logo',
    (tester) async {
      desktop(tester);
      final store = SnapshotStore();
      await tester.pumpWidget(Tableo(store: store, fileDialogs: LogoDialog()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Événements').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Propriétés'));
      await tester.pumpAndSettle();
      final phrase = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText ==
                'Phrase sur les fiches de table (facultative)',
      );
      final activity = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Activité',
      );
      final meals = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Prévoir des repas',
      );
      await tester.tap(activity);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soirée').last);
      await tester.pumpAndSettle();
      await tester.tap(meals);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Non').last);
      await tester.pumpAndSettle();
      final seating = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Côtés assis par défaut',
      );
      await tester.tap(seating);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tous côtés').last);
      await tester.pumpAndSettle();
      await tester.enterText(phrase, 'Bienvenue à notre soirée');
      await tester.tap(find.text('Choisir un logo'));
      for (
        var i = 0;
        i < 20 && find.text('Retirer le logo').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Retirer le logo'), findsOneWidget);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(store.saved['tableCards']['message'], 'Bienvenue à notre soirée');
      expect(store.saved['tableCards']['logo'], isNotEmpty);
      expect(store.saved['activity'], 'Soirée');
      expect(store.saved['mealService'], 'Non');
      expect(store.saved['defaultSides'], 'Tous côtés');
      expect(store.saved['room']['defaultSides'], isNull);
      expect(store.saved['room']['mealService'], isNull);
      await tester.tap(find.text('Propriétés'));
      await tester.pumpAndSettle();
      await tester.enterText(phrase, 'Annulé');
      await tester.tap(meals);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oui').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.saved['tableCards']['message'], 'Bienvenue à notre soirée');
      expect(store.saved['mealService'], 'Non');
      await tester.tap(find.text('Propriétés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retirer le logo'));
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(store.saved['tableCards']['logo'], isNull);
      expect(store.saved['tableCards']['message'], 'Bienvenue à notre soirée');
      expect(tester.takeException(), isNull);
    },
  );
}
