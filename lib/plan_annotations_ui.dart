part of 'main.dart';

extension _PlanAnnotations on _HomeState {
  Future<void> imageEditor([Json? item]) async {
    if (planReadOnly) return;
    String? data = item?['imageData'];
    var label = item?['label'] ?? 'Image';
    double w = number(item?['w'], 3), h = number(item?['h'], 2);
    if (item == null) {
      final path = await (widget.fileDialogs ?? WindowsFileDialogs()).choose(
        FileRequest(
          title: 'Ajouter une image au plan',
          initialPath:
              '${widget.store.directory}${Platform.pathSeparator}image.png',
          extension: 'image',
          description: 'Images PNG ou JPEG',
          save: false,
        ),
      );
      if (path == null || !mounted || planReadOnly) return;
      try {
        final file = File(path);
        if (await file.length() > 10000000) {
          throw const FormatException('L’image doit peser moins de 10 Mo.');
        }
        final bytes = await file.readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        final targetWidth = min(
          descriptor.width,
          min(1600, (1600 * descriptor.width / descriptor.height).round()),
        ).clamp(1, 1600);
        descriptor.dispose();
        buffer.dispose();
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: targetWidth,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            data = base64Encode(
              png!.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
            );
            if (data.length > 16000000) {
              throw const FormatException(
                'Image trop volumineuse après conversion.',
              );
            }
            h = w * frame.image.height / frame.image.width;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
        label = path.split(RegExp(r'[\\/]')).last;
      } catch (e) {
        toast('Impossible de lire cette image PNG ou JPEG : $e');
        return;
      }
    }
    if (!mounted || planReadOnly) return;
    final value = await form(
      item == null ? 'Ajouter une image' : 'Modifier l’image',
      {
        'label': label,
        'w': w,
        'h': h,
        'fixed': item?['fixed'] == true ? 'Oui' : 'Non',
      },
      {
        'label': 'Nom de l’image',
        'w': 'Largeur (m)',
        'h': 'Hauteur (m)',
        'fixed': 'Position fixée',
      },
      choices: {
        'fixed': ['Non', 'Oui'],
      },
      numeric: {'w', 'h'},
    );
    if (value == null || planReadOnly) return;
    if (number(value['w']) <= 0 ||
        number(value['h']) <= 0 ||
        !number(value['w']).isFinite ||
        !number(value['h']).isFinite) {
      toast('Les dimensions doivent être positives.');
      return;
    }
    change(() {
      if (item != null) {
        item.addAll(value);
        item['fixed'] = value['fixed'] == 'Oui';
      } else {
        final image = <String, dynamic>{
          ...value,
          'id': uid(),
          'kind': 'image',
          'shape': 'rectangle',
          'x': 1.0,
          'y': 1.0,
          'angle': 0.0,
          'fixed': value['fixed'] == 'Oui',
          'imageData': data,
        };
        rows(p!, 'items').add(image);
        selected = image['id'];
      }
    });
  }

  Future<void> arrowEditor([Json? item]) async {
    if (planReadOnly) return;
    final v = await form(
      item == null ? 'Ajouter une flèche' : 'Modifier la flèche',
      {
        'label': item?['label'] ?? 'Flèche',
        'w': item?['w'] ?? 3.0,
        'h': item?['h'] ?? .7,
        'angle': item?['angle'] ?? 0.0,
        'zoneColor': item?['zoneColor'] ?? 'Orange',
        'opacity': item?['opacity'] ?? 1.0,
        'annotationFill': item?['annotationFill'] ?? 'Plein',
        'fixed': item?['fixed'] == true ? 'Oui' : 'Non',
      },
      {
        'label': 'Nom (repère interne)',
        'w': 'Longueur (m)',
        'h': 'Épaisseur (m)',
        'angle': 'Angle (degrés, 0 : vers la droite)',
        'zoneColor': 'Couleur',
        'opacity': 'Opacité (0 à 1)',
        'annotationFill': 'Remplissage',
        'fixed': 'Position fixée',
      },
      choices: {
        'zoneColor': zoneColors.keys.toList(),
        'annotationFill': ['Plein', 'Contour'],
        'fixed': ['Non', 'Oui'],
      },
      numeric: {'w', 'h', 'angle', 'opacity'},
    );
    if (v == null || planReadOnly) return;
    if (number(v['w']) <= 0 ||
        number(v['h']) <= 0 ||
        number(v['opacity']) < 0 ||
        number(v['opacity']) > 1 ||
        ['w', 'h', 'angle', 'opacity'].any((k) => !number(v[k]).isFinite)) {
      toast('Vérifier les dimensions, l’angle et l’opacité.');
      return;
    }
    v.addAll({
      'id': item?['id'] ?? uid(),
      'kind': 'arrow',
      'shape': 'rectangle',
      'x': item?['x'] ?? 1.0,
      'y': item?['y'] ?? 1.0,
      'angle': number(v['angle']) % 360,
      'fixed': v['fixed'] == 'Oui',
    });
    change(() {
      if (item == null) {
        rows(p!, 'items').add(v);
      } else {
        item.addAll(v);
      }
      selected = v['id'];
      selectedObjects
        ..clear()
        ..add(v['id']);
      selectedTables.clear();
    });
  }

