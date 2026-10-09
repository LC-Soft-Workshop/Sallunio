import 'domain.dart';

String reservationName(Json g) =>
    '${g['name']}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
bool sameReservation(Json a, Json b) => [
  'count',
  'meal',
  'needs',
  'allergy',
].every((k) => (a[k] ?? '') == (b[k] ?? ''));

class CsvImportPlan {
  final List<Json> incoming;
  final List<List<Json>> matches;
  final List<bool> duplicates;
  late final List<String?> decisions;
  late final List<String?> targets;
  CsvImportPlan(List<Json> existing, List<Json> source)
    : incoming = source.map(clone).toList(),
      matches = source
          .map(
            (g) => existing
                .where((old) => reservationName(old) == reservationName(g))
                .map(clone)
                .toList(),
          )
          .toList(),
      duplicates = source
          .map(
            (g) =>
                source
                    .where(
                      (other) => reservationName(other) == reservationName(g),
                    )
                    .length >
                1,
          )
          .toList() {
    decisions = List.generate(
      source.length,
      (i) => duplicates[i]
          ? null
          : matches[i].isEmpty
          ? 'Ajouter distinct'
          : matches[i].length == 1 &&
                sameReservation(matches[i].first, incoming[i])
          ? 'Ignorer'
          : null,
    );
    targets = List.filled(source.length, null);
  }
  bool get hasDuplicates => duplicates.any((v) => v);
  String label(int i) {
    if (duplicates[i]) {
      return 'Doublon potentiel dans le CSV : décision requise pour chaque ligne.';
    }
    if (matches[i].isEmpty) {
      return 'Nouvelle réservation : ajout proposé, aucune correspondance existante.';
    }
    if (matches[i].length == 1 &&
        sameReservation(matches[i].first, incoming[i])) {
      return 'Ligne identique aux champs du groupe existant : ignorer proposé. Aucun rapprochement d’identité automatique.';
    }
    return matches[i].length > 1
        ? 'Plusieurs groupes homonymes existants : choisir explicitement une action et une cible.'
        : 'Même référent, données différentes : choisir explicitement une action.';
  }

  void validate() {
    final used = <String>{};
    for (var i = 0; i < incoming.length; i++) {
      if (decisions[i] == null) {
        throw FormatException(
          'Ligne ${i + 2} : choisir une action pour la correspondance ou le doublon.',
        );
      }
      if (![
        'Ignorer',
        'Ajouter distinct',
        'Mettre à jour',
      ].contains(decisions[i])) {
        throw const FormatException('Décision invalide');
      }
      if (decisions[i] == 'Mettre à jour' &&
          (targets[i] == null ||
              !matches[i].any((g) => g['id'] == targets[i]) ||
              !used.add(targets[i]!))) {
        throw const FormatException(
          'Choisir une cible existante unique pour chaque mise à jour.',
        );
      }
    }
  }
}

void applyCsvImport(Json p, CsvImportPlan plan, {bool replace = false}) {
  plan.validate();
  // Check every target before making the first change.
  for (var i = 0; i < plan.incoming.length; i++) {
    if (plan.decisions[i] == 'Mettre à jour' &&
        !rows(p, 'groups').any((g) => g['id'] == plan.targets[i])) {
      throw const FormatException(
        'Groupe cible absent : refaire la prévisualisation.',
      );
    }
  }
  if (replace) clearReservations(p);
  for (var i = 0; i < plan.incoming.length; i++) {
    final g = plan.incoming[i];
    if (plan.decisions[i] == 'Ajouter distinct') {
      rows(p, 'groups').add(clone(g));
    }
    if (plan.decisions[i] == 'Mettre à jour') {
      final old = rows(
            p,
            'groups',
          ).firstWhere((g) => g['id'] == plan.targets[i]),
          previous = old['count'] as int;
      for (final k in ['name', 'count', 'meal', 'needs', 'allergy']) {
        old[k] = g[k];
      }
      resizeReservation(old, old['count'], previousCount: previous);
    }
  }
}
