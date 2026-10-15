part of 'main.dart';

extension _OrganizerEditors on _HomeState {
  Set<String> selectedPlanIds() => {
    ...selectedObjects,
    ...selectedTables,
    ?selected,
  };
  void runOrganizerChange(VoidCallback action) {
    try {
      change(action);
    } catch (e) {
      toast('$e');
    }
  }

  void organizerTool(String tool) {
    switch (tool) {
      case 'search':
        searchPlanDialog();
      case 'align':
        alignmentDialog();
      case 'duplicate':
        runOrganizerChange(() => duplicatePlanSelection(p!, selectedPlanIds()));
      case 'properties':
        bulkPropertiesEditor();
      case 'numbers':
        renumberDialog();
    }
  }

  void finishRectangleSelection() {
    if (selectionStart == null || selectionEnd == null) return;
    if ((selectionEnd! - selectionStart!).distance * planScale < 4) {
      final point = selectionEnd!;
      selectionStart = selectionEnd = null;
      selectionRectangle.value = null;
      final hit = planItemAt(point);
      if (hit != null) {
        selectPlanItem(
          hit,
          additive: HardwareKeyboard.instance.isControlPressed,
          toggleHandles: true,
        );
      } else if (!HardwareKeyboard.instance.isControlPressed) {
        clearPlanSelection();
      }
      return;
    }

    final ids = {
      ...selectionBase,
      ...rectangleSelection(
        p!,
        selectionStart!.dx,
        selectionStart!.dy,
        selectionEnd!.dx,
        selectionEnd!.dy,
      ),
    };
    selectionRectangle.value = null;
    final furnitureIds = tables(p!).map((t) => t['id']).toSet();
    refreshMixed(() {
      rotationMode = false;
      selectedObjects.clear();
      selectedObjects.addAll(ids);
      selectedTables.clear();
      selectedTables.addAll(ids.where(furnitureIds.contains));
      selected = ids.isEmpty ? null : ids.last;
      selectionStart = selectionEnd = null;
    });
  }