  Future<void> annotationEditor(String kind, [Json? item]) async {
    if (planReadOnly) return;
    if (kind == 'arrow') {
      await arrowEditor(item);
      return;
    }
    final info = kind == 'info';
    final value = await form(
      item == null
          ? 'Ajouter ${objectLabels[kind]}'
          : 'Modifier ${objectLabels[kind]}',
      {
        'label': item?['label'] ?? (info ? 'Espace informatif' : 'Texte'),
        if (info) 'shape': item?['shape'] ?? 'rectangle',
        if (info) 'annotationFill': item?['annotationFill'] ?? 'Plein',
        if (info) 'w': item?['w'] ?? 4.0,
        if (info) 'h': item?['h'] ?? 3.0,
        if (info) 'zoneColor': item?['zoneColor'] ?? 'Bleu',
        if (info) 'opacity': item?['opacity'] ?? .25,
        'fontSize': item?['fontSize'] ?? 16.0,
        'bold': item?['bold'] == true ? 'Oui' : 'Non',
        'italic': item?['italic'] == true ? 'Oui' : 'Non',
        'underline': item?['underline'] == true ? 'Oui' : 'Non',
        'direction': number(item?['angle']) % 180 == 90
            ? 'Vertical'
            : 'Horizontal',
        'fixed': item?['fixed'] == true ? 'Oui' : 'Non',
      },
      {
        'label': info ? 'Nom de l’espace' : 'Texte',
        if (info) 'shape': 'Forme',
        if (info) 'annotationFill': 'Remplissage',
        if (info) 'w': 'Largeur ou diamètre (m)',
        if (info) 'h': 'Hauteur (m, cercle/carré : identique à la largeur)',
        if (info) 'zoneColor': 'Couleur',
        if (info) 'opacity': 'Opacité (0 à 1)',
        'fontSize': 'Taille du texte',
        'bold': 'Gras',
        'italic': 'Italique',
        'underline': 'Souligné',
        'direction': 'Orientation du texte',
        'fixed': 'Position fixée',
      },
      choices: {
        if (info)
          'shape': ['rectangle', 'carré', 'cercle', 'ovale', 'triangle'],
        if (info) 'annotationFill': ['Plein', 'Contour'],
        if (info) 'zoneColor': zoneColors.keys.toList(),
        'bold': ['Non', 'Oui'],
        'italic': ['Non', 'Oui'],
        'underline': ['Non', 'Oui'],
        'direction': ['Horizontal', 'Vertical'],
        'fixed': ['Non', 'Oui'],
      },
      numeric: {
        if (info) ...['w', 'h', 'opacity'],
        'fontSize',
      },
      multiline: {'label'},
    );
    if (value == null) return;
    if ('${value['label']}'.trim().isEmpty ||
        '${value['label']}'.length > 1000 ||
        number(value['fontSize']) < 6 ||
        number(value['fontSize']) > 120 ||
        info &&
            (number(value['w']) <= 0 ||
                number(value['h']) <= 0 ||
                number(value['opacity']) < 0 ||
                number(value['opacity']) > 1)) {
      toast(
        'Vérifier le texte, les dimensions, la taille (6 à 120) et l’opacité (0 à 1).',
      );
      return;
    }
    final v = <String, dynamic>{
      ...?(item),
      ...value,
      'id': item?['id'] ?? uid(),
      'kind': kind,
      'shape': info ? value['shape'] : 'rectangle',
      'x': item?['x'] ?? 1.0,
      'y': item?['y'] ?? 1.0,
    };
    if (info && ['cercle', 'carré'].contains(v['shape'])) v['h'] = v['w'];
    for (final key in ['fixed', 'bold', 'italic', 'underline']) {
      v[key] = value[key] == 'Oui';
    }
    final oldAngle = number(item?['angle']);
    v['angle'] =
        value['direction'] == (oldAngle % 180 == 90 ? 'Vertical' : 'Horizontal')
        ? oldAngle
        : value['direction'] == 'Vertical'
        ? 90.0
        : 0.0;
    v.remove('direction');
    if (!info) {
      final painter = TextPainter(
        text: TextSpan(text: v['label'], style: annotationTextStyle(v, 50)),
        textDirection: TextDirection.ltr,
      )..layout();
      v['w'] = max(.2, painter.width / 50);
      v['h'] = max(.15, painter.height / 50);
    }
    change(() {
      if (item == null) {
        rows(p!, 'items').add(v);
      } else {
        item.clear();
        item.addAll(v);
      }
      selected = v['id'];
      selectedObjects.clear();
      selectedObjects.add(v['id']);
      selectedTables.clear();
    });
  }

