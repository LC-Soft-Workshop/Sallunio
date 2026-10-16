import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'domain.dart';
import 'plan_export.dart';

String newPdfPath(String directory) =>
    '$directory${Platform.pathSeparator}plan-sallunio-${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}-${uid().split('-').last}.pdf';

Future<void> exportPdf(
  Json source,
  String path, {
  DateTime? exportedAt,
  String? exportReference,
  bool overwriteConfirmed = false,
  bool cardsOnly = false,
  bool includePlan = true,
  bool includeSummary = true,
  bool includeCards = true,
  bool includeReception = false,
  bool includeService = false,
  bool includeWaiting = false,
  bool includePlaceLabels = false,
  bool includeLegend = true,
  String planAudience = 'Organisation',
  int planColumns = 1,
  int planRows = 1,
}) async {
  final p = clone(source); // Capture before the first asynchronous operation.
  if (planColumns < 1 || planColumns > 6 || planRows < 1 || planRows > 6) {
    throw const FormatException('Choisir de 1 à 6 feuilles par axe.');
  }
  final waiting = rows(p, 'groups').where((g) => g['waiting'] == true).toList();
  p['groups'] = rows(p, 'groups').where((g) => g['waiting'] != true).toList();
  final planMarkers = planAudience == 'Organisation';
  if (cardsOnly) {
    includePlan = false;
    includeSummary = false;
    includeCards = true;
    includeReception = false;
    includeService = false;
    includeWaiting = false;
  }
  if (!includePlan &&
      !includeSummary &&
      !includeCards &&
      !includeReception &&
      !includeWaiting &&
      !includeService) {
    throw const FormatException('Choisir au moins un élément à exporter.');
  }
  if (includeCards &&
      !includePlan &&
      !includeSummary &&
      !includeReception &&
      !includeWaiting &&
      !includeService &&
      !tables(p).any(
        (t) =>
            occupancy(p, t['id']) > 0 || standPortions(p, t['id']).isNotEmpty,
      )) {
    throw const FormatException(
      'Aucune table occupée : attribuer les réservations avant de générer les fiches.',
    );
  }
  final when = exportedAt ?? DateTime.now();
  final reference = exportReference ?? uid();
  if (File(path).existsSync() && !overwriteConfirmed) {
    throw FileSystemException(
      'Ce PDF existe déjà : choisir un nouveau nom',
      path,
    );
  }
  final doc = pw.Document(
    title: p['name'],
    subject: 'Export Sallunio $reference',
  );
  final fontFile = File(
    '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/arial.ttf',
  );
  final font = fontFile.existsSync()
      ? pw.Font.ttf((await fontFile.readAsBytes()).buffer.asByteData())
      : pw.Font.helvetica();
  Future<pw.Font> variantFont(String name) async {
    final file = File(
      '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/$name',
    );
    return file.existsSync()
        ? pw.Font.ttf((await file.readAsBytes()).buffer.asByteData())
        : font;
  }

  final theme = pw.ThemeData.withFont(
    base: font,
    bold: await variantFont('arialbd.ttf'),
    italic: await variantFont('ariali.ttf'),
    boldItalic: await variantFont('arialbi.ttf'),
  );
  List<pw.Widget> annotationPdfWidgets(
    double scale,
    bool foreground, [
    String? onlyItemId,
  ]) => [
    for (final item in rows(p, 'items').where(
      (i) => foreground
          ? ['text', 'arrow'].contains(i['kind'])
          : i['kind'] == 'info',
    )) ...[
      if (onlyItemId == null || item['id'] == onlyItemId) ...[
        if (!foreground || item['kind'] == 'arrow')
          pw.Positioned(
            left: number(item['x']) * scale,
            top: number(item['y']) * scale,
            child: rotatedPdfLabel(
              item,
              pw.SvgImage(
                svg: annotationFigureSvg(item),
                width: number(item['w']) * scale,
                height: number(item['h']) * scale,
              ),
            ),
          ),
        if (item['kind'] != 'arrow')
          pw.Positioned(
            left:
                (number(item['x']) +
                    (!foreground ? number(item['labelDx']) : 0)) *
                scale,
            top:
                (number(item['y']) +
                    (!foreground
                        ? number(item['h']) -
                              .06 +
                              number(item['labelDy']) -
                              number(item['fontSize'], 16) /
                                  50 *
                                  1.2 *
                                  '${item['label']}'.split('\n').length
                        : 0)) *
                scale,
            child: rotatedPdfLabel(
              item,
              pw.Container(
                width: number(item['w']) * scale,
                height: !foreground
                    ? number(item['fontSize'], 16) *
                          scale /
                          50 *
                          1.2 *
                          '${item['label']}'.split('\n').length
                    : null,
                child: pw.FittedBox(
                  fit: pw.BoxFit.scaleDown,
                  child: pw.Text(
                    item['label'],
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: number(item['fontSize'], 16) * scale / 50,
                      fontWeight: item['bold'] == true
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      fontStyle: item['italic'] == true
                          ? pw.FontStyle.italic
                          : pw.FontStyle.normal,
                      decoration: item['underline'] == true
                          ? pw.TextDecoration.underline
                          : pw.TextDecoration.none,
                      color: PdfColor.fromInt(0xff123c38),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ],
  ];
  final ts = tables(p);
  final cardStyle = p['tableCards'] as Map? ?? {};
  final cardMessage = (cardStyle['message'] ?? '').toString().trim();
  final cardLogo =
      cardStyle['logo'] is String && (cardStyle['logo'] as String).isNotEmpty
      ? pw.MemoryImage(base64Decode(cardStyle['logo']))
      : null;
  final geometry = PlanGeometry(p, rows(p, 'items'));
  final scale = min(
    490 / number(p['room']['width']),
    550 / number(p['room']['height']),
  );
  List<pw.Widget> layerSeatLabels(Json table, double scale) {
    final labels = tablePlaceLabels(p, table, geometry);
    final points = placeLabelPositions(
      geometry.view(table),
      labels.length,
      geometry.blocked[table['id']] ?? {},
    ).map((point) => rotatedLocalPoint(table, point)).toList();
    return [
      for (var i = 0; i < points.length; i++)
        pw.Positioned(
          left: (number(table['x']) + points[i].x - .26) * scale,
          top: (number(table['y']) + points[i].y - .1) * scale,
          child: pw.Container(
            width: .52 * scale,
            height: .2 * scale,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(
                labels[i] == null ? 0xfff1f3f2 : 0xffe1efe7,
              ),
              border: pw.Border.all(
                color: PdfColor.fromInt(0xff527567),
                width: .008 * scale,
              ),
            ),
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              child: pw.Text(
                labels[i] ?? 'Libre',
                style: pw.TextStyle(
                  fontSize: .095 * scale,
                  color: PdfColor.fromInt(0xff123c38),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  pw.Widget orderedPlanCanvas(double scale) {
    final ordered = planPaintOrder(p);
    final routeIndex = ordered.indexWhere(
      (i) => !isPlanAnnotation(i) || ['arrow', 'text'].contains(i['kind']),
    );
    pw.Widget svgLayer({bool grid = false, bool route = false, String? id}) =>
        pw.Positioned(
          left: 0,
          top: 0,
          child: pw.SvgImage(
            svg: planSvg(
              p,
              withGrid: grid,
              includeRoute: route,
              drawItems: id != null,
              onlyItemId: id,
              sharedGeometry: geometry,
              showMarkers: planMarkers,
              transparentBackground: true,
            ),
            width: number(p['room']['width']) * scale,
            height: number(p['room']['height']) * scale,
          ),
        );
    return pw.Container(
      width: number(p['room']['width']) * scale,
      height: number(p['room']['height']) * scale,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(),
      ),
      child: pw.Stack(
        children: [
          svgLayer(grid: true),
          for (final (index, item) in ordered.indexed) ...[
            if (index == routeIndex) svgLayer(route: true),
            if (item['kind'] == 'image')
              pw.Positioned(
                left: number(item['x']) * scale,
                top: number(item['y']) * scale,
                child: rotatedPdfLabel(
                  item,
                  pw.Image(
                    pw.MemoryImage(base64Decode(item['imageData'])),
                    width: number(item['w']) * scale,
                    height: number(item['h']) * scale,
                    fit: pw.BoxFit.fill,
                  ),
                ),
              ),
            if (['info', 'text', 'arrow'].contains(item['kind']))
              ...annotationPdfWidgets(
                scale,
                item['kind'] != 'info',
                item['id'],
              ),
            if (!isPlanAnnotation(item) && visibleInPlanPdf(item)) ...[
              svgLayer(id: item['id']),
              pw.Positioned(
                left: number(item['x']) * scale,
                top: number(item['y']) * scale,
                child: rotatedPdfLabel(
                  item,
                  pw.Container(
                    width: number(item['w']) * scale,
                    height: number(item['h']) * scale,
                    padding: const pw.EdgeInsets.all(2),
                    alignment: pw.Alignment.center,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      child: pw.Text(
                        isSeatingFurniture(item)
                            ? planAudience == 'Visiteurs'
                                  ? furnitureShortLabel(item)
                                  : furniturePlanLabel(p, item)
                            : '${item['label']}',
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColor.fromInt(0xff123c38),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (includePlaceLabels &&
                  planAudience == 'Organisation' &&
                  isSeatingFurniture(item))
                ...layerSeatLabels(item, scale),
            ],
          ],
          if (routeIndex < 0) svgLayer(route: true),
        ],
      ),
    );
  }

  pw.Widget planCanvas(double scale) => p['planLayerOrder'] is List
      ? orderedPlanCanvas(scale)
      : pw.Container(
          width: number(p['room']['width']) * scale,
          height: number(p['room']['height']) * scale,
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            border: pw.Border.all(),
          ),
          child: pw.Stack(
            children: [
              for (final item in rows(
                p,
                'items',
              ).where((i) => i['kind'] == 'image'))
                pw.Positioned(
                  left: number(item['x']) * scale,
                  top: number(item['y']) * scale,
                  child: rotatedPdfLabel(
                    item,
                    pw.Image(
                      pw.MemoryImage(base64Decode(item['imageData'])),
                      width: number(item['w']) * scale,
                      height: number(item['h']) * scale,
                      fit: pw.BoxFit.fill,
                    ),
                  ),
                ),
              ...annotationPdfWidgets(scale, false),
              for (final foreground in [false, true]) ...[
                pw.Positioned(
                  left: 0,
                  top: 0,
                  child: pw.SvgImage(
                    svg: planSvg(
                      p,
                      tablesOnly: foreground,
                      withGrid: !foreground,
                      showMarkers: planMarkers,
                      transparentBackground: true,
                    ),
                    width: number(p['room']['width']) * scale,
                    height: number(p['room']['height']) * scale,
                  ),
                ),
                ...planPaintOrder(p)
                    .where(
                      (item) =>
                          visibleInPlanPdf(item) &&
                          !isPlanAnnotation(item) &&
                          isSeatingFurniture(item) == foreground,
                    )
                    .map(
                      (t) => pw.Positioned(
                        left: number(t['x']) * scale,
                        top: number(t['y']) * scale,
                        child: rotatedPdfLabel(
                          t,
                          pw.Container(
                            width: number(t['w']) * scale,
                            height: number(t['h']) * scale,
                            padding: const pw.EdgeInsets.all(2),
                            alignment: pw.Alignment.center,
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              child: pw.Text(
                                isSeatingFurniture(t)
                                    ? planAudience == 'Visiteurs'
                                          ? furnitureShortLabel(t)
                                          : furniturePlanLabel(p, t)
                                    : '${t['label']}',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColor.fromInt(0xff123c38),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
              ...annotationPdfWidgets(scale, true),
              if (includePlaceLabels && planAudience == 'Organisation')
                ...ts.expand((table) {
                  final labels = tablePlaceLabels(p, table, geometry);
                  final points = placeLabelPositions(
                    geometry.view(table),
                    labels.length,
                    geometry.blocked[table['id']] ?? {},
                  ).map((point) => rotatedLocalPoint(table, point)).toList();
                  return [
                    for (var i = 0; i < points.length; i++)
                      pw.Positioned(
                        left: (number(table['x']) + points[i].x - .26) * scale,
                        top: (number(table['y']) + points[i].y - .1) * scale,
                        child: pw.Container(
                          width: .52 * scale,
                          height: .2 * scale,
                          alignment: pw.Alignment.center,
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(
                              labels[i] == null ? 0xfff1f3f2 : 0xffe1efe7,
                            ),
                            border: pw.Border.all(
                              color: PdfColor.fromInt(0xff527567),
                              width: .008 * scale,
                            ),
                          ),
                          child: pw.FittedBox(
                            fit: pw.BoxFit.scaleDown,
                            child: pw.Text(
                              labels[i] ?? 'Libre',
                              style: pw.TextStyle(
                                fontSize: .095 * scale,
                                color: PdfColor.fromInt(0xff123c38),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ];
                }),
            ],
          ),
        );
  if (includePlan && planColumns == 1 && planRows == 1) {
    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(35),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(p['name'], style: const pw.TextStyle(fontSize: 20)),
            pw.SizedBox(height: 8),
            pw.Text(
              '${p['room']['name']} - ${p['room']['width']} x ${p['room']['height']} m',
            ),
            pw.Text(
              'Export ${when.toIso8601String()} - référence $reference',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.SizedBox(height: 16),
            planCanvas(scale),
            pw.SizedBox(height: 16),
            pw.Text(
              'Plan de préparation. Contrôles indicatifs par boîtes englobantes. Passage cible : ${p['aisle']} m. Vérifier sur site les sorties, portes et cheminements accessibles.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (includeLegend) ...[
              pw.Text(
                'Légende : gris = vide ; orange pâle = partiellement occupée ; vert pâle = pleine ; rouge = conflit.',
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 8),
              pw.Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  if (planMarkers)
                    for (final entry in planMarkerColors(p).entries)
                      if (tables(p).any(
                        (table) =>
                            tableMarkers(p, table['id']).contains(entry.key),
                      ))
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          children: [
                            pw.SvgImage(
                              svg:
                                  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 14 14">${planMarkerSvg(entry.key, entry.value, 7, 7)}</svg>',
                              width: 8,
                              height: 8,
                            ),
                            pw.SizedBox(width: 4),
                            pw.Text(
                              entry.key,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
  if (includePlan && (planColumns > 1 || planRows > 1)) {
    final tileScale = min(
      520 * planColumns / number(p['room']['width']),
      620 * planRows / number(p['room']['height']),
    );
    final width = number(p['room']['width']) * tileScale / planColumns,
        height = number(p['room']['height']) * tileScale / planRows;
    for (var row = 0; row < planRows; row++) {
      for (var col = 0; col < planColumns; col++) {
        final sheet = row * planColumns + col + 1;
        doc.addPage(
          pw.Page(
            theme: theme,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(35),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '${p['name']} — plan assemblé',
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.Text(
                  'Feuille $sheet / ${planColumns * planRows} — rangée ${row + 1}, colonne ${col + 1}',
                ),
                pw.SizedBox(height: 10),
                pw.Container(
                  decoration: pw.BoxDecoration(border: pw.Border.all()),
                  child: pw.ClipRect(
                    child: pw.SizedBox(
                      width: width,
                      height: height,
                      child: pw.Stack(
                        children: [
                          pw.Positioned(
                            left: -col * width,
                            top: -row * height,
                            child: planCanvas(tileScale),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Assembler en $planColumns colonnes et $planRows rangées. Imprimer à 100 %. Couper les marges le long du cadre.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.Text(
                  'Gauche : ${col > 0 ? sheet - 1 : 'bord'} • Droite : ${col + 1 < planColumns ? sheet + 1 : 'bord'} • Haut : ${row > 0 ? sheet - planColumns : 'bord'} • Bas : ${row + 1 < planRows ? sheet + planColumns : 'bord'}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                if (includeLegend && planMarkers)
                  pw.Text(
                    planMarkerColors(p).keys
                        .where(
                          (key) => tables(
                            p,
                          ).any((t) => tableMarkers(p, t['id']).contains(key)),
                        )
                        .join(' • '),
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                if (includeLegend)
                  pw.Text(
                    'Légende : gris = vide ; orange = partiellement occupée ; vert = pleine ; rouge = conflit.',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
              ],
            ),
          ),
        );
      }
    }
  }
  if (includeSummary && rows(p, 'groups').any(isStandBooking)) {
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            'Exposants et stands',
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.Text(standSummaryLabel(p)),
          for (final g in rows(p, 'groups').where(isStandBooking))
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6),
              child: pw.Text(
                '${g['name']} - ${g['standUnit'] == 'Mètres linéaires' ? '${number(g['requestedMetres']).toStringAsFixed(2)} m demandés' : '${g['requestedTables'] ?? 1} table(s) demandée(s)'}\n${standAllocationText(p, g)}',
              ),
            ),
        ],
      ),
    );
  }
  if (includeSummary) {
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(p['name'], style: const pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 8),
          pw.Text(
            mealsEnabled(p) ? 'Réservations et repas' : 'Réservations',
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'Référent',
              rows(p, 'groups').any(isStandBooking)
                  ? 'Places / demande'
                  : 'Places',
              'Tables',
              mealsEnabled(p) ? 'Repas / besoins' : 'Besoins',
            ],
            data: rows(p, 'groups')
                .map(
                  (g) => [
                    g['name'],
                    isStandBooking(g)
                        ? (g['standUnit'] == 'Mètres linéaires'
                              ? '${g['requestedMetres']} m'
                              : '${g['requestedTables'] ?? 1} tables')
                        : '${g['count']}',
                    isStandBooking(g)
                        ? standAllocationText(p, g)
                        : (g['alloc'] as List)
                              .map(
                                (a) =>
                                    '${ts.where((t) => t['id'] == a['table']).first['label']} (${a['count']})',
                              )
                              .join(', '),
                    mealsEnabled(p)
                        ? '${g['meal']}\n${g['allergy']}\n${reservationSpecialNeeds(g)}'
                        : reservationSpecialNeeds(g),
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 18),
          if (mealsEnabled(p)) ...[
            pw.Text(
              'Ne mange pas conserve une place et est exclu du total repas.',
            ),
            pw.Text(
              'Total repas : ${mealTotals(p).entries.where((e) => e.key != 'Ne mange pas').fold<int>(0, (s, e) => s + e.value)}',
            ),
            ...List<String>.from(p['meals'])
                .map((meal) => pw.Text('$meal : ${mealTotals(p)[meal]}')),
          ],
          ...rows(p, 'groups')
              .where((g) => (g['seats'] as List? ?? []).isNotEmpty)
              .expand(
                (g) => [
                  pw.SizedBox(height: 12),
                  pw.Text('Places anonymes : ${g['name']}'),
                  ...((g['seats'] as List).cast<Json>().take(g['count'])).map(
                    (s) => pw.Text(
                      'Place ${s['number']} : ${mealsEnabled(p) ? '${s['meal']} ; ' : ''} ${s['need'] ?? ''}${(s['number'] as int) <= (g['childChairs'] as int? ?? 0) ? ' ; chaise enfant' : ''}${mealsEnabled(p) ? ' ; allergies ${s['allergy'] ?? ''}' : ''} ; accompagnant ${s['companion'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }
  if (includeWaiting) {
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(p['name'], style: const pw.TextStyle(fontSize: 20)),
          pw.Text('Liste d’attente', style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 8),
          pw.Text(
            '${waiting.length} réservation(s) en attente - non attribuées.',
          ),
          pw.SizedBox(height: 14),
          if (waiting.isEmpty)
            pw.Text('Aucune réservation en attente.')
          else
            pw.TableHelper.fromTextArray(
              headers: [
                'Référent / exposant',
                'Effectif',
                'Demande',
                'Coordonnées',
                'Besoins spéciaux',
              ],
              data: waiting
                  .map(
                    (g) => [
                      g['name'],
                      '${g['count']}',
                      isStandBooking(g)
                          ? '${g['standUnit'] == 'Mètres linéaires' ? g['requestedMetres'] : g['requestedTables']} ${g['standUnit'] == 'Mètres linéaires' ? 'm linéaires' : 'table(s)'}'
                          : 'Places assises',
                      [g['contact'], g['email'], g['phone']]
                          .where(
                            (v) => v != null && v.toString().trim().isNotEmpty,
                          )
                          .join('\n'),
                      reservationSpecialNeeds(g),
                    ],
                  )
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(7),
            ),
        ],
      ),
    );
  }
  if (includeReception) {
    final groups = [...rows(p, 'groups')]
      ..sort(
        (a, b) =>
            _alphabeticalKey(a['name']).compareTo(_alphabeticalKey(b['name'])),
      );
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(p['name'], style: const pw.TextStyle(fontSize: 20)),
          pw.Text('Liste d’accueil', style: const pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 8),
          pw.Text(
            '${groups.length} réservations - ${groups.fold<int>(0, (sum, g) => sum + (g['count'] as int))} personnes. Classement par référent.',
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: [
              'Présent',
              'Référent / groupe',
              'Effectif',
              'Tables et places',
              'Besoins spéciaux',
            ],
            data: groups
                .map(
                  (g) => [
                    '[  ]',
                    g['name'],
                    '${g['count']}',
                    _assignedTableText(p, g),
                    reservationSpecialNeeds(g),
                  ],
                )
                .toList(),
            cellStyle: const pw.TextStyle(fontSize: 11),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 10,
            ),
          ),
        ],
      ),
    );
  }
  if (includeService) {
    final totals = mealTotals(p);
    final serviceRows = <List<String>>[];
    for (final table in ts.where((t) => occupancy(p, t['id']) > 0)) {
      for (final group in rows(p, 'groups')) {
        final count = (group['alloc'] as List)
            .where((a) => a['table'] == table['id'])
            .fold<int>(0, (sum, a) => sum + (a['count'] as int));
        if (count == 0) continue;
        serviceRows.add([
          table['label'],
          group['name'],
          '$count',
          if (mealsEnabled(p)) group['meal'],
          [
            if ((group['needs'] ?? '').toString().isNotEmpty) group['needs'],
            if (mealsEnabled(p) &&
                (group['allergy'] ?? '').toString().isNotEmpty)
              'Allergies : ${group['allergy']}',
            if ((group['seats'] as List? ?? []).isNotEmpty)
              'Voir détails par réservation',
          ].join('\n'),
        ]);
      }
    }
    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) => [
          pw.Text(p['name'], style: const pw.TextStyle(fontSize: 20)),
          pw.Text(
            'Préparation cuisine et service',
            style: const pw.TextStyle(fontSize: 18),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '${rows(p, 'groups').fold<int>(0, (sum, g) => sum + (g['count'] as int))} personnes réservées - ${ts.fold<int>(0, (sum, t) => sum + occupancy(p, t['id']))} attribuées.',
          ),
          if (mealsEnabled(p)) ...[
            pw.Text(
              'Quantités à préparer pour toutes les personnes réservées, y compris celles sans table.',
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Repas', 'Quantité'],
              data: totals.entries
                  .where((entry) => entry.key != 'Ne mange pas')
                  .map((entry) => [entry.key, '${entry.value}'])
                  .toList(),
              cellStyle: const pw.TextStyle(fontSize: 12),
            ),
            pw.Text(
              'Total repas : ${totals.entries.where((entry) => entry.key != 'Ne mange pas').fold<int>(0, (sum, entry) => sum + entry.value)}. Sans repas : ${totals['Ne mange pas'] ?? 0}.',
            ),
          ] else
            pw.Text('Événement sans repas.'),
          pw.SizedBox(height: 16),
          pw.Text('Service par table', style: const pw.TextStyle(fontSize: 16)),
          pw.TableHelper.fromTextArray(
            headers: [
              'Table',
              'Référent / groupe',
              'Places',
              if (mealsEnabled(p)) 'Repas par défaut',
              mealsEnabled(p) ? 'Besoins / allergies' : 'Besoins',
            ],
            data: serviceRows,
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.all(7),
          ),
          if (rows(
            p,
            'groups',
          ).any((group) => (group['seats'] as List? ?? []).isNotEmpty)) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'Détails particuliers par réservation',
              style: const pw.TextStyle(fontSize: 16),
            ),
            pw.Text(
              'Les exceptions individuelles sont décrites par réservation ; leur place précise à chaque table reste à vérifier au service.',
            ),
            ...rows(p, 'groups')
                .where((group) => (group['seats'] as List? ?? []).isNotEmpty)
                .expand(
                  (group) => [
                    pw.SizedBox(height: 8),
                    pw.Text(
                      '${group['name']} - ${_assignedTableText(p, group)}',
                    ),
                    for (final seat
                        in (group['seats'] as List).cast<Json>().take(
                          group['count'],
                        ))
                      if ((mealsEnabled(p) && seat['meal'] != group['meal']) ||
                          (seat['need'] ?? '') != '' ||
                          (mealsEnabled(p) && (seat['allergy'] ?? '') != '') ||
                          (seat['companion'] ?? '') != '')
                        pw.Text(
                          'Place ${seat['number']} : ${mealsEnabled(p) ? '${seat['meal']} ; ' : ''}${seat['need']}${mealsEnabled(p) ? ' ; allergies ${seat['allergy']}' : ''} ; accompagnant ${seat['companion']}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                  ],
                ),
          ],
          if (!freeSeating(p) &&
              rows(p, 'groups')
                  .where((g) => !isStandBooking(g))
                  .any(
                    (group) =>
                        (group['alloc'] as List).fold<int>(
                          0,
                          (sum, a) => sum + (a['count'] as int),
                        ) <
                        group['count'],
                  )) ...[
            pw.SizedBox(height: 14),
            pw.Text(
              'Personnes restant à placer',
              style: const pw.TextStyle(fontSize: 16),
            ),
            for (final group in rows(
              p,
              'groups',
            ).where((g) => !isStandBooking(g)))
              if ((group['alloc'] as List).fold<int>(
                    0,
                    (sum, a) => sum + (a['count'] as int),
                  ) <
                  group['count'])
                pw.Text(
                  '${group['name']} : ${(group['count'] as int) - (group['alloc'] as List).fold<int>(0, (sum, a) => sum + (a['count'] as int))} personne(s)',
                ),
          ],
        ],
      ),
    );
  }
  final occupiedTables = includeCards
      ? ts
            .where(
              (t) =>
                  occupancy(p, t['id']) > 0 ||
                  standPortions(p, t['id']).isNotEmpty,
            )
            .toList()
      : <Json>[];
  for (var i = 0; i < occupiedTables.length; i += 4) {
    final batch = occupiedTables.skip(i).take(4).toList();
    final cards = batch
        .map(
          (t) => pw.Container(
            width: PdfPageFormat.a6.width,
            height: PdfPageFormat.a6.height,
            padding: const pw.EdgeInsets.all(15),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.FittedBox(
              fit: pw.BoxFit.scaleDown,
              alignment: pw.Alignment.topLeft,
              child: pw.SizedBox(
                width: PdfPageFormat.a6.width - 30,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${t['label'].toString().startsWith('T') && int.tryParse(t['label'].toString().substring(1)) != null ? 'Table ${t['label'].toString().substring(1)}' : t['label']}',
                      style: const pw.TextStyle(fontSize: 30),
                    ),
                    pw.Text(
                      furnitureUse(t) == furnitureUses[1]
                          ? '${standLength(t).toStringAsFixed(2)} m de table'
                          : '${occupancy(p, t['id'])} / ${usableSeatCapacity(p, t)} places utilisables',
                    ),
                    if (furnitureUse(t) == furnitureUses.first &&
                        geometry.capacity(t) < t['capacity'])
                      pw.Text(
                        '${t['capacity']} déclarées ; assises retirées aux jonctions',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    pw.SizedBox(height: 15),
                    for (final a in standPortions(p, t['id']))
                      pw.Text(
                        '${a['name']} : ${a['whole'] == true ? 'table entière - ' : ''}${number(a['length']).toStringAsFixed(2)} m',
                        style: const pw.TextStyle(fontSize: 11),
                      ),
                    ...rows(p, 'groups')
                        .where(
                          (g) => (g['alloc'] as List).any(
                            (a) => a['table'] == t['id'] && a['count'] > 0,
                          ),
                        )
                        .map(
                          (g) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 10),
                            child: pw.Text(
                              '${g['name']} : ${(g['alloc'] as List).where((a) => a['table'] == t['id']).fold<int>(0, (s, a) => s + (a['count'] as int))} places',
                              style: const pw.TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    if (cardLogo != null || cardMessage.isNotEmpty)
                      pw.SizedBox(height: 14),
                    if (cardLogo != null)
                      pw.Center(
                        child: pw.Image(
                          cardLogo,
                          width: 150,
                          height: 55,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    if (cardLogo != null && cardMessage.isNotEmpty)
                      pw.SizedBox(height: 8),
                    if (cardMessage.isNotEmpty)
                      pw.Center(
                        child: pw.Text(
                          cardMessage,
                          textAlign: pw.TextAlign.center,
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        )
        .toList();
    doc.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Column(
          children: [
            pw.Row(children: cards.take(2).toList()),
            if (cards.length > 2) pw.Row(children: cards.skip(2).toList()),
          ],
        ),
      ),
    );
  }
  final bytes = await doc.save();
  final output = overwriteConfirmed
      ? File(path)
      : await File(path).create(exclusive: true);
  await output.writeAsBytes(bytes, flush: true);
}

String _assignedTableText(Json p, Json group) {
  if (isStandBooking(group)) {
    final text = standAllocationText(p, group);
    return text.isEmpty ? 'Stand non attribué' : text;
  }
  final assigned = (group['alloc'] as List).fold<int>(
    0,
    (sum, a) => sum + (a['count'] as int),
  );
  final labels = (group['alloc'] as List)
      .map(
        (a) =>
            '${tables(p).firstWhere((table) => table['id'] == a['table'])['label']} (${a['count']})',
      )
      .toList();
  if (assigned < group['count']) {
    labels.add(
      '${(group['count'] as int) - assigned} ${freeSeating(p) ? 'en placement libre' : 'à placer'}',
    );
  }
  return labels.isEmpty ? 'Sans attribution' : labels.join(', ');
}

String _alphabeticalKey(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

pw.Widget rotatedPdfLabel(Json t, pw.Widget child) =>
    pw.Transform.rotate(angle: -number(t['angle']) * pi / 180, child: child);
