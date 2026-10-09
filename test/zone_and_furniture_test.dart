import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'attributions_test.dart' show SnapshotStore, desktop;

void main() {
  for (final fill in ['Plein', 'Invisible']) {
    testWidgets(
      'Zone $fill stays selectable and resizable; tables have no handles',
      (tester) async {
        desktop(tester);
        final store = SnapshotStore();
        final zone = rows(
          store.saved,
          'items',
        ).firstWhere((i) => i['kind'] == 'zone');
        zone['fixed'] = false;
        zone['zoneFill'] = fill;
        if (fill == 'Invisible') zone['label'] = '';
        final id = zone['id'], width = number(zone['w']);
        await tester.pumpWidget(Tableo(store: store));
        await tester.pumpAndSettle();
        expect(
          find.byTooltip('${issues(store.saved).length} alertes à examiner'),
          findsOneWidget,
        );
        await tester.tapAt(
          tester.getCenter(find.byKey(ValueKey('plan-item-$id'))),
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final handle = find.byKey(ValueKey('resize-$id-bottom-right'));
        expect(handle, findsOneWidget);
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(25, 25));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 10));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 10));
        await tester.pump();
        await gesture.moveBy(const Offset(20, 10));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
        final saved = rows(
          store.saved,
          'items',
        ).firstWhere((i) => i['id'] == id);
        expect(number(saved['w']), greaterThan(width));
        await tester.tapAt(tester.getCenter(find.text('T1\n0/6').first));
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Redimensionner la zone'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('Propagation keeps legacy rotated dimensions and position for capacity changes', () {
    final p = demoProject(), old = rows(demoProject(), 'types').first;
    final type = rows(p, 'types').first;
    final table = tables(p).first;
    final w = table['w'];
    table['w'] = table['h'];
    table['h'] = w;
    final before = clone(table);
    final updated = {...type, 'capacity': 8};
    expect(propagateFurniture(p, type, updated), false);
    expect(table['x'], before['x']);
    expect(table['y'], before['y']);
    expect(table['w'], before['w']);
    expect(table['h'], before['h']);
    expect(table['capacity'], 8);
    expect(old['w'], type['w']);
    expect(propagateFurniture(p, type, {...type, 'w': 2.4}), true);
    expect(table['w'], .8);
    expect(table['h'], 2.4);
    expect(table['x'], before['x']);
    expect(table['y'], before['y']);
  });
  test('Zone resizing keeps opposite corner and never resizes tables', () {
    final p = demoProject();
    final zone = rows(p, 'items').firstWhere((i) => i['kind'] == 'zone');
    final origin = clone(zone);
    resizeZone(p, zone, origin, -1, -.5, 'top-left');
    expect(
      number(zone['x']) + number(zone['w']),
      closeTo(number(origin['x']) + number(origin['w']), 1e-8),
    );
    expect(
      number(zone['y']) + number(zone['h']),
      closeTo(number(origin['y']) + number(origin['h']), 1e-8),
    );
    final table = tables(p).first, before = clone(tables(p).first);
    resizeZone(p, table, before, 2, 2, 'bottom-right');
    expect(table, before);
  });
  test('Overlapping zones create no alert, table-zone overlap still does', () {
    final p = demoProject();
    p['groups'] = [];
    final zone = rows(p, 'items').firstWhere((i) => i['kind'] == 'zone');
    p['items'] = [
      zone,
      {...zone, 'id': 'other', 'label': 'Zone bis'},
    ];
    expect(issues(p), isEmpty);
    final table = tables(demoProject()).first;
    table['x'] = zone['x'];
    table['y'] = zone['y'];
    p['items'].add(table);
    expect(issues(p).any((v) => v.contains('chevauchement')), true);
  });
}
