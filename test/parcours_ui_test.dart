import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/parcours.dart';
import 'package:tableo/parcours_painter.dart';
import 'package:tableo/plan_export.dart';

import 'flutter_paths.dart';
import 'parcours_test.dart' show market;
import 'imposed_parcours_test.dart' show perimeterMarket;
import 'open_parcours_test.dart' show lateralEntranceMarket, simpleOpen;
import 'ui_test.dart' show MemoryStore, immediateArrangement;

void desktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> fonts(WidgetTester tester) => tester.runAsync(() async {
  for (final entry in {
    'Roboto': 'C:/Windows/Fonts/arial.ttf',
    'MaterialIcons': materialIconsPath(),
  }.entries) {
    await (FontLoader(entry.key)..addFont(
          File(entry.value).readAsBytes().then((v) => v.buffer.asByteData()),
        ))
        .load();
  }
});

void main() {
  testWidgets('Closed lateral entrance retains the linked maze and its exit', (
    tester,
  ) async {
    desktop(tester);
    await fonts(tester);
    final p = lateralEntranceMarket();
    p['parcoursSettings']['circulation'] = 'Fermé';
    arrange(p);
    expect(parcoursWarnings(p), isEmpty);
    expect(parcoursUnservedTables(p), isEmpty);
    expect(parcoursPaths(p).first.first, parcoursPaths(p).first.last);
    expect(tables(p).any((t) => t['parcoursRole'] == 'spine'), true);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: Tableo(store: MemoryStore([p])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('output/qa').createSync(recursive: true);
      File('output/qa/closed-lateral.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lateral entrance with an optimized terminal area is readable', (
    tester,
  ) async {
    desktop(tester);
    await fonts(tester);
    final p = lateralEntranceMarket();
    arrange(p);
    expect(parcoursWarnings(p), isEmpty);
    expect(parcoursUnservedTables(p), isEmpty);
    simpleOpen(p);
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: Tableo(store: MemoryStore([p])),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('output/qa').createSync(recursive: true);
      File('output/qa/open-optimized.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Imposed loop render shows the spine, alternating ends and arrows',
    (tester) async {
      desktop(tester);
      await fonts(tester);
      final p = perimeterMarket(extras: 7);
      arrange(p);
      expect(parcoursWarnings(p), isEmpty);
      expect(parcoursArrows(p), isNotEmpty);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(store: MemoryStore([p])),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('output/qa').createSync(recursive: true);
        File('output/qa/imposed-loop.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Parcours option is absent for Loto and Soirée, present for allowed events',
    (tester) async {
      desktop(tester);
      for (final activity in roomActivities) {
        final p = market()
          ..['activity'] = activity
          ..['arrangementMode'] = 'Standard';
        await tester.pumpWidget(
          Tableo(
            key: ValueKey(activity),
            store: MemoryStore([p]),
            arrangementRunner: immediateArrangement,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disposer mobilier'));
        await tester.pumpAndSettle();
        expect(
          find.text('Mode de disposition'),
          parcoursAvailable(p) ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Arrangement reads exhibitor spacing from event comfort only', (
    tester,
  ) async {
    desktop(tester);
    await fonts(tester);
    final p = market()..['comfort'] = {'exhibitorGap': 1.75};
    final before = clone(p);
    await tester.pumpWidget(Tableo(store: MemoryStore([p])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disposer mobilier'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parcours-gap')), findsNothing);
    expect(
      find.text(
        'Espace exposants dos à dos : 1,75 m — réglé dans Confort de l’événement.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(p['comfort'], before['comfort']);
    expect(p['parcoursSettings'], before['parcoursSettings']);
  });

  testWidgets('Settings, validation, arrangement, and undo operate locally', (
    tester,
  ) async {
    desktop(tester);
    await fonts(tester);
    final p = market()..['arrangementMode'] = 'Standard';
    final before = clone(p);
    await tester.pumpWidget(
      Tableo(store: MemoryStore([p]), arrangementRunner: immediateArrangement),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disposer mobilier'));
    await tester.pumpAndSettle();
    final mode = find.widgetWithText(
      DropdownButtonFormField<String>,
      'Standard',
    );
    await tester.tap(mode);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcours des exposants en S').last);
    await tester.pumpAndSettle();
    expect(find.text('Parcours fermé'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Parcours fermé'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Parcours ouvert').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parcours-gap')), findsNothing);
    expect(find.byKey(const ValueKey('parcours-gap-info')), findsOneWidget);
    await tester.tap(find.text('Disposer'));
    await tester.pumpAndSettle();
    expect(parcoursCurrent(p), true);
    expect(p['comfort'], before['comfort']);
    expect(parcoursWarnings(p), isEmpty);
    expect(p['parcoursSettings']['exhibitorGap'], 1.2);
    expect(p['parcoursSettings']['circulation'], 'Ouvert');
    expect(p['parcoursSettings']['imposedLoop'], false);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Annuler'));
    await tester.pumpAndSettle();
    expect(p['items'], before['items']);
    expect(p['arrangementMode'], 'Standard');
  });
  testWidgets(
    'Visible visitor route matches PDF and clear/dark renders stay readable',
    (tester) async {
      desktop(tester);
      await fonts(tester);
      final p = market();
      arrange(p);
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(store: MemoryStore([p])),
        ),
      );
      await tester.pumpAndSettle();
      for (final dark in [false, true]) {
        if (dark) {
          await tester.tap(find.byTooltip('Passer au mode sombre'));
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .any((v) => v.painter is ParcoursPainter),
          true,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('output/qa').createSync(recursive: true);
          File('output/qa/parcours-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
      final display = find.byKey(const ValueKey('plan-tool-display'));
      await tester.ensureVisible(display);
      await tester.tap(display);
      await tester.pumpAndSettle();
      final toggle = find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<String> && w.value == 'route',
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(p['showParcours'], false);
      expect(planSvg(p), isNot(contains('<polyline')));
      tables(p).first['joinGap'] = .15;
      expect(parcoursCurrent(p), false);
      await tester.tap(display);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((v) => v.painter)
          .whereType<ParcoursPainter>();
      expect(p['showParcours'], true);
      expect(painters.single.paths, isNotEmpty);
      expect(painters.single.stale, true);
      expect(parcoursPaths(p), isEmpty);
      expect(
        find.text(
          'Dernier tracé en pointillés. Vous pouvez recalculer le parcours ou garder le plan actuel.',
        ),
        findsOneWidget,
      );
    },
  );
}