  Future<void> searchPlanDialog() async {
    var query = '';
    final id = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: const Text('Rechercher sur le plan'),
          content: SizedBox(
            width: 520,
            height: 380,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Numéro, modèle, groupe ou personne',
                  ),
                  onChanged: (value) => update(() => query = value),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final item in searchPlanItems(p!, query))
                        ListTile(
                          title: Text(furnitureShortLabel(item)),
                          subtitle: Text(
                            furnitureTooltip(
                              p!,
                              item,
                            ).split('\n').take(3).join(' • '),
                          ),
                          onTap: () => Navigator.pop(c, item['id']),
                        ),
                    ],
                  ),
                ),
                if (searchPlanItems(p!, query).isEmpty)
                  const Text(
                    'Aucun emplacement correspondant. Une réservation sans attribution ne peut pas être localisée.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Fermer'),
            ),
          ],
        ),
      ),
    );
    if (id != null && mounted) {
      focusPlanItem(rows(p!, 'items').firstWhere((i) => i['id'] == id));
    }
  }

  Future<void> alignmentDialog() async {
    if (planReadOnly) return;
    final options = [
      'Aligner à gauche',
      'Aligner à droite',
      'Aligner en haut',
      'Aligner en bas',
      'Centrer horizontalement',
      'Centrer verticalement',
      'Répartir horizontalement',
      'Répartir verticalement',
    ];
    final values = await form(
      'Aligner ou répartir',
      {'action': options.first},
      {'action': 'Action'},
      choices: {'action': options},
    );
    if (values != null) {
      runOrganizerChange(
        () => alignFurnitureSelection(p!, selectedPlanIds(), values['action']),
      );
    }
  }

  Future<void> bulkPropertiesEditor() async {
    if (planReadOnly) return;
    final ids = selectedPlanIds();
    if (ids.isEmpty) {
      toast('Sélectionner des pièces.');
      return;
    }
    const keep = 'Ne pas modifier';
    final items = rows(
      p!,
      'items',
    ).where((i) => ids.contains(i['id'])).toList();
    const fieldNames = {
      'usage': 'usage',
      'capacity': 'capacité',
      'sides': 'côtés assis',
      'seatSide': 'côté assis',
      'seating': 'assises',
      'joinGap': 'écart de jonction',
      'note': 'note',
    };
    final mixed =
        ['usage', 'capacity', 'sides', 'seatSide', 'seating', 'joinGap', 'note']
            .where((k) => items.map((i) => '${i[k]}').toSet().length > 1)
            .map((k) => fieldNames[k]!)
            .join(', ');
    final value = await form(
      'Propriétés de ${ids.length} pièces',
      {
        'usage': keep,
        'sides': keep,
        'seatSide': keep,
        'seating': keep,
        'capacityApply': 'Non',
        'capacity': 6,
        'joinMode': keep,
        'joinGap': 0.0,
        'joinGapSides': joinGapSideNames.first,
        'noteApply': 'Non',
        'note': '',
        'numberLocked': keep,
      },
      {
        'usage': 'Usage',
        'sides': 'Côtés assis (tables)',
        'seatSide': 'Côté assis (tables)',
        'seating': 'Assises (tables)',
        'capacityApply': 'Modifier la capacité des tables',
        'capacity': 'Capacité des tables',
        'joinMode': 'Jonctions des tables',
        'joinGap': 'Écart de jonction (m)',
        'joinGapSides': 'Bords concernés',
        'noteApply': 'Appliquer la note à la sélection',
        'note': 'Note',
        'numberLocked': 'Conserver les numéros',
      },
      extraContent: Text(
        mixed.isEmpty
            ? 'Les valeurs communes peuvent être modifiées.'
            : 'Valeurs différentes dans la sélection : $mixed. Les champs Ne pas modifier sont conservés.',
      ),
      choices: {
        'usage': [keep, ...furnitureUses],
        'sides': [keep, ...seatingModes],
        'seatSide': [keep, ...seatingSideNames],
        'seating': [keep, 'Chaises', 'Bancs', 'Mixte'],
        'capacityApply': ['Non', 'Oui'],
        'joinMode': [keep, 'Hériter', 'Personnaliser'],
        'joinGapSides': joinGapSideNames,
        'noteApply': ['Non', 'Oui'],
        'numberLocked': [keep, 'Non', 'Oui'],
      },
      integer: {'capacity'},
      numeric: {'joinGap'},
    );
    if (value == null) return;
    final changes = <String, dynamic>{
      for (final k in ['usage', 'sides', 'seatSide', 'seating'])
        if (value[k] != keep) k: value[k],
    };
    if (value['capacityApply'] == 'Oui') {
      changes['capacity'] = value['capacity'];
    }
    if (value['noteApply'] == 'Oui') changes['note'] = value['note'];
    if (value['numberLocked'] != keep) {
      changes['numberLocked'] = value['numberLocked'] == 'Oui';
    }
    if (value['joinMode'] != 'Ne pas modifier') {
      changes['joinGap'] = value['joinMode'] == 'Hériter'
          ? null
          : value['joinGap'];
      changes['joinGapSides'] = value['joinGapSides'];
    }
    if (changes.isEmpty) return;
    if (!await confirm(
      'Appliquer à la sélection ?',
      'Seuls les champs choisis seront modifiés. Un changement d’usage retire les assignations incompatibles. Positions et rotations conservées.',
    )) {
      return;
    }
    runOrganizerChange(() => bulkFurnitureProperties(p!, ids, changes));
  }

  Future<void> renumberDialog() async {
    if (planReadOnly) return;
    var order = 'Rangées';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final labels = renumberingPreview(p!, order);
          return KeyboardDialog(
            title: const Text('Renuméroter volontairement'),
            content: SizedBox(
              width: 540,
              height: 420,
              child: Column(
                children: [
                  const Text(
                    'Si vous avez déjà imprimé des étiquettes ou des documents, ils ne correspondront plus aux nouveaux numéros. Aucune renumérotation automatique. Annuler dans l’application permet de revenir en arrière.',
                  ),
                  DropdownButton<String>(
                    value: order,
                    items: [
                      for (final v in ['Rangées', 'Colonnes'])
                        DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'Rangées'
                                ? 'De haut en bas, de gauche à droite'
                                : 'De gauche à droite, de haut en bas',
                          ),
                        ),
                    ],
                    onChanged: (v) => update(() => order = v!),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final item in tables(p!))
                          ListTile(
                            dense: true,
                            title: Text(
                              '${furnitureShortLabel(item)} → ${labels[item['id']] ?? furnitureShortLabel(item)}${item['numberLocked'] == true ? ' (numéro conservé)' : ''}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Valider les nouveaux numéros'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true) {
      runOrganizerChange(
        () => applyRenumbering(p!, renumberingPreview(p!, order)),
      );
    }
  }

  Widget reservationFilterBar() {
    final filters = [
      'Toutes',
      'Confirmées',
      'Liste d’attente',
      'Attribution complète',
      'Attribution partielle',
      'Sans attribution',
      'Mobilité / PMR',
      if (mealsEnabled(p!))
        for (final meal in p!['meals']) 'Repas : $meal',
      for (final model in rows(p!, 'types')) 'Modèle : ${model['id']}',
    ];
    if (!filters.contains(reservationFilter)) reservationFilter = 'Toutes';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: PopupMenuButton<String>(
              tooltip: 'Filtrer les réservations',
              onSelected: (value) =>
                  refreshMixed(() => reservationFilter = value),
              itemBuilder: (_) => [
                for (final value in filters)
                  PopupMenuItem(
                    value: value,
                    child: Text(
                      value.startsWith('Modèle : ')
                          ? 'Modèle : ${rows(p!, 'types').firstWhere((t) => t['id'] == value.substring(9))['name']}'
                          : value,
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    Text(reservationFilter),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
          Text(
            '${rows(p!, 'groups').where((g) => g['waiting'] == true).length} en attente',
          ),
        ],
      ),
    );
  }

  Future<void> waitingStatusEditor(Json group) async {
    if (eventReadOnly) return;
    final waiting = group['waiting'] != true;
    if (waiting &&
        !await confirm(
          'Mettre en liste d’attente ?',
          'La réservation est conservée ; ses assignations seront retirées et elle sera exclue de l’attribution automatique jusqu’à confirmation.',
        )) {
      return;
    }
    runOrganizerChange(() => setWaitingStatus(p!, group, waiting));
  }

  Future<void> swapReservationsEditor(Json group) async {
    if (eventReadOnly) return;
    final others = rows(
      p!,
      'groups',
    ).where((g) => g['id'] != group['id'] && g['waiting'] != true).toList();
    if (others.isEmpty) {
      toast('Aucune autre réservation confirmée.');
      return;
    }
    final value = await form(
      'Échanger les assignations',
      {'other': others.first['id']},
      {'other': 'Autre réservation'},
      choices: {'other': others.map((g) => g['id'] as String).toList()},
      choiceLabels: {for (final g in others) g['id']: g['name']},
    );
    if (value == null) return;
    final preview = clone(p!);
    try {
      swapReservationAssignments(preview, group['id'], value['other']);
    } catch (e) {
      toast('$e');
      return;
    }
    final checks = {
      ...reservationPreferenceChecks(preview),
      ...issues(preview),
    }.toList();
    if (!await confirm(
      'Confirmer l’échange ?',
      'Les noms et besoins restent liés à leurs réservations. Les quantités attribuées doivent être équivalentes.\n${checks.isEmpty ? 'Aucune alerte de préférence détectée.' : checks.join('\n')}',
    )) {
      return;
    }
    runOrganizerChange(
      () => swapReservationAssignments(p!, group['id'], value['other']),
    );
  }
}

class _PlanReview {
  final PlanGeometry geometry;
  final List<String> alerts;
  late final List<Json> assignments;
  late final Json stats;
  late final Set<String> conflicts;
  _PlanReview(Json project)
    : geometry = PlanGeometry(project, physicalPlanItems(project)),
      alerts = issues(project) {
    assignments = tableAssignments(project, geometry);
    stats = workspaceStats(project, assignments);
    final items = physicalPlanItems(project);
    conflicts = {
      for (final item in tables(project))
        if (!fits(project, item, items, geometry: geometry))
          item['id'] as String,
    };
  }
}

class SelectionRectanglePainter extends CustomPainter {
  final ValueNotifier<Rect?> rectangle;
  SelectionRectanglePainter(this.rectangle) : super(repaint: rectangle);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = rectangle.value;
    if (rect == null) return;
    canvas.drawRect(rect, Paint()..color = const Color(0x332196f3));
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xff1565c0),
    );
  }

  @override
  bool shouldRepaint(covariant SelectionRectanglePainter old) =>
      old.rectangle != rectangle;
}
