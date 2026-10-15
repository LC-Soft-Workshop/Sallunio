part of 'main.dart';

extension _PlanWorkspace on _HomeState {
  void reorderPlanSelection(String action) {
    if (planReadOnly) return;
    final ids = selectedPlanIds();
    if (rows(
      p!,
      'items',
    ).any((i) => ids.contains(i['id']) && i['fixed'] == true)) {
      return;
    }
    change(() => changePlanLayer(p!, ids, action));
  }

  List<Widget> orderedPlanWidgets(List<Widget> children) {
    final ranks = {
      for (final (n, item) in planPaintOrder(p!).indexed) item['id']: n,
    };
    String? layerId(Widget w) {
      final key = w.key;
      final value = key is ValueKey ? key.value : null;
      return value is (String, String, String) && value.$1 == 'plan-layer'
          ? value.$2
          : null;
    }

    final layered =
        children.indexed.where((e) => layerId(e.$2) != null).toList()
          ..sort((a, b) {
            final rank = (ranks[layerId(a.$2)] ?? 0).compareTo(
              ranks[layerId(b.$2)] ?? 0,
            );
            return rank != 0 ? rank : a.$1.compareTo(b.$1);
          });
    var n = 0;
    return [
      for (final child in children)
        layerId(child) == null ? child : layered[n++].$2,
    ];
  }

  Json? planItemAt(Offset point) => planPaintOrder(p!).reversed.where((item) {
    final angle = -number(item['angle']) * pi / 180;
    final dx = point.dx - number(item['x']) - number(item['w']) / 2,
        dy = point.dy - number(item['y']) - number(item['h']) / 2;
    final x = dx * cos(angle) - dy * sin(angle),
        y = dx * sin(angle) + dy * cos(angle);
    return x.abs() <= number(item['w']) / 2 && y.abs() <= number(item['h']) / 2;
  }).firstOrNull;
  void endRectanglePointer() {
    if (selectionStart != null &&
        selectionEnd != null &&
        (selectionEnd! - selectionStart!).distance * planScale >= 4) {
      finishRectangleSelection();
    }
  }

  void rectangleDoubleClick() {
    final point = selectionEnd ?? selectionStart;
    selectionStart = selectionEnd = null;
    selectionRectangle.value = null;
    final item = point == null ? null : planItemAt(point);
    if (item == null) {
      clearPlanSelection();
      return;
    }
    selectPlanItem(item);
    if (!planReadOnly) itemEdit(item);
  }

  void clearPlanSelection() => refreshMixed(() {
    rotationMode = false;
    rotationDrag = null;
    selected = null;
    selectedTables.clear();
    selectedObjects.clear();
  });
  void savePlanView() {
    if (p == null || eventReadOnly) return;
    p!['planView'] = {
      'matrix': transform.value.storage.toList(),
      'legend': showLegend,
      'names': showPlaceLabels,
    };
  }

  void restorePlanView() {
    rotationMode = false;
    rotationDrag = null;
    final view = p?['planView'] as Map?;
    final values = view?['matrix'] as List?;
    transform.value = values != null && values.length == 16
        ? Matrix4.fromList(values.map((v) => number(v)).toList())
        : Matrix4.identity();
    showLegend = true;
    showPlaceLabels = view?['names'] == true;
  }

  void resetPlanView() {
    refreshMixed(() => transform.value = Matrix4.identity());
    savePlanView();
    persist();
  }

  void zoomPlan(double factor) {
    final current = transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(.4, 5.0);
    final matrix = transform.value.clone()
      ..scaleByDouble(next / current, next / current, 1, 1);
    refreshMixed(() => transform.value = matrix);
    savePlanView();
    persist();
  }

  void focusPlanItem(Json item) {
    selectPlanItem(item, additive: false);
    final center =
        planOrigin +
        Offset(
          (number(item['x']) + number(item['w']) / 2) * planScale,
          (number(item['y']) + number(item['h']) / 2) * planScale,
        );
    final matrix = Matrix4.identity()
      ..translateByDouble(
        planOrigin.dx +
            number(p!['room']['width']) * planScale / 2 -
            center.dx * 1.5,
        planOrigin.dy +
            number(p!['room']['height']) * planScale / 2 -
            center.dy * 1.5,
        0,
        1,
      )
      ..scaleByDouble(1.5, 1.5, 1, 1);
    refreshMixed(() => transform.value = matrix);
    savePlanView();
    persist();
  }

