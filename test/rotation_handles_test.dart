import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'joining_test.dart' show table;
import 'plan_images_test.dart' show image;
import 'plan_annotations_test.dart' show annotation;
import 'annotation_shapes_test.dart' show arrow;
import 'mixed_furniture_test.dart' show exhibitor;
import 'plan_toolbar_test.dart' show clickTool;

Future<void> slowClick(WidgetTester t, Finder target) async {
  await t.tap(target);
  await t.pump(const Duration(milliseconds: 400));
  await t.pumpAndSettle();
}

Json pmr() => {
  ...table('pmr', 3, 3, w: .9, h: 1.2),
  'kind': 'pmr',
  'shape': 'emplacement PMR',
  'label': 'PMR 1',
  'capacity': 1,
  'usage': furnitureUses.first,
};
Future<void> turn(WidgetTester t, Finder item, double degrees) async {
  final center =
      (t.getCenter(find.byKey(const ValueKey('rotation-handle-0'))) +
          t.getCenter(find.byKey(const ValueKey('rotation-handle-2')))) /
      2;
  final start = t.getCenter(find.byKey(const ValueKey('rotation-handle-4'))),
      vector = start - center;
  final gesture = await t.startGesture(start, kind: PointerDeviceKind.mouse);
  for (var n = 1; n <= 8; n++) {
    final angle = degrees * n / 8 * pi / 180;
    await gesture.moveTo(
      center +
          Offset(
            vector.dx * cos(angle) - vector.dy * sin(angle),
            vector.dx * sin(angle) + vector.dy * cos(angle),
          ),
    );
    await t.pump();
  }
  await gesture.up();
  await t.pumpAndSettle();
}

