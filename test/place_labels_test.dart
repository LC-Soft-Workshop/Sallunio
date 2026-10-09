import 'flutter_paths.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'ui_test.dart' show MemoryStore;

Json labelledPlan() {
  final p = demoProject(), table = tables(demoProject()).first;
  final id = tables(p).first['id'];
  final groups = rows(p, 'groups');
  groups[0]['name'] = 'Camille';
  groups[0]['alloc'] = [
    {'table': id, 'count': 3},
  ];
  groups[1]['name'] = 'Morgan';
  groups[1]['alloc'] = [
    {'table': id, 'count': 2},
  ];
  groups[2]['alloc'] = [];
  assert(table['capacity'] == 6);
  return p;
}

void main() {
  test(
    'One label per usable place, repeated by allocation, remaining place free',
    () {
      final p = labelledPlan(), table = tables(labelledPlan()).first;
      expect(tablePlaceLabels(p, tables(p).first), [
        'Camille',
        'Camille',
        'Camille',
        'Morgan',
        'Morgan',
        null,
      ]);
      expect(tablePlaceLabels(p, tables(p)[1]), List.filled(6, null));
      expect(table['capacity'], 6);
      p['joining'] = 'Grands côtés';
      tables(p)[1]['x'] = tables(p).first['x'];
      tables(p)[1]['y'] =
          number(tables(p).first['y']) + number(tables(p).first['h']);
      expect(
        tablePlaceLabels(p, tables(p).first).length,
        effectiveCapacity(p, tables(p).first),
      );
      expect(tablePlaceLabels(p, tables(p).first).length, 3);
    },
  );
  testWidgets(
    'Checkbox activates labels that become readable only with sufficient zoom',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final font = FontLoader('Roboto')
          ..addFont(
            File('C:/Windows/Fonts/arial.ttf')
                .readAsBytes()
                .then((b) => b.buffer.asByteData()),
          );
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(
            File(materialIconsPath())
                .readAsBytes()
                .then((b) => b.buffer.asByteData()),
          );
        await icons.load();
      });
      final p = labelledPlan(), capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: Tableo(store: MemoryStore([p])),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Afficher les groupes par place'));
      await tester.pumpAndSettle();
      Iterable<PlaceLabelsPainter> painters() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<PlaceLabelsPainter>();
      expect(painters().every((p) => !p.visible), true);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final viewport = tester.getRect(find.byType(InteractiveViewer));
      final table = tester.getRect(
        find.byKey(ValueKey('plan-item-${tables(p).first['id']}')),
      );
      final centre = table.center - viewport.topLeft;
      viewer.transformationController!.value = Matrix4.diagonal3Values(5, 5, 1)
        ..setTranslationRaw(
          viewport.width / 2 - centre.dx * 5,
          viewport.height / 2 - centre.dy * 5,
          0,
        );
      await tester.pumpAndSettle();
      expect(painters().every((p) => p.visible), true);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('output/qa').create(recursive: true);
        await File('output/qa/place-labels.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    },
  );
}
