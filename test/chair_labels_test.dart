import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;
import 'mixed_furniture_test.dart' show audiencePlan, seatedGroup;

void main() {
  test('Legacy chair display keeps original labels, custom labels and stable numbers', () {
    final p = audiencePlan(count: 1), chair = tables(p).single;
    chair['label'] = 'Chaise 12';
    expect(furniturePlanLabel(p, chair), 'C12');
    expect(chair['label'], 'Chaise 12');
    chair['label'] = 'Loge A';
    expect(furniturePlanLabel(p, chair), 'Loge A');
    final type = {
      'id': 'chairs',
      'name': 'Chaise pliante',
      'shape': 'chaise',
      'w': .5,
      'h': .5,
      'capacity': 1,
      'quantity': 3,
      'limit': 3,
      'source': 'Propre',
      'enabled': true,
      'seating': 'Chaises',
    };
    p['types'] = [type];
    chair['type'] = 'chairs';
    chair['label'] = 'Chaise 1';
    chair['x'] = 1.0;
    chair['y'] = 3.0;
    expect(addFurniture(p, [type], all: true).placed, 2);
    expect(tables(p).map(furnitureShortLabel), ['C1', 'C2', 'C3']);
  });
  testWidgets(
    'A rotated chair shows a short fitted number and upright reservation tooltip',
    (t) async {
      desktop(t);
      final store = SnapshotStore()..saved = audiencePlan(count: 1);
      final p = store.saved, chair = tables(p).single;
      chair.addAll({
        'label': 'Chaise 12',
        'type': 'chairs',
        'x': 6.0,
        'y': 4.0,
        'angle': 45.0,
      });
      p['types'] = [
        {
          'id': 'chairs',
          'name': 'Chaise pliante bleue',
          'shape': 'chaise',
          'w': .5,
          'h': .5,
          'capacity': 1,
          'quantity': 5,
          'limit': 5,
          'source': 'Propre',
          'enabled': true,
          'seating': 'Chaises',
        },
      ];
      final g = seatedGroup('a', 1);
      g['name'] = 'Famille fictive';
      g['alloc'] = [
        {'table': chair['id'], 'count': 1},
      ];
      g['seats'] = [
        {
          'number': 1,
          'name': 'Alice fictive',
          'table': chair['id'],
          'slot': 0,
          'fixed': true,
          'meal': 'Normal',
          'allergy': '',
          'need': '',
          'companion': '',
        },
      ];
      p['groups'] = [g];
      await t.pumpWidget(Tableo(store: store));
      await t.pumpAndSettle();
      final item = find.byKey(ValueKey('plan-item-${chair['id']}'));
      expect(
        find.descendant(of: item, matching: find.text('C12')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: item, matching: find.byType(FittedBox)),
        findsWidgets,
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(t.getCenter(item));
      await t.pump(const Duration(milliseconds: 700));
      expect(
        find.textContaining('Modèle de mobilier : Chaise pliante bleue'),
        findsOneWidget,
      );
      expect(
        find.textContaining('réservée à Alice fictive — Famille fictive'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await mouse.removePointer();
    },
  );
  for (final entry in {
    'table': 'Table',
    'bench': 'Banc',
    'pmr': 'Emplacement PMR',
  }.entries) {
    testWidgets('Plan hover information for ${entry.value}', (t) async {
      final p = audiencePlan(count: 1);
      final item = tables(p).single;
      item.addAll({
        'kind': entry.key,
        'label': 'Repère 7',
        'note': 'Note fictive',
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                positionedFurniture(
                  p,
                  item,
                  PlanGeometry(p, rows(p, 'items')),
                  1,
                  const Positioned(
                    left: 50,
                    top: 50,
                    child: SizedBox(
                      width: 100,
                      height: 100,
                      child: ColoredBox(color: Colors.grey),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(100, 100));
      await t.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('${entry.value} : Repère 7'), findsOneWidget);
      expect(find.textContaining('Note : Note fictive'), findsOneWidget);
      expect(t.takeException(), isNull);
      await mouse.removePointer();
    });
  }
  test('Stand and service information follows furniture usage', () {
    final p = audiencePlan(count: 1), item = tables(p).single;
    item['kind'] = 'table';
    item['usage'] = furnitureUses[1];
    expect(furnitureTooltip(p, item), contains('Stand libre'));
    item['usage'] = furnitureUses[2];
    expect(furnitureTooltip(p, item), contains('Usage : ${furnitureUses[2]}'));
    expect(furnitureTooltip(p, item), isNot(contains('Place 1 :')));
  });
  test('Blocked chair tooltip reports reservation without occupant and hides meals when disabled', () {
    final p = audiencePlan(count: 1);
    p['mealService'] = 'Non';
    final chair = tables(p).single;
    chair['blockedSlots'] = [0];
    expect(
      furnitureTooltip(p, chair),
      contains('bloquée / réservée sans occupant'),
    );
    expect(furnitureTooltip(p, chair), isNot(contains('Repas')));
  });
}
