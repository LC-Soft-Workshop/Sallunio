part of 'main.dart';

extension _MixedFurnitureEditors on _HomeState {
  Future<void> assignmentSettings(Json event) async {
    final v = await form(
      'Attribution de l’événement',
      {
        'assignmentMode': eventAssignmentMode(event),
        'standUnit': event['standUnit'] ?? standUnits.first,
        'allowMixedStandTypes': mixedStandTypesAllowed(event) ? 'Oui' : 'Non',
        'seatingAssignment': event['seatingAssignment'] ?? 'Attribué',
      },
      {
        'assignmentMode': 'Usage principal des nouvelles réservations',
        'standUnit': 'Unité par défaut des stands',
        'allowMixedStandTypes': 'Autoriser des modèles différents pour un stand (tables ou mètres linéaires)',
        'seatingAssignment': 'Placement (libre : garde seulement les places manuelles/verrouillées)',
      },
      choices: {
        'assignmentMode': assignmentModes,
        'standUnit': standUnits,
        'allowMixedStandTypes': ['Non', 'Oui'],
        'seatingAssignment': ['Attribué', 'Libre'],
      },
    );
    if (v == null) return;
    void apply() {
      setSeatingAssignment(event, v['seatingAssignment']);
      v['allowMixedStandTypes'] = v['allowMixedStandTypes'] == 'Oui';
      event.addAll(v);
    }

    if (event['id'] == p?['id']) {
      change(apply);
    } else {
      apply();
      await widget.store.save(event);
    }
    toast(
      'Réglages enregistrés. Les pièces et réservations existantes conservent leur usage.',
    );
  }

  Future<void> standAllocationEdit(Json group) async {
    final draft = clone(p!);
    final g = rows(draft, 'groups').firstWhere((v) => v['id'] == group['id']);
    final ts = tables(draft)
        .where(
          (t) =>
              furnitureUse(t) == furnitureUses[1] &&
              !tableOutsideRoom(draft, t),
        )
        .toList();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: Text('Stand de ${g['name']}'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    g['standUnit'] == 'Mètres linéaires'
                        ? 'Demande : ${number(g['requestedMetres']).toStringAsFixed(2)} m'
                        : 'Demande : ${g['requestedTables'] ?? 1} table(s)',
                  ),
                  const Text(
                    'Le métrage correspond uniquement à la surface de table, sans les jonctions ni les allées.',
                  ),
                  for (final a in (g['standAlloc'] as List? ?? []).toList())
                    ListTile(
                      title: Text(
                        '${ts.where((t) => t['id'] == a['table']).firstOrNull?['label'] ?? 'Table'} — ${number(a['length']).toStringAsFixed(2)} m à partir de ${number(a['offset']).toStringAsFixed(2)} m',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            update(() => (g['standAlloc'] as List).remove(a)),
                      ),
                    ),
                  for (final t in ts)
                    ListTile(
                      title: Text(
                        '${t['label']} — ${standLength(t).toStringAsFixed(2)} m',
                      ),
                      subtitle: Text(
                        standPortions(draft, t['id'])
                            .map(
                              (a) =>
                                  '${a['name']} : ${number(a['length']).toStringAsFixed(2)} m',
                            )
                            .join(', '),
                      ),
                      trailing: OutlinedButton(
                        child: const Text('Attribuer'),
                        onPressed: () async {
                          final whole =
                              g['standUnit'] != 'Mètres linéaires' ||
                              g['shareTable'] == 'Non' ||
                              t['shape'] == 'cercle';
                          final values = whole
                              ? <String, dynamic>{
                                  'offset': 0.0,
                                  'length': standLength(t),
                                }
                              : await form(
                                  'Portion de ${t['label']}',
                                  {
                                    'offset':
                                        availableStandIntervals(
                                          draft,
                                          t,
                                        ).firstOrNull?.$1 ??
                                        0.0,
                                    'length':
                                        availableStandIntervals(
                                          draft,
                                          t,
                                        ).firstOrNull?.$2 ??
                                        standLength(t),
                                  },
                                  {
                                    'offset': 'Début (m)',
                                    'length': 'Longueur attribuée (m)',
                                  },
                                  numeric: {'offset', 'length'},
                                );
                          if (values == null) return;
                          try {
                            setStandPortion(
                              draft,
                              g,
                              t,
                              offset: number(values['offset']),
                              length: number(values['length']),
                              whole: whole,
                            );
                            update(() => error = null);
                          } catch (e) {
                            update(() => error = '$e');
                          }
                        },
                      ),
                    ),
                  CheckboxListTile(
                    title: const Text('Verrouiller ces attributions'),
                    value: g['locked'] == true,
                    onChanged: (v) => update(() => g['locked'] = v),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      change(() {
        group['standAlloc'] = g['standAlloc'];
        group['locked'] = g['locked'];
      });
    }
  }

