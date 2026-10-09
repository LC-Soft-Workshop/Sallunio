import 'dart:async';
import 'dart:convert';

import 'app_version.dart';
import 'github_updates.dart';
import 'external_links.dart';
import 'event_backup.dart';
import 'backup_merge.dart';

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'storage.dart';
import 'exports.dart';
import 'csv_example.dart';
import 'csv_delta.dart';
import 'file_dialogs.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  if (args.length == 2 && args.first == '--smoke-test') {
    try {
      await store.open(path: args[1]);
      final sample = demoProject();
      sample['attendanceTarget'] = 25;
      sample['joining'] = 'Petits côtés';
      arrange(sample);
      final added = addFurniture(sample, [
        rows(sample, 'types').first,
      ], all: true);
      allocate(sample);
      final summary = allocationSummary(sample);
      if (added.remaining != 0 || summary['remaining'] != 0) {
        throw StateError(
          'Mobilier ou groupes non placés dans la démonstration native',
        );
      }
      await store.save(sample);
      final restored = await store.load();
      validateProject(restored.first);
      final restoredTables = tableAssignments(restored.first);
      final restoredTotal = restoredTables.fold<int>(
        0,
        (s, t) => s + (t['occupied'] as int),
      );
      if (restoredTotal != summary['assigned']) {
        throw StateError(
          'Désaccord entre compteurs tables et bilan enregistré',
        );
      }
      await exportPdf(restored.first, '${args[1]}/runtime-plan.pdf');
      await File('${args[1]}/runtime-report.json').writeAsString(
        jsonEncode({
          'sqlite': restored.length == 1,
          'tables': tables(sample).length,
          'groups': rows(sample, 'groups').length,
          'pdf': true,
          'joining': sample['joining'],
          'batchAdded': added.placed,
          'batchRemaining': added.remaining,
          'participantsAssigned': summary['assigned'],
          'perTable': {
            for (final t in restoredTables) t['label']: t['occupied'],
          },
          'countersMatchSummary': true,
          'workspaceCounters': workspaceStats(restored.first),
        }),
      );
      await store.close();
      exit(0);
    } catch (e) {
      await File('${args[1]}/runtime-error.txt').writeAsString('$e');
      exit(1);
    }
  }
  try {
    await store.open(
      path: args.length == 2 && args.first == '--ui-test' ? args[1] : null,
    );
    runApp(
      Tableo(
        store: store,
        updateService: args.contains('--ui-test')
            ? null
            : GithubUpdateService(
                repository: githubRepository,
                installedVersion: appVersion,
              ),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SelectableText('Ouverture du stockage impossible : $e'),
          ),
        ),
      ),
    );
  }
}

class Tableo extends StatelessWidget {
  final Store store;
  final FileDialogs? fileDialogs;
  final UpdateService? updateService;
  final LinkOpener? linkOpener;
  const Tableo({
    super.key,
    required this.store,
    this.fileDialogs,
    this.updateService,
    this.linkOpener,
  });
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Tableo',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b64)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff3f5f4),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
    ),
    home: Home(
      store: store,
      fileDialogs: fileDialogs,
      updateService: updateService,
      linkOpener: linkOpener,
    ),
  );
}