  Widget selectionSummary() {
    final ids = {...selectedObjects, ...selectedTables};
    final selectedItems = rows(
      p!,
      'items',
    ).where((i) => ids.contains(i['id'])).toList();
    final kinds = <String, int>{};
    for (final i in selectedItems) {
      final name = switch (i['kind']) {
        'chair' => 'chaise(s)',
        'bench' => 'banc(s)',
        'table' => 'table(s)',
        'pmr' => 'emplacement(s) PMR',
        _ => 'objet(s)',
      };
      kinds.update(name, (v) => v + 1, ifAbsent: () => 1);
    }
    var groups = 0;
    final visited = <String>{};
    final geo = PlanGeometry(p!, rows(p!, 'items'));
    for (final item in selectedItems.where((i) => i['kind'] == 'table')) {
      if (visited.contains(item['id'])) continue;
      groups++;
      visited.addAll(
        tables(p!)
            .where((t) => geo.sameAssembly(item, t))
            .map((t) => t['id'] as String),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selectedItems.isEmpty
                  ? 'Aucune sélection'
                  : '${moveAssembly ? '$groups groupe(s) • ' : ''}${kinds.entries.map((e) => '${e.value} ${e.key}').join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selectedItems.isNotEmpty)
            IconButton(
              tooltip: 'Désélectionner — Échap',
              onPressed: clearPlanSelection,
              icon: const Icon(Icons.close, size: 18),
            ),
          IconButton(
            key: const ValueKey('plan-zoom-out'),
            tooltip: 'Dézoomer',
            onPressed: () => zoomPlan(1 / 1.25),
            icon: const Icon(Icons.remove, size: 18),
          ),
          ValueListenableBuilder<Matrix4>(
            valueListenable: transform,
            builder: (_, v, child) =>
                Text('${(v.getMaxScaleOnAxis() * 100).round()} %'),
          ),
          IconButton(
            key: const ValueKey('plan-zoom-in'),
            tooltip: 'Zoomer',
            onPressed: () => zoomPlan(1.25),
            icon: const Icon(Icons.add, size: 18),
          ),
          IconButton(
            tooltip: 'Ajuster à la salle',
            onPressed: resetPlanView,
            icon: const Icon(Icons.fit_screen, size: 18),
          ),
        ],
      ),
    );
  }

  int availableFurniture(Json model) => max(
    0,
    min(model['limit'] as int, model['quantity'] as int) -
        rows(p!, 'items').where((i) => i['type'] == model['id']).length,
  );
  Future<void> addFurnitureQuantity(Json model) async {
    if (planReadOnly) return;
    final available = availableFurniture(model);
    if (available == 0 || model['enabled'] != true) return;
    if (available == 1) {
      addTables([model]);
      return;
    }
    var input = '1';
    final amount = await showDialog<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final count = int.tryParse(input);
          final valid = count != null && count > 0 && count <= available;
          return KeyboardDialog(
            title: Text('Ajouter ${model['name']}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Encore disponibles sur le plan : $available'),
                TextFormField(
                  key: const ValueKey('add-furniture-quantity'),
                  initialValue: input,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantité à ajouter',
                    errorText: valid ? null : 'Choisir de 1 à $available',
                  ),
                  onChanged: (value) => update(() => input = value),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: valid ? () => Navigator.pop(c, count) : null,
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
    if (amount != null && mounted) addTables([model], requestedCount: amount);
  }

  void addPmrPlace() {
    if (planReadOnly) return;
    final item = <String, dynamic>{
      'id': uid(),
      'kind': 'pmr',
      'shape': 'emplacement PMR',
      'label': 'PMR ${tables(p!).where((i) => i['kind'] == 'pmr').length + 1}',
      'x': 1.0,
      'y': 1.0,
      'w': number(eventComfort(p!)['pmrSeatWidth']),
      'h': number(eventComfort(p!)['pmrDepth']),
      'capacity': 1,
      'fixed': false,
      'usage': furnitureUses.first,
    };
    final positioned = findPosition(p!, item, rows(p!, 'items'));
    if (positioned == null) {
      toast('Aucun emplacement disponible pour cet emplacement PMR.');
      return;
    }
    change(() => rows(p!, 'items').add(positioned));
  }

  Widget addPlanMenu() => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: SizedBox(
      width: 38,
      height: 38,
      child: MenuAnchor(
        builder: (c, controller, child) => IconButton(
          key: const ValueKey('plan-tool-add'),
          tooltip: 'Ajouter',
          padding: EdgeInsets.zero,
          icon: toolFace(Icons.add_box_outlined),
          onPressed: planReadOnly
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
        ),
        menuChildren: [
          SubmenuButton(
            menuChildren: [
              for (final model in rows(p!, 'types'))
                MenuItemButton(
                  key: ValueKey('add-table-type-${model['id']}'),
                  onPressed:
                      availableFurniture(model) > 0 && model['enabled'] == true
                      ? () => addFurnitureQuantity(model)
                      : null,
                  child: Tooltip(
                    message: availableFurniture(model) == 0
                        ? 'Maximum autorisé atteint : ${min(model['quantity'] as int, model['limit'] as int)} élément(s) de mobilier.'
                        : model['enabled'] != true
                        ? 'Mobilier exclu de cet événement'
                        : '${availableFurniture(model)} encore disponibles',
                    child: Text(
                      '${model['name']} — ${availableFurniture(model)} disponibles',
                    ),
                  ),
                ),
            ],
            child: const Text('Mobilier'),
          ),
          MenuItemButton(
            onPressed: addPmrPlace,
            child: const Text('Emplacement PMR'),
          ),
          for (final kind in [
            'zone',
            'obstacle',
            'entry',
            'exit',
            'door',
            'info',
            'text',
            'image',
            'arrow',
          ])
            MenuItemButton(
              onPressed: () => addObject(kind),
              child: Text(objectLabels[kind] ?? kind),
            ),
        ],
      ),
    ),
  );
  void planBackgroundContext(PointerDownEvent event) {
    final pos = event.localPosition / planScale;
    if (rows(p!, 'items').any(
      (i) =>
          pos.dx >= number(i['x']) &&
          pos.dx <= number(i['x']) + number(i['w']) &&
          pos.dy >= number(i['y']) &&
          pos.dy <= number(i['y']) + number(i['h']),
    )) {
      return;
    }
    planContextMenu(event.position);
  }

  Future<void> planContextMenu(Offset position, [Json? item]) async {
    if (item != null && !selectedObjects.contains(item['id'])) {
      selectPlanItem(item, additive: false);
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: item == null
          ? [
              PopupMenuItem(
                enabled: !planReadOnly,
                value: 'add',
                child: Text('Ajouter du mobilier…'),
              ),
              PopupMenuItem(
                enabled: !planReadOnly,
                value: 'zone',
                child: Text('Ajouter une zone…'),
              ),
              PopupMenuItem(
                enabled: !planReadOnly,
                value: 'clear',
                child: Text('Vider la salle…'),
              ),
            ]
          : [
              PopupMenuItem(
                value: 'edit',
                enabled: !planReadOnly,
                child: const Text('Modifier'),
              ),
              PopupMenuItem(
                value: 'rotate',
                enabled: !planReadOnly && item['fixed'] != true,
                child: const Text('Pivoter 90°'),
              ),
              for (final entry in planLayerActions.entries)
                PopupMenuItem(
                  value: entry.key,
                  enabled: !planReadOnly && item['fixed'] != true,
                  child: Text(entry.value),
                ),
              PopupMenuItem(
                value: 'lock',
                enabled: !planReadOnly,
                child: Text(
                  item['fixed'] == true ? 'Déverrouiller' : 'Verrouiller',
                ),
              ),
              PopupMenuItem(
                value: 'remove',
                enabled: !planReadOnly && item['fixed'] != true,
                child: const Text('Retirer'),
              ),
            ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        if (selectedTables.length > 1) {
          bulkPropertiesEditor();
        } else {
          itemEdit(item!);
        }
      case 'rotate':
        rotatePlanSelection(item);
      case 'front':
      case 'back':
      case 'forward':
      case 'backward':
        reorderPlanSelection(choice);
      case 'lock':
        change(() => item!['fixed'] = item['fixed'] != true);
      case 'remove':
        removePlanSelection();
      case 'zone':
        addObject('zone');
      case 'clear':
        roomClear();
      case 'add':
        final models = rows(p!, 'types');
        final chosen = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(position.dx, position.dy, 1, 1),
            Offset.zero & overlay.size,
          ),
          items: [
            for (final m in models)
              PopupMenuItem(
                value: m['id'],
                enabled: availableFurniture(m) > 0 && m['enabled'] == true,
                child: Text(
                  '${m['name']} — ${availableFurniture(m)} disponibles',
                ),
              ),
          ],
        );
        if (chosen != null && mounted) {
          addFurnitureQuantity(models.firstWhere((m) => m['id'] == chosen));
        }
    }
  }
}