void main() {
  test('Group rotation preserves allocations, dimensions, types and rejects locked changes atomically', () {
    final a = table('a', 3, 3), b = table('b', 6, 3);
    final p = demoProject()..['items'] = [a, b];
    final origins = [clone(a), clone(b)],
        groups = clone({'groups': p['groups']}),
        types = clone({'types': p['types']});
    expect(rotatePlanFromOrigins(p, origins, const Point(5.4, 3.4), 90), true);
    expect(number(a['x']), closeTo(4.5, 1e-6));
    expect(number(a['y']), closeTo(1.5, 1e-6));
    expect(number(b['y']), closeTo(4.5, 1e-6));
    expect(a['w'], origins.first['w']);
    expect(p['groups'], groups['groups']);
    expect(p['types'], types['types']);
    b['fixed'] = true;
    final before = clone(p);
    expect(rotatePlanFromOrigins(p, origins, const Point(5.4, 3.4), 45), false);
    expect(p, before);
    b['fixed'] = false;
    p['planLocked'] = true;
    expect(rotatePlanFromOrigins(p, origins, const Point(5.4, 3.4), 45), false);
  });
  test(
    'Rotated resizing preserves the opposite corner in world coordinates',
    () {
      final a = image('image')
            ..addAll({'x': 3.0, 'y': 3.0, 'w': 3.0, 'h': 1.0, 'angle': 90.0}),
          original = clone(image('unused'));
      original.addAll(a);
      final before =
          rotatedLocalPoint(a, const Point(0.0, 0.0)) +
          Point(number(a['x']), number(a['y']));
      expect(resizeRotatedBox(a, original, 0, 1, true, true), true);
      expect(a['w'], closeTo(4, 1e-6));
      final after =
          rotatedLocalPoint(a, const Point(0.0, 0.0)) +
          Point(number(a['x']), number(a['y']));
      expect(after.x, closeTo(before.x, 1e-6));
      expect(after.y, closeTo(before.y, 1e-6));
    },
  );
  test('Rotated stand rows remain continuous and never jump an aisle', () {
    for (final gap in [0.0, 1.2]) {
      final a = table('a', 3, 3)..['usage'] = furnitureUses[1],
          b = table('b', 4.8 + gap, 3)..['usage'] = furnitureUses[1];
      final p = demoProject()
        ..['items'] = [a, b]
        ..['groups'] = [exhibitor('Stand', 3)];
      rotatePlanFromOrigins(
        p,
        [clone(a), clone(b)],
        Point(4.8 + gap / 2, 3.4),
        45,
      );
      expect(standContinues(a, b), gap == 0);
      allocateStands(p);
      expect(
        number(standSummary(p)['assignedMetres']),
        closeTo(gap == 0 ? 3 : 1.8, 1e-6),
      );
    }
  });
  for (final kind in [
    'table',
    'chair',
    'bench',
    'pmr',
    'zone',
    'obstacle',
    'entry',
    'exit',
    'door',
    'info',
    'image',
    'text',
    'arrow',
  ]) {
    testWidgets(
      '$kind switches resize and rotation on successive slow clicks',
      (t) async {
        desktop(t);
        final item = kind == 'image'
            ? image('item')
            : kind == 'info' || kind == 'text'
            ? annotation(kind, 'item')
            : kind == 'arrow'
            ? arrow('item')
            : {
                ...table('item', 3, 3),
                'kind': kind,
                'shape': kind == 'chair'
                    ? 'chaise'
                    : kind == 'bench'
                    ? 'banc'
                    : kind == 'pmr'
                    ? 'emplacement PMR'
                    : 'rectangle',
              };
        item['x'] = 3.0;
        item['y'] = 3.0;
        item['w'] = 2.0;
        item['h'] = 1.0;
        final store = SnapshotStore()
          ..saved['items'] = [item]
          ..saved['groups'] = <Json>[];
        await t.pumpWidget(Tableo(store: store));
        await t.pumpAndSettle();
        final target = find.byKey(const ValueKey('plan-item-item'));
        await slowClick(t, target);
        expect(find.byKey(const ValueKey('rotation-frame')), findsNothing);
        await slowClick(t, target);
        expect(find.byKey(const ValueKey('rotation-frame')), findsOneWidget);
        expect(find.byKey(const ValueKey('rotation-handle-4')), findsOneWidget);
        if (['info', 'image', 'arrow'].contains(kind)) {
          expect(
            find.byKey(const ValueKey('annotation-resize-item-true-true')),
            findsNothing,
          );
        }
        await slowClick(t, target);
        expect(find.byKey(const ValueKey('rotation-frame')), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'PMR free rotation is continuous, undoable and rapid double click still edits',
    (t) async {
      desktop(t);
      final store = SnapshotStore()
        ..saved['items'] = [pmr()]
        ..saved['groups'] = <Json>[];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final item = find.byKey(const ValueKey('plan-item-pmr'));
      await t.tap(find.byKey(const ValueKey('plan-zoom-in')));
      await t.pumpAndSettle();
      await slowClick(t, item);
      await slowClick(t, item);
      await turn(t, item, 90);
      final rotated = rows(store.saved, 'items').single;
      expect(number(rotated['angle']), closeTo(90, 2));
      expect(rotated['w'], .9);
      expect(rotated['h'], 1.2);
      expect(rotated['x'], closeTo(3, 1e-6));
      await t.tap(find.byIcon(Icons.undo).first);
      await t.pumpAndSettle();
      expect(number(rows(store.saved, 'items').single['angle']), 0);
      await t.tap(item);
      await t.pump(const Duration(milliseconds: 60));
      await t.tap(item);
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Annuler').last);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('A multiple selection rotates as one group', (t) async {
    desktop(t);
    final store = SnapshotStore()
      ..saved['items'] = [table('a', 3, 3), table('b', 6, 3)]
      ..saved['groups'] = <Json>[];
    await t.pumpWidget(Tableo(store: store));
    await t.pumpAndSettle();
    final a = find.byKey(const ValueKey('plan-item-a')),
        b = find.byKey(const ValueKey('plan-item-b'));
    await slowClick(t, a);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await slowClick(t, b);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await slowClick(t, a);
    expect(find.byKey(const ValueKey('rotation-frame')), findsOneWidget);
    await turn(t, a, 90);
    final actual = rows(store.saved, 'items');
    expect(number(actual.first['angle']), closeTo(90, 2));
    expect(number(actual.last['angle']), closeTo(90, 2));
    expect(number(actual.first['x']), closeTo(number(actual.last['x']), .05));
    expect(
      number(actual.last['y']) - number(actual.first['y']),
      closeTo(3, .05),
    );
  });
  testWidgets(
    'Rectangle selection also supports click cycling and direct rotation handles',
    (t) async {
      desktop(t);
      final store = SnapshotStore()
        ..saved['items'] = [pmr()]
        ..saved['groups'] = <Json>[];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await clickTool(t, 'select');
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is CheckedPopupMenuItem<String> && w.value == 'rectangle',
        ),
      );
      await t.pumpAndSettle();
      final item = find.byKey(const ValueKey('plan-item-pmr'));
      for (var n = 0; n < 2; n++) {
        await t.tapAt(t.getCenter(item));
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('rotation-frame')), findsOneWidget);
      await turn(t, item, 90);
      expect(
        number(rows(store.saved, 'items').single['angle']),
        closeTo(90, 2),
      );
      await t.tapAt(t.getCenter(item));
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rotation-frame')), findsNothing);
      await t.tapAt(t.getCenter(item));
      await t.pump(const Duration(milliseconds: 60));
      await t.tapAt(t.getCenter(item));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Annuler').last);
      await t.pumpAndSettle();
    },
  );
  testWidgets(
    'Shift snaps rotation and fixed objects never expose rotation handles',
    (t) async {
      desktop(t);
      final store = SnapshotStore()
        ..saved['items'] = [pmr()]
        ..saved['groups'] = <Json>[];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final item = find.byKey(const ValueKey('plan-item-pmr'));
      await slowClick(t, item);
      await slowClick(t, item);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await turn(t, item, 44);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(number(rows(store.saved, 'items').single['angle']), 45);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      final fixed = SnapshotStore()..saved['items'] = [pmr()..['fixed'] = true];
      await t.pumpWidget(Tableo(store: fixed));
      await t.pumpAndSettle();
      await slowClick(t, item);
      await slowClick(t, item);
      expect(find.byKey(const ValueKey('rotation-frame')), findsNothing);
    },
  );
}