  Future<void> seatFurnitureEdit(Json t) async {
    final v = await form(
      'Modifier ${t['label']}',
      {
        ...t,
        'usage': furnitureUse(t),
        'angle': number(t['angle']),
        'numberLocked': t['numberLocked'] == true ? 'Oui' : 'Non',
      },
      {
        'label': 'Numéro / libellé',
        'x': 'X (m)',
        'y': 'Y (m)',
        'usage': 'Usage',
        'angle': 'Orientation (degrés)',
        'numberLocked': 'Conserver ce numéro lors d’une renumérotation',
      },
      choices: {
        'usage': [furnitureUses.first, 'Service'],
        'numberLocked': ['Non', 'Oui'],
      },
      numeric: {'x', 'y', 'angle'},
    );
    if (v == null) return;
    v['numberLocked'] = v['numberLocked'] == 'Oui';
    if (furnitureUse(t) != furnitureUse(v) &&
        !await confirm(
          'Changer l’usage ?',
          'Les attributions seront retirées ; les réservations restent conservées.',
        )) {
      return;
    }
    change(() {
      if (furnitureUse(t) != furnitureUse(v)) {
        changeFurnitureUsage(p!, {t['id'] as String}, furnitureUse(v));
      }
      t.addAll(v);
    });
    await numberedSeatsEdit(t);
  }

  Future<void> numberedSeatsEdit(Json t) async {
    if (furnitureUse(t) != furnitureUses.first) return;
    final draft = clone(p!);
    final item = tables(draft).firstWhere((v) => v['id'] == t['id']);
    final cap = item['kind'] == 'table'
        ? effectiveCapacity(draft, item)
        : autonomousCapacity(draft, {...item, 'blockedSlots': []});
    final blocked = Set<int>.from(item['blockedSlots'] as List? ?? []);
    final candidates = <String, (Json, int)>{};
    for (final g in rows(
      draft,
      'groups',
    ).where((g) => !isStandBooking(g) && g['waiting'] != true)) {
      for (var n = 0; n < g['count']; n++) {
        candidates['${g['id']}:$n'] = (g, n);
      }
    }
    final choices = <int, String>{};
    for (final e in candidates.entries) {
      final seat = individualSeat(e.value.$1, e.value.$2);
      if (seat['table'] == t['id'] && seat['slot'] is int) {
        choices[seat['slot']] = e.key;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: Text('Places numérotées — ${t['label']}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Une attribution manuelle est conservée lors du placement automatique. Une place bloquée reste vide et réduit la capacité disponible.',
                  ),
                  for (var slot = 0; slot < cap; slot++)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('seat-$slot-${choices[slot]}'),
                            initialValue: choices[slot] ?? '',
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Place ${slot + 1}',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('Libre'),
                              ),
                              for (final e in candidates.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    '${e.value.$1['name']} — ${individualSeat(e.value.$1, e.value.$2)['name'].toString().isEmpty ? 'personne ${e.value.$2 + 1}' : individualSeat(e.value.$1, e.value.$2)['name']}',
                                  ),
                                ),
                            ],
                            onChanged: blocked.contains(slot)
                                ? null
                                : (v) => update(() => choices[slot] = v!),
                          ),
                        ),
                        Checkbox(
                          value: blocked.contains(slot),
                          onChanged: (v) => update(() {
                            if (v == true) {
                              blocked.add(slot);
                              choices.remove(slot);
                            } else {
                              blocked.remove(slot);
                            }
                          }),
                        ),
                        const Text('Bloquée'),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (choices.values.where((v) => v != '').toSet().length !=
                    choices.values.where((v) => v != '').length) {
                  toast('Une personne ne peut occuper deux places.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    change(() {
      t['blockedSlots'] = blocked.toList()..sort();
      for (final g in rows(p!, 'groups').where((g) => !isStandBooking(g))) {
        g['seats'] = List.generate(
          g['count'] as int,
          (n) => individualSeat(g, n),
        );
        for (final seat in (g['seats'] as List)) {
          if (seat['table'] == t['id']) {
            seat.remove('table');
            seat.remove('slot');
            seat.remove('fixed');
          }
        }
      }
      for (final e in choices.entries.where((e) => e.value != '')) {
        final pair = candidates[e.value]!;
        final g = rows(
          p!,
          'groups',
        ).firstWhere((v) => v['id'] == pair.$1['id']);
        final seat = g['seats'][pair.$2] as Json;
        seat['table'] = t['id'];
        seat['slot'] = e.key;
        seat['fixed'] = true;
      }
      rebuildSeatAllocations(p!);
    });
  }

  Future<void> audienceDisposition() async {
    if (arranging) return;
    final zones = rows(p!, 'items').where((t) => t['kind'] == 'zone').toList();
    if (zones.isEmpty) {
      toast('Créer une zone pour représenter la scène.');
      return;
    }
    final settings = p!['audienceSettings'] as Map? ?? {};
    final v = await form(
      'Disposition des sièges face à la scène',
      {
        'scene': settings['scene'] ?? zones.first['id'],
        'layout': settings['layout'] ?? audienceLayouts.first,
        'side': settings['side'] ?? 'Bas',
        'leftAngle': settings['leftAngle'] ?? 45,
        'rightAngle': settings['rightAngle'] ?? 45,
        'opening': settings['opening'] ?? 90,
        'fanClearanceAngle': settings['fanClearanceAngle'] ?? 30,
      },
      {
        'scene': 'Zone scène',
        'layout': 'Mode de déploiement',
        'side': 'Côté public par rapport à la scène',
        'leftAngle': 'Angle du bloc gauche (degrés)',
        'rightAngle': 'Angle du bloc droit (degrés)',
        'opening': 'Ouverture de l’arc (degrés)',
        'fanClearanceAngle':
            'Angle du dégagement près des coins de la scène (degrés)',
      },
      fieldVisible: (values, key) =>
          ![
            'leftAngle',
            'rightAngle',
            'opening',
            'fanClearanceAngle',
          ].contains(key) ||
          (key == 'opening'
              ? values['layout'] == audienceLayouts[2]
              : values['layout'] == audienceLayouts[1]),
      extraContent: const Text(
        'Les distances devant la scène, entre les rangées et entre les sièges se règlent dans Confort de l’événement.',
      ),
      choiceLabels: {
        for (final z in zones) z['id'] as String: proximityTargetName(z),
      },
      choices: {
        'scene': zones.map((z) => z['id'] as String).toList(),
        'layout': audienceLayouts,
        'side': seatingSideNames,
      },
      numeric: {'leftAngle', 'rightAngle', 'opening', 'fanClearanceAngle'},
    );
    if (v == null) return;
    if ([
          'leftAngle',
          'rightAngle',
          'fanClearanceAngle',
        ].any((k) => number(v[k]) < 0 || number(v[k]) > 75) ||
        number(v['opening']) < 10 ||
        number(v['opening']) > 160) {
      toast('Angles : 0 à 75° ; ouverture : 10 à 160°.');
      return;
    }
    refreshMixed(() => arranging = true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      var outside = 0;
      change(() {
        outside = arrangeAudience(p!, v);
        p!['arrangementMode'] = 'Scène';
      });
      toast(
        outside == 0
            ? 'Sièges disposés. Espacements réglés dans Confort.'
            : '$outside pièces hors salle : espace insuffisant.',
      );
    } catch (e) {
      toast('$e');
    } finally {
      if (mounted) refreshMixed(() => arranging = false);
    }
  }
}