class Home extends StatefulWidget {
  final Store store;
  final FileDialogs? fileDialogs;
  final UpdateService? updateService;
  final LinkOpener? linkOpener;
  const Home({
    super.key,
    required this.store,
    this.fileDialogs,
    this.updateService,
    this.linkOpener,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<Json> projects = [];
  Json? p;
  String? selected;
  double dragX = 0, dragY = 0;
  Json? resizeOrigin;
  double resizeDx = 0, resizeDy = 0;
  int page = 0;
  bool saving = false;
  bool loaded = false;
  int pendingWrites = 0;
  String status = 'Chargement…';
  final undo = <Json>[], redo = <Json>[];
  final transform = TransformationController();
  final cursorPosition = ValueNotifier<Offset?>(null);
  bool showPlaceLabels = false;
  bool checkingUpdates = false;
  UpdateInfo? availableUpdate;
  Future<void> pending = Future.value();
  @override
  void initState() {
    super.initState();
    load();
    if (widget.updateService != null) checkForUpdates(silent: true);
  }

  @override
  void dispose() {
    transform.dispose();
    cursorPosition.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final list = await widget.store.load();
    for (final event in list) {
      migrateEventSettings(event);
    }
    if (list.isEmpty && widget.store.demoOnEmpty) {
      final d = demoProject();
      await widget.store.save(d);
      list.add(d);
    }
    if (mounted) {
      setState(() {
        projects = list;
        final previous = p?['id'];
        p = list.isEmpty
            ? null
            : list.firstWhere(
                (event) => event['id'] == previous,
                orElse: () => list.first,
              );
        if (previous != p?['id']) {
          selected = null;
          undo.clear();
          redo.clear();
          transform.value = Matrix4.identity();
        }
        loaded = true;
        status = 'Enregistré localement';
      });
    }
  }

  void checkpoint() {
    if (p == null) return;
    undo.add(clone(p!));
    if (undo.length > 40) undo.removeAt(0);
    redo.clear();
  }

  Future<void> persist() async {
    final snapshot = clone(p!);
    pendingWrites++;
    setState(() {
      saving = true;
      status = 'Enregistrement…';
    });
    pending = pending
        .then((_) => widget.store.save(snapshot))
        .then((_) {
          if (mounted) {
            setState(() {
              pendingWrites--;
              saving = pendingWrites > 0;
              status = saving ? 'Enregistrement…' : 'Enregistré localement';
            });
          }
        })
        .catchError((Object e) {
          if (mounted) {
            setState(() {
              pendingWrites--;
              saving = pendingWrites > 0;
              status = 'Échec sauvegarde : $e';
            });
          }
        });
    await pending;
  }

  void change(void Function() action) {
    checkpoint();
    setState(action);
    persist();
  }

  Future<void> openGithub(Uri uri) async {
    try {
      await (widget.linkOpener ?? WindowsLinkOpener()).open(uri);
    } catch (error) {
      if (mounted) toast('Ouverture impossible : $error');
    }
  }

  Future<void> checkForUpdates({bool silent = false}) async {
    if (checkingUpdates) return;
    setState(() => checkingUpdates = true);
    try {
      final service =
          widget.updateService ??
          GithubUpdateService(
            repository: githubRepository,
            installedVersion: appVersion,
          );
      final update = await service.check();
      if (!mounted) return;
      setState(() => availableUpdate = update);
      if (!silent) {
        if (update == null) {
          toast('Votre version est à jour.');
        } else {
          await updateDetails(update);
        }
      }
    } catch (error) {
      if (mounted && !silent) {
        toast('Vérification des mises à jour impossible : $error');
      }
    } finally {
      if (mounted) setState(() => checkingUpdates = false);
    }
  }

  Future<void> updateDetails(UpdateInfo update) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Tableo ${update.version} est disponible'),
      content: const SizedBox(
        width: 500,
        child: Text(
          'Les changements sont présentés en français sur GitHub. La nouvelle version s’utilise dans son propre dossier ; vos événements restent dans votre dossier personnel Windows. La vérification ne transmet aucune donnée des événements.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Fermer'),
        ),
        TextButton(
          onPressed: () => openGithub(update.changelogUrl),
          child: const Text('Voir les changements'),
        ),
        FilledButton(
          onPressed: () => openGithub(update.releaseUrl),
          child: const Text('Télécharger sur GitHub'),
        ),
      ],
    ),
  );

  Widget versionMenu() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (availableUpdate != null)
        TextButton(
          onPressed: () => updateDetails(availableUpdate!),
          child: Text('Mise à jour ${availableUpdate!.version}'),
        ),
      PopupMenuButton<String>(
        tooltip: 'Version et mises à jour',
        onSelected: (value) {
          if (value == 'check') checkForUpdates();
          if (value == 'history') {
            final url =
                (widget.updateService ??
                        GithubUpdateService(
                          repository: githubRepository,
                          installedVersion: appVersion,
                        ))
                    .changelogUrl;
            if (url != null) openGithub(url);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'check',
            enabled: !checkingUpdates,
            child: Text(
              checkingUpdates ? 'Vérification…' : 'Vérifier les mises à jour',
            ),
          ),
          PopupMenuItem(
            value: 'history',
            enabled:
                (widget.updateService ??
                        GithubUpdateService(
                          repository: githubRepository,
                          installedVersion: appVersion,
                        ))
                    .changelogUrl !=
                null,
            child: const Text('Journal des changements (GitHub)'),
          ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text('Version $appVersion', style: TextStyle(fontSize: 12)),
        ),
      ),
    ],
  );

  void toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Confirmer'),
            ),
          ],
        ),
      ) ??
      false;
  Future<String?> ask(
    String title,
    String initial, {
    String label = 'Valeur',
    FileRequest? browse,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(labelText: label),
                ),
                if (browse != null)
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final path =
                            await (widget.fileDialogs ?? WindowsFileDialogs())
                                .choose(
                                  FileRequest(
                                    title: browse.title,
                                    initialPath: controller.text,
                                    extension: browse.extension,
                                    description: browse.description,
                                    save: browse.save,
                                  ),
                                );
                        if (!c.mounted) return;
                        if (path != null) {
                          Navigator.pop(
                            c,
                            browse.save
                                ? withExtension(path, browse.extension)
                                : path,
                          );
                        }
                      } catch (e) {
                        if (c.mounted) {
                          await showDialog<void>(
                            context: c,
                            builder: (errorContext) => AlertDialog(
                              title: const Text('Fichier inaccessible'),
                              content: Text('$e'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(errorContext),
                                  child: const Text('Fermer'),
                                ),
                              ],
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      browse.save
                          ? 'Parcourir • Enregistrer sous'
                          : 'Parcourir • Ouvrir',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(
                    c,
                    browse?.save == true
                        ? withExtension(
                            controller.text.trim(),
                            browse!.extension,
                          )
                        : controller.text.trim(),
                  );
                }
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Json?> form(
    String title,
    Json initial,
    Map<String, String> labels, {
    Map<String, List<String>> choices = const {},
    Set<String> numeric = const {},
    Set<String> integer = const {},
    void Function(Json, String)? onChoiceChanged,
    bool autoObjectLabel = false,
  }) async {
    final controls = {
      for (final k in labels.keys)
        k: TextEditingController(text: '${initial[k] ?? ''}'),
    };
    final values = {...initial};
    var labelModified = false;
    String? error;
    return showDialog<Json>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...labels.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: choices.containsKey(e.key)
                          ? DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue:
                                  choices[e.key]!.contains('${values[e.key]}')
                                  ? '${values[e.key]}'
                                  : choices[e.key]!.first,
                              items: choices[e.key]!
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                        autoObjectLabel && e.key == 'kind'
                                            ? objectLabels[v] ?? v
                                            : v,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              key: ValueKey('${e.key}-${values[e.key]}'),
                              onChanged: (v) => update(() {
                                values[e.key] = v;
                                if (autoObjectLabel &&
                                    e.key == 'kind' &&
                                    !labelModified) {
                                  controls['label']!.text =
                                      objectLabels[v] ?? v!;
                                  values['label'] = controls['label']!.text;
                                }
                                onChoiceChanged?.call(values, e.key);
                              }),
                              decoration: InputDecoration(labelText: e.value),
                            )
                          : TextField(
                              controller: controls[e.key],
                              maxLines: e.key == 'note' ? 3 : 1,
                              maxLength: e.key == 'note' ? 1000 : null,
                              onChanged: (_) {
                                if (autoObjectLabel && e.key == 'label') {
                                  labelModified = true;
                                }
                              },
                              decoration: InputDecoration(labelText: e.value),
                            ),
                    ),
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                for (final k in labels.keys) {
                  if (!choices.containsKey(k)) {
                    values[k] = controls[k]!.text.trim();
                  }
                }
                for (final k in choices.keys) {
                  values[k] ??= choices[k]!.first;
                }
                for (final k in numeric) {
                  final v = double.tryParse(
                    '${values[k]}'.replaceAll(',', '.'),
                  );
                  if (v == null || !v.isFinite || v <= 0 || v > 200) {
                    update(
                      () => error =
                          '${labels[k]} : valeur entre 0 et 200, strictement positive.',
                    );
                    return;
                  }
                  values[k] = v;
                }
                for (final k in integer) {
                  final v = int.tryParse('${values[k]}');
                  if (v == null ||
                      v < (k == 'capacity' ? 0 : 1) ||
                      v > (k == 'capacity' ? 100 : 10000)) {
                    update(
                      () => error = k == 'capacity'
                          ? 'Capacité : entier de 0 à 100 (0 = table de service).'
                          : '${labels[k]} : entier de 1 à 10000.',
                    );
                    return;
                  }
                  values[k] = v;
                }
                if (labels.containsKey('name') && '${values['name']}'.isEmpty) {
                  update(() => error = 'Un nom est nécessaire.');
                  return;
                }
                Navigator.pop(c, values);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<Json?> roomForm(Json initial, String title) => form(
    title,
    {
      for (final entry in initial.entries)
        if (!['activity', 'mealService', 'defaultSides'].contains(entry.key))
          entry.key: entry.value,
    },
    {
      'name': 'Nom de la salle',
      'alias': 'Alias',
      'address': 'Adresse',
      'width': 'Largeur (m)',
      'height': 'Profondeur (m)',
      'polygon': 'Contour optionnel : 0,0;12,0;12,6;8,6;8,9;0,9',
    },
    numeric: {'width', 'height'},
  );

  Future<Json?> eventSettingsForm(Json event) => form(
    'Nouvel événement',
    {
      'name': event['name'],
      'activity': eventActivity(event),
      'mealService': mealsEnabled(event) ? 'Oui' : 'Non',
      'defaultSides': eventSeatingSides(event),
    },
    {
      'name': 'Nom de l’événement',
      'activity': 'Activité',
      'mealService': 'Prévoir des repas',
      'defaultSides': 'Côtés assis par défaut',
    },
    choices: {
      'activity': roomActivities,
      'mealService': ['Oui', 'Non'],
      'defaultSides': seatingModes,
    },
    onChoiceChanged: (values, key) {
      if (key == 'activity') {
        values['mealService'] = activityDefaults(
          values['activity'],
        )['mealService'];
        values['defaultSides'] = activityDefaults(
          values['activity'],
        )['defaultSides'];
      }
    },
  );

  Future<void> eventProperties(Json event) async {
    var activity = eventActivity(event);
    var mealService = mealsEnabled(event) ? 'Oui' : 'Non';
    var defaultSides = eventSeatingSides(event);
    final style = event['tableCards'] as Map? ?? {};
    final name = TextEditingController(text: event['name']);
    final phrase = TextEditingController(text: style['message'] ?? '');
    var logo = style['logo'] is String ? base64Decode(style['logo']) : null;
    var loading = false;
    String? error;
    final route = DialogRoute<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Propriétés de l’événement'),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nom de l’événement',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: activity,
                    decoration: const InputDecoration(labelText: 'Activité'),
                    items: roomActivities
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() {
                      activity = value!;
                      mealService = activityDefaults(activity)['mealService'];
                      defaultSides = activityDefaults(activity)['defaultSides'];
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(mealService),
                    initialValue: mealService,
                    decoration: const InputDecoration(
                      labelText: 'Prévoir des repas',
                    ),
                    items: ['Oui', 'Non']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => mealService = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('seating-$defaultSides'),
                    initialValue: defaultSides,
                    decoration: const InputDecoration(
                      labelText: 'Côtés assis par défaut',
                    ),
                    items: seatingModes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => update(() => defaultSides = value!),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Réglage pour les nouveaux modèles de tables de cet événement. Les tables existantes gardent leurs côtés assis.',
                    ),
                  ),
                  TextField(
                    controller: phrase,
                    maxLength: 400,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Phrase sur les fiches de table (facultative)',
                    ),
                    onChanged: (_) => update(() {}),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          logo == null
                              ? 'Choisir un logo'
                              : 'Remplacer le logo',
                        ),
                        onPressed: loading
                            ? null
                            : () async {
                                update(() {
                                  loading = true;
                                  error = null;
                                });
                                try {
                                  final path =
                                      await (widget.fileDialogs ??
                                              WindowsFileDialogs())
                                          .choose(
                                            FileRequest(
                                              title: 'Logo des fiches de table',
                                              initialPath:
                                                  '${widget.store.directory}${Platform.pathSeparator}logo.png',
                                              extension: 'image',
                                              description: 'Images PNG ou JPEG',
                                              save: false,
                                            ),
                                          );
                                  if (path != null) {
                                    final bytes = await File(path)
                                        .readAsBytes();
                                    if (bytes.length > 5 * 1024 * 1024) {
                                      throw const FormatException(
                                        'Choisir une image de moins de 5 Mo.',
                                      );
                                    }
                                    final codec = await ui
                                        .instantiateImageCodec(
                                          bytes,
                                          targetWidth: 600,
                                          allowUpscaling: false,
                                        );
                                    try {
                                      final frame = await codec.getNextFrame();
                                      try {
                                        final png = await frame.image
                                            .toByteData(
                                              format: ui.ImageByteFormat.png,
                                            );
                                        if (png == null) {
                                          throw const FormatException(
                                            'Image non lisible.',
                                          );
                                        }
                                        if (c.mounted) {
                                          update(
                                            () =>
                                                logo = png.buffer.asUint8List(),
                                          );
                                        }
                                      } finally {
                                        frame.image.dispose();
                                      }
                                    } finally {
                                      codec.dispose();
                                    }
                                  }
                                } catch (e) {
                                  if (c.mounted) {
                                    update(
                                      () => error = 'Logo non chargé : $e',
                                    );
                                  }
                                } finally {
                                  if (c.mounted) update(() => loading = false);
                                }
                              },
                      ),
                      if (logo != null)
                        TextButton(
                          onPressed: loading
                              ? null
                              : () => update(() => logo = null),
                          child: const Text('Retirer le logo'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 14),
                  const Text('Aperçu indicatif d’une fiche A6'),
                  SizedBox(
                    width: 260,
                    child: AspectRatio(
                      aspectRatio: 105 / 148,
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Table 1',
                              style: TextStyle(fontSize: 26),
                            ),
                            const Text('6 places utilisables'),
                            const SizedBox(height: 16),
                            const Text('Référent exemple : 6 places'),
                            const SizedBox(height: 14),
                            if (logo != null)
                              Center(
                                child: Image.memory(
                                  logo!,
                                  height: 60,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            if (logo != null && phrase.text.trim().isNotEmpty)
                              const SizedBox(height: 8),
                            if (phrase.text.trim().isNotEmpty)
                              Text(
                                phrase.text.trim(),
                                textAlign: TextAlign.center,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ces choix sont enregistrés pour cet événement et repris à chaque export, sans nouvelle demande.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () {
                      if (name.text.trim().isEmpty) {
                        update(() => error = 'Un nom est nécessaire.');
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
    final ok = await Navigator.of(context).push(route);
    if (ok == true) {
      void apply() {
        event['name'] = name.text.trim();
        event['activity'] = activity;
        event['mealService'] = mealService;
        event['defaultSides'] = defaultSides;
        event['room'].remove('activity');
        event['room'].remove('mealService');
        event['room'].remove('defaultSides');
        event['tableCards'] = {
          'message': phrase.text.trim(),
          if (logo != null) 'logo': base64Encode(logo!),
        };
      }

      if (event['id'] == p?['id']) {
        change(apply);
      } else {
        setState(apply);
        await widget.store.save(event);
      }
    }
    await route.completed;
    name.dispose();
    phrase.dispose();
  }

  Future<void> selectEvent(Json event) async {
    await pending;
    if (!mounted) return;
    setState(() {
      p = event;
      selected = null;
      undo.clear();
      redo.clear();
      transform.value = Matrix4.identity();
    });
  }

  Future<void> createEvent() async {
    final settings = await eventSettingsForm(newProject('Nouvel événement'));
    if (settings == null) return;
    final name = (settings['name'] as String).trim();
    if (name.isEmpty) {
      toast('Un nom d’événement est nécessaire.');
      return;
    }
    final event = newProject(name)..addAll(settings);
    final room = await roomForm(event['room'], 'Créer la salle');
    if (room == null) return;
    try {
      roomPolygon(room);
    } catch (e) {
      toast('$e');
      return;
    }
    event['room'] = room;
    await widget.store.save(event);
    if (!mounted) return;
    setState(() {
      projects.add(event);
    });
    await selectEvent(event);
    if (mounted) setState(() => page = 0);
  }

  Future<void> newRoom() async {
    final initial = newProject('Salle')['room'] as Json;
    final room = await roomForm(initial, 'Créer la salle');
    if (room == null) return;
    try {
      roomPolygon(room);
    } catch (e) {
      toast('$e');
      return;
    }
    if (rows(p!, 'items').isNotEmpty &&
        !await confirm(
          'Changer de salle ?',
          'Le mobilier placé conserve ses positions, côtés assis et attributions. Vérifier les dimensions dans Contrôles. Les nouveaux modèles suivront les réglages de la nouvelle salle.',
        )) {
      return;
    }
    change(() {
      p!['activity'] = eventActivity(p!);
      p!['mealService'] = mealsEnabled(p!) ? 'Oui' : 'Non';
      p!['defaultSides'] = eventSeatingSides(p!);
      rows(p!, 'rooms').add(clone(p!['room']));
      p!['room'] = room;
    });
  }

  Future<void> roomEdit() async {
    final r = await roomForm(p!['room'], 'Salle • mesures');
    if (r != null) {
      try {
        roomPolygon(r);
      } catch (e) {
        toast('$e');
        return;
      }
      change(() {
        p!['activity'] = eventActivity(p!);
        p!['mealService'] = mealsEnabled(p!) ? 'Oui' : 'Non';
        p!['defaultSides'] = eventSeatingSides(p!);
        (p!['history'] as List).add({
          'date': DateTime.now().toIso8601String(),
          'room': clone(p!['room']),
          'items': rows(p!, 'items').map(clone).toList(),
          'types': rows(p!, 'types').map(clone).toList(),
          'joining': p!['joining'] ?? 'Aucun',
        });
        p!['room'] = r;
      });
    }
  }

  Future<void> typeEdit([Json? type]) async {
    final old = type;
    final t = await form(
      'Type de mobilier',
      type ??
          {
            'id': uid(),
            'name': 'Nouvelle table',
            'shape': 'rectangle',
            'w': 1.8,
            'h': .8,
            'capacity': eventSeatingSides(p!) == 'Un côté' ? 3 : 6,
            'sides': eventSeatingSides(p!),
            'seatSide': 'Bas',
            'quantity': 10,
            'limit': 10,
            'source': 'Propre',
            'enabled': true,
            'seating': 'Chaises',
          },
      {
        'name': 'Nom du type',
        'shape': 'Forme',
        'w': 'Longueur ou diamètre (m)',
        'h': 'Largeur (m), ignorée pour cercle/carré',
        'capacity': 'Capacité par défaut (0 = service)',
        'sides': 'Côtés assis',
        'seatSide': 'Côté assis si un seul côté',
        'quantity': 'Quantité disponible',
        'limit': 'Quantité autorisée',
        'source': 'Provenance',
        'seating': 'Assises',
      },
      choices: {
        'shape': ['rectangle', 'carré', 'cercle', 'banc'],
        'source': ['Propre', 'Salle', 'Emprunté'],
        'seating': ['Chaises', 'Bancs', 'Mixte'],
        'sides': seatingModes,
        'seatSide': seatingSideNames,
      },
      numeric: {'w', 'h'},
      integer: {'capacity', 'quantity', 'limit'},
    );
    if (t == null) return;
    if (t['limit'] > t['quantity']) {
      toast('La limite ne peut pas dépasser le stock.');
      return;
    }
    if (['cercle', 'carré'].contains(t['shape'])) t['h'] = t['w'];
    final used = rows(p!, 'items').where((i) => i['type'] == t['id']).length;
    if (used > t['limit']) {
      toast(
        '$used instances utilisées : retirer du plan avant de réduire la limite.',
      );
      return;
    }
    change(() {
      if (old == null) {
        rows(p!, 'types').add(t);
      } else {
        rows(p!, 'types')[rows(p!, 'types').indexOf(old)] = t;
      }
    });
    if (old != null &&
        await confirm(
          'Propager aux instances ?',
          'Mettre à jour assises et capacités, ainsi que les dimensions si elles ont changé ? Positions et orientations conservées. Les attributions seront contrôlées.',
        )) {
      var resized = false;
      change(() => resized = propagateFurniture(p!, old, t));
      if (resized &&
          await confirm(
            'Revoir la disposition ?',
            'Les dimensions des pièces ont changé. Proposer une nouvelle disposition automatique ? Les positions fixées sont conservées.',
          )) {
        change(() {
          final failed = arrange(p!);
          toast(
            failed == 0
                ? 'Nouvelle disposition proposée. Vérifier les contrôles.'
                : '$failed pièces sans emplacement : positions conservées.',
          );
        });
      }
    }
  }

  void addTable(Json t) => addTables([t]);
  void addTables(List<Json> types, {bool all = false}) {
    late AddResult result;
    change(() {
      result = addFurniture(p!, types, all: all);
      p!['lastFurnitureAdd'] = {
        'placed': result.placed,
        'remaining': result.remaining,
      };
      if (result.placed > 0) {
        selected = rows(p!, 'items').last['id'];
        if (!all) page = 0;
      }
    });
    toast(
      '${result.placed} objet(s) ajouté(s) en position libre. ${result.remaining} non placé(s), conservés dans le stock. ${result.placed == 0 && result.remaining == 0 ? 'Types exclus ou stock autorisé épuisé.' : ''}',
    );
  }

  void assignGroups() {
    change(() => allocate(p!));
    final summary = allocationSummary(p!);
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Attribution des groupes'),
        content: Text(
          '${summary['assigned']} / ${summary['requested']} personnes attribuées.\n${summary['remaining']} encore sans attribution.\n${(summary['excluded'] as List).isEmpty ? 'Toutes les tables passent les contrôles géométriques disponibles.' : 'Tables écartées pour conflits ou passage insuffisant : ${(summary['excluded'] as List).join(', ')}. Corriger le plan ou utiliser Disposer tables puis relancer.'}\nLes attributions verrouillées sont conservées. Vérifier les besoins dans Contrôles.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              setState(() => page = 5);
            },
            child: const Text('Voir les attributions'),
          ),
        ],
      ),
    );
  }

  Future<void> attendanceTargetEdit() async {
    final input = TextEditingController(
      text: p!['attendanceTarget']?.toString() ?? '',
    );
    String? error;
    final result = await showDialog<Json>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Objectif de personnes de l’événement'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Maximum attendu saisi par vous. Repère de préparation indépendant de la capacité réglementaire de la salle. Facultatif ; zéro est une valeur distincte de non renseigné.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: input,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Objectif maximum attendu (facultatif)',
                  ),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, {'target': null}),
              child: const Text('Non renseigné'),
            ),
            FilledButton(
              onPressed: () {
                final text = input.text.trim();
                final value = text.isEmpty ? null : int.tryParse(text);
                if (text.isNotEmpty && (value == null || value < 0)) {
                  update(
                    () => error =
                        'Entier positif ou zéro attendu, ou laisser vide.',
                  );
                  return;
                }
                Navigator.pop(c, {'target': value});
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) change(() => p!['attendanceTarget'] = result['target']);
  }

  Widget workspaceCounters(Json stats) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
    color: const Color(0xffeaf0ed),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Compteurs de l’événement',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: attendanceTargetEdit,
              child: const Text('Modifier l’objectif'),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (c, space) {
            final columns = space.maxWidth >= 900 ? 6 : 3;
            final width = (space.maxWidth - (columns - 1) * 8) / columns;
            final values = <String, String>{
              'Objectif maximum attendu':
                  stats['target']?.toString() ?? 'Non renseigné',
              'Réservations (groupes)': '${stats['reservations']}',
              'Personnes réservées': '${stats['reserved']}',
              'Capacité utilisable totale': '${stats['capacity']}',
              'Personnes attribuées': '${stats['assigned']}',
              'Places encore libres': '${stats['free']}',
            };
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: values.entries
                  .map(
                    (e) => Container(
                      key: ValueKey('workspace-${e.key}'),
                      width: width,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.key, style: const TextStyle(fontSize: 11)),
                          const SizedBox(height: 4),
                          Text(
                            e.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: e.value == 'Non renseigné' ? 15 : 21,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        ...(stats['alerts'] as List).map(
          (text) => Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
            ),
          ),
        ),
      ],
    ),
  );
  Widget joiningSettings() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 235,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('${p!['id']}-${p!['joining']}'),
                initialValue: '${p!['joining'] ?? 'Aucun'}',
                decoration: const InputDecoration(
                  labelText: 'Accolement autorisé dans ce plan',
                ),
                items: joiningModes
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (m) => change(() => p!['joining'] = m),
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Faces autorisées en contact, centres alignés, même entre dimensions différentes. Glisser près d’un bord pour accrocher (14 cm). Rondes séparées. Assises contre une table ou un mur retirées ; capacité recalculée.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> addObject() async {
    final v = await form(
      'Ajouter au plan',
      {
        'id': uid(),
        'kind': 'obstacle',
        'label': 'Obstacle',
        'shape': 'rectangle',
        'x': 1.0,
        'y': 1.0,
        'w': 1.0,
        'h': 1.0,
        'fixed': false,
      },
      {
        'label': 'Libellé (zone personnalisable)',
        'kind': 'Fonction',
        'shape': 'Forme',
        'w': 'Longueur / diamètre (m)',
        'h': 'Largeur (m)',
        'zoneColor': 'Couleur (zone)',
        'zoneFill': 'Remplissage (zone)',
      },
      choices: {
        'kind': ['obstacle', 'zone', 'entry', 'exit', 'door'],
        'zoneColor': zoneColors.keys.toList(),
        'zoneFill': zoneFills,
        'shape': ['rectangle', 'carré', 'cercle', 'triangle'],
      },
      numeric: {'w', 'h'},
      autoObjectLabel: true,
    );
    if (v != null) {
      if (['cercle', 'carré'].contains(v['shape'])) v['h'] = v['w'];
      change(() {
        rows(p!, 'items').add(v);
        selected = v['id'];
      });
    }
  }

  Future<void> itemEdit(Json t) async {
    final v = await form(
      'Modifier ${t['label']}',
      t,
      {
        'label': 'Libellé',
        'x': 'X (m)',
        'y': 'Y (m)',
        'w': 'Longueur / diamètre (m)',
        'h': 'Largeur (m)',
        if (t['kind'] == 'zone') ...{
          'zoneColor': 'Couleur',
          'zoneFill': 'Remplissage',
        },
        if (t['kind'] == 'table') ...{
          'note': 'Note d’organisation (interne)',
          'capacity': 'Capacité individuelle (0 = service)',
          'seating': 'Assises',
          'sides': 'Côtés assis',
          'seatSide': 'Côté assis si un seul côté',
        },
        if (t['kind'] == 'door') 'opening': 'Sens ouverture (indicatif)',
      },
      numeric: {'w', 'h'},
      integer: {if (t['kind'] == 'table') 'capacity'},
      choices: {
        if (t['kind'] == 'zone') ...{
          'zoneColor': zoneColors.keys.toList(),
          'zoneFill': zoneFills,
        },
        if (t['kind'] == 'table') 'seating': ['Chaises', 'Bancs', 'Mixte'],
        if (t['kind'] == 'table') 'sides': seatingModes,
        if (t['kind'] == 'table') 'seatSide': seatingSideNames,
        if (t['kind'] == 'door')
          'opening': [
            'Intérieur gauche',
            'Intérieur droite',
            'Extérieur gauche',
            'Extérieur droite',
          ],
      },
    );
    if (v != null) {
      for (final k in ['x', 'y']) {
        final n = double.tryParse('${v[k]}'.replaceAll(',', '.'));
        if (n == null || !n.isFinite || n < 0) {
          toast('Position positive en mètres attendue.');
          return;
        }
        v[k] = n;
      }
      if (['cercle', 'carré'].contains(v['shape'])) v['h'] = v['w'];
      change(() {
        rows(p!, 'items')[rows(p!, 'items').indexOf(t)] = v;
      });
    }
  }

  Future<void> groupEdit([Json? g]) async {
    final v = await form(
      'Réservation de groupe',
      g ??
          {
            'id': uid(),
            'name': '',
            'count': 4,
            'meal': 'Normal',
            'allergy': '',
            'needs': '',
            'companion': 'Non',
            'alloc': <Json>[],
            'locked': false,
            'reserved': '',
          },
      {
        'name': 'Référent (prénom possible)',
        'count': 'Effectif',
        if (mealsEnabled(p!)) 'meal': 'Repas par défaut',
        'allergy': 'Allergies (complément)',
        'needs': 'Besoin de mobilité',
        'companion': 'Accompagnant proche',
        'note': 'Note d’organisation (interne)',
      },
      choices: {
        if (mealsEnabled(p!)) 'meal': List<String>.from(p!['meals']),
        'needs': ['', 'Fauteuil', 'Autre mobilité'],
        'companion': ['Non', 'Oui'],
      },
      integer: {'count'},
    );
    if (v != null) {
      final previousCount = g?['count'] as int?;
      change(() {
        if (g == null) {
          rows(p!, 'groups').add(v);
        } else {
          resizeReservation(v, v['count'], previousCount: g['count']);
          rows(p!, 'groups')[rows(p!, 'groups').indexOf(g)] = v;
        }
      });
      if (previousCount != null && previousCount != v['count']) {
        final assigned = (v['alloc'] as List).fold<int>(
          0,
          (sum, a) => sum + (a['count'] as int),
        );
        final remaining = max(0, (v['count'] as int) - assigned);
        toast(
          'Effectif modifié : $previousCount → ${v['count']} personnes. $assigned attribuées, $remaining à placer.',
        );
      }
    }
  }

  Future<void> proximityEdit(Json group) async {
    final others = rows(
      p!,
      'groups',
    ).where((g) => g['id'] != group['id']).toList();
    final draft = reservationPreferences(p!, group);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Proximité de ${group['name']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Préférences entre réservations, dans les deux sens. Proche : repère 3 m. Loin : repère ${farPreferenceDistance(p!).toStringAsFixed(1)} m. Distances entre centres des tables ; priorité à l’éloignement si les souhaits se concurrencent. Relancer l’attribution après modification.',
                  ),
                  if (others.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Ajouter une autre réservation pour définir une préférence.',
                      ),
                    ),
                  ...others.map(
                    (other) => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: InputDecoration(labelText: other['name']),
                        initialValue: draft[other['id']] ?? '',
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Sans préférence'),
                          ),
                          DropdownMenuItem(
                            value: 'near',
                            child: Text('Proche de ce groupe'),
                          ),
                          DropdownMenuItem(
                            value: 'far',
                            child: Text('Loin de ce groupe'),
                          ),
                        ],
                        onChanged: (value) => update(() {
                          draft.remove(other['id']);
                          if (value != '') {
                            draft[other['id'] as String] = value!;
                          }
                        }),
                      ),
                    ),
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
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      change(() {
        for (final other in others) {
          setReservationPreference(
            p!,
            group,
            other['id'] as String,
            draft[other['id']],
          );
        }
      });
      toast(
        'Préférences enregistrées. Relancer l’attribution automatique pour les prendre en compte.',
      );
    }
  }

  Future<void> allocationEdit(Json g) async {
    final ts = tables(p!);
    final counts = {
      for (final t in ts)
        t['id'] as String: TextEditingController(
          text:
              '${(g['alloc'] as List).where((a) => a['table'] == t['id']).fold<int>(0, (s, a) => s + (a['count'] as int))}',
        ),
    };
    var locked = g['locked'] == true;
    var reserved = '${g['reserved'] ?? ''}';
    var separate = '${g['separate'] ?? ''}';
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Tables de ${g['name']}'),
          content: SizedBox(
            width: 470,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${g['count']} places. Une attribution manuelle peut nécessiter une correction des passages.',
                  ),
                  const SizedBox(height: 12),
                  ...ts.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: counts[t['id']],
                        decoration: InputDecoration(
                          labelText:
                              '${t['label']} • ${effectiveCapacity(p!, t)} places utilisables (${t['capacity']} déclarées)',
                        ),
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: locked,
                    onChanged: (v) => update(() => locked = v!),
                    title: const Text(
                      'Conserver ces attributions lors du placement auto',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: ts.any((t) => t['id'] == reserved)
                        ? reserved
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Table imposée au placement automatique',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Aucune')),
                      ...ts.map(
                        (t) => DropdownMenuItem(
                          value: t['id'] as String,
                          child: Text(t['label']),
                        ),
                      ),
                    ],
                    onChanged: (v) => reserved = v!,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue:
                        rows(p!, 'groups').any((v) => v['id'] == separate)
                        ? separate
                        : '',
                    decoration: const InputDecoration(
                      labelText: 'Séparé de ce groupe (tables différentes)',
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('Aucun')),
                      ...rows(p!, 'groups')
                          .where((v) => v['id'] != g['id'])
                          .map(
                            (v) => DropdownMenuItem(
                              value: v['id'] as String,
                              child: Text(v['name']),
                            ),
                          ),
                    ],
                    onChanged: (v) => separate = v!,
                  ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                var sum = 0;
                for (final t in ts) {
                  final n = int.tryParse(counts[t['id']]!.text);
                  if (n == null || n < 0) {
                    update(() => error = 'Entiers positifs ou zéro attendus.');
                    return;
                  }
                  sum += n;
                  final old = (g['alloc'] as List)
                      .where((a) => a['table'] == t['id'])
                      .fold<int>(0, (s, a) => s + (a['count'] as int));
                  if (n + occupancy(p!, t['id']) - old >
                      effectiveCapacity(p!, t)) {
                    update(() => error = '${t['label']} : capacité dépassée.');
                    return;
                  }
                }
                if (sum > g['count']) {
                  update(() => error = 'Effectif du groupe dépassé.');
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
    if (ok == true) {
      change(() {
        g['alloc'] = ts
            .where((t) => int.parse(counts[t['id']]!.text) > 0)
            .map(
              (t) => {
                'table': t['id'],
                'count': int.parse(counts[t['id']]!.text),
              },
            )
            .toList();
        g['locked'] = locked;
        g['reserved'] = reserved;
        g['separate'] = separate;
        g['placementReview'] = false;
      });
    }
  }

  Future<void> anonymousSeats(Json g) async {
    final draft = clone(g);
    draft['seats'] = List<Json>.generate(
      g['count'],
      (i) => i < (g['seats'] as List? ?? []).length
          ? clone(g['seats'][i])
          : {
              'number': i + 1,
              'meal': g['meal'],
              'need': '',
              'allergy': '',
              'companion': '',
            },
    );
    var revision = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Places anonymes • ${g['name']}'),
          content: SizedBox(
            width: 720,
            height: 460,
            child: Column(
              children: [
                const Text(
                  'Places anonymes, sans identité individuelle. Retirer une place réduit l’effectif et plafonne les quantités attribuées ; vérifier ensuite les tables.',
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    key: ValueKey(revision),
                    itemCount: (draft['seats'] as List).length,
                    itemBuilder: (c, i) {
                      final s = draft['seats'][i] as Json;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Place ${i + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Retirer la place anonyme ${i + 1}',
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                  onPressed: () async {
                                    if (draft['count'] == 1) {
                                      toast(
                                        'Supprimer le groupe dans Réservations pour retirer sa dernière place.',
                                      );
                                      return;
                                    }
                                    if (await confirm(
                                      'Retirer la place anonyme ${i + 1} ?',
                                      'L’effectif de ce groupe passera de ${draft['count']} à ${(draft['count'] as int) - 1}. Repas et besoins de cette place retirés, liens d’accompagnant renumérotés. La modification reste annulable tant que vous ne cliquez pas Enregistrer.',
                                    )) {
                                      if (!c.mounted) return;
                                      update(() {
                                        removeAnonymousPlace(draft, i);
                                        revision++;
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (mealsEnabled(p!))
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      initialValue: s['meal'],
                                      decoration: const InputDecoration(
                                        labelText: 'Repas',
                                      ),
                                      items: List<String>.from(p!['meals'])
                                          .map(
                                            (m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(m),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (v) => s['meal'] = v,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    initialValue: s['need'],
                                    decoration: const InputDecoration(
                                      labelText: 'Mobilité',
                                    ),
                                    items: ['', 'Fauteuil', 'Autre mobilité']
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m,
                                            child: Text(
                                              m.isEmpty ? 'Aucun besoin' : m,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) => s['need'] = v,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: s['allergy'],
                                    onChanged: (v) => s['allergy'] = v,
                                    decoration: const InputDecoration(
                                      labelText: 'Allergies',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: s['companion'],
                                    onChanged: (v) => s['companion'] = v,
                                    decoration: const InputDecoration(
                                      labelText: 'Accompagnant : n° place liée',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
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
        resizeReservation(draft, draft['count']);
        g.clear();
        g.addAll(draft);
      });
    }
  }

  Future<void> resetReservations() async {
    final stats = workspaceStats(p!);
    if (await confirm(
      'Supprimer toutes les réservations ?',
      '${stats['reservations']} groupe(s), ${stats['reserved']} personne(s) seront supprimés, avec leurs besoins, repas et attributions. Salle, mobilier, capacités, positions des tables et objectif de l’événement conservés.',
    )) {
      change(() {
        clearReservations(p!);
        search = '';
      });
    }
  }

  Future<List<Json>?> chooseImportSources(List<Json> events) async {
    if (events.length < 2) return events;
    int? source;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Origine du contenu à importer'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Utiliser le contenu d’un seul événement ou fusionner les événements sélectionnés ?',
                  ),
                  for (var i = 0; i < events.length; i++)
                    ListTile(
                      title: Text('Événement ${i + 1} : ${events[i]['name']}'),
                      leading: Icon(
                        source == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: () => update(() => source = i),
                    ),
                  ListTile(
                    title: const Text('Fusionner les événements sélectionnés'),
                    subtitle: const Text(
                      'Choix explicite pour les salles, modèles ou réservations en commun.',
                    ),
                    leading: Icon(
                      source == -1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: () => update(() => source = -1),
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
              onPressed: source == null ? null : () => Navigator.pop(c, true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return null;
    return source == -1 ? events : [events[source!]];
  }

  Future<Map<String, String>?> resolveBackupConflicts(
    BackupMergePlan plan,
  ) async {
    if (plan.conflicts.isEmpty) return {};
    final decisions = <String, String>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('Éléments en commun (${plan.conflicts.length})'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choisissez la version à conserver pour chaque élément, y compris ceux de l’événement ouvert. Aucun choix n’est fait automatiquement.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pour le mobilier, garder une version garde son modèle et ses tables. Les versions écartées et leurs tables sont retirées du résultat, y compris celles de l’événement ouvert ; leurs attributions deviennent à réattribuer. Les réservations écartées ne sont pas conservées. La salle active reste inchangée.',
                  ),
                  TextButton(
                    onPressed: () => update(() {
                      for (final conflict in plan.conflicts) {
                        decisions[conflict.key] = keepAllVersions;
                      }
                    }),
                    child: const Text('Tout conserver séparément'),
                  ),
                  for (final conflict in plan.conflicts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            conflict.label,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final version in conflict.versions)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Text(
                                '${version.origin}\n${version.description}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              '${conflict.key}/${decisions[conflict.key]}',
                            ),
                            isExpanded: true,
                            initialValue: decisions[conflict.key],
                            decoration: const InputDecoration(
                              labelText: 'Version à garder',
                            ),
                            items: [
                              for (final version in conflict.versions)
                                DropdownMenuItem(
                                  value: version.token,
                                  child: Text(
                                    '${version.origin} — ${version.description}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const DropdownMenuItem(
                                value: keepAllVersions,
                                child: Text(
                                  'Conserver les versions séparément',
                                ),
                              ),
                            ],
                            onChanged: (value) =>
                                update(() => decisions[conflict.key] = value!),
                          ),
                        ],
                      ),
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
              onPressed: decisions.length == plan.conflicts.length
                  ? () => Navigator.pop(c, true)
                  : null,
              child: const Text('Importer les choix'),
            ),
          ],
        ),
      ),
    );
    return accepted == true ? decisions : null;
  }

  Future<List<Json>?> selectBackupEvents(
    List<Json> events, {
    required bool importing,
  }) {
    final chosen = <int>{
      for (var i = 0; i < events.length; i++)
        if (importing || events[i]['id'] == p?['id']) i,
    };
    return showDialog<List<Json>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            importing ? 'Événements à importer' : 'Événements à sauvegarder',
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: Text(importing ? 'Tout importer' : 'Tout sauvegarder'),
                  value: chosen.length == events.length,
                  onChanged: (value) => update(() {
                    chosen.clear();
                    if (value == true) {
                      chosen.addAll(List.generate(events.length, (i) => i));
                    }
                  }),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < events.length; i++)
                          CheckboxListTile(
                            title: Text(events[i]['name']),
                            subtitle: Text(
                              '${events[i]['room']['name']} • ${rows(events[i], 'groups').length} réservations',
                            ),
                            value: chosen.contains(i),
                            onChanged: (value) => update(() {
                              value == true ? chosen.add(i) : chosen.remove(i);
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(c, [
                      for (var i = 0; i < events.length; i++)
                        if (chosen.contains(i)) events[i],
                    ]),
              child: Text(importing ? 'Importer la sélection' : 'Continuer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> saveImportedEvents(List<Json> events) async {
    final navigator = Navigator.of(context);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Import en cours'),
          content: SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ),
    );
    navigator.push(progress);
    try {
      await pending;
      await widget.store.saveEvents(events);
    } finally {
      if (navigator.mounted && progress.isActive) {
        navigator.removeRoute(progress);
      }
    }
  }

  Future<void> fileAction(String action) async {
    final isPdf = action == 'Export PDF';
    final exportPlaceLabels = showPlaceLabels;
    final snapshot = action == 'Importer projet' ? null : clone(p!);
    final atClick = DateTime.now();
    final reference = uid();
    Json? backup;
    if (action == 'Exporter projet') {
      final events = projects
          .map((event) => clone(event['id'] == p!['id'] ? p! : event))
          .toList();
      final chosen = await selectBackupEvents(events, importing: false);
      if (chosen == null) return;
      backup = eventBackup(chosen);
    }
    if (!mounted) return;
    var includePlan = true, includeSummary = true, includeCards = true;
    var includeReception = false, includeService = false;
    if (isPdf) {
      final occupied = tables(snapshot!)
          .any((t) => occupancy(snapshot, t['id']) > 0);
      includeCards = occupied;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: const Text('Export PDF'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Choisissez les éléments à réunir dans un seul PDF.',
                    ),
                    CheckboxListTile(
                      title: const Text('Plan de salle'),
                      value: includePlan,
                      onChanged: (value) => update(() => includePlan = value!),
                    ),
                    CheckboxListTile(
                      title: const Text('Récapitulatif de l’événement'),
                      subtitle: const Text(
                        'Réservations, attributions, repas et besoins',
                      ),
                      value: includeSummary,
                      onChanged: (value) =>
                          update(() => includeSummary = value!),
                    ),
                    CheckboxListTile(
                      title: const Text('Fiches de table'),
                      subtitle: Text(
                        occupied
                            ? 'Quatre fiches A6 par feuille A4, tables occupées uniquement'
                            : 'Aucune table occupée : attribuez les réservations pour créer des fiches',
                      ),
                      value: includeCards,
                      onChanged: occupied
                          ? (value) => update(() => includeCards = value!)
                          : null,
                    ),
                    CheckboxListTile(
                      title: const Text('Liste d’accueil'),
                      subtitle: const Text(
                        'Référents classés par nom, effectifs, tables et cases de pointage imprimées',
                      ),
                      value: includeReception,
                      onChanged: (value) =>
                          update(() => includeReception = value!),
                    ),
                    CheckboxListTile(
                      title: const Text('Fiche cuisine et service'),
                      subtitle: const Text(
                        'Quantités de repas, service par table, allergies et besoins particuliers',
                      ),
                      value: includeService,
                      onChanged: (value) =>
                          update(() => includeService = value!),
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
                onPressed:
                    includePlan ||
                        includeSummary ||
                        includeCards ||
                        includeReception ||
                        includeService
                    ? () => Navigator.pop(c, true)
                    : null,
                child: const Text('Continuer'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
    }
    final defaultPath = isPdf
        ? newPdfPath(widget.store.directory)
        : '${widget.store.directory}${Platform.pathSeparator}projet-tableo.tableo.json';
    final path = await ask(
      '$action • chemin du fichier',
      defaultPath,
      label: 'Chemin complet (dossier existant)',
      browse: FileRequest(
        title: action,
        initialPath: defaultPath,
        extension: isPdf ? 'pdf' : 'tableo.json',
        description: isPdf ? 'PDF (*.pdf)' : 'Projet Tableo (*.json)',
        save: action != 'Importer projet',
      ),
    );
    if (path == null) return;
    try {
      if (action == 'Importer projet') {
        final available = readEventBackup(await File(path).readAsString());
        if (!mounted) return;
        final chosen = await selectBackupEvents(available, importing: true);
        if (chosen == null) return;
        if (!mounted) return;
        var complete = true,
            furniture = false,
            reservations = false,
            rooms = false;
        final mode = await showDialog<bool>(
          context: context,
          builder: (c) => StatefulBuilder(
            builder: (c, update) => AlertDialog(
              title: const Text('Contenu à importer'),
              content: SizedBox(
                width: 540,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CheckboxListTile(
                        title: const Text(
                          'Restauration complète des événements',
                        ),
                        subtitle: const Text(
                          'Restaure tout : événements, salles, plan et disposition, mobilier, réservations et attributions, zones, obstacles, entrées, sorties et autres réglages. Recrée les événements de la sauvegarde, séparément de l’événement ouvert.',
                        ),
                        value: complete,
                        onChanged: (value) => update(() {
                          complete = value!;
                          if (complete) {
                            furniture = false;
                            reservations = false;
                            rooms = false;
                          }
                        }),
                      ),
                      const Divider(),
                      Text(
                        p == null
                            ? 'Ouvrez un événement pour y ajouter du contenu.'
                            : 'Import partiel dans l’événement ouvert : ${p!['name']}',
                      ),
                      CheckboxListTile(
                        title: const Text(
                          'Tout sélectionner pour l’événement ouvert',
                        ),
                        value: rooms && furniture && reservations,
                        onChanged: p == null
                            ? null
                            : (value) => update(() {
                                rooms = furniture = reservations = value!;
                                if (value == true) complete = false;
                              }),
                      ),
                      CheckboxListTile(
                        title: const Text('Salles'),
                        subtitle: const Text(
                          'Dimensions et contours, ajoutés aux salles mémorisées. La salle active reste inchangée.',
                        ),
                        value: rooms,
                        onChanged: p == null
                            ? null
                            : (value) => update(() {
                                rooms = value!;
                                if (rooms) complete = false;
                              }),
                      ),
                      CheckboxListTile(
                        title: const Text('Mobilier'),
                        subtitle: const Text(
                          'Types de mobilier, tables et bancs. Conserve la salle actuelle ; vérifier les positions après import.',
                        ),
                        value: furniture,
                        onChanged: p == null
                            ? null
                            : (value) => update(() {
                                furniture = value!;
                                if (furniture) complete = false;
                              }),
                      ),
                      CheckboxListTile(
                        title: const Text('Réservations'),
                        subtitle: const Text(
                          'Groupes, repas et besoins. Les attributions sont reprises seulement si le mobilier est importé aussi.',
                        ),
                        value: reservations,
                        onChanged: p == null
                            ? null
                            : (value) => update(() {
                                reservations = value!;
                                if (reservations) complete = false;
                              }),
                      ),
                      if (!complete)
                        const Text(
                          'Import partiel limité aux salles, au mobilier et aux réservations cochés. Pour reprendre aussi tout le plan, les zones, obstacles, entrées et sorties, choisissez « Restauration complète des événements ».',
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
                  onPressed: complete || rooms || furniture || reservations
                      ? () => Navigator.pop(c, true)
                      : null,
                  child: const Text('Importer'),
                ),
              ],
            ),
          ),
        );
        if (mode != true) return;
        if (!mounted) return;
        if (complete) {
          final imported = chosen
              .map((event) => clone(event)..['id'] = uid())
              .toList();
          await saveImportedEvents(imported);
          if (!mounted) return;
          setState(() {
            projects.addAll(imported);
            p = imported.first;
            selected = null;
            undo.clear();
            redo.clear();
            transform.value = Matrix4.identity();
          });
        } else {
          final sources = await chooseImportSources(chosen);
          if (sources == null || !mounted) return;
          final plan = BackupMergePlan(
            p!,
            sources,
            rooms: rooms,
            furniture: furniture,
            reservations: reservations,
          );
          final decisions = await resolveBackupConflicts(plan);
          if (decisions == null || !mounted) return;
          final merged = plan.apply(decisions);
          await saveImportedEvents([merged]);
          if (!mounted) return;
          checkpoint();
          setState(() {
            p!.clear();
            p!.addAll(merged);
            selected = null;
          });
        }
      } else {
        var overwrite = false;
        if (File(path).existsSync() &&
            !await confirm('Remplacer le fichier ?', path)) {
          return;
        }
        overwrite = File(path).existsSync();
        if (isPdf) {
          await exportPdf(
            snapshot!,
            path,
            exportedAt: atClick,
            exportReference: reference,
            overwriteConfirmed: overwrite,
            includePlan: includePlan,
            includeSummary: includeSummary,
            includeCards: includeCards,
            includeReception: includeReception,
            includeService: includeService,
            includePlaceLabels: exportPlaceLabels,
          );
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('PDF exporté'),
              content: SizedBox(
                width: 650,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Événement : ${snapshot['name']}\nSalle : ${snapshot['room']['name']}\nÉtat pris au clic : ${atClick.toIso8601String()}\nRéférence : $reference',
                    ),
                    const SizedBox(height: 12),
                    const Text('Nouveau fichier écrit complètement :'),
                    SelectableText(File(path).absolute.path),
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
          );
          return;
        } else {
          await File(
            path,
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(backup));
        }
      }
      toast('$action terminé : $path');
    } catch (e) {
      toast('$action impossible : $e');
    }
  }

  String? savedCsvExample;
  String get bundledCsvExample {
    final bundled =
        '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}examples${Platform.pathSeparator}modele-reservations.csv';
    return File(bundled).existsSync()
        ? bundled
        : File('examples/modele-reservations.csv').absolute.path;
  }

  Future<void> csvExample() async {
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('CSV d’exemple • réservations par groupe'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Une ligne par groupe, uniquement des exemples fictifs. Fichier UTF-8 avec accents et séparateur point-virgule, compatible avec un tableur français.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Obligatoires',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'référent : nom du groupe ou référent, prénom possible, non vide.\neffectif : entier de 1 à 10 000, nombre réel de personnes du groupe.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Facultatifs',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'repas : Normal, Végétarien, Sans gluten, Ne mange pas ; vide = Normal. Un repas personnalisé doit déjà exister dans l’événement.\nmobilité : vide, Fauteuil ou Autre mobilité ; besoin à vérifier, sans garantie PMR.\nallergies : indication complémentaire libre, cumulable avec repas et mobilité.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ne mange pas conserve une place, sans compter comme repas. Les valeurs CSV décrivent le groupe ; les exceptions par place anonyme et l’accompagnant se règlent après import dans Besoins et repas. Garder la première ligne d’en-tête ; aucune ligne de commentaire.',
                ),
                const SizedBox(height: 12),
                const Text('Modèle inclus dans l’application :'),
                SelectableText(bundledCsvExample),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Fermer'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(c, true),
            icon: const Icon(Icons.save_alt),
            label: const Text('Enregistrer une copie'),
          ),
        ],
      ),
    );
    if (save != true) return;
    final path = await ask(
      'Enregistrer le CSV d’exemple',
      '${widget.store.directory}${Platform.pathSeparator}modele-reservations.csv',
      label: 'Chemin complet dans un dossier existant',
      browse: FileRequest(
        title: 'Enregistrer le CSV d’exemple',
        initialPath:
            '${widget.store.directory}${Platform.pathSeparator}modele-reservations.csv',
        extension: 'csv',
        description: 'Réservations CSV (*.csv)',
        save: true,
      ),
    );
    if (path == null) return;
    try {
      if (File(path).existsSync() &&
          !await confirm('Remplacer le fichier ?', path)) {
        return;
      }
      await saveExampleCsv(path);
      savedCsvExample = path;
      toast(
        'CSV d’exemple enregistré : $path. Le bouton d’import proposera ce chemin ; aucune réservation modifiée.',
      );
    } catch (e) {
      toast('Enregistrement impossible : $e');
    }
  }

  Future<void> csvImport() async {
    final path = await ask(
      'Importer réservations CSV',
      savedCsvExample ?? bundledCsvExample,
      label: 'Chemin du fichier UTF-8',
      browse: FileRequest(
        title: 'Ouvrir les réservations CSV',
        initialPath: savedCsvExample ?? bundledCsvExample,
        extension: 'csv',
        description: 'Réservations CSV (*.csv)',
        save: false,
      ),
    );
    if (path == null) return;
    try {
      final csv = parseCsv(await File(path).readAsString());
      if (csv.length < 2) {
        throw const FormatException(
          'En-tête et au moins une ligne nécessaires',
        );
      }
      final headers = csv.first;
      int find(String key, int fallback) {
        final i = headers.indexWhere((h) => h.toLowerCase().contains(key));
        return i >= 0 ? i : fallback;
      }

      var nameCol = find('référ', 0),
          countCol = find('effect', min(1, headers.length - 1)),
          mealCol = find('repas', -1),
          needCol = find('mobil', -1),
          allergyCol = find('allerg', -1);
      var mode = 'Delta';
      if (!mounted) return;
      final mapping = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) {
            Widget column(String label, int value, void Function(int) set) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue: value,
                    decoration: InputDecoration(labelText: label),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('Non fourni'),
                      ),
                      ...List.generate(
                        headers.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text('${i + 1}. ${headers[i]}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => set(v!),
                  ),
                );
            return AlertDialog(
              title: const Text('Prévisualisation et mapping'),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${csv.length - 1} lignes. Extrait :'),
                      SelectableText(
                        csv.take(5).map((r) => r.join(' | ')).join('\n'),
                      ),
                      const SizedBox(height: 15),
                      column('Référent', nameCol, (v) => nameCol = v),
                      column('Effectif', countCol, (v) => countCol = v),
                      column('Repas', mealCol, (v) => mealCol = v),
                      column('Mobilité', needCol, (v) => needCol = v),
                      column('Allergies', allergyCol, (v) => allergyCol = v),
                      if (rows(p!, 'groups').isEmpty)
                        const Text(
                          'Liste vide : import en ajout, sans remplacement.',
                        )
                      else
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: mode,
                          items: ['Delta', 'Remplacer réservations']
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) => mode = v!,
                          decoration: const InputDecoration(labelText: 'Mode'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameCol < 0 || countCol < 0 || nameCol == countCol) {
                      toast(
                        'Choisir deux colonnes distinctes pour référent et effectif.',
                      );
                      return;
                    }
                    Navigator.pop(c, true);
                  },
                  child: const Text('Valider les lignes'),
                ),
              ],
            );
          },
        ),
      );
      if (mapping != true) return;
      final incoming = <Json>[];
      for (var i = 1; i < csv.length; i++) {
        final r = csv[i];
        String cell(int col) => col >= 0 && col < r.length ? r[col] : '';
        final n = int.tryParse(cell(countCol));
        if (cell(nameCol).isEmpty || n == null || n < 1 || n > 10000) {
          throw FormatException(
            'Ligne ${i + 1} : référent/effectif invalide. Import annulé.',
          );
        }
        final meal = cell(mealCol).isEmpty ? 'Normal' : cell(mealCol);
        if (!(p!['meals'] as List).contains(meal)) {
          throw FormatException(
            'Ligne ${i + 1} : repas inconnu "$meal". Ajouter ce repas avant import.',
          );
        }
        incoming.add({
          'id': uid(),
          'name': cell(nameCol),
          'count': n,
          'meal': meal,
          'needs': cell(needCol),
          'allergy': cell(allergyCol),
          'companion': 'Non',
          'alloc': <Json>[],
        });
      }
      final empty = rows(p!, 'groups').isEmpty;
      final plan = CsvImportPlan(
        mode == 'Remplacer réservations' ? [] : rows(p!, 'groups'),
        incoming,
      );
      if (empty && !plan.hasDuplicates) {
        if (!await confirm(
          'Ajouter ${incoming.length} réservations ?',
          '${incoming.fold<int>(0, (s, g) => s + (g['count'] as int))} personnes. La liste est vide : toutes les lignes validées seront ajoutées.',
        )) {
          return;
        }
        change(() => applyCsvImport(p!, plan));
        toast('Réservations ajoutées.');
        return;
      }
      if (mode == 'Remplacer réservations' && !plan.hasDuplicates) {
        if (!await confirm(
          'Remplacer ${rows(p!, 'groups').length} réservations ?',
          '${incoming.length} nouveaux groupes. Seules les réservations et leurs attributions sont remplacées ; le plan est conservé.',
        )) {
          return;
        }
        change(() => p!['groups'] = incoming);
        toast('Réservations remplacées.');
        return;
      }
      final decisions = plan.decisions,
          matches = plan.matches,
          targets = plan.targets;
      String? importError;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plan.hasDuplicates
                      ? 'Import • doublons à vérifier'
                      : 'Import • nouvelles réservations et correspondances',
                ),
                if (importError != null)
                  Text(
                    importError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            content: SizedBox(
              width: 760,
              height: 460,
              child: ListView.builder(
                itemCount: incoming.length,
                itemBuilder: (_, i) {
                  final g = incoming[i], m = matches[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ligne ${i + 2} : ${g['name']} • ${g['count']} • ${g['meal']} • ${g['needs']} • allergies : ${g['allergy']}',
                          ),
                          Text(plan.label(i)),
                          if (m.isNotEmpty)
                            Text(
                              'Existants : ${m.map((v) => '${v['count']} personnes / ${v['meal']} / ${v['needs']} / allergies : ${v['allergy']}').join(' ; ')}',
                            ),
                          DropdownButton<String>(
                            value: decisions[i],
                            hint: const Text('Choisir une action'),
                            items:
                                [
                                      'Ignorer',
                                      'Ajouter distinct',
                                      if (m.isNotEmpty) 'Mettre à jour',
                                    ]
                                    .map(
                                      (v) => DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          v == 'Ajouter distinct' &&
                                                  m.isEmpty &&
                                                  !plan.duplicates[i]
                                              ? 'Ajouter'
                                              : v,
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => update(() => decisions[i] = v!),
                          ),
                          if (decisions[i] == 'Mettre à jour')
                            DropdownButton<String>(
                              hint: const Text('Choisir le groupe existant'),
                              value: targets[i],
                              items: m
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v['id'] as String,
                                      child: Text(
                                        '${v['name']} • ${v['count']} • ${v['id'].toString().substring(v['id'].toString().length - 6)}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => update(() => targets[i] = v),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () {
                  try {
                    plan.validate();
                  } catch (e) {
                    update(() => importError = '$e');
                    return;
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Confirmer l’import'),
              ),
            ],
          ),
        ),
      );
      if (ok == true) {
        if (mode == 'Remplacer réservations' &&
            !await confirm(
              'Remplacer les réservations ?',
              'Seules les lignes retenues remplaceront les groupes et leurs attributions ; salle, mobilier et objectif conservés.',
            )) {
          return;
        }
        change(
          () => applyCsvImport(
            p!,
            plan,
            replace: mode == 'Remplacer réservations',
          ),
        );
      }
    } catch (e) {
      toast('Import annulé : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (p == null) {
      if (loaded) {
        return Scaffold(
          appBar: AppBar(title: const Text('Tableo')),
          bottomNavigationBar: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [versionMenu()],
            ),
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Aucun événement'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: createEvent,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer un événement'),
                ),
                TextButton.icon(
                  onPressed: () => fileAction('Importer projet'),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Importer une sauvegarde'),
                ),
              ],
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final alerts = issues(p!);
    final geometry = PlanGeometry(p!, rows(p!, 'items'));
    final stats = workspaceStats(p!, tableAssignments(p!, geometry));
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.table_restaurant),
            const SizedBox(width: 10),
            const Text('Tableo'),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: projects
                            .map(
                              (event) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: ChoiceChip(
                                  label: Text(event['name']),
                                  selected: event['id'] == p!['id'],
                                  onSelected: (_) => selectEvent(event),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: createEvent,
                    icon: const Icon(Icons.add),
                    label: const Text('Événement'),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Annuler',
            onPressed: undo.isEmpty
                ? null
                : () {
                    redo.add(clone(p!));
                    final prev = undo.removeLast();
                    setState(() {
                      p!.clear();
                      p!.addAll(prev);
                    });
                    persist();
                  },
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Rétablir',
            onPressed: redo.isEmpty
                ? null
                : () {
                    undo.add(clone(p!));
                    final next = redo.removeLast();
                    setState(() {
                      p!.clear();
                      p!.addAll(next);
                    });
                    persist();
                  },
            icon: const Icon(Icons.redo),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'CSV') {
                csvImport();
              } else {
                fileAction(v);
              }
            },
            itemBuilder: (_) => [
              'Exporter projet',
              'Importer projet',
              'Export PDF',
              'CSV',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Fichiers ▾'),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            extended: true,
            selectedIndex: page,
            onDestinationSelected: (v) => setState(() => page = v),
            destinations: [
              NavigationRailDestination(
                icon: Icon(Icons.map_outlined),
                label: Text('Plan de salle'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory_2_outlined),
                label: Text('Mobilier'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.groups_outlined),
                label: Text('Réservations'),
              ),
              NavigationRailDestination(
                icon: Tooltip(
                  message: alerts.isEmpty
                      ? 'Aucune alerte'
                      : '${alerts.length} alertes à examiner',
                  child: Badge(
                    isLabelVisible: alerts.isNotEmpty,
                    label: Text('${alerts.length}'),
                    child: const Icon(Icons.fact_check_outlined),
                  ),
                ),
                label: Text('Contrôles'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                label: Text('Événements'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.assignment_outlined),
                label: Text('Attributions'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: 145,
                    child: Text(
                      'V1 locale • hors ligne\n${saving ? 'En cours…' : status}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                workspaceCounters(stats),
                Expanded(
                  child: switch (page) {
                    0 => plan(),
                    1 => inventory(),
                    2 => reservations(reservationPreferenceChecks(p!)),
                    3 => controls(alerts),
                    5 => attributions(),
                    _ => events(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: const Color(0xffe7eeeb),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${tables(p!).length} tables • ${tables(p!).fold<int>(0, (s, t) => s + geometry.capacity(t))} places utilisables • ${rows(p!, 'groups').fold<int>(0, (s, g) => s + (g['count'] as int))} participants • ${alerts.length} points à examiner. Repères indicatifs, sans garantie de conformité.',
              ),
            ),
            const SizedBox(width: 16),
            if (page == 0)
              ValueListenableBuilder<Offset?>(
                valueListenable: cursorPosition,
                builder: (_, point, _) {
                  final chosen = rows(
                    p!,
                    'items',
                  ).where((item) => item['id'] == selected);
                  final item = chosen.isEmpty ? null : chosen.first;
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      [
                        if (point != null)
                          'Curseur : X ${point.dx.toStringAsFixed(2)} m • Y ${point.dy.toStringAsFixed(2)} m',
                        if (item != null)
                          '${item['label']} : X ${number(item['x']).toStringAsFixed(2)} m • Y ${number(item['y']).toStringAsFixed(2)} m',
                      ].join('\n'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            versionMenu(),
          ],
        ),
      ),
    );
  }

  Widget heading(String title, String subtitle, List<Widget> actions) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final titleBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(subtitle),
              ],
            );
            final buttons = Wrap(spacing: 8, runSpacing: 8, children: actions);
            if (constraints.maxWidth < 1100) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleBlock,
                  if (actions.isNotEmpty) const SizedBox(height: 10),
                  buttons,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: titleBlock),
                SizedBox(width: constraints.maxWidth * .65, child: buttons),
              ],
            );
          },
        ),
      );
  Future<void> roomClear() async {
    final choices = <String>{};
    var includeLocked = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final preview = clone(p!);
          clearRoom(preview, choices, includeLocked: includeLocked);
          final objects =
              rows(p!, 'items').length - rows(preview, 'items').length;
          final before = workspaceStats(p!), after = workspaceStats(preview);
          final assigned =
              (before['assigned'] as int) - (after['assigned'] as int);
          return AlertDialog(
            title: const Text('Vider la salle'),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Choisir les éléments à retirer. Les réservations, effectifs et préférences entre groupes restent conservés.',
                    ),
                    ...roomClearChoices.entries.map(
                      (e) => CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        value: choices.contains(e.key),
                        onChanged: (v) => update(() {
                          if (v == true) {
                            choices.add(e.key);
                          } else {
                            choices.remove(e.key);
                          }
                        }),
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Inclure les éléments verrouillés'),
                      value: includeLocked,
                      onChanged: (v) => update(() => includeLocked = v!),
                    ),
                    Text(
                      '$objects objets retirés • $assigned personnes désattribuées • ${rows(p!, 'types').length - rows(preview, 'types').length} types retirés.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Les éléments verrouillés sont conservés sauf si la case est cochée. Retirer une table retire aussi ses attributions, même verrouillées. Retirer seulement les types conserve les pièces placées, détachées du stock. Annuler permet de revenir en arrière après l’opération.',
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
                onPressed: choices.isEmpty
                    ? null
                    : () => Navigator.pop(c, true),
                child: const Text('Vider les éléments cochés'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true) {
      change(() {
        clearRoom(p!, choices, includeLocked: includeLocked);
        if (!rows(p!, 'items').any((i) => i['id'] == selected)) selected = null;
      });
      toast('Éléments cochés retirés. Réservations conservées.');
    }
  }

  Future<void> arrangeWithOptions() async {
    var corner = p!['arrangementCorner'] ?? arrangementCorners.first;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Disposition automatique'),
          content: SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: corner,
              decoration: const InputDecoration(labelText: 'Point de départ'),
              items: arrangementCorners
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => update(() => corner = value),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Disposer'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    change(() {
      p!['arrangementCorner'] = corner;
      final failed = arrange(p!);
      toast(
        failed == 0
            ? 'Disposition proposée. Examiner les contrôles.'
            : 'Pas assez de place : $failed tables placées hors salle, en rouge. Réduire le nombre de tables ou revoir la salle et les passages.',
      );
    });
  }

  Widget plan() {
    final geometry = PlanGeometry(p!, rows(p!, 'items'));
    final attributionRows = tableAssignments(p!, geometry);
    final conflicts = {
      for (final i in tables(p!))
        if (!fits(p!, i, rows(p!, 'items'), geometry: geometry))
          i['id'] as String,
    };
    final palette = planMarkerColors(p!);
    final markerNames = palette.keys.toList();
    final markerColors = {
      for (final entry in palette.entries) entry.key: Color(entry.value),
    };
    final counts = Map<String, int>.unmodifiable({
      for (final row in attributionRows)
        row['id'] as String: row['occupied'] as int,
    });
    final counterKey = ValueKey(
      'plan-${p!['id']}-$showPlaceLabels-${jsonEncode(attributionRows.map((r) => [r['id'], r['label'], r['occupied'], r['capacity']]).toList())}',
    );
    final room = p!['room'],
        ts = rows(p!, 'items').where((i) => i['id'] == selected).toList();
    final t = ts.isEmpty ? null : ts.first;
    final pending = tables(p!)
        .where((item) => unplacedTable(p!, item))
        .toList();
    final drawingWidth = rows(p!, 'items').fold<double>(
      number(room['width']),
      (value, item) => max(
        value,
        number(item['x']) + number(item['w']) + (pending.isEmpty ? 0 : .3),
      ),
    );
    final drawingHeight = rows(p!, 'items').fold<double>(
      number(room['height']),
      (value, item) => max(
        value,
        number(item['y']) + number(item['h']) + (pending.isEmpty ? 0 : .3),
      ),
    );
    return Column(
      children: [
        heading(
          '${room['name']}',
          '${room['width']} × ${room['height']} m • glisser un objet ; glisser le fond pour déplacer la vue',
          [
            TextButton(onPressed: roomEdit, child: const Text('Salle')),
            TextButton.icon(
              onPressed: roomClear,
              icon: const Icon(Icons.clear_all),
              label: const Text('Vider la salle'),
            ),
            TextButton(
              onPressed: () => setState(() => page = 2),
              child: const Text('Réservations →'),
            ),
            TextButton(
              onPressed: addObject,
              child: const Text('+ Objet / zone'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.rotate_right),
              label: const Text('Toutes les tables : 90°'),
              onPressed: () => change(() {
                rotateTables(p!);
                toast(
                  'Tables pivotées autour de leur centre. Les conflits sont signalés en rouge ; Annuler permet de revenir en arrière.',
                );
              }),
            ),
            FilledButton.tonal(
              onPressed: arrangeWithOptions,
              child: const Text('Disposer tables'),
            ),
          ],
        ),
        joiningSettings(),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 10, 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xffe4ebe7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LayoutBuilder(
                    key: counterKey,
                    builder: (c, constraints) {
                      final scale = max(
                        .1,
                        min(
                          (constraints.maxWidth - 60) / drawingWidth,
                          (constraints.maxHeight - 60) / drawingHeight,
                        ),
                      );
                      return InteractiveViewer(
                        transformationController: transform,
                        minScale: .4,
                        maxScale: 5,
                        boundaryMargin: const EdgeInsets.all(500),
                        child: Center(
                          child: MouseRegion(
                            onExit: (_) => cursorPosition.value = null,
                            child: Listener(
                              onPointerHover: (event) => cursorPosition.value =
                                  event.localPosition / scale,
                              onPointerMove: (event) => cursorPosition.value =
                                  event.localPosition / scale,
                              child: SizedBox(
                                width: drawingWidth * scale,
                                height: drawingHeight * scale,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      width: number(room['width']) * scale,
                                      height: number(room['height']) * scale,
                                      child: CustomPaint(
                                        painter: GridPainter(
                                          scale,
                                          roomPolygon(room),
                                        ),
                                      ),
                                    ),
                                    if (pending.isNotEmpty)
                                      Positioned(
                                        left:
                                            (number(room['width']) +
                                                max(.6, number(p!['aisle']))) *
                                            scale,
                                        top: 0,
                                        child: const Text(
                                          'Hors salle : manque de place',
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ...rows(p!, 'items').map(
                                      (i) => Positioned(
                                        left: number(i['x']) * scale,
                                        top: number(i['y']) * scale,
                                        child: GestureDetector(
                                          key: ValueKey('plan-item-${i['id']}'),
                                          behavior: i['kind'] == 'zone'
                                              ? HitTestBehavior.opaque
                                              : HitTestBehavior.deferToChild,
                                          onTap: () => setState(
                                            () => selected = i['id'],
                                          ),
                                          onDoubleTap: () => itemEdit(i),
                                          onPanStart: (_) {
                                            if (i['fixed'] != true) {
                                              selected = i['id'];
                                              checkpoint();
                                              i.remove('unplacedByArrangement');
                                              dragX = number(i['x']);
                                              dragY = number(i['y']);
                                            }
                                          },
                                          onPanUpdate: (d) {
                                            if (i['fixed'] == true) return;
                                            setState(() {
                                              i['x'] =
                                                  (dragX + d.delta.dx / scale)
                                                      .clamp(
                                                        0,
                                                        max(
                                                          0,
                                                          number(
                                                                room['width'],
                                                              ) -
                                                              number(i['w']),
                                                        ),
                                                      );
                                              i['y'] =
                                                  (dragY + d.delta.dy / scale)
                                                      .clamp(
                                                        0,
                                                        max(
                                                          0,
                                                          number(
                                                                room['height'],
                                                              ) -
                                                              number(i['h']),
                                                        ),
                                                      );
                                              dragX = number(i['x']);
                                              dragY = number(i['y']);
                                              final snapped = snapToJoin(
                                                p!,
                                                i,
                                                rows(p!, 'items'),
                                              );
                                              i['x'] = snapped['x'];
                                              i['y'] = snapped['y'];
                                            });
                                          },
                                          onPanEnd: (_) {
                                            if (i['fixed'] != true) {
                                              final snapped = snapToJoin(
                                                p!,
                                                i,
                                                rows(p!, 'items'),
                                              );
                                              setState(() {
                                                i['x'] = snapped['x'];
                                                i['y'] = snapped['y'];
                                              });
                                            }
                                            persist();
                                          },
                                          child: SizedBox(
                                            width: number(i['w']) * scale,
                                            height: number(i['h']) * scale,
                                            child: CustomPaint(
                                              painter: ItemPainter(
                                                i,
                                                i['id'] == selected,
                                                conflict: conflicts.contains(
                                                  i['id'],
                                                ),
                                                occupied: counts[i['id']] ?? 0,
                                                capacity: i['kind'] == 'table'
                                                    ? geometry.capacity(i)
                                                    : 0,
                                              ),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  if (i['kind'] == 'table' &&
                                                      showPlaceLabels)
                                                    Positioned.fill(
                                                      child: IgnorePointer(
                                                        child: ValueListenableBuilder<Matrix4>(
                                                          valueListenable:
                                                              transform,
                                                          builder:
                                                              (
                                                                _,
                                                                matrix,
                                                                child,
                                                              ) => CustomPaint(
                                                                painter: PlaceLabelsPainter(
                                                                  i,
                                                                  tablePlaceLabels(
                                                                    p!,
                                                                    i,
                                                                    geometry,
                                                                  ),
                                                                  geometry.blocked[i['id']] ??
                                                                      {},
                                                                  scale,
                                                                  scale *
                                                                          matrix
                                                                              .getMaxScaleOnAxis() >=
                                                                      85,
                                                                ),
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  if (i['kind'] == 'table')
                                                    Positioned(
                                                      bottom: 2,
                                                      left: 3,
                                                      right: 3,
                                                      child: Wrap(
                                                        spacing: 3,
                                                        runSpacing: 2,
                                                        children: [
                                                          ...tableMarkers(
                                                            p!,
                                                            i['id'] as String,
                                                          ).map(
                                                            (name) => Tooltip(
                                                              message: name,
                                                              child: Container(
                                                                width: 9,
                                                                height: 9,
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      markerColors[name],
                                                                  shape: BoxShape
                                                                      .circle,
                                                                  border: Border.all(
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  if (i['kind'] == 'zone' &&
                                                      i['id'] == selected &&
                                                      i['fixed'] != true)
                                                    ...[
                                                      'top-left',
                                                      'top-right',
                                                      'bottom-left',
                                                      'bottom-right',
                                                    ].map(
                                                      (corner) => Positioned(
                                                        left:
                                                            corner.contains(
                                                              'left',
                                                            )
                                                            ? -7
                                                            : null,
                                                        right:
                                                            corner.contains(
                                                              'right',
                                                            )
                                                            ? -7
                                                            : null,
                                                        top:
                                                            corner.contains(
                                                              'top',
                                                            )
                                                            ? -7
                                                            : null,
                                                        bottom:
                                                            corner.contains(
                                                              'bottom',
                                                            )
                                                            ? -7
                                                            : null,
                                                        child: Tooltip(
                                                          message: 'Redimensionner la zone',
                                                          child: GestureDetector(
                                                            key: ValueKey(
                                                              'resize-${i['id']}-$corner',
                                                            ),
                                                            onPanStart: (_) {
                                                              checkpoint();
                                                              resizeOrigin =
                                                                  clone(i);
                                                              resizeDx =
                                                                  resizeDy = 0;
                                                            },
                                                            onPanUpdate: (d) =>
                                                                setState(() {
                                                                  resizeDx +=
                                                                      d
                                                                          .delta
                                                                          .dx /
                                                                      scale;
                                                                  resizeDy +=
                                                                      d
                                                                          .delta
                                                                          .dy /
                                                                      scale;
                                                                  resizeZone(
                                                                    p!,
                                                                    i,
                                                                    resizeOrigin!,
                                                                    resizeDx,
                                                                    resizeDy,
                                                                    corner,
                                                                  );
                                                                }),
                                                            onPanEnd: (_) =>
                                                                persist(),
                                                            child: Container(
                                                              width: 18,
                                                              height: 18,
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .white,
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .deepOrange,
                                                                  width: 2,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  if (conflicts.contains(
                                                    i['id'],
                                                  ))
                                                    const Positioned(
                                                      top: -12,
                                                      right: -8,
                                                      child: Tooltip(
                                                        message: 'Conflit : chevauchement, dégagement ou limite de salle. Voir Contrôles.',
                                                        child: Icon(
                                                          Icons.warning_amber,
                                                          color: Colors.red,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  IgnorePointer(
                                                    child: Center(
                                                      child: Text(
                                                        '${i['label']}${i['kind'] == 'table'
                                                            ? i['capacity'] == 0
                                                                  ? '\nService'
                                                                  : '\n${counts[i['id']] ?? 0}/${geometry.capacity(i)}${unplacedTable(p!, i) ? '\nNon placée' : ''}'
                                                            : ''}',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: max(
                                                            8,
                                                            min(12, scale * .2),
                                                          ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: const Color(
                                                            0xff123c38,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 250,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 20, 16),
                  child: ListView(
                    key: const ValueKey('plan-sidebar'),
                    children: [
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Afficher les groupes par place'),
                        subtitle: const Text(
                          'Référent répété par personne attribuée. Zoomer pour lire les noms.',
                        ),
                        value: showPlaceLabels,
                        onChanged: (v) => setState(() => showPlaceLabels = v!),
                      ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('${p!['id']}-${p!['wallSupport']}'),
                        initialValue: (p!['wallSupport'] ?? 'Aucun')
                            .toString()
                            .replaceAll(' / allée centrale', ''),
                        decoration: const InputDecoration(
                          labelText: 'Appui au mur',
                        ),
                        items: wallModes
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v, maxLines: 2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => change(() => p!['wallSupport'] = v),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Places côté mur retirées. Pour réserver une allée, dessiner une zone manuellement.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Text(
                        'Légende',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ...[
                        (const Color(0xffd7ddda), 'Vide'),
                        (const Color(0xffffd9ad), 'Partiellement occupée'),
                        (const Color(0xffa9d8bf), 'Pleine'),
                      ].map(
                        (state) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(width: 18, height: 12, color: state.$1),
                              const SizedBox(width: 8),
                              Expanded(child: Text(state.$2)),
                            ],
                          ),
                        ),
                      ),
                      const ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.warning_amber, color: Colors.red),
                        title: Text('Rouge : conflit de place ou de couloir'),
                      ),
                      if (conflicts.isNotEmpty)
                        Text(
                          '${conflicts.length} tables en conflit. Voir Contrôles.',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ...markerNames.map(
                        (name) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: markerColors[name],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name)),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Repères des groupes attribués. Pour un groupe réparti, vérifier les personnes à chaque table. PMR : accès à vérifier sur place.',
                        ),
                      ),
                      const Divider(),
                      const Text(
                        'Sélection',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (t == null)
                        const Text(
                          'Cliquer un objet. Double-clic pour modifier ses dimensions et sa position.',
                        ),
                      if (t != null) ...[
                        Text(
                          '${t['label']}',
                          style: const TextStyle(fontSize: 22),
                        ),
                        Text(
                          '${t['w']} × ${t['h']} m\nX ${number(t['x']).toStringAsFixed(2)} / Y ${number(t['y']).toStringAsFixed(2)}',
                        ),
                        if (t['kind'] == 'table')
                          Text(
                            '${t['seating']} • ${t['sides']}\n${geometry.capacity(t)} places utilisables / ${t['capacity']} déclarées\n${(geometry.blocked[t['id']] ?? {}).isEmpty ? '' : 'Faces accolées sans assises : ${(geometry.blocked[t['id']] ?? {}).map((s) => {'left': 'gauche', 'right': 'droite', 'top': 'haut', 'bottom': 'bas'}[s]).join(', ')}'}',
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Position fixée'),
                          value: t['fixed'] == true,
                          onChanged: (v) => change(() => t['fixed'] = v),
                        ),
                        OutlinedButton(
                          onPressed: () => itemEdit(t),
                          child: const Text('Modifier'),
                        ),
                        if ((t['note'] ?? '').toString().isNotEmpty)
                          Text('Note : ${t['note']}'),
                        OutlinedButton(
                          onPressed: () {
                            change(() {
                              rotateTable(t, p!);
                            });
                          },
                          child: const Text('Pivoter 90°'),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (await confirm(
                              'Retirer cet objet ?',
                              'Les attributions liées à cette table seront retirées.',
                            )) {
                              change(() {
                                rows(p!, 'items').remove(t);
                                for (final g in rows(p!, 'groups')) {
                                  (g['alloc'] as List).removeWhere(
                                    (a) => a['table'] == t['id'],
                                  );
                                  if (g['reserved'] == t['id']) {
                                    g['reserved'] = '';
                                  }
                                }
                                selected = null;
                              });
                            }
                          },
                          child: const Text('Retirer'),
                        ),
                      ],
                      const Divider(),
                      const Text('Ajouter une table'),
                      ...rows(p!, 'types')
                          .where((v) => v['shape'] != 'banc')
                          .map(
                            (v) => TextButton(
                              onPressed: () => addTable(v),
                              child: Text('+ ${v['name']}'),
                            ),
                          ),
                      const Divider(),
                      OutlinedButton(
                        onPressed: () {
                          transform.value = Matrix4.identity();
                        },
                        child: const Text('Recentrer la vue'),
                      ),
                      const Text(
                        'Molette : zoom. Couleurs des tables : occupation. Gris : obstacles. Bleu : zones. Accès libellés en clair.\nÉcart entre tables mesuré bord à bord, une seule fois. Assises contrôlées aux limites de salle. Pas de distance imposée avec les autres objets ; chevauchements signalés.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget inventory() => Column(
    children: [
      heading(
        'Mobilier privé',
        'Stock et dimensions par type, réservés à cet événement.',
        [
          FilledButton(
            onPressed: () => typeEdit(),
            child: const Text('+ Type'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => addTables(
              rows(p!, 'types')
                  .where((t) => t['shape'] != 'banc' && t['enabled'] == true)
                  .toList(),
              all: true,
            ),
            child: const Text('Ajouter toutes les tables sélectionnées'),
          ),
        ],
      ),
      joiningSettings(),
      if (p!['lastFurnitureAdd'] is Map)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Card(
            child: ListTile(
              title: Text(
                'Dernier ajout : ${p!['lastFurnitureAdd']['placed']} placé(s), ${p!['lastFurnitureAdd']['remaining']} non placé(s).',
              ),
              subtitle: const Text(
                'Le reliquat reste disponible dans le stock. Aucun objet ajouté hors salle ou empilé.',
              ),
              trailing: TextButton(
                onPressed: () => setState(() => page = 0),
                child: const Text('Voir le plan'),
              ),
            ),
          ),
        ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            ...rows(p!, 'types').map(
              (t) => Card(
                child: ListTile(
                  leading: Checkbox(
                    value: t['enabled'],
                    onChanged: (v) => change(() => t['enabled'] = v),
                  ),
                  title: Text(
                    '${t['name']} • ${t['shape']} • ${t['w']} × ${t['h']} m',
                  ),
                  subtitle: Text(
                    '${t['source']} • ${t['capacity']} places • ${t['seating']}\n${rows(p!, 'items').where((i) => i['type'] == t['id']).length} utilisées / ${t['limit']} autorisées / ${t['quantity']} disponibles',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => typeEdit(t),
                        child: const Text('Modifier'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => addTable(t),
                        child: const Text('Ajouter au plan'),
                      ),
                      if (t['shape'] != 'banc')
                        TextButton(
                          onPressed: () => addTables([t], all: true),
                          child: const Text('Ajouter tout'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Encombrement de chaise : 55 cm, banc : 40 cm autour des côtés assis. Mode mixte conservateur : enveloppe de chaise. Les bancs ajoutés au plan ont leur longueur propre ; leur liaison précise aux côtés de table reste manuelle.',
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget attributions() {
    final assigned = tableAssignments(p!);
    final total = assigned.fold<int>(0, (s, t) => s + (t['occupied'] as int));
    final requested = rows(
      p!,
      'groups',
    ).fold<int>(0, (s, g) => s + (g['count'] as int));
    return Column(
      children: [
        heading(
          'Attributions par table',
          '$total / $requested personnes attribuées • effectifs par groupe, sans noms individuels.',
          [
            OutlinedButton(
              onPressed: () => setState(() => page = 0),
              child: const Text('Voir sur le plan'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => page = 2),
              child: const Text('Modifier les groupes'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              if (assigned.isEmpty)
                const Card(
                  child: ListTile(
                    title: Text(
                      'Aucune table dans le plan. Ajouter du mobilier avant d’attribuer.',
                    ),
                  ),
                ),
              ...assigned.map(
                (t) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t['label']} • ${t['occupied']} / ${t['capacity']} places',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if ((t['groups'] as List).isEmpty)
                          const Text('Aucun groupe attribué'),
                        ...rows(t, 'groups').map(
                          (g) => Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${g['name']} • ${g['count']} personnes',
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  final group = rows(
                                    p!,
                                    'groups',
                                  ).firstWhere((v) => v['id'] == g['id']);
                                  allocationEdit(group);
                                },
                                child: const Text('Modifier les tables'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (requested > total)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text(
                      '${requested - total} personnes encore sans attribution. Ouvrir Réservations et Contrôles.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String search = '';
  Widget reservations(List<String> preferenceChecks) => ListView(
    key: const ValueKey('reservations-list'),
    padding: EdgeInsets.zero,
    children: [
      heading('Réservations', 'Groupes par référent, sans noms individuels.', [
        TextButton(
          onPressed: () async {
            final v = await ask(
              'Repas personnalisé',
              '',
              label: 'Nom du repas',
            );
            if (v != null && !(p!['meals'] as List).contains(v)) {
              change(() => (p!['meals'] as List).add(v));
            }
          },
          child: const Text('+ Repas'),
        ),
        FilledButton(
          onPressed: () => groupEdit(),
          child: const Text('+ Groupe'),
        ),
        OutlinedButton.icon(
          onPressed: rows(p!, 'groups').isEmpty ? null : resetReservations,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Tout supprimer'),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Importer les réservations → attribuer les groupes aux tables',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: csvImport,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('1. Importer les réservations (CSV)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: csvExample,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('CSV d’exemple'),
                    ),
                    FilledButton.icon(
                      onPressed: assignGroups,
                      icon: const Icon(Icons.groups),
                      label: const Text('2. Attribuer les groupes aux tables'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${allocationSummary(p!)['assigned']} / ${allocationSummary(p!)['requested']} personnes attribuées. Préparer le mobilier et les passages dans Plan de salle ; corriger chaque groupe avec Tables. Les attributions verrouillées restent conservées.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            labelText: 'Rechercher un référent → sa table',
          ),
          onChanged: (v) => setState(() => search = v),
        ),
      ),
      const SizedBox(height: 12),
      ...rows(
        p!,
        'groups',
      ).where((g) => g['name'].toString().toLowerCase().contains(search.toLowerCase())).map((
        g,
      ) {
        final places = (g['alloc'] as List)
            .map((a) {
              final t = tables(p!).where((t) => t['id'] == a['table']);
              return '${t.isEmpty ? 'Table absente' : t.first['label']} (${a['count']})';
            })
            .join(', ');
        return Card(
          margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(child: Text('${g['count']}')),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g['name'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(places.isEmpty ? 'Sans attribution' : places),
                      if ((g['note'] ?? '').toString().isNotEmpty)
                        Text('Note : ${g['note']}'),
                      Builder(
                        builder: (_) {
                          final assigned = (g['alloc'] as List).fold<int>(
                            0,
                            (sum, a) => sum + (a['count'] as int),
                          );
                          final remaining = max(
                            0,
                            (g['count'] as int) - assigned,
                          );
                          return Text(
                            '${g['count']} personnes réservées • $assigned attribuées • $remaining à placer',
                            style: TextStyle(
                              color: remaining > 0 ? Colors.deepOrange : null,
                            ),
                          );
                        },
                      ),
                      Text(
                        '${mealsEnabled(p!) ? '${g['meal']} • ' : ''}${g['needs']} ${g['allergy']}',
                      ),
                      if (reservationPreferences(p!, g).isNotEmpty)
                        Text(
                          reservationPreferences(p!, g).entries
                              .map((e) {
                                final other = rows(
                                  p!,
                                  'groups',
                                ).firstWhere((v) => v['id'] == e.key);
                                return '${e.value == 'near' ? 'Proche de' : 'Loin de'} ${other['name']}';
                              })
                              .join(' • '),
                        ),
                      if ((g['seats'] as List? ?? []).isNotEmpty)
                        Text(
                          '${(g['seats'] as List).length} places anonymes détaillées ; vérifier la liaison aux tables.',
                        ),
                      ...preferenceChecks
                          .where(
                            (message) =>
                                message.startsWith('${g['name']} / ') ||
                                message.contains(' / ${g['name']} :'),
                          )
                          .map(
                            (message) => Text(
                              message,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                    ],
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => groupEdit(g),
                      child: const Text('Modifier'),
                    ),
                    TextButton(
                      onPressed: () => anonymousSeats(g),
                      child: const Text('Besoins et repas'),
                    ),
                    TextButton(
                      onPressed: () => proximityEdit(g),
                      child: const Text('Proximité'),
                    ),
                    TextButton(
                      onPressed: () => allocationEdit(g),
                      child: const Text('Tables'),
                    ),
                    Tooltip(
                      message: 'Supprimer le groupe',
                      child: TextButton.icon(
                        onPressed: () async {
                          if (await confirm(
                            'Supprimer ${g['name']} ?',
                            '1 groupe, ${g['count']} personne(s). Besoins, repas et attributions de ce groupe supprimés ; salle et tables conservées.',
                          )) {
                            change(() => removeReservation(p!, g['id']));
                          }
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Supprimer'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    ],
  );
  Widget controls(List<String> alerts) => Column(
    children: [
      heading(
        'Contrôles de préparation',
        'Aide à la décision ; vérifier les conditions réelles et obligations applicables.',
        [
          TextButton(
            onPressed: () async {
              final v = await ask(
                'Passage de travail',
                '${p!['aisle']}',
                label: 'Écart entre les bords des tables (m)',
              );
              if (v != null) {
                final n = number(v, -1);
                if (n >= .5 && n <= 3) {
                  change(() => p!['aisle'] = n);
                } else {
                  toast('Valeur entre 0,5 et 3 m attendue.');
                }
              }
            },
            child: Text('Passage ${p!['aisle']} m'),
          ),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'La valeur 90 cm est un repère de travail configurable. Les collisions sont conservatrices (boîtes englobantes). Les portes sont traitées comme zones réservées rectangulaires : saisir toute la surface du débattement. Le sens est annoté, sans calcul de l’arc.\nAccessibilité : aucun calcul de trajet continu dans cette version. Vérifier l’entrée, toute l’allée jusqu’à la place, le bout de table, l’espace fauteuil et l’accompagnant. Les besoins restent signalés.',
                ),
              ),
            ),
            if (alerts.isEmpty)
              const ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text(
                  'Aucun conflit détecté par les contrôles disponibles. Vérification sur site nécessaire.',
                ),
              ),
            ...alerts.map(
              (s) => Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.warning_amber,
                    color: Colors.deepOrange,
                  ),
                  title: Text(s),
                ),
              ),
            ),
            if (preparationNotes(p!).isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Informations de préparation',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              ...preparationNotes(p!).map(
                (note) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(note),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
  Widget events() => Column(
    children: [
      heading(
        'Événements et salles',
        'Sauvegarde locale automatique. Exporter un projet pour une copie indépendante.',
        [
          TextButton(
            onPressed: () => fileAction('Exporter projet'),
            child: const Text('Sauvegarder projet'),
          ),
          FilledButton(
            onPressed: createEvent,
            child: const Text('+ Événement'),
          ),
        ],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ...projects.map(
              (v) => Card(
                child: ListTile(
                  selected: v['id'] == p!['id'],
                  title: Text(v['name']),
                  subtitle: Text(
                    '${v['room']['name']} • ${rows(v, 'groups').length} groupes',
                  ),
                  onTap: () => setState(() {
                    p = v;
                    selected = null;
                    undo.clear();
                    redo.clear();
                    transform.value = Matrix4.identity();
                  }),
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => eventProperties(v),
                        child: const Text('Propriétés'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final name = await ask(
                            'Dupliquer la configuration',
                            '${v['name']} • copie',
                          );
                          if (name == null) return;
                          final copy = clone(v);
                          copy['id'] = uid();
                          copy['name'] = name;
                          copy['groups'] = <Json>[];
                          copy['history'] = <Json>[];
                          await widget.store.save(copy);
                          setState(() {
                            projects.add(copy);
                            p = copy;
                            selected = null;
                            undo.clear();
                            redo.clear();
                          });
                        },
                        child: const Text('Dupliquer sans réservations'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (!await confirm(
                            'Supprimer ${v['name']} ?',
                            'Toutes les données de cet événement seront supprimées de la base locale. Les copies exportées restent sous votre contrôle.',
                          )) {
                            return;
                          }
                          await pending;
                          await widget.store.delete(v['id']);
                          await load();
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Supprimer'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(),
            Text(
              'Salle active : ${p!['room']['name']}',
              style: const TextStyle(fontSize: 18),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: roomEdit,
                  child: const Text('Modifier la salle'),
                ),
                OutlinedButton(
                  onPressed: () =>
                      change(() => rows(p!, 'rooms').add(clone(p!['room']))),
                  child: const Text('Mémoriser cette salle'),
                ),
                OutlinedButton(
                  onPressed: newRoom,
                  child: const Text('+ Salle'),
                ),
              ],
            ),
            ...rows(p!, 'rooms').map(
              (r) => ListTile(
                title: Text('${r['name']} • ${r['width']} × ${r['height']} m'),
                trailing: TextButton(
                  onPressed: () => change(() {
                    final prev = clone(p!['room']);
                    p!['room'] = clone(r);
                    rows(p!, 'rooms').remove(r);
                    rows(p!, 'rooms').add(prev);
                  }),
                  child: const Text('Utiliser les dimensions'),
                ),
              ),
            ),
            const Divider(),
            Text(
              'Historique : ${(p!['history'] as List).length} instantanés avant modification de salle.',
            ),
            ...rows(p!, 'history').reversed
                .take(10)
                .map(
                  (h) => ListTile(
                    title: Text(h['date']),
                    subtitle: Text(h['room']['name']),
                    trailing: TextButton(
                      onPressed: () async {
                        if (await confirm(
                          'Restaurer la configuration ?',
                          'Salle, mobilier et plan restaurés. Les attributions personnes seront effacées pour éviter des liens invalides.',
                        )) {
                          change(() {
                            p!['room'] = clone(h['room']);
                            p!['items'] = (h['items'] as List)
                                .map((i) => clone(i))
                                .toList();
                            p!['types'] = (h['types'] as List)
                                .map((i) => clone(i))
                                .toList();
                            p!['joining'] = h['joining'] ?? 'Aucun';
                            for (final g in rows(p!, 'groups')) {
                              g['alloc'] = <Json>[];
                              g['reserved'] = '';
                            }
                          });
                        }
                      },
                      child: const Text('Restaurer'),
                    ),
                  ),
                ),
            const Divider(),
            SelectableText(
              'Données : ${widget.store.directory}\nLes données des événements restent sur cet ordinateur. La vérification des versions contacte GitHub sans transmettre vos événements. Aucun compte requis. La conservation des exports relève de votre organisation. Définir une durée appropriée selon votre contexte.',
            ),
            TextButton(
              onPressed: resetReservations,
              child: const Text(
                'Effacer les données de réservation de cet événement',
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class GridPainter extends CustomPainter {
  final double scale;
  final List<Point<double>> polygon;
  GridPainter(this.scale, this.polygon);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final line = Paint()
      ..color = const Color(0xffe5ebe7)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += scale) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += scale) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0xff536a61)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (polygon.isNotEmpty) {
      final contour = Path()
        ..moveTo(polygon.first.x * scale, polygon.first.y * scale);
      for (final pt in polygon.skip(1)) {
        contour.lineTo(pt.x * scale, pt.y * scale);
      }
      contour.close();
      final outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        contour,
      );
      canvas.drawPath(outside, Paint()..color = const Color(0xffbdc8c1));
      canvas.drawPath(
        contour,
        Paint()
          ..color = const Color(0xff536a61)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.scale != scale || old.polygon.toString() != polygon.toString();
}

class ItemPainter extends CustomPainter {
  final Json item;
  final bool selected;
  final bool conflict;
  final int occupied, capacity;
  ItemPainter(
    this.item,
    this.selected, {
    this.conflict = false,
    this.occupied = 0,
    this.capacity = 0,
  });
  @override
  void paint(Canvas c, Size s) {
    if (item['kind'] == 'zone' && item['zoneFill'] == 'Invisible') return;
    final color = item['unplacedByArrangement'] == true && conflict
        ? const Color(0xffffcccc)
        : switch (item['kind']) {
            'table' =>
              occupied == 0
                  ? const Color(0xffd7ddda)
                  : occupied < capacity
                  ? const Color(0xffffd9ad)
                  : const Color(0xffa9d8bf),
            'zone' => Color(
              zoneColors[item['zoneColor']] ?? zoneColors['Bleu']!,
            ),
            'entry' => const Color(0xffd3c3ed),
            'exit' => const Color(0xfff6dc96),
            'door' => const Color(0xfff6c4aa),
            _ => const Color(0xffc6ceca),
          };
    final style = item['kind'] == 'zone'
        ? item['zoneFill'] ?? 'Plein'
        : 'Plein';
    final fill = Paint()
      ..color = style == 'Contour seul' ? Colors.transparent : color;
    final border = Paint()
      ..color = conflict
          ? Colors.red
          : selected
          ? Colors.deepOrange
          : item['kind'] == 'zone' && style == 'Contour seul'
          ? Color.lerp(color, Colors.black, .35)!
          : const Color(0xff527567)
      ..style = PaintingStyle.stroke
      ..strokeWidth = conflict || selected ? 3 : 1.5;
    if (item['shape'] == 'cercle') {
      c.drawOval(Offset.zero & s, fill);
      c.drawOval(Offset.zero & s, border);
    } else if (item['shape'] == 'triangle') {
      final path = Path()
        ..moveTo(s.width / 2, 0)
        ..lineTo(s.width, s.height)
        ..lineTo(0, s.height)
        ..close();
      c.drawPath(path, fill);
      c.drawPath(path, border);
    } else {
      c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3)),
        fill,
      );
      c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(3)),
        border,
      );
    }
    if (style == 'Hachures' || style == 'Hachures croisées') {
      c.save();
      final path = Path();
      if (item['shape'] == 'cercle') {
        path.addOval(Offset.zero & s);
      } else if (item['shape'] == 'triangle') {
        path.moveTo(s.width / 2, 0);
        path.lineTo(s.width, s.height);
        path.lineTo(0, s.height);
        path.close();
      } else {
        path.addRect(Offset.zero & s);
      }
      c.clipPath(path);
      final hatch = Paint()
        ..color = const Color(0xff527567).withValues(alpha: .6)
        ..strokeWidth = 1;
      for (var x = -s.height; x < s.width + s.height; x += 9) {
        c.drawLine(Offset(x, 0), Offset(x + s.height, s.height), hatch);
        if (style == 'Hachures croisées') {
          c.drawLine(Offset(x, 0), Offset(x - s.height, s.height), hatch);
        }
      }
      c.restore();
    }
  }

  @override
  bool shouldRepaint(ItemPainter old) => true;
}

class PlaceLabelsPainter extends CustomPainter {
  final Json table;
  final List<String?> labels;
  final Set<String> blocked;
  final double scale;
  final bool visible;
  PlaceLabelsPainter(
    this.table,
    this.labels,
    this.blocked,
    this.scale,
    this.visible,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (!visible || labels.isEmpty) return;
    final positions = placeLabelPositions(
      table,
      labels.length,
      blocked,
    ).map((point) => Offset(point.x * scale, point.y * scale)).toList();
    for (var i = 0; i < positions.length; i++) {
      final text = TextPainter(
        text: TextSpan(
          text: labels[i] ?? 'Libre',
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: scale * .095,
            color: const Color(0xff123c38),
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: scale * .5);
      final rect = Rect.fromCenter(
        center: positions[i],
        width: scale * .52,
        height: max(scale * .20, text.height + scale * .04),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(scale * .03)),
        Paint()
          ..color = labels[i] == null
              ? const Color(0xfff1f3f2)
              : const Color(0xffe1efe7),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(scale * .03)),
        Paint()
          ..color = const Color(0xff527567)
          ..style = PaintingStyle.stroke
          ..strokeWidth = scale * .008,
      );
      text.paint(
        canvas,
        Offset(
          positions[i].dx - text.width / 2,
          positions[i].dy - text.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(PlaceLabelsPainter old) => true;
}
