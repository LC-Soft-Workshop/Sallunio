import 'package:flutter_test/flutter_test.dart';
import 'package:tableo/domain.dart';
import 'package:tableo/csv_delta.dart';

Json g(String name, {int count = 2}) => {
  'id': uid(),
  'name': name,
  'count': count,
  'meal': 'Normal',
  'needs': '',
  'allergy': '',
  'alloc': <Json>[],
};
void main() {
  test(
    'Empty and new-only imports propose additions, preserve all configuration',
    () {
      final p = demoProject();
      clearReservations(p);
      p['attendanceTarget'] = 25;
      final before = clone(p);
      final plan = CsvImportPlan([], [g('Nouveau'), g('Autre')]);
      expect(plan.decisions, ['Ajouter distinct', 'Ajouter distinct']);
      applyCsvImport(p, plan);
      expect(rows(p, 'groups').length, 2);
      p['groups'] = <Json>[];
      expect(p, before);
    },
  );
  test('Identical reimport is clearly labelled and ignored without changing placement', () {
    final old = g('Camille');
    old['alloc'] = [
      {'table': 't', 'count': 2},
    ];
    final plan = CsvImportPlan([old], [g(' Camille ')]);
    expect(plan.decisions, ['Ignorer']);
    expect(plan.label(0), contains('identique'));
    final p = newProject('fictif');
    p['groups'] = [old];
    final before = clone(p);
    applyCsvImport(p, plan);
    expect(p, before);
  });
  test(
    'Mixed existing and new: changed homonym unresolved, new defaults to add',
    () {
      final old = g('Camille'), p = newProject('fictif');
      p['groups'] = [old];
      final plan = CsvImportPlan([old], [g('Camille', count: 3), g('Nouveau')]);
      expect(plan.decisions, [null, 'Ajouter distinct']);
      expect(() => applyCsvImport(p, plan), throwsFormatException);
      expect(rows(p, 'groups').length, 1);
      plan.decisions[0] = 'Mettre à jour';
      plan.targets[0] = old['id'];
      applyCsvImport(p, plan);
      expect(rows(p, 'groups').map((g) => g['count']), [3, 2]);
    },
  );
  test('Homonyms and internal duplicates require explicit decisions even on empty event', () {
    final old = [g('Alex'), g('Alex')];
    final plan = CsvImportPlan(old, [g('Alex')]);
    expect(plan.decisions, [null]);
    expect(plan.matches[0].length, 2);
    final duplicates = CsvImportPlan([], [g(' René '), g('rené', count: 3)]);
    expect(duplicates.hasDuplicates, true);
    expect(duplicates.decisions, [null, null]);
    expect(() => duplicates.validate(), throwsFormatException);
    duplicates.decisions[0] = 'Ajouter distinct';
    duplicates.decisions[1] = 'Ignorer';
    final p = newProject('fictif');
    applyCsvImport(p, duplicates);
    expect(rows(p, 'groups').length, 1);
  });
  test('Same-field duplicate CSV still unresolved, same target cannot be updated twice', () {
    final old = g('Alex'), plan = CsvImportPlan([old], [g('Alex'), g('Alex')]);
    expect(plan.decisions, [null, null]);
    plan.decisions[0] = 'Mettre à jour';
    plan.decisions[1] = 'Mettre à jour';
    plan.targets[0] = old['id'];
    plan.targets[1] = old['id'];
    expect(() => plan.validate(), throwsFormatException);
  });
}
