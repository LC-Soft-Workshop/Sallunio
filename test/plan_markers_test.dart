import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/plan_export.dart';
import 'package:tableo/plan_marker.dart';

void main() {
  test('Meals and special needs remain distinguishable without color', () {
    expect(planMarkerShape('Mobilité / PMR'), PlanMarkerShape.hexagon);
    expect(planMarkerShape('Emplacement adapté'), PlanMarkerShape.hexagon);
    expect(planMarkerShape('Allergie'), PlanMarkerShape.triangle);
    for (final meal in [
      'Normal',
      'Végétarien',
      'Sans gluten',
      'Ne mange pas',
      'Personnalisé',
    ]) {
      expect(planMarkerShape('Repas : $meal'), PlanMarkerShape.circle);
    }
  });

  test('Default categories have separate colors, stable with custom meals', () {
    final p = newProject('Fictif');
    final colors = planMarkerColors(p);
    expect(colors.values.toSet().length, colors.length);
    p['meals'] = ['Personnalisé', ...p['meals'].reversed];
    final changed = planMarkerColors(p);
    for (final name in colors.keys) {
      expect(changed[name], colors[name]);
    }
    expect(colors['Repas : Normal'], 0xff1565c0);
    expect(colors['Repas : Végétarien'], 0xff2e7d32);
    expect(colors['Repas : Sans gluten'], 0xffef6c00);
    expect(colors['Repas : Ne mange pas'], 0xff37474f);
    p['meals'] = [...p['meals'], for (var i = 0; i < 20; i++) 'Menu $i'];
    final many = planMarkerColors(p);
    expect(many.values.toSet().length, many.length);
  });

  test('PDF markers retain the shared shape and color', () {
    for (final name in ['Mobilité / PMR', 'Allergie', 'Repas : Normal']) {
      final svg = planMarkerSvg(name, 0xff1565c0, 10, 20);
      expect(svg, contains('fill="#1565c0"'));
      if (name.startsWith('Repas')) {
        expect(svg, startsWith('<circle'));
      } else {
        expect(svg, startsWith('<polygon'));
        final points = RegExp('points="([^"]+)"')
            .firstMatch(svg)!
            .group(1)!
            .split(' ');
        expect(points.length, name == 'Allergie' ? 3 : 6);
      }
    }
  });

  testWidgets('All marker shapes paint at table and legend sizes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            for (final name in ['Mobilité / PMR', 'Allergie', 'Repas : Normal'])
              for (final size in [12.0, 16.0])
                PlanMarker(name: name, color: Colors.blue, size: size),
          ],
        ),
      ),
    );
    expect(find.byType(PlanMarker), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