Widget positionedFurniture(
  Json project,
  Json item,
  PlanGeometry geometry,
  double scale,
  Positioned original,
) => Positioned(
  key: ValueKey(('plan-layer', item['id'] as String, 'body')),
  left: original.left,
  top: original.top,
  child: Tooltip(
    message: furnitureTooltip(project, item, geometry),
    waitDuration: const Duration(milliseconds: 450),
    child: Transform.rotate(
      angle: number(item['angle']) * pi / 180,
      transformHitTests: true,
      child: original.child,
    ),
  ),
);

class StandPortionsPainter extends CustomPainter {
  final Json project, item;
  final bool showNames;
  StandPortionsPainter(this.project, this.item, {this.showNames = true});
  @override
  void paint(Canvas c, Size s) {
    final horizontal = number(item['w']) >= number(item['h']),
        length = standLength(item);
    for (final a in standPortions(project, item['id'])) {
      final start = number(a['offset']) / length,
          end = (number(a['offset']) + number(a['length'])) / length;
      c.drawRect(
        horizontal
            ? Rect.fromLTRB(s.width * start, 0, s.width * end, s.height)
            : Rect.fromLTRB(0, s.height * start, s.width, s.height * end),
        Paint()..color = Color(a['color'] as int),
      );
      if (!showNames) continue;
      final rect = horizontal
          ? Rect.fromLTRB(s.width * start, 0, s.width * end, s.height)
          : Rect.fromLTRB(0, s.height * start, s.width, s.height * end);
      final text = TextPainter(
        text: TextSpan(
          text: a['name'].toString(),
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'Roboto',
            color: Color(0xff123c38),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: max(0, rect.width - 4));
      if (rect.width > 12 && rect.height > 12) {
        text.paint(
          c,
          Offset(
            rect.center.dx - text.width / 2,
            rect.center.dy - text.height / 2,
          ),
        );
      }
    }
    if (standPortions(project, item['id']).isNotEmpty) {
      final label = TextPainter(
        text: TextSpan(
          text: item['label'].toString(),
          style: const TextStyle(
            fontSize: 8,
            fontFamily: 'Roboto',
            color: Color(0xff123c38),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: s.width);
      label.paint(c, const Offset(3, 2));
    }
  }

  @override
  bool shouldRepaint(covariant StandPortionsPainter oldDelegate) => true;
}

class SeatNumbers extends StatelessWidget {
  final Json project, item;
  const SeatNumbers(this.project, this.item, {super.key});
  @override
  Widget build(BuildContext context) {
    final count = autonomousCapacity(project, {...item, 'blockedSlots': []});
    return Flex(
      direction: number(item['w']) >= number(item['h'])
          ? Axis.horizontal
          : Axis.vertical,
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Text(
                '${i + 1}${(item['blockedSlots'] as List? ?? []).contains(i) ? ' ×' : ''}',
                style: const TextStyle(fontSize: 9, color: Color(0xff123c38)),
              ),
            ),
          ),
      ],
    );
  }
}