  TextStyle annotationTextStyle(Json item, double scale) => TextStyle(
    fontSize: number(item['fontSize'], 16) * scale / 50,
    color: widget.darkMode ? Colors.white : const Color(0xff123c38),
    fontWeight: item['bold'] == true ? FontWeight.bold : FontWeight.normal,
    fontStyle: item['italic'] == true ? FontStyle.italic : FontStyle.normal,
    decoration: item['underline'] == true ? TextDecoration.underline : null,
  );

  void annotationDragStart(Json item) {
    if (planReadOnly || item['fixed'] == true) return;
    selectPlanItem(item, additive: HardwareKeyboard.instance.isControlPressed);
    checkpoint();
  }

  Iterable<Widget> annotationPlanWidgets(
    double scale, {
    required bool foreground,
  }) sync* {
    for (final item in rows(p!, 'items').where(
      (i) => foreground
          ? ['text', 'arrow'].contains(i['kind'])
          : ['image', 'info'].contains(i['kind']),
    )) {
      final info = item['kind'] == 'info';
      final editable = !planReadOnly && item['fixed'] != true;
      final chosen = selectedPlanIds().contains(item['id']);
      Widget movable(Widget child, {bool label = false}) => GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        key: ValueKey(
          label ? 'annotation-label-${item['id']}' : 'plan-item-${item['id']}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: () => selectPlanItem(
          item,
          toggleHandles: true,
          additive: HardwareKeyboard.instance.isControlPressed,
        ),
        onSecondaryTapDown: (d) => planContextMenu(d.globalPosition, item),
        onDoubleTap: () => item['kind'] == 'image'
            ? imageEditor(item)
            : annotationEditor(item['kind'], item),
        onPanStart: editable ? (_) => annotationDragStart(item) : null,
        onPanUpdate: editable
            ? (d) => refreshMixed(() {
                if (label && info) {
                  item['labelDx'] =
                      number(item['labelDx']) + d.delta.dx / scale;
                  item['labelDy'] =
                      number(item['labelDy']) + d.delta.dy / scale;
                } else {
                  item['x'] = max(0.0, number(item['x']) + d.delta.dx / scale);
                  item['y'] = max(0.0, number(item['y']) + d.delta.dy / scale);
                }
              })
            : null,
        onPanEnd: editable ? (_) => persist() : null,
        child: child,
      );
      final image = item['kind'] == 'image', arrow = item['kind'] == 'arrow';
      if (info || image || arrow) {
        yield Positioned(
          key: ValueKey(('plan-layer', item['id'] as String, 'body')),
          left: number(item['x']) * scale,
          top: number(item['y']) * scale,
          child: movable(
            Transform.rotate(
              angle: number(item['angle']) * pi / 180,
              child: Container(
                width: number(item['w']) * scale,
                height: number(item['h']) * scale,
                decoration: image && chosen
                    ? BoxDecoration(
                        border: Border.all(color: Colors.blue, width: 2),
                      )
                    : null,
                child: image
                    ? Image.memory(
                        base64Decode(item['imageData']),
                        fit: BoxFit.fill,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : CustomPaint(
                        painter: AnnotationFigurePainter(item, scale, chosen),
                      ),
              ),
            ),
          ),
        );
      }
      if (!image && !arrow) {
        final labelStyle = annotationTextStyle(item, scale);
        final painter = TextPainter(
          text: TextSpan(text: item['label'], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = info
            ? number(item['x']) +
                  number(item['w']) / 2 +
                  number(item['labelDx'])
            : number(item['x']) + number(item['w']) / 2;
        final ly = info
            ? number(item['y']) +
                  number(item['h']) -
                  .06 +
                  number(item['labelDy'])
            : number(item['y']) + number(item['h']) / 2;
        yield Positioned(
          key: ValueKey(('plan-layer', item['id'] as String, 'label')),
          left: lx * scale - painter.width / 2,
          top: ly * scale - (info ? painter.height : painter.height / 2),
          child: movable(
            Transform.rotate(
              angle: number(item['angle']) * pi / 180,
              child: Container(
                decoration: chosen && !info
                    ? BoxDecoration(border: Border.all(color: Colors.blue))
                    : null,
                child: Text(item['label'], style: labelStyle),
              ),
            ),
            label: info,
          ),
        );
      }
    }
  }

  Iterable<Widget> annotationResizeHandles(double scale) sync* {
    if (planReadOnly || measuring || rotationModeActive) return;
    for (final item in rows(
      p!,
      'items',
    ).where((i) => ['info', 'image', 'arrow'].contains(i['kind']))) {
      final info = item['kind'] == 'info',
          image = item['kind'] == 'image',
          arrow = item['kind'] == 'arrow';
      final chosen = selectedPlanIds().contains(item['id']),
          editable = item['fixed'] != true;
      if ((info || image || arrow) && chosen && editable) {
        for (final corner in [
          (false, false),
          (true, false),
          (false, true),
          (true, true),
        ]) {
          final anchor = rotatedLocalPoint(
            item,
            Point(
              corner.$1 ? number(item['w']) : 0.0,
              corner.$2 ? number(item['h']) : 0.0,
            ),
          );
          yield Positioned(
            left: (number(item['x']) + anchor.x) * scale - 8,
            top: (number(item['y']) + anchor.y) * scale - 8,
            key: ValueKey(
              'annotation-resize-${item['id']}-${corner.$1}-${corner.$2}',
            ),
            child: Tooltip(
              message: 'Redimensionner — Maj : conserver les proportions',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (_) {
                  checkpoint();
                  resizeOrigin = {...item};
                  resizeDx = resizeDy = 0;
                },
                onPanUpdate: (d) => refreshMixed(() {
                  final dx = d.delta.dx / scale, dy = d.delta.dy / scale;
                  resizeDx += dx;
                  resizeDy += dy;
                  if (resizeOrigin != null) {
                    resizeRotatedBox(
                      item,
                      resizeOrigin!,
                      resizeDx,
                      resizeDy,
                      corner.$1,
                      corner.$2,
                      preserveAspect: HardwareKeyboard.instance.isShiftPressed,
                    );
                  }
                }),
                onPanEnd: (_) => persist(),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.blue),
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
  }
}

class AnnotationFigurePainter extends CustomPainter {
  final Json item;
  final double scale;
  final bool selected;
  AnnotationFigurePainter(this.item, this.scale, this.selected);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    if (annotationEllipse(item)) {
      path.addOval(Offset.zero & size);
    } else {
      final vertices = annotationVertices(item);
      path.moveTo(
        vertices.first.x * size.width,
        vertices.first.y * size.height,
      );
      for (final v in vertices.skip(1)) {
        path.lineTo(v.x * size.width, v.y * size.height);
      }
      path.close();
    }
    final color = Color(zoneColors[item['zoneColor']] ?? zoneColors['Bleu']!);
    if (item['annotationFill'] != 'Contour') {
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: number(item['opacity'], .25)),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, scale / 50)
        ..color = color,
    );
    if (selected) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.blue,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationFigurePainter old) => true;
}
