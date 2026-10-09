import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'domain.dart';
import 'plan_export.dart';

String newPdfPath(String directory) =>
    '$directory${Platform.pathSeparator}plan-tableo-${DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}-${uid().split('-').last}.pdf';

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
  bool includePlaceLabels = false,
}) async {
  final p = clone(source); // Capture before the first asynchronous operation.
  if (cardsOnly) {
    includePlan = false;
    includeSummary = false;
    includeCards = true;
    includeReception = false;
    includeService = false;
  }
  if (!includePlan &&
      !includeSummary &&
      !includeCards &&
      !includeReception &&
      !includeService) {
    throw const FormatException('Choisir au moins un élément à exporter.');
  }
  if (includeCards &&
      !includePlan &&
      !includeSummary &&
      !includeReception &&
      !includeService &&
      !tables(p).any((t) => occupancy(p, t['id']) > 0)) {
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
    subject: 'Export Tableo $reference',
  );
  final fontFile = File(
    '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/arial.ttf',
  );
  final font = fontFile.existsSync()
      ? pw.Font.ttf((await fontFile.readAsBytes()).buffer.asByteData())
      : pw.Font.helvetica();
  final theme = pw.ThemeData.withFont(base: font, bold: font);
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
  if (includePlan) {
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
            pw.Container(
              width: number(p['room']['width']) * scale,
              height: number(p['room']['height']) * scale,
              decoration: pw.BoxDecoration(border: pw.Border.all()),
              child: pw.Stack(
                children: [
                  pw.Positioned(
                    left: 0,
                    top: 0,
                    child: pw.SvgImage(
                      svg: planSvg(p),
                      width: number(p['room']['width']) * scale,
                      height: number(p['room']['height']) * scale,
                    ),
                  ),
                  ...rows(p, 'items')
                      .where(visibleInPlanPdf)
                      .map(
                        (t) => pw.Positioned(
                          left: number(t['x']) * scale,
                          top: number(t['y']) * scale,
                          child: pw.Container(
                            width: number(t['w']) * scale,
                            height: number(t['h']) * scale,
                            padding: const pw.EdgeInsets.all(2),
                            alignment: pw.Alignment.center,
                            child: pw.FittedBox(
                              fit: pw.BoxFit.scaleDown,
                              child: pw.Text(
                                '${t['label']}${t['kind'] == 'table'
                                    ? t['capacity'] == 0
                                          ? '\nService'
                                          : '\n${occupancy(p, t['id'])}/${geometry.capacity(t)}'
                                    : ''}',
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
                  if (includePlaceLabels)
                    ...ts.expand((table) {
                      final labels = tablePlaceLabels(p, table, geometry);
                      final points = placeLabelPositions(
                        table,
                        labels.length,
                        geometry.blocked[table['id']] ?? {},
                      );
                      return [
                        for (var i = 0; i < points.length; i++)
                          pw.Positioned(
                            left:
                                (number(table['x']) + points[i].x - .26) *
                                scale,
                            top:
                                (number(table['y']) + points[i].y - .1) * scale,
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
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Plan de préparation. Contrôles indicatifs par boîtes englobantes. Passage cible : ${p['aisle']} m. Vérifier sur site les sorties, portes et cheminements accessibles.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text(
              'Légende : gris = vide ; orange pâle = partiellement occupée ; vert pâle = pleine ; rouge = conflit.',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 8),
            pw.Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final entry in planMarkerColors(p).entries)
                  if (tables(p).any(
                    (table) => tableMarkers(p, table['id']).contains(entry.key),
                  ))
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Container(
                          width: 6,
                          height: 6,
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromInt(entry.value),
                            shape: pw.BoxShape.circle,
                          ),
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
        ),
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
            'Réservations et repas',
            style: const pw.TextStyle(fontSize: 20),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'Référent',
              'Places',
              'Tables',
              mealsEnabled(p) ? 'Repas / besoins' : 'Besoins',
            ],
            data: rows(p, 'groups')
                .map(
                  (g) => [
                    g['name'],
                    '${g['count']}',
                    (g['alloc'] as List)
                        .map(
                          (a) =>
                              '${ts.where((t) => t['id'] == a['table']).first['label']} (${a['count']})',
                        )
                        .join(', '),
                    mealsEnabled(p)
                        ? '${g['meal']}\n${g['allergy']} ${g['needs']}'
                        : '${g['allergy']} ${g['needs']}',
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
                      'Place ${s['number']} : ${mealsEnabled(p) ? '${s['meal']} ; ' : ''} ${s['need']} ; allergies ${s['allergy']} ; accompagnant ${s['companion']}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
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
            ],
            data: groups
                .map(
                  (g) => [
                    '[  ]',
                    g['name'],
                    '${g['count']}',
                    _assignedTableText(p, g),
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
            if ((group['allergy'] ?? '').toString().isNotEmpty)
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
              'Besoins / allergies',
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
                          (seat['allergy'] ?? '') != '' ||
                          (seat['companion'] ?? '') != '')
                        pw.Text(
                          'Place ${seat['number']} : ${mealsEnabled(p) ? '${seat['meal']} ; ' : ''}${seat['need']} ; allergies ${seat['allergy']} ; accompagnant ${seat['companion']}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                  ],
                ),
          ],
          if (rows(p, 'groups').any(
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
            for (final group in rows(p, 'groups'))
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
      ? ts.where((t) => occupancy(p, t['id']) > 0).toList()
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
                      '${occupancy(p, t['id'])} / ${geometry.capacity(t)} places utilisables',
                    ),
                    if (geometry.capacity(t) < t['capacity'])
                      pw.Text(
                        '${t['capacity']} déclarées ; assises retirées aux jonctions',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    pw.SizedBox(height: 15),
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
    labels.add('${(group['count'] as int) - assigned} à placer');
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
