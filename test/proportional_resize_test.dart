import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'plan_images_test.dart' show image;
import 'attributions_test.dart' show SnapshotStore, desktop;
import 'rotation_handles_test.dart' show slowClick;

void main() {
  test(
    'All corners and angles preserve proportions and the opposite world corner',
    () {
      for (final angle in [0.0, 35.0, 90.0]) {
        for (final right in [true, false]) {
          for (final bottom in [true, false]) {
            final original = image(
              'i',
            )..addAll({'x': 5.0, 'y': 5.0, 'w': 4.0, 'h': 2.0, 'angle': angle});
            final item = clone(original);
            final before =
                rotatedLocalPoint(
                  original,
                  Point(right ? 0.0 : 4.0, bottom ? 0.0 : 2.0),
                ) +
                const Point(5.0, 5.0);
            final a = angle * pi / 180,
                dx = (right ? 1.0 : -1.0) * cos(a),
                dy = (right ? 1.0 : -1.0) * sin(a);
            expect(
              resizeRotatedBox(
                item,
                original,
                dx,
                dy,
                right,
                bottom,
                preserveAspect: true,
              ),
              true,
            );
            expect(number(item['w']) / number(item['h']), closeTo(2, 1e-9));
            final after =
                rotatedLocalPoint(
                  item,
                  Point(
                    right ? 0.0 : number(item['w']),
                    bottom ? 0.0 : number(item['h']),
                  ),
                ) +
                Point(number(item['x']), number(item['y']));
            expect(after.x, closeTo(before.x, 1e-9));
            expect(after.y, closeTo(before.y, 1e-9));
          }
        }
      }
    },
  );
  test('Aspect lock is optional and minimum dimensions keep the ratio', () {
    final original = image('i')
      ..addAll({'x': 5.0, 'y': 5.0, 'w': 4.0, 'h': 2.0});
    final item = clone(original);
    resizeRotatedBox(item, original, 1, 0, true, true, preserveAspect: true);
    expect(item['w'], 5);
    expect(item['h'], 2.5);
    resizeRotatedBox(item, original, 1, 0, true, true);
    expect(item['w'], 5);
    expect(item['h'], 2);
    resizeRotatedBox(item, original, -20, 0, true, true, preserveAspect: true);
    expect(number(item['h']), closeTo(.2, 1e-9));
    expect(number(item['w']) / number(item['h']), 2);
  });
  test('Zones keep proportional dimensions without escaping room limits', () {
    final p = demoProject();
    final zone = <String, dynamic>{
      'id': 'z',
      'kind': 'zone',
      'x': 2.0,
      'y': 2.0,
      'w': 4.0,
      'h': 2.0,
      'fixed': false,
      'shape': 'rectangle',
    };
    final original = clone(zone);
    resizeZone(p, zone, original, 2, 0, 'bottom-right', preserveAspect: true);
    expect(zone['w'], 6);
    expect(zone['h'], 3);
    final before = clone(zone);
    resizeZone(p, zone, original, 100, 0, 'bottom-right', preserveAspect: true);
    expect(zone, before);
  });
  testWidgets(
    'Shift image resizing preserves its ratio, releasing Shift returns to free sizing',
    (t) async {
      desktop(t);
      final store = SnapshotStore()
        ..saved['items'] = [image('i')..['h'] = 2.0]
        ..saved['groups'] = <Json>[];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      await slowClick(t, find.byKey(const ValueKey('plan-item-i')));
      final handle = find.byKey(
        const ValueKey('annotation-resize-i-true-true'),
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final gesture = await t.startGesture(
        t.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(20, 0));
      await t.pump();
      await gesture.moveBy(const Offset(20, 0));
      await t.pump();
      await gesture.up();
      await t.pumpAndSettle();
      expect(
        number(rows(store.saved, 'items').single['w']) /
            number(rows(store.saved, 'items').single['h']),
        closeTo(2, 1e-9),
      );
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final free = await t.startGesture(
        t.getCenter(handle),
        kind: PointerDeviceKind.mouse,
      );
      await free.moveBy(const Offset(20, 0));
      await t.pump();
      await free.moveBy(const Offset(20, 0));
      await t.pump();
      await free.up();
      await t.pumpAndSettle();
      expect(
        number(rows(store.saved, 'items').single['w']) /
            number(rows(store.saved, 'items').single['h']),
        greaterThan(2),
      );
      expect(t.takeException(), isNull);
    },
  );
}
