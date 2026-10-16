import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/external_links.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'update_ui_test.dart' show FakeLinks;

void main() {
  test('Official comfort link and GitHub are permitted; other destinations are refused', () {
    for (final link in [
      'https://github.com/LC-Soft-Workshop/Sallunio',
      'https://www.legifrance.gouv.fr/loda/article_lc/LEGIARTI000034485952',
    ]) {
      expect(() => validateExternalLink(Uri.parse(link)), returnsNormally);
    }
    for (final link in [
      'http://www.legifrance.gouv.fr/',
      'https://github.com.example.org/',
      'https://www.legifrance.gouv.fr.example.org/',
      'https://person@github.com/',
      'file:///C:/test',
      'https://github.com:1234/',
    ]) {
      expect(
        () => validateExternalLink(Uri.parse(link)),
        throwsFormatException,
      );
    }
  });
  testWidgets(
    'Comfort recommendation opens the official article without changing event data',
    (t) async {
      desktop(t);
      final store = SnapshotStore();
      final links = FakeLinks();
      await t.pumpWidget(Tableo(store: store, linkOpener: links));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('plan-tool-settings')));
      await t.tap(find.byKey(const ValueKey('plan-tool-settings')));
      await t.pumpAndSettle();
      await t.tap(find.text('Confort').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Repères officiels d’accessibilité'));
      await t.pumpAndSettle();
      await t.tap(find.text('Repères officiels d’accessibilité'));
      await t.pumpAndSettle();
      expect(
        links.opened.single.toString(),
        'https://www.legifrance.gouv.fr/loda/article_lc/LEGIARTI000034485952',
      );
      validateExternalLink(links.opened.single);
      expect(t.takeException(), isNull);
    },
  );
}
