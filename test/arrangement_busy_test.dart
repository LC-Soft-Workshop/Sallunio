import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/main.dart';

import 'parcours_ui_test.dart' show desktop;
import 'ui_test.dart' show MemoryStore;

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'Calculation stays visible, blocks retries and ${fail ? 'preserves the plan on failure' : 'commits once and supports undo'}',
      (tester) async {
        desktop(tester);
        final p = demoProject(), before = clone(p), job = Completer<Json>();
        Json? input;
        var calls = 0;
        await tester.pumpWidget(
          Tableo(
            store: MemoryStore([p]),
            arrangementRunner: (draft) {
              calls++;
              input = draft;
              return job.future;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disposer tables'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Disposer'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(calls, 1);
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.text('Disposition en cours…'), findsWidgets);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Disposition en cours…'),
        );
        expect(button.onPressed, isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump(const Duration(milliseconds: 300));
        expect(calls, 1);
        expect(p, before);
        if (fail) {
          job.completeError(StateError('Erreur fictive'));
        } else {
          job.complete(arrangeProject(input!));
        }
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Disposer tables'),
              )
              .onPressed,
          isNotNull,
        );
        if (fail) {
          expect(p, before);
          expect(
            find.textContaining('Le plan précédent est conservé'),
            findsOneWidget,
          );
        } else {
          await tester.tap(find.byTooltip('Annuler'));
          await tester.pumpAndSettle();
          expect(p, before);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'Real background worker returns a changed copy and leaves its input intact',
    () async {
      final p = demoProject(), before = clone(p);
      final result = await arrangeInBackground(p);
      expect(p, before);
      expect(result['items'], isNotEmpty);
      expect(identical(p, result), false);
    },
  );
}
