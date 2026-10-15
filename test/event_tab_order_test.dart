import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';
import 'package:tableo/storage.dart';

import 'ui_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'Dragging event tabs preserves active event and reloads saved order',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = [
        for (final name in ['A', 'B', 'C'])
          newProject('Fictif $name')..['id'] = name,
      ];
      final store = MemoryStore(events);
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      final a = find.byKey(const ValueKey('event-tab-A')),
          c = find.byKey(const ValueKey('event-tab-C'));
      await tester.timedDrag(
        a,
        tester.getCenter(c) - tester.getCenter(a) + const Offset(50, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(store.eventOrder, ['B', 'C', 'A']);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .singleWhere((w) => w.selected)
            .label,
        isA<Text>().having((t) => t.data, 'active', 'Fictif A'),
      );
      expect(events.map((e) => e['id']), unorderedEquals(['A', 'B', 'C']));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(Tableo(store: store));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(const ValueKey('event-tab-B'))).dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('event-tab-A'))).dx,
        ),
      );
    },
  );
  test('Stored tab order survives reopening and edits without changing projects', () async {
    Directory('tmp').createSync(recursive: true);
    final folder = Directory('tmp').createTempSync('event-order-');
    final store = Store();
    await store.open(path: folder.path);
    try {
      final events = [
        for (final id in ['a', 'b', 'c']) newProject('Fictif $id')..['id'] = id,
      ];
      for (final e in events) {
        await store.save(e);
      }
      await store.saveEventOrder(['b', 'c', 'a']);
      await store.save(events[1]..['name'] = 'Fictif renommé');
      await store.close();
      await store.open(path: folder.path);
      expect(store.orderedEvents(await store.load()).map((e) => e['id']), [
        'b',
        'c',
        'a',
      ]);
      final d = newProject('Nouveau fictif')..['id'] = 'd';
      await store.save(d);
      await store.delete('c');
      expect(store.orderedEvents(await store.load()).map((e) => e['id']), [
        'b',
        'a',
        'd',
      ]);
    } finally {
      await store.close();
      expect(
        folder.resolveSymbolicLinksSync().startsWith(
          '${Directory('tmp').resolveSymbolicLinksSync()}${Platform.pathSeparator}',
        ),
        isTrue,
      );
      folder.deleteSync(recursive: true);
    }
  });
}
