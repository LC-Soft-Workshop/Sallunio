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

void main() {
  testWidgets('Plan shows markers, conflict legend and collective rotation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'C:/Windows/Fonts/arial.ttf',
        'MaterialIcons': materialIconsPath(),
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              File(entry.value)
                  .readAsBytes()
                  .then((v) => v.buffer.asByteData()),
            ))
            .load();
      }
    });
    final project = demoProject();
    allocate(project);
    project['aisle'] = 1.5;
    tables(project)[1]['x'] = tables(project)[0]['x'];
    tables(project)[1]['y'] = tables(project)[0]['y'];
    final capture = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: capture,
        child: Tableo(store: MemoryStore([project])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Légende'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Mobilité / PMR'),
      80,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('plan-sidebar')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Mobilité / PMR'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsWidgets);
    await tester.tap(find.text('Toutes les tables : 90°'));
    await tester.pumpAndSettle();
    expect(tables(project).first['w'], .8);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('output/qa').create(recursive: true);
      await File('output/qa/plan-1.0.5.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
