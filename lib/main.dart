import 'keyboard_dialog.dart';

import 'dart:async';
import 'dart:convert';

import 'app_version.dart';
import 'event_icons.dart';
import 'github_updates.dart';
import 'external_links.dart';
import 'event_backup.dart';
import 'backup_merge.dart';

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show DragStartBehavior, kPrimaryMouseButton;

import 'domain.dart';
import 'plan_tools.dart';
import 'magnetism.dart';
import 'plan_marker.dart';
import 'parcours.dart';
import 'parcours_painter.dart';
import 'parcours_snapshot.dart';

import 'package:flutter/services.dart';

import 'storage.dart';
import 'exports.dart';
import 'csv_example.dart';
import 'csv_delta.dart';
import 'file_dialogs.dart';

part 'mixed_furniture_ui.dart';
part 'plan_workspace_ui.dart';
part 'organizer_features_ui.dart';
part 'plan_annotations_ui.dart';
part 'plan_rotation_ui.dart';

Json arrangeProject(Json project) {
  arrange(project);
  return project;
}

Future<Json> arrangeInBackground(Json project) =>
    Isolate.run(() => arrangeProject(project));

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
      final market = newProject('Marché fictif — test natif');
      market['room'].addAll({'width': 18.0, 'height': 12.0});
      market['activity'] = 'Marché de Noël';
      market['mealService'] = 'Non';
      market['arrangementMode'] = 'Parcours';
      market['parcoursSettings'] = {
        'orientation': 'Automatique',
        'closure': 'À l’extérieur',
        'exhibitorGap': 1.2,
      };
      final template = tables(demoProject()).first;
      market['items'] = <Json>[
        for (var i = 0; i < 20; i++)
          {
            ...clone(template),
            'id': 'native-parcours-$i',
            'label': 'T${i + 1}',
            'fixed': false,
          },
        {
          'id': 'native-entry',
          'label': 'Entrée',
          'kind': 'entry',
          'shape': 'rectangle',
          'fixed': false,
          'x': 0.0,
          'y': 0.0,
          'w': .6,
          'h': .6,
        },
        {
          'id': 'native-exit',
          'label': 'Sortie',
          'kind': 'exit',
          'shape': 'rectangle',
          'fixed': false,
          'x': 17.4,
          'y': 11.4,
          'w': .6,
          'h': .6,
        },
        {
          'id': 'native-bar',
          'kind': 'zone',
          'shape': 'rectangle',
          'fixed': false,
          'label': 'Bar fictif',
          'x': 8.0,
          'y': 4.0,
          'w': 2.0,
          'h': 2.0,
          'zoneFill': 'Hachures',
          'zoneColor': 'Bleu',
          'parcoursAccess': 'À desservir',
        },
      ];
      if (arrange(market) != 0 || parcoursWarnings(market).isNotEmpty) {
        throw StateError('Parcours natif incomplet');
      }
      await store.save(market);
      final restoredMarket = (await store.load()).firstWhere(
        (event) => event['id'] == market['id'],
      );
      validateProject(restoredMarket);
      if (!parcoursCurrent(restoredMarket)) {
        throw StateError('Parcours non conservé en base');
      }
      if ((restoredMarket['parcoursPlan']['services'] as List).isEmpty) {
        throw StateError('Bar non desservi dans le test natif');
      }
      await exportPdf(restoredMarket, '${args[1]}/runtime-parcours.pdf');
      final imposed = clone(market);
      imposed['id'] = 'native-imposed';
      imposed['label'] = 'Parcours imposé fictif';
      imposed['wallSupport'] = 'Tous les murs';
      imposed['parcoursSettings'] = {
        'orientation': 'Horizontale',
        'closure': 'À l’extérieur',
        'exhibitorGap': 1.2,
        'imposedLoop': true,
      };
      imposed['items'] = <Json>[
        for (var i = 0; i < 42; i++)
          {
            ...clone(template),
            'id': 'imposed-$i',
            'label': 'T${i + 1}',
            'fixed': false,
          },
        clone(rows(market, 'items').firstWhere((i) => i['kind'] == 'entry')),
      ];
      final computed = await arrangeInBackground(imposed);
      if (parcoursWarnings(computed).isNotEmpty ||
          !tables(computed).any((t) => t['parcoursRole'] == 'spine')) {
        throw StateError('Boucle imposée native invalide');
      }
      await store.save(computed);
      final restoredImposed = (await store.load()).firstWhere(
        (e) => e['id'] == 'native-imposed',
      );
      validateProject(restoredImposed);
      if (!parcoursCurrent(restoredImposed)) {
        throw StateError('Boucle imposée non conservée en base');
      }
      await exportPdf(restoredImposed, '${args[1]}/runtime-imposed.pdf');
      final mixed = newProject('Mobilier mixte fictif — test natif');
      mixed['room'].addAll({'width': 16.0, 'height': 14.0});
      mixed['mealService'] = 'Non';
      mixed['comfort'] = {...comfortableDefaults(mixed), 'wallGap': .45};
      mixed['items'] = <Json>[
        {
          'id': 'scene',
          'kind': 'zone',
          'shape': 'rectangle',
          'label': 'Scène fictive',
          'x': 5.0,
          'y': 0.0,
          'w': 6.0,
          'h': 1.0,
          'fixed': true,
        },
        for (var i = 0; i < 12; i++)
          {
            ...clone(template),
            'id': 'seat-$i',
            'kind': 'chair',
            'shape': 'chaise',
            'label': 'Chaise ${i + 1}',
            'w': .5,
            'h': .5,
            'capacity': 1,
            'fixed': false,
          },
        for (var i = 0; i < 2; i++)
          {
            ...clone(template),
            'id': 'stand-$i',
            'label': 'Stand ${i + 1}',
            'usage': furnitureUses[1],
            'x': 2.0 + i * 1.8,
            'y': 11.0,
          },
      ];
      final stand = {
        ...clone(rows(demoProject(), 'groups').first),
        'id': 'native-stand',
        'name': 'Exposant fictif',
        'count': 1,
        'alloc': <Json>[],
        'bookingKind': assignmentModes[1],
        'standUnit': standUnits[1],
        'requestedTables': 1,
        'requestedMetres': 3.0,
        'shareTable': 'Oui',
        'standAlloc': <Json>[],
      };
      mixed['groups'] = <Json>[stand];
      if (arrangeAudience(mixed, {
            'scene': 'scene',
            'side': 'Bas',
            'layout': audienceLayouts[2],
            'opening': 90.0,
            'leftAngle': 45.0,
            'rightAngle': 45.0,
          }) !=
          0) {
        throw StateError('Sièges non disposés');
      }
      allocate(mixed);
      validateProject(mixed);
      await store.save(mixed);
      final restoredMixed = (await store.load()).firstWhere(
        (e) => e['id'] == mixed['id'],
      );
      validateProject(restoredMixed);
      if (number(standSummary(restoredMixed)['assignedMetres']) != 3 ||
          (rows(restoredMixed, 'groups').single['standAlloc'] as List).length !=
              2) {
        throw StateError('Métrage non conservé en base');
      }
      await exportPdf(restoredMixed, '${args[1]}/runtime-mixed.pdf');
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
          'mixedFurnitureNative': true,
          'parcoursNative': true,
          'imposedLoopNative': true,
          'parcoursTables': tables(restoredMarket).length,
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

class Tableo extends StatefulWidget {
  final Future<Json> Function(Json)? arrangementRunner;
  final Store store;
  final FileDialogs? fileDialogs;
  final UpdateService? updateService;
  final LinkOpener? linkOpener;
  const Tableo({
    super.key,
    required this.store,
    this.arrangementRunner,
    this.fileDialogs,
    this.updateService,
    this.linkOpener,
  });
  @override
  State<Tableo> createState() => _TableoState();
}

class _TableoState extends State<Tableo> {
  late bool darkMode;
  bool savingTheme = false;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    darkMode = widget.store.darkMode;
  }

  Future<void> toggleTheme() async {
    if (savingTheme) return;
    final previous = darkMode;
    setState(() {
      darkMode = !darkMode;
      savingTheme = true;
    });
    try {
      await widget.store.saveDarkMode(darkMode);
    } catch (_) {
      if (!mounted) return;
      setState(() => darkMode = previous);
      messenger.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Le choix du thème n’a pas pu être enregistré.'),
        ),
      );
    } finally {
      if (mounted) setState(() => savingTheme = false);
    }
  }

  ThemeData appTheme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff176b64),
      brightness: brightness,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xff141c19)
        : const Color(0xfff3f5f4),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Sallunio',
    scaffoldMessengerKey: messenger,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
    home: Home(
      arrangementRunner: widget.arrangementRunner,
      store: widget.store,
      fileDialogs: widget.fileDialogs,
      updateService: widget.updateService,
      linkOpener: widget.linkOpener,
      darkMode: darkMode,
      onToggleTheme: savingTheme ? null : toggleTheme,
    ),
  );
}

class Home extends StatefulWidget {
  final Future<Json> Function(Json)? arrangementRunner;
  final Store store;
  final FileDialogs? fileDialogs;
  final UpdateService? updateService;
  final LinkOpener? linkOpener;
  final bool darkMode;
  final VoidCallback? onToggleTheme;
  const Home({
    super.key,
    required this.store,
    this.arrangementRunner,
    this.fileDialogs,
    this.updateService,
    this.linkOpener,
    this.darkMode = false,
    this.onToggleTheme,
  });
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  void refreshMixed(VoidCallback action) => setState(action);
  Widget themeButton() => IconButton(
    tooltip: widget.darkMode ? 'Passer au mode clair' : 'Passer au mode sombre',
    onPressed: widget.onToggleTheme,
    icon: Icon(
      widget.darkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
    ),
  );

  Color surfaceFor(Color light, {bool elevated = false}) => widget.darkMode
      ? elevated
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerLow
      : light;
  List<Json> projects = [];
  Json? p;
  String? selected;
  final dragOrigins = <String, Json>{};
  double dragDx = 0, dragDy = 0;
  bool magnetismEnabled = true;
  MagneticSnap dragSnap = const MagneticSnap();
  final toolbarScroll = ScrollController();
  Json? resizeOrigin;
  double resizeDx = 0, resizeDy = 0;
  int page = 0;
  bool saving = false;
  bool arranging = false, arrangementDialogOpen = false;
  bool loaded = false;
  int pendingWrites = 0;
  String status = 'Chargement…';
  final undo = <Json>[], redo = <Json>[];
  final transform = TransformationController();
  final cursorPosition = ValueNotifier<Offset?>(null);
  bool showPlaceLabels = false, showLegend = true;
  double planScale = 1;
  Offset planOrigin = Offset.zero;
  final selectedTables = <String>{};
  final selectedObjects = <String>{};
  bool removingSelection = false;
  bool reorderingEvents = false;
  bool multiSelect = false, moveAssembly = false, measuring = false;
  String planFilter = 'Toutes les tables';
  String reservationFilter = 'Toutes';
  bool selectRectangle = false;
  Offset? selectionStart, selectionEnd;
  final selectionRectangle = ValueNotifier<Rect?>(null);
  String? reviewStamp;
  _PlanReview? cachedReview;
  _PlanReview planReview() {
    final stamp = jsonEncode(p);
    if (reviewStamp != stamp || cachedReview == null) {
      cachedReview = _PlanReview(p!);
      reviewStamp = stamp;
    }
    return cachedReview!;
  }

  Set<String> selectionBase = {};
  Offset? measureStart, measureEnd;
  Set<String> draggingTables = {};
  bool dragBlocked = false;

  final planCanvasSurfaceKey = GlobalKey();
  _PlanRotationDrag? rotationDrag;
  bool rotationMode = false;
  String? rotationSelectionKey;
  bool get rotationModeActive =>
      rotationMode &&
      rotationSelectionKey == (selectedPlanIds().toList()..sort()).join('|');
  bool additiveClick = false;
  void selectPlanItem(Json item, {bool? additive, bool toggleHandles = false}) {
    final multiple = additive ?? HardwareKeyboard.instance.isControlPressed;
    var group = moveAssembly && item['kind'] == 'table'
        ? tables(p!)
              .where(
                (t) =>
                    PlanGeometry(p!, rows(p!, 'items')).sameAssembly(item, t),
              )
              .map((t) => t['id'] as String)
              .toSet()
        : {item['id'] as String};
    if (toggleHandles &&
        !multiple &&
        selectedPlanIds().contains(item['id']) &&
        selectedPlanIds().length > 1) {
      group = selectedPlanIds();
    }
    final same =
        selectedPlanIds().length == group.length &&
        group.every(selectedPlanIds().contains);
    final nextRotation =
        toggleHandles &&
            same &&
            !multiple &&
            !planReadOnly &&
            item['fixed'] != true
        ? !rotationModeActive
        : rotationModeActive && same && !multiple;
    setState(() {
      rotationMode = nextRotation;
      rotationSelectionKey = (group.toList()..sort()).join('|');
      final remove = multiple && group.every(selectedObjects.contains);
      if (!multiple) {
        selectedObjects.clear();
        selectedTables.clear();
      }
      if (remove) {
        selectedObjects.removeAll(group);
        selectedTables.removeAll(group);
      } else {
        selectedObjects.addAll(group);
        selectedTables.addAll(
          group.where((id) => tables(p!).any((t) => t['id'] == id)),
        );
      }
      selected = remove
          ? (selectedObjects.isEmpty ? null : selectedObjects.last)
          : item['id'];
    });
  }

  List<Widget> objectResizeHandles(Json item, double scale) {
    return ['top-left', 'top-right', 'bottom-left', 'bottom-right'].map((
      corner,
    ) {
      final left = corner.contains('left'), top = corner.contains('top');
      final anchor = rotatedLocalPoint(
        item,
        Point(left ? 0.0 : number(item['w']), top ? 0.0 : number(item['h'])),
      );
      return Positioned(
        left: (number(item['x']) + anchor.x) * scale - 12,
        top: (number(item['y']) + anchor.y) * scale - 12,
        child: MouseRegion(
          cursor: left == top
              ? SystemMouseCursors.resizeUpLeftDownRight
              : SystemMouseCursors.resizeUpRightDownLeft,
          child: Tooltip(
            message: 'Redimensionner — Maj : conserver les proportions',
            child: GestureDetector(
              key: ValueKey('resize-${item['id']}-$corner'),
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) {
                checkpoint();
                resizeOrigin = clone(item);
                resizeDx = resizeDy = 0;
              },
              onPanUpdate: (d) => setState(() {
                resizeDx += d.delta.dx / scale;
                resizeDy += d.delta.dy / scale;
                resizeZone(
                  p!,
                  item,
                  resizeOrigin!,
                  resizeDx,
                  resizeDy,
                  corner,
                  preserveAspect: HardwareKeyboard.instance.isShiftPressed,
                );
              }),
              onPanEnd: (_) => persist(),
              child: SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: const Color(0xff1565c0),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

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
    toolbarScroll.dispose();
    transform.dispose();
    cursorPosition.dispose();
    selectionRectangle.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final list = await widget.store.load();
    list.setAll(0, widget.store.orderedEvents(list));
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
          selectedObjects.clear();
          selectedTables.clear();
          undo.clear();
          redo.clear();
          transform.value = Matrix4.identity();
        }
        restorePlanView();
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
    if (eventReadOnly) return;
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

  bool get eventReadOnly => p?['eventLocked'] == true;
  bool get planReadOnly => eventReadOnly || p?['planLocked'] == true;
  bool? routeVisibilityOverride;
  bool get routeVisible =>
      routeVisibilityOverride ?? (p?['showParcours'] != false);
  String protectedPlan(Json project) => jsonEncode({
    for (final key in [
      'room',
      'items',
      'joining',
      'wallSupport',
      'comfort',
      'aisle',
      'seatingSides',
      'parcoursSettings',
      'audienceSettings',
      'arrangementMode',
      'arrangementCorner',
    ])
      key: project[key],
  });
  Future<void> toggleEventLock(Json event) async {
    await pending;
    if (!mounted) return;
    setState(() {
      event['eventLocked'] = event['eventLocked'] != true;
      if (event['id'] == p?['id']) {
        undo.clear();
        redo.clear();
      }
    });
    await widget.store.save(clone(event));
  }

  void togglePlanLock() {
    if (eventReadOnly) return;
    setState(() {
      p!['planLocked'] = p!['planLocked'] != true;
      undo.clear();
      redo.clear();
    });
    persist();
  }

  void change(void Function() action) {
    if (eventReadOnly) {
      toast('Événement verrouillé : lecture seule.');
      return;
    }
    final before = planReadOnly ? clone(p!) : null;
    checkpoint();
    setState(() {
      action();
      if (before != null && protectedPlan(before) != protectedPlan(p!)) {
        p!.clear();
        p!.addAll(before);
        undo.removeLast();
        toast(
          'Plan verrouillé : déverrouiller le plan pour modifier le mobilier ou la disposition.',
        );
      }
      prunePlacePreferences(p!);
    });
    persist();
  }

  Future<void> openExternalLink(Uri uri) async {
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
    builder: (c) => KeyboardDialog(
      title: Text('Sallunio ${update.version} est disponible'),
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
          onPressed: () => openExternalLink(update.changelogUrl),
          child: const Text('Voir les changements'),
        ),
        FilledButton(
          onPressed: () => openExternalLink(update.releaseUrl),
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
            if (url != null) openExternalLink(url);
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
          child: Text(
            'Version $appVersionLabel',
            style: TextStyle(fontSize: 12),
          ),
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
        builder: (c) => KeyboardDialog(
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
        builder: (c, update) => KeyboardDialog(
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
                            builder: (errorContext) => KeyboardDialog(
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
    Set<String> multiline = const {},
    bool Function(Json, String)? fieldVisible,
    Map<String, String> choiceLabels = const {},
    Widget? extraContent,
    Set<String> radioChoices = const {},
    String Function(Json, String, String)? fieldLabel,
    String? Function(Json)? validate,
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
        builder: (c, update) => KeyboardDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...labels.entries
                      .where((e) => fieldVisible?.call(values, e.key) ?? true)
                      .map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: radioChoices.contains(e.key)
                              ? RadioGroup<String>(
                                  groupValue: values[e.key] as String?,
                                  onChanged: (value) => update(() {
                                    final before = {...values};
                                    values[e.key] = value;
                                    onChoiceChanged?.call(values, e.key);
                                    for (final key in controls.keys) {
                                      if (before[key] != values[key]) {
                                        controls[key]!.text =
                                            '${values[key] ?? ''}';
                                      }
                                    }
                                  }),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(e.value),
                                      Wrap(
                                        children: [
                                          for (final value in choices[e.key]!)
                                            SizedBox(
                                              width:
                                                  values[e.key] ==
                                                      'Emplacement PMR'
                                                  ? 220
                                                  : 150,
                                              child: RadioListTile<String>(
                                                dense: true,
                                                contentPadding: EdgeInsets.zero,
                                                value: value,
                                                title: Text(value),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                )
                              : choices.containsKey(e.key)
                              ? DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue:
                                      choices[e.key]!.contains(
                                        '${values[e.key]}',
                                      )
                                      ? '${values[e.key]}'
                                      : choices[e.key]!.first,
                                  items: choices[e.key]!
                                      .map(
                                        (v) => DropdownMenuItem(
                                          value: v,
                                          child: Text(
                                            autoObjectLabel && e.key == 'kind'
                                                ? objectLabels[v] ?? v
                                                : choiceLabels[v] ?? v,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  key: ValueKey('${e.key}-${values[e.key]}'),
                                  onChanged:
                                      e.key == '_joinGapSides' &&
                                          values['_joinGapMode'] == 'Hériter'
                                      ? null
                                      : (v) => update(() {
                                          values[e.key] = v;
                                          if (autoObjectLabel &&
                                              e.key == 'kind' &&
                                              !labelModified) {
                                            controls['label']!.text =
                                                objectLabels[v] ?? v!;
                                            values['label'] =
                                                controls['label']!.text;
                                          }
                                          onChoiceChanged?.call(values, e.key);
                                        }),
                                  decoration: InputDecoration(
                                    labelText:
                                        fieldLabel?.call(
                                          values,
                                          e.key,
                                          e.value,
                                        ) ??
                                        e.value,
                                  ),
                                )
                              : TextField(
                                  controller: controls[e.key],
                                  enabled:
                                      e.key != '_joinGapM' ||
                                      values['_joinGapMode'] != 'Hériter',
                                  maxLines:
                                      e.key == 'note' ||
                                          multiline.contains(e.key)
                                      ? 3
                                      : 1,
                                  maxLength: e.key == 'note' ? 1000 : null,
                                  onChanged: (text) {
                                    values[e.key] = text;
                                    if (autoObjectLabel && e.key == 'label') {
                                      labelModified = true;
                                    }
                                  },
                                  decoration: InputDecoration(
                                    labelText:
                                        fieldLabel?.call(
                                          values,
                                          e.key,
                                          e.value,
                                        ) ??
                                        e.value,
                                    helperText: e.key == '_joinGapM'
                                        ? '0,60 m = 60 cm'
                                        : null,
                                  ),
                                ),
                        ),
                      ),
                  ?extraContent,
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
                  if (k == '_joinGapM' && values['_joinGapMode'] == 'Hériter') {
                    continue;
                  }
                  if (v == null ||
                      !v.isFinite ||
                      (k == 'angle'
                          ? v < -360
                          : [
                              '_joinGapM',
                              'x',
                              'y',
                              'offset',
                              'leftAngle',
                              'rightAngle',
                              'fanClearanceAngle',
                            ].contains(k)
                          ? v < 0
                          : v <= 0) ||
                      v >
                          (k == '_joinGapM'
                              ? 2
                              : k == 'angle'
                              ? 360
                              : 200)) {
                    update(
                      () => error = k == '_joinGapM'
                          ? 'Espacement de jonction : nombre de 0 à 2 m.'
                          : '${labels[k]} : valeur entre 0 et 200, strictement positive.',
                    );
                    return;
                  }
                  values[k] = v;
                }
                for (final k in integer) {
                  final v = int.tryParse('${values[k]}');
                  if (v == null ||
                      v < (['capacity', 'childChairs'].contains(k) ? 0 : 1) ||
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
                final validationError = validate?.call(values);
                if (validationError != null) {
                  update(() => error = validationError);
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
      'assignmentMode': eventAssignmentMode(event),
      'standUnit': event['standUnit'] ?? standUnits.first,
      'seatingAssignment': event['seatingAssignment'] ?? 'Attribué',
    },
    {
      'name': 'Nom de l’événement',
      'activity': 'Activité',
      'mealService': 'Prévoir des repas',
      'defaultSides': 'Côtés assis par défaut',
      'assignmentMode': 'Attribution principale',
      'standUnit': 'Unité des stands',
      'seatingAssignment': 'Placement des personnes',
    },
    choices: {
      'activity': roomActivities,
      'mealService': ['Oui', 'Non'],
      'defaultSides': seatingModes,
      'assignmentMode': assignmentModes,
      'standUnit': standUnits,
      'seatingAssignment': ['Attribué', 'Libre'],
    },
    onChoiceChanged: (values, key) {
      if (key == 'activity') {
        values['assignmentMode'] =
            ['Marché de Noël', 'Brocante'].contains(values['activity'])
            ? assignmentModes[1]
            : assignmentModes.first;
        values['mealService'] = activityDefaults(
          values['activity'],
        )['mealService'];
        values['defaultSides'] = activityDefaults(
          values['activity'],
        )['defaultSides'];
      }
    },
  );

  Future<void> comfortEdit(Json event) async {
    if (event['eventLocked'] == true || event['planLocked'] == true) {
      toast('Événement ou plan verrouillé.');
      return;
    }
    final initial = event['comfort'] == null && rows(event, 'items').isEmpty
        ? comfortableDefaults(event)
        : eventComfort(event);
    final controls = {
      for (final key in comfortFieldLabels.keys)
        key: TextEditingController(text: '${initial[key]}'),
    };
    var prefer = initial['preferMainAisles'] == 'Oui';
    String? error;
    Json? accepted;
    final route = DialogRoute<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: Text('Confort de ${event['name']}'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Réglages propres à cet événement • ${eventActivity(event)}${mealsEnabled(event) ? ' avec repas' : ' sans repas'}. Toutes les distances sont en mètres.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Une allée est mesurée libre d’assises. L’écart entre deux tables n’est compté qu’une fois, bord à bord. Hors jonctions, la disposition conserve au moins les deux profondeurs d’assise plus l’allée libre. Avec PMR, elle utilise la largeur d’allée PMR.',
                  ),
                  TextButton.icon(
                    key: const ValueKey('comfort-recommended'),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Proposer des valeurs confortables'),
                    onPressed: () => update(() {
                      final proposed = comfortableDefaults(event);
                      for (final key in controls.keys) {
                        controls[key]!.text = '${proposed[key]}';
                      }
                      prefer = true;
                      error = null;
                    }),
                  ),
                  const Text(
                    'Repères proposés : 60 à 65 cm par personne ; 90 cm pour une place PMR, avec 1,30 m de profondeur ; 1,20 m d’allée courante et 1,50 m avec PMR. Pour un repas, 2,40 m entre tables laisse deux assises de 60 cm et une allée de 1,20 m. Ajuster aux fauteuils, au service et à la fréquentation.',
                  ),
                  const SizedBox(height: 12),
                  for (final entry in comfortFieldLabels.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        key: ValueKey('comfort-${entry.key}'),
                        controller: controls[entry.key],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: entry.value,
                          helperText:
                              [
                                'childChairWidth',
                                'childChairDepth',
                              ].contains(entry.key)
                              ? 'Dimensions proposées pour les nouveaux modèles de chaises enfant. Adapter au mobilier réel ; les écarts entre sièges et entre rangées restent applicables.'
                              : entry.key == 'fanSideGap'
                              ? 'Éventail uniquement : recul ajouté aux sièges inclinés, avec une limite oblique près des coins de la scène. Le bloc central conserve sa propre distance.'
                              : entry.key == 'sceneGap'
                              ? 'Distance entre le bord de scène et les premiers sièges ; le bloc central ne dépend pas des angles de l’éventail.'
                              : entry.key == 'exhibitorGap'
                              ? 'Réserve privée pour les deux rangées d’exposants, indépendante de l’allée visiteurs.'
                              : entry.key == 'parcoursWallGap'
                              ? 'Derrière une rangée simple ; l’appui autorisé reste réservé aux bords de connexion.'
                              : null,
                        ),
                      ),
                    ),
                  CheckboxListTile(
                    key: const ValueKey('comfort-main-aisles'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Privilégier les places PMR près des allées principales',
                    ),
                    value: prefer,
                    onChanged: (v) => update(() => prefer = v!),
                  ),
                  const Text(
                    'Les places adaptées sont prioritaires. L’attribution privilégie ensuite celles proches des allées principales repérées ou des passages du parcours. Une zone libre peut être marquée « Allée principale ». Les places individuelles déjà imposées et les attributions verrouillées restent conservées.',
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Les repères aident à préparer le plan ; vérifier sur place la continuité du trajet et les espaces de manœuvre. Le logiciel ne certifie pas l’accessibilité.',
                  ),
                  TextButton(
                    onPressed: () => openExternalLink(
                      Uri.parse(
                        'https://www.legifrance.gouv.fr/loda/article_lc/LEGIARTI000034485952',
                      ),
                    ),
                    child: const Text('Repères officiels d’accessibilité'),
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
                final settings = <String, dynamic>{
                  for (final entry in controls.entries)
                    entry.key: number(entry.value.text, -1),
                  'preferMainAisles': prefer ? 'Oui' : 'Non',
                };
                final candidate = clone(event)..['comfort'] = settings;
                candidate['aisle'] = settings['tableGap'];
                try {
                  validateProject(candidate);
                } catch (e) {
                  update(() => error = '$e');
                  return;
                }
                accepted = settings;
                Navigator.pop(c);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    for (final control in controls.values) {
      control.dispose();
    }
    if (accepted == null) return;
    void apply() {
      event['comfort'] = accepted;
      event['aisle'] = accepted!['tableGap'];
      if (event['parcoursSettings'] is Map) {
        event['parcoursSettings']['exhibitorGap'] = accepted!['exhibitorGap'];
      }
    }

    if (event['id'] == p?['id']) {
      change(apply);
    } else {
      setState(apply);
      await widget.store.save(event);
    }
    toast(
      'Confort enregistré. Positions et attributions conservées ; relancer la disposition ou l’attribution pour appliquer les nouveaux repères.',
    );
  }

  Future<void> eventProperties(Json event) async {
    if (event['eventLocked'] == true) {
      toast('Événement verrouillé : lecture seule.');
      return;
    }
    var activity = eventActivity(event);
    var iconChoice = eventIconNames.contains(event['icon'])
        ? event['icon'] as String
        : 'Automatique';
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
        builder: (c, update) => KeyboardDialog(
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
                    key: const ValueKey('event-icon-choice'),
                    initialValue: iconChoice,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Icône de l’événement',
                    ),
                    items: [
                      for (final choice in ['Automatique', ...eventIconNames])
                        DropdownMenuItem(
                          value: choice,
                          child: Row(
                            children: [
                              Icon(
                                eventIconData[choice == 'Automatique'
                                    ? defaultEventIcon(activity)
                                    : choice],
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                choice == 'Automatique'
                                    ? 'Automatique (${defaultEventIcon(activity)})'
                                    : choice,
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (value) => update(() => iconChoice = value!),
                  ),
                  const SizedBox(height: 16),
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
                  OutlinedButton.icon(
                    onPressed: () => assignmentSettings(event),
                    icon: const Icon(Icons.event_seat),
                    label: const Text(
                      'Attribution : sièges, stands et placement libre',
                    ),
                  ),
                  const SizedBox(height: 18),
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
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(color: Color(0xff123c38)),
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
        if (iconChoice == 'Automatique') {
          event.remove('icon');
        } else {
          event['icon'] = iconChoice;
        }
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
      savePlanView();
      persist();
      p = event;
      routeVisibilityOverride = null;
      selected = null;
      selectedObjects.clear();
      selectedTables.clear();
      undo.clear();
      redo.clear();
      restorePlanView();
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
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
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
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
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
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
    final old = type;
    String category(dynamic shape) => switch (shape) {
      'banc' => 'Banc',
      'chaise' => 'Chaise',
      'chaise enfant' => 'Chaise enfant',
      'emplacement PMR' => 'Emplacement PMR',
      _ => 'Table',
    };
    final defaults = <String, Json>{
      'Table': {
        'name': 'Nouvelle table',
        'w': 1.8,
        'h': .8,
        'shape': 'rectangle',
      },
      'Banc': {'name': 'Nouveau banc', 'w': 2.0, 'h': .4, 'shape': 'banc'},
      'Chaise': {
        'name': 'Nouvelle chaise',
        'w': .5,
        'h': .5,
        'shape': 'chaise',
      },
      'Chaise enfant': {
        'name': 'Nouvelle chaise enfant',
        'w': number(eventComfort(p!)['childChairWidth']),
        'h': number(eventComfort(p!)['childChairDepth']),
        'shape': 'chaise enfant',
      },
      'Emplacement PMR': {
        'name': 'Nouvel emplacement PMR',
        'w': number(eventComfort(p!)['pmrSeatWidth']),
        'h': number(eventComfort(p!)['pmrDepth']),
        'shape': 'emplacement PMR',
      },
    };
    final t = await form(
      'Type de mobilier',
      joinGapFormValues(
        type != null
            ? {...type, '_furnitureKind': category(type['shape'])}
            : {
                '_furnitureKind': 'Table',
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
                'usage': eventAssignmentMode(p!) == assignmentModes[1]
                    ? furnitureUses[1]
                    : furnitureUses.first,
              },
      ),
      {
        '_furnitureKind': 'Catégorie de mobilier',
        'name': 'Nom du type',
        '_joinGapMode':
            'Jonctions : hériter du réglage général ou personnaliser',
        '_joinGapM': 'Espacement de jonction (m, 0 = contact)',
        '_joinGapSides': 'Bords concernés (suivent la rotation)',
        'shape': 'Forme de la table',
        'usage': 'Usage des nouvelles pièces',
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
      radioChoices: {'_furnitureKind'},
      fieldLabel: (values, key, label) => values['_furnitureKind'] == 'Table'
          ? label
          : key == 'w'
          ? (values['_furnitureKind'] == 'Banc'
                ? 'Longueur du banc (m)'
                : 'Largeur (m)')
          : key == 'h'
          ? 'Profondeur (m)'
          : label,
      onChoiceChanged: (values, key) {
        if (key != '_furnitureKind') return;
        final d = defaults[values[key]]!;
        if (defaults.values.any((v) => v['name'] == values['name'])) {
          values['name'] = d['name'];
        }
        values['shape'] = d['shape'];
        values['w'] = d['w'];
        values['h'] = d['h'];
        if (values[key] != 'Table') values['usage'] = furnitureUses.first;
      },
      fieldVisible: (values, key) =>
          values['_furnitureKind'] == 'Table' ||
          ![
            'shape',
            'usage',
            'capacity',
            'sides',
            'seatSide',
            'seating',
            '_joinGapMode',
            '_joinGapM',
            '_joinGapSides',
          ].contains(key),
      choices: {
        '_joinGapMode': ['Hériter', 'Personnaliser'],
        '_joinGapSides': joinGapSideNames,
        '_furnitureKind': defaults.keys.toList(),
        'shape': ['rectangle', 'carré', 'cercle'],
        'usage': furnitureUses,
        'source': ['Propre', 'Salle', 'Emprunté'],
        'seating': ['Chaises', 'Bancs', 'Mixte'],
        'sides': seatingModes,
        'seatSide': seatingSideNames,
      },
      numeric: {'w', 'h', '_joinGapM'},
      integer: {'capacity', 'quantity', 'limit'},
    );
    if (t == null) return;
    t.remove('_furnitureKind');
    if ([
      'chaise',
      'chaise enfant',
      'emplacement PMR',
      'banc',
    ].contains(t['shape'])) {
      t['usage'] = furnitureUses.first;
      if (['chaise', 'chaise enfant'].contains(t['shape'])) {
        t['capacity'] = 1;
        if (old == null && number(t['w']) == 1.8 && number(t['h']) == .8) {
          t['w'] = .5;
          t['h'] = .5;
        }
      }
      if (t['shape'] == 'emplacement PMR') {
        t['capacity'] = 1;
        t['w'] = number(eventComfort(p!)['pmrSeatWidth']);
        t['h'] = number(eventComfort(p!)['pmrDepth']);
      }
    }
    saveJoinGapForm(t);
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
          'Mettre à jour l’usage, les assises et les capacités, ainsi que les dimensions si elles ont changé ? Positions et orientations conservées. Les attributions incompatibles avec le nouvel usage seront retirées.',
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
  void addTables(List<Json> types, {bool all = false, int? requestedCount}) {
    if (planReadOnly) return;
    late AddResult result;
    change(() {
      result = addFurniture(
        p!,
        types,
        all: all,
        requestedCount: requestedCount,
      );
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

  Future<void> assignGroups() async {
    final bookings = rows(
      p!,
      'groups',
    ).where((g) => g['waiting'] != true).toList();
    if (bookings.isNotEmpty &&
        bookings.every(isStandBooking) &&
        !tables(p!).any((t) => furnitureUse(t) == furnitureUses[1])) {
      final available = tables(p!)
          .where(
            (t) =>
                t['kind'] == 'table' &&
                furnitureUse(t) == furnitureUses.first &&
                occupancy(p!, t['id']) == 0 &&
                !tableOutsideRoom(p!, t),
          )
          .toList();
      if (available.isNotEmpty) {
        if (!await confirm(
          'Utiliser ces tables pour les stands ?',
          'Les réservations demandent des stands, mais les tables du plan sont encore en places assises. Passer ${available.length} table(s) libres en Stand / exposition : ${available.map((t) => t['label']).join(', ')} ? Les positions et rotations seront conservées.',
        )) {
          return;
        }
        if (!mounted) return;
        change(
          () => changeFurnitureUsage(
            p!,
            available.map((t) => t['id'] as String).toSet(),
            furnitureUses[1],
          ),
        );
      }
    }
    if (!mounted) return;
    change(() => allocate(p!));
    final summary = allocationSummary(p!);
    showDialog<void>(
      context: context,
      builder: (c) => KeyboardDialog(
        title: const Text('Attribution des groupes'),
        content: Text(
          '${rows(p!, 'groups').any(isStandBooking) ? '${standSummaryLabel(p!)}\n${standAllocationWarnings(p!).join('\n')}\n' : ''}${freeSeating(p!) ? 'Placement libre : aucune attribution automatique des places assises.\n' : ''}${rows(p!, 'groups').any((g) => !isStandBooking(g)) ? '${summary['assigned']} / ${summary['requested']} personnes attribuées.\n${summary['remaining']} encore sans attribution.\n' : ''}${(summary['excluded'] as List).isEmpty ? 'Toutes les tables passent les contrôles géométriques disponibles.' : 'Tables écartées pour conflits ou passage insuffisant : ${(summary['excluded'] as List).join(', ')}. Corriger le plan ou utiliser Disposer mobilier puis relancer.'}\nLes attributions verrouillées sont conservées. Vérifier les besoins dans Contrôles.',
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
        builder: (c, update) => KeyboardDialog(
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
    color: surfaceFor(const Color(0xffeaf0ed)),
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
                        color: surfaceFor(Colors.white, elevated: true),
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
        if (rows(p!, 'groups').any(isStandBooking))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(standSummaryLabel(p!)),
          ),
      ],
    ),
  );
  Json joinGapFormValues(Json owner) {
    final resolved = owner['joinGap'] != null
        ? owner
        : tableJoinSettings(p!, owner);
    return {
      ...owner,
      '_joinGapMode': owner['joinGap'] == null ? 'Hériter' : 'Personnaliser',
      '_joinGapM': number(resolved['joinGap']),
      '_joinGapSides': resolved['joinGapSides'] ?? joinGapSideNames.first,
    };
  }

  void saveJoinGapForm(Json owner) {
    if (owner.remove('_joinGapMode') == 'Personnaliser') {
      owner['joinGap'] = number(owner['_joinGapM']);
      owner['joinGapSides'] = owner['_joinGapSides'];
    } else {
      owner.remove('joinGap');
      owner.remove('joinGapSides');
    }
    owner.remove('_joinGapM');
    owner.remove('_joinGapSides');
  }

  Future<void> joinGapDefaultsEdit() async {
    final value = await form(
      'Jonctions — réglage général du mobilier',
      {...joinGapFormValues(p!), '_joinGapMode': 'Personnaliser'},
      {
        '_joinGapM': 'Espacement entre tables jointes (m, 0 = contact)',
        '_joinGapSides': 'Bords concernés',
      },
      numeric: {'_joinGapM'},
      choices: {'_joinGapSides': joinGapSideNames},
    );
    if (value == null) return;
    saveJoinGapForm(value);
    change(() {
      p!['joinGap'] = value['joinGap'];
      p!['joinGapSides'] = value['joinGapSides'];
    });
    toast(
      'Réglage enregistré. Les positions restent conservées ; relancer la disposition pour appliquer les nouveaux écarts.',
    );
  }

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
            TextButton.icon(
              key: const ValueKey('join-gap-defaults'),
              onPressed: joinGapDefaultsEdit,
              icon: const Icon(Icons.settings_ethernet),
              label: Text(
                'Écart : ${(number(p!['joinGap']) * 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} cm',
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'Centres alignés. Écart : table → type → réglage général. Le plus grand écart est retenu une seule fois. Rondes séparées.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> addObject([String kind = 'obstacle']) async {
    if (kind == 'image') {
      await imageEditor();
      return;
    }
    if (['info', 'text', 'arrow'].contains(kind)) {
      await annotationEditor(kind);
      return;
    }
    if (planReadOnly) return;
    final v = await form(
      'Ajouter au plan',
      {
        'id': uid(),
        'kind': kind,
        'label': objectLabels[kind] ?? 'Obstacle',
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
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
    if (t['kind'] == 'image') {
      await imageEditor(t);
      return;
    }
    if (isPlanAnnotation(t)) {
      await annotationEditor(t['kind'], t);
      return;
    }
    if (isSeatingFurniture(t) && t['kind'] != 'table') {
      await seatFurnitureEdit(t);
      return;
    }
    final v = await form(
      'Modifier ${t['label']}',
      {
        ...t,
        if (t['kind'] == 'table') 'usage': furnitureUse(t),
        if (t['kind'] == 'table')
          'numberLocked': t['numberLocked'] == true ? 'Oui' : 'Non',
        if (isPlanAccess(t))
          'accessAudience': t['accessAudience'] ?? accessAudiences.first,
        if (canIncludeInProximity(t))
          'proximityEnabled': t['proximityEnabled'] ?? 'Non',
        if (t['kind'] == 'table') ...joinGapFormValues(t),
        if (t['kind'] == 'table') '_applyJoinGapNow': 'Oui',
        if (t['kind'] == 'zone') 'mainAisle': t['mainAisle'] ?? 'Non',
        if (t['kind'] == 'zone')
          'parcoursAccess': t['parcoursAccess'] ?? 'À exclure',
        if (t['kind'] == 'zone')
          'parcoursPassage': t['parcoursPassage'] ?? 'Non',
      },
      {
        'label': 'Libellé',
        if (isPlanAccess(t))
          'accessAudience':
              rows(p!, 'items').where((i) => i['kind'] == t['kind']).length == 1
              ? 'Public autorisé (accès unique : commun à tous)'
              : 'Public autorisé',
        if (canIncludeInProximity(t))
          'proximityEnabled': 'Inclure dans les préférences de proximité',
        'x': 'X (m)',
        'y': 'Y (m)',
        'w': 'Longueur / diamètre (m)',
        'h': 'Largeur (m)',
        if (t['kind'] == 'zone') ...{
          'mainAisle': 'Allée principale pour le placement PMR',
          'zoneColor': 'Couleur',
          'zoneFill': 'Remplissage',
          if (parcoursAvailable(p!))
            'parcoursAccess': 'Rôle dans le parcours visiteurs',
          if (parcoursAvailable(p!))
            'parcoursPassage': 'Traversable par les visiteurs (allée)',
        },
        if (t['kind'] == 'table') ...{
          'usage': 'Usage',
          'numberLocked': 'Conserver ce numéro lors d’une renumérotation',
          'note': 'Note d’organisation (interne)',
          '_joinGapMode': 'Jonctions : hériter du type ou personnaliser',
          '_joinGapM': 'Espacement de jonction (m, 0 = contact)',
          '_joinGapSides': 'Bords concernés (suivent la rotation)',
          '_applyJoinGapNow':
              'Appliquer l’écart aux jonctions existantes maintenant',
          'capacity': 'Capacité individuelle (0 = service)',
          'seating': 'Assises',
          'sides': 'Côtés assis',
          'seatSide': 'Côté assis si un seul côté',
        },
        if (t['kind'] == 'door') 'opening': 'Sens ouverture (indicatif)',
      },
      extraContent:
          t['kind'] == 'table' && furnitureUse(t) == furnitureUses.first
          ? TextButton(
              onPressed: () =>
                  Navigator.of(context)
                      .pop(<String, dynamic>{'_seatEditor': true}),
              child: const Text('Places numérotées et réservées'),
            )
          : null,
      numeric: {'w', 'h', if (t['kind'] == 'table') '_joinGapM'},
      integer: {if (t['kind'] == 'table') 'capacity'},
      choices: {
        if (isPlanAccess(t)) 'accessAudience': accessAudiences,
        if (canIncludeInProximity(t)) 'proximityEnabled': ['Non', 'Oui'],
        if (t['kind'] == 'table') '_joinGapMode': ['Hériter', 'Personnaliser'],
        if (t['kind'] == 'table') '_joinGapSides': joinGapSideNames,
        if (t['kind'] == 'table') '_applyJoinGapNow': ['Oui', 'Non'],
        if (t['kind'] == 'zone') ...{
          'mainAisle': ['Non', 'Oui'],
          'zoneColor': zoneColors.keys.toList(),
          'zoneFill': zoneFills,
          if (parcoursAvailable(p!)) 'parcoursAccess': parcoursZoneAccess,
          if (parcoursAvailable(p!)) 'parcoursPassage': ['Non', 'Oui'],
        },
        if (t['kind'] == 'table') 'usage': furnitureUses,
        if (t['kind'] == 'table') 'numberLocked': ['Non', 'Oui'],
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
    if (v?['_seatEditor'] == true) {
      await numberedSeatsEdit(t);
      return;
    }
    if (v != null) {
      if (t['kind'] == 'table') {
        saveJoinGapForm(v);
        v['numberLocked'] = v['numberLocked'] == 'Oui';
      }
      for (final k in ['x', 'y']) {
        final n = double.tryParse('${v[k]}'.replaceAll(',', '.'));
        if (n == null || !n.isFinite || n < 0) {
          toast('Position positive en mètres attendue.');
          return;
        }
        v[k] = n;
      }
      if (['cercle', 'carré'].contains(v['shape'])) v['h'] = v['w'];
      final applyGap = v.remove('_applyJoinGapNow') == 'Oui';
      if (v['capacity'] != 0 &&
          furnitureUse(t) != furnitureUse(v) &&
          !await confirm(
            'Changer l’usage ?',
            'Les attributions de cette pièce seront retirées. Les réservations et la disposition restent conservées.',
          )) {
        return;
      }
      final before = clone(p!);
      String? result;
      change(() {
        if (furnitureUse(t) != furnitureUse(v)) {
          changeFurnitureUsage(p!, {t['id'] as String}, furnitureUse(v));
        }
        rows(p!, 'items')[rows(p!, 'items').indexOf(t)] = v;
        if (applyGap && t['kind'] == 'table') {
          result = applyTableJoinGapLocally(p!, before, v['id'] as String);
        }
      });
      if (result != null) toast(result!);
    }
  }

  Future<void> groupEdit([Json? g]) async {
    final v = await form(
      'Réservation',
      {
        'id': uid(),
        'bookingKind': g == null
            ? eventAssignmentMode(p!)
            : g['bookingKind'] ?? assignmentModes.first,
        'standUnit': p!['standUnit'] ?? standUnits.first,
        'requestedTables': 1,
        'requestedMetres': 3.0,
        'shareTable': 'Oui',
        'requestedType': '',
        'contact': '',
        'email': '',
        'phone': '',
        'childChairs': 0,
        'waiting': false,
        'standAlloc': <Json>[],
        'name': '',
        'count': 4,
        'meal': 'Normal',
        'allergy': '',
        'needs': '',
        'companion': 'Non',
        'alloc': <Json>[],
        'locked': false,
        'reserved': '',
        ...?g,
      },
      {
        'bookingKind': 'Réservation pour',
        'name': 'Référent / exposant',
        'contact': 'Contact (facultatif)',
        'email': 'Adresse e-mail (facultatif)',
        'phone': 'Téléphone (facultatif)',
        'standUnit': 'Demande de stand : unité',
        'requestedTables': 'Nombre de tables demandé',
        'requestedMetres': 'Mètres linéaires demandés',
        'requestedType': 'Modèle de table souhaité',
        'shareTable': 'Partager une table en mode métrage',
        'count': 'Nombre de personnes',
        'childChairs':
            'Chaises enfant (stock encore disponible : ${max(0, childChairStock(p!) - reservedChildChairs(p!, exceptId: g?['id']))})',
        if (mealsEnabled(p!)) 'meal': 'Repas par défaut',
        if (mealsEnabled(p!)) 'allergy': 'Allergies (complément)',
        'needs': 'Besoin de mobilité',
        'companion': 'Accompagnant proche',
        'note': 'Note d’organisation (interne)',
      },
      fieldVisible: (values, key) {
        final stand = values['bookingKind'] == assignmentModes[1];
        if ([
          'standUnit',
          'requestedTables',
          'requestedMetres',
          'requestedType',
          'shareTable',
        ].contains(key)) {
          return stand &&
              (key != 'requestedTables' || values['standUnit'] == 'Tables') &&
              (key != 'requestedMetres' && key != 'shareTable' ||
                  values['standUnit'] == 'Mètres linéaires');
        }
        if (['meal', 'allergy'].contains(key)) {
          return !stand && mealsEnabled(p!);
        }
        return true;
      },
      choiceLabels: {
        for (final t in rows(p!, 'types'))
          t['id'] as String: t['name'] as String,
      },
      choices: {
        if (mealsEnabled(p!)) 'meal': List<String>.from(p!['meals']),
        'bookingKind': assignmentModes,
        'standUnit': standUnits,
        'shareTable': ['Oui', 'Non'],
        'requestedType': [
          '',
          ...rows(p!, 'types')
              .where(
                (t) => ![
                  'banc',
                  'chaise',
                  'chaise enfant',
                  'emplacement PMR',
                ].contains(t['shape']),
              )
              .map((t) => t['id'] as String),
        ],
        'needs': ['', 'Fauteuil', 'Autre mobilité'],
        'companion': ['Non', 'Oui'],
      },
      validate: (values) => childChairReservationError(p!, values),
      integer: {'count', 'requestedTables', 'childChairs'},
      numeric: {'requestedMetres'},
    );
    if (v != null) {
      final childError = childChairReservationError(p!, v);
      if (childError != null) {
        toast(childError);
        return;
      }
      final duplicates = similarReservations(p!, v);
      if (duplicates.isNotEmpty &&
          !await confirm(
            'Réservation similaire',
            'Une réservation porte le même nom ou contact : ${duplicates.map((g) => g['name']).join(', ')}. Conserver cette réservation distincte ?',
          )) {
        return;
      }
      if (g != null &&
          (g['bookingKind'] ?? assignmentModes.first) != v['bookingKind'] &&
          !await confirm(
            'Changer le mode de réservation ?',
            'Les attributions de cette réservation seront retirées. Identités et préférences sont conservées.',
          )) {
        return;
      }
      final previousCount = g?['count'] as int?;
      change(() {
        if (g == null) {
          rows(p!, 'groups').add(v);
        } else {
          if ((g['bookingKind'] ?? assignmentModes.first) !=
              (v['bookingKind'] ?? assignmentModes.first)) {
            v['alloc'] = <Json>[];
            v['standAlloc'] = <Json>[];
            for (final seat in (v['seats'] as List? ?? [])) {
              seat.remove('table');
              seat.remove('slot');
            }
          }
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
    final placeDraft = reservationPlacePreferences(group);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: Text('Proximité de ${group['name']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Préférences entre réservations, dans les deux sens, et avec les zones et accès activés sur le plan. Proche : repère 3 m. Loin : repère ${farPreferenceDistance(p!).toStringAsFixed(1)} m. Distances entre centres des tables ; priorité à l’éloignement si les souhaits se concurrencent. Relancer l’attribution après modification.',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Accès : une entrée ou sortie unique est commune à tous. Avec plusieurs accès, les choix tiennent compte de la mobilité des personnes du groupe, accompagnants compris.',
                    ),
                  ),
                  if (proximityTargets(p!).any(
                    (item) =>
                        !accessCompatible(p!, item, group) &&
                        placeDraft.containsKey(item['id']),
                  ))
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Un souhait enregistré concerne un accès devenu incompatible. Il sera retiré en enregistrant ces préférences.',
                      ),
                    ),
                  ...groupProximityTargets(p!, group).map(
                    (place) => Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('proximity-place-${place['id']}'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: proximityTargetName(place),
                        ),
                        initialValue: placeDraft[place['id']] ?? '',
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Sans préférence'),
                          ),
                          DropdownMenuItem(
                            value: 'near',
                            child: Text('Proche'),
                          ),
                          DropdownMenuItem(value: 'far', child: Text('Loin')),
                        ],
                        onChanged: (value) => update(() {
                          placeDraft.remove(place['id']);
                          if (value != null && value.isNotEmpty) {
                            placeDraft[place['id'] as String] = value;
                          }
                        }),
                      ),
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
        final allowed = groupProximityTargets(
          p!,
          group,
        ).map((item) => item['id']).toSet();
        group['placeProximity'] = {
          for (final entry in placeDraft.entries)
            if (allowed.contains(entry.key)) entry.key: entry.value,
        };
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
    if (g['waiting'] == true) {
      toast('Confirmer la réservation avant de l’attribuer.');
      return;
    }
    if (isStandBooking(g)) {
      await standAllocationEdit(g);
      return;
    }
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
        builder: (c, update) => KeyboardDialog(
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

  Future<void> adaptedPlacesEdit(Json table) async {
    final draft = clone(table);
    final places = adaptedPlaces(draft).map(clone).toList();
    draft['adaptedPlaces'] = places;
    String? error;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final capacity = effectiveCapacity(p!, draft);
          return KeyboardDialog(
            title: Text('Places adaptées • ${table['label']}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Réserver un emplacement pour un fauteuil. La largeur supplémentaire réduit la capacité : une place ordinaire suit le réglage de confort de l’événement. La profondeur réserve le dégagement des assises. Dimensions à ajuster à votre situation.',
                    ),
                    if (p!['comfort'] != null)
                      Text(
                        'Minimums de l’événement : ${eventComfort(p!)["pmrSeatWidth"]} m de largeur et ${eventComfort(p!)["pmrDepth"]} m de profondeur. Un emplacement individuel peut réserver davantage.',
                      ),
                    Text(
                      '${table['capacity']} places déclarées → $capacity places utilisables ; ${occupancy(p!, table['id'])} personnes attribuées.',
                    ),
                    for (var index = 0; index < places.length; index++)
                      Padding(
                        key: ObjectKey(places[index]),
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue:
                                  (places[index]['slot'] as int) < capacity
                                  ? places[index]['slot']
                                  : null,
                              decoration: const InputDecoration(
                                labelText: 'Emplacement sur la table',
                              ),
                              items: [
                                for (var n = 0; n < capacity; n++)
                                  DropdownMenuItem(
                                    value: n,
                                    child: Text('Place ${n + 1}'),
                                  ),
                              ],
                              onChanged: (v) => places[index]['slot'] = v,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: '${places[index]['width']}',
                                    decoration: const InputDecoration(
                                      labelText: 'Largeur (m)',
                                    ),
                                    onChanged: (v) => update(
                                      () => places[index]['width'] = v,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: '${places[index]['depth']}',
                                    decoration: const InputDecoration(
                                      labelText: 'Profondeur (m)',
                                    ),
                                    onChanged: (v) => update(
                                      () => places[index]['depth'] = v,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Retirer cet emplacement adapté',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () =>
                                      update(() => places.removeAt(index)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un emplacement adapté'),
                      onPressed: capacity <= places.length
                          ? null
                          : () => update(() {
                              final used = places.map((v) => v['slot']).toSet();
                              places.add({
                                'slot': List.generate(
                                  capacity,
                                  (i) => i,
                                ).firstWhere((i) => !used.contains(i)),
                                'width': number(
                                  eventComfort(p!)['pmrSeatWidth'],
                                ),
                                'depth': number(eventComfort(p!)['pmrDepth']),
                              });
                            }),
                    ),
                    if (occupancy(p!, table['id']) > capacity)
                      const Text(
                        'La capacité sera dépassée : réattribuer les personnes après enregistrement.',
                        style: TextStyle(color: Colors.red),
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
                onPressed: () {
                  final slots = <int>{};
                  for (final place in places) {
                    final width = number(place['width'], double.nan),
                        depth = number(place['depth'], double.nan);
                    final slot = place['slot'] as int?;
                    if (!width.isFinite ||
                        width < .6 ||
                        width > 3 ||
                        !depth.isFinite ||
                        depth < .55 ||
                        depth > 3 ||
                        slot == null ||
                        slot < 0 ||
                        slot >= capacity ||
                        !slots.add(slot)) {
                      update(
                        () => error = 'Choisir des places distinctes utilisables, une largeur de 0,60 à 3 m et une profondeur de 0,55 à 3 m.',
                      );
                      return;
                    }
                    place['width'] = width;
                    place['depth'] = depth;
                  }
                  Navigator.pop(c, true);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
    if (accepted == true) change(() => table['adaptedPlaces'] = places);
  }

  Future<void> csvExport() async {
    String section = 'Réservations';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: const Text('Exporter en CSV'),
          content: SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              initialValue: section,
              decoration: const InputDecoration(labelText: 'Contenu'),
              items: [
                'Réservations',
                'Liste d’attente',
                'Attributions',
                if (mealsEnabled(p!)) 'Totaux des repas',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => update(() => section = v!),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Exporter'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    final captured = clone(p!);
    final initial =
        '${widget.store.directory}${Platform.pathSeparator}sallunio-${section.toLowerCase().replaceAll(' ', '-')}.csv';
    final path = await ask(
      'Enregistrer le CSV',
      initial,
      label: 'Chemin complet',
      browse: FileRequest(
        title: 'Exporter en CSV',
        initialPath: initial,
        extension: 'csv',
        description: 'Fichier CSV (*.csv)',
        save: true,
      ),
    );
    if (path == null) return;
    try {
      if (File(path).existsSync() &&
          !await confirm('Remplacer le fichier ?', path)) {
        return;
      }
      await File(path).writeAsString(eventCsv(captured, section));
      toast('CSV enregistré : $path');
    } catch (e) {
      toast('Export impossible : $e');
    }
  }

  Future<void> anonymousSeats(Json g) async {
    final draft = clone(g);
    draft['seats'] = List<Json>.generate(
      g['count'],
      (i) => i < (g['seats'] as List? ?? []).length
          ? clone(g['seats'][i])
          : !mealsEnabled(p!)
          ? individualSeat(g, i)
          : {
              'number': i + 1,
              'meal': g['meal'],
              'need': '',
              'allergy': mealsEnabled(p!) ? '' : g['allergy'] ?? '',
              'companion': '',
            },
    );
    pruneIndividualPlaces(p!, draft);
    var revision = 0;
    String? placementError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => KeyboardDialog(
          title: Text('Personnes et places • ${g['name']}'),
          content: SizedBox(
            width: 720,
            height: 460,
            child: Column(
              children: [
                const Text(
                  'Les noms sont facultatifs. Les personnes suivent les quantités attribuées aux tables ; un emplacement peut être précisé après attribution. Retirer une place réduit l’effectif.',
                ),
                if (placementError != null)
                  Text(
                    placementError!,
                    style: const TextStyle(color: Colors.red),
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
                                      'L’effectif de ce groupe passera de ${draft['count']} à ${(draft['count'] as int) - 1}. Préférences de cette place retirées, liens d’accompagnant renumérotés. La modification reste annulable tant que vous ne cliquez pas Enregistrer.',
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
                            TextFormField(
                              key: ValueKey('person-name-$i'),
                              initialValue: s['name'] ?? '',
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Nom de la personne (facultatif)',
                              ),
                              onChanged: (v) => s['name'] = v,
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (_) {
                                final choices = assignedTables(p!, g);
                                if (choices.isEmpty) {
                                  return const Text(
                                    'Aucune table attribuée pour cette personne.',
                                  );
                                }
                                final selectedTable = choices
                                    .where((t) => t['id'] == s['table'])
                                    .toList();
                                final automatic =
                                    assignedPeople(p!, g)[i]['table'] as Json?;
                                final table = selectedTable.isNotEmpty
                                    ? selectedTable.first
                                    : automatic;
                                final capacity = table == null
                                    ? 0
                                    : effectiveCapacity(p!, table);
                                final slot =
                                    table != null && s['table'] == table['id']
                                    ? int.tryParse('${s['slot']}')
                                    : null;
                                return Column(
                                  children: [
                                    DropdownButtonFormField<String>(
                                      isExpanded: true,
                                      key: ValueKey(
                                        'person-table-$i-${s['table']}',
                                      ),
                                      decoration: const InputDecoration(
                                        labelText: 'Table de cette personne',
                                      ),
                                      initialValue: selectedTable.isEmpty
                                          ? ''
                                          : s['table'],
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('Automatique'),
                                        ),
                                        ...choices.map(
                                          (t) => DropdownMenuItem(
                                            value: t['id'] as String,
                                            child: Text(t['label']),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) => update(() {
                                        s.remove('slot');
                                        if (v == '') {
                                          s.remove('table');
                                        } else {
                                          s['table'] = v;
                                        }
                                      }),
                                    ),
                                    if (table != null) ...[
                                      const SizedBox(height: 8),
                                      DropdownButtonFormField<int>(
                                        key: ValueKey(
                                          'person-slot-$i-${table['id']}',
                                        ),
                                        decoration: InputDecoration(
                                          labelText:
                                              '${table['label']} : emplacement',
                                        ),
                                        initialValue:
                                            slot != null &&
                                                slot >= 0 &&
                                                slot < capacity
                                            ? slot
                                            : -1,
                                        items: [
                                          const DropdownMenuItem(
                                            value: -1,
                                            child: Text('Automatique'),
                                          ),
                                          for (var n = 0; n < capacity; n++)
                                            DropdownMenuItem(
                                              value: n,
                                              child: Text(
                                                'Place ${n + 1}${adaptedPlaces(table).any((a) => a['slot'] == n) ? ' — adaptée' : ''}',
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) {
                                          if (v == -1) {
                                            s.remove('slot');
                                          } else {
                                            s['table'] = table['id'];
                                            s['slot'] = v;
                                          }
                                        },
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),
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
                                if (mealsEnabled(p!))
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
              onPressed: () {
                final pinned = <String, int>{}, slots = <String>{};
                for (final seat in (draft['seats'] as List).cast<Json>()) {
                  final table = seat['table'];
                  if (table == null) continue;
                  pinned[table] = (pinned[table] ?? 0) + 1;
                  final count = (draft['alloc'] as List)
                      .where((a) => a['table'] == table)
                      .fold<int>(0, (sum, a) => sum + (a['count'] as int));
                  if (pinned[table]! > count ||
                      seat['slot'] != null &&
                          !slots.add('$table-${seat['slot']}')) {
                    update(
                      () => placementError = 'Choisir des places distinctes et respecter le nombre de personnes attribué à chaque table.',
                    );
                    return;
                  }
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
        builder: (c, update) => KeyboardDialog(
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
        builder: (c, update) => KeyboardDialog(
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
        builder: (c, update) => KeyboardDialog(
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
        child: KeyboardDialog(
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
    if (action == 'Importer projet' && eventReadOnly) {
      toast('Déverrouiller l’événement avant un import.');
      return;
    }
    final isPdf = action == 'Export PDF';
    var exportPlaceLabels = showPlaceLabels;
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
    var includeWaiting = false;
    var includeLegend = true;
    var planAudience = 'Organisation';
    var planColumns = 1, planRows = 1;
    if (isPdf) {
      final occupied = tables(snapshot!)
          .any((t) => occupancy(snapshot, t['id']) > 0);
      includeCards = occupied;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => KeyboardDialog(
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
                    DropdownButtonFormField<String>(
                      initialValue: planAudience,
                      decoration: const InputDecoration(
                        labelText: 'Réglages pour le destinataire du plan',
                      ),
                      items: [
                        for (final v in [
                          'Organisation',
                          'Visiteurs',
                          'Exposants',
                        ])
                          DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (value) => update(() {
                        planAudience = value!;
                        includePlan = true;
                        includeSummary = planAudience == 'Organisation';
                        includeCards =
                            planAudience == 'Organisation' && occupied;
                        includeWaiting = false;
                        includeReception = false;
                        includeService = false;
                        exportPlaceLabels =
                            planAudience == 'Organisation' && showPlaceLabels;
                      }),
                    ),
                    CheckboxListTile(
                      title: const Text('Plan de salle'),
                      value: includePlan,
                      onChanged: (value) => update(() => includePlan = value!),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: CheckboxListTile(
                        title: const Text('Afficher la légende sur le plan'),
                        value: includeLegend,
                        onChanged: includePlan
                            ? (value) => update(() => includeLegend = value!)
                            : null,
                      ),
                    ),
                    if (includePlan)
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: planColumns,
                              decoration: const InputDecoration(
                                labelText: 'Feuilles en largeur',
                              ),
                              items: [
                                for (var n = 1; n <= 6; n++)
                                  DropdownMenuItem(value: n, child: Text('$n')),
                              ],
                              onChanged: (v) => update(() => planColumns = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: planRows,
                              decoration: const InputDecoration(
                                labelText: 'Feuilles en hauteur',
                              ),
                              items: [
                                for (var n = 1; n <= 6; n++)
                                  DropdownMenuItem(value: n, child: Text('$n')),
                              ],
                              onChanged: (v) => update(() => planRows = v!),
                            ),
                          ),
                        ],
                      ),
                    if (includePlan && (planColumns > 1 || planRows > 1))
                      Text(
                        'Plan sur ${planColumns * planRows} pages A4, avec repères d’assemblage.',
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
                      title: const Text('Liste d’attente'),
                      subtitle: const Text(
                        'Réservations en attente, demandes et coordonnées',
                      ),
                      value: includeWaiting,
                      onChanged: (value) =>
                          update(() => includeWaiting = value!),
                    ),
                    if (mealsEnabled(p!))
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
                        includeWaiting ||
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
        : '${widget.store.directory}${Platform.pathSeparator}projet-sallunio.tableo.json';
    final path = await ask(
      '$action • chemin du fichier',
      defaultPath,
      label: 'Chemin complet (dossier existant)',
      browse: FileRequest(
        title: action,
        initialPath: defaultPath,
        extension: isPdf ? 'pdf' : 'tableo.json',
        description: isPdf ? 'PDF (*.pdf)' : 'Projet Sallunio (*.json)',
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
            builder: (c, update) => KeyboardDialog(
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
            includeWaiting: includeWaiting,
            includePlaceLabels: exportPlaceLabels,
            includeLegend: includeLegend,
            planAudience: planAudience,
            planColumns: planColumns,
            planRows: planRows,
          );
          if (!mounted) return;
          await showDialog<void>(
            context: context,
            builder: (c) => KeyboardDialog(
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
      builder: (c) => KeyboardDialog(
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
                  'Ne mange pas conserve une place, sans compter comme repas. Les valeurs CSV décrivent le groupe ; les exceptions par place anonyme et l’accompagnant se règlent après import dans Préférences. Garder la première ligne d’en-tête ; aucune ligne de commentaire.',
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
    if (eventReadOnly) return;
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
            return KeyboardDialog(
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
      final nearMatches = <String>{};
      for (final incomingGroup in incoming) {
        for (final existing
            in (mode == 'Remplacer réservations'
                ? <Json>[]
                : similarReservations(p!, incomingGroup))) {
          if ('${existing['name']}'.trim().toLowerCase() !=
              '${incomingGroup['name']}'.trim().toLowerCase()) {
            nearMatches.add('${incomingGroup['name']} / ${existing['name']}');
          }
        }
      }
      if (nearMatches.isNotEmpty &&
          !await confirm(
            'Noms similaires à l’import',
            'Vérifier ces correspondances avant de continuer : ${nearMatches.join(', ')}. Aucun rapprochement automatique supplémentaire ne sera fait.',
          )) {
        return;
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
          builder: (c, update) => KeyboardDialog(
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

  Future<void> reorderEvents(int oldIndex, int newIndex) async {
    if (reorderingEvents) return;
    final before = [...projects];
    if (newIndex == oldIndex) return;
    setState(() {
      reorderingEvents = true;
      projects.insert(newIndex, projects.removeAt(oldIndex));
    });
    try {
      await widget.store.saveEventOrder(
        projects.map((e) => e['id'] as String).toList(),
      );
    } catch (_) {
      if (mounted) {
        setState(() => projects = before);
        toast('Impossible d’enregistrer l’ordre des événements.');
      }
    } finally {
      if (mounted) setState(() => reorderingEvents = false);
    }
  }

  Future<void> removePlanSelection({Set<String>? itemIds}) async {
    if (p == null || page != 0 || removingSelection || arranging) return;
    final ids = itemIds ?? {...selectedObjects, ...selectedTables, ?selected};
    final removable = rows(p!, 'items')
        .where((i) => ids.contains(i['id']) && i['fixed'] != true)
        .map((i) => i['id'])
        .toSet();
    if (removable.isEmpty) return;
    removingSelection = true;
    try {
      change(() {
        rows(p!, 'items').removeWhere((i) => removable.contains(i['id']));
        prunePlacePreferences(p!);
        for (final g in rows(p!, 'groups')) {
          (g['standAlloc'] as List?)?.removeWhere(
            (a) => removable.contains(a['table']),
          );
          (g['alloc'] as List).removeWhere(
            (a) => removable.contains(a['table']),
          );
          if (removable.contains(g['reserved'])) g['reserved'] = '';
          for (final seat in (g['seats'] as List? ?? [])) {
            if (removable.contains(seat['table'])) {
              seat.remove('table');
              seat.remove('slot');
            }
          }
        }
        selectedTables.removeAll(removable);
        selectedObjects.removeAll(removable);
        if (removable.contains(selected)) selected = null;
      });
    } finally {
      removingSelection = false;
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (eventReadOnly && event.logicalKey != LogicalKeyboardKey.escape) {
        return KeyEventResult.ignored;
      }
      if (planReadOnly &&
          event.logicalKey == LogicalKeyboardKey.delete &&
          page == 0) {
        return KeyEventResult.handled;
      }
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (event is KeyDownEvent &&
          page == 0 &&
          !planReadOnly &&
          ModalRoute.of(context)?.isCurrent == true &&
          focusContext?.findAncestorStateOfType<EditableTextState>() == null &&
          [
            LogicalKeyboardKey.arrowLeft,
            LogicalKeyboardKey.arrowRight,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.arrowDown,
          ].contains(event.logicalKey)) {
        final ids = selectedPlanIds();
        if (ids.isNotEmpty) {
          final step = HardwareKeyboard.instance.isShiftPressed ? .1 : .01;
          final dx = event.logicalKey == LogicalKeyboardKey.arrowLeft
              ? -step
              : event.logicalKey == LogicalKeyboardKey.arrowRight
              ? step
              : 0.0;
          final dy = event.logicalKey == LogicalKeyboardKey.arrowUp
              ? -step
              : event.logicalKey == LogicalKeyboardKey.arrowDown
              ? step
              : 0.0;
          runOrganizerChange(() => nudgeSelection(p!, ids, dx, dy));
          return KeyEventResult.handled;
        }
      }

      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          page == 0 &&
          ModalRoute.of(context)?.isCurrent == true) {
        clearPlanSelection();
        return KeyEventResult.handled;
      }
      if (event is! KeyDownEvent ||
          event.logicalKey != LogicalKeyboardKey.delete ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed ||
          page != 0 ||
          ModalRoute.of(context)?.isCurrent != true ||
          focusContext?.findAncestorStateOfType<EditableTextState>() != null) {
        return KeyEventResult.ignored;
      }
      removePlanSelection();
      return KeyEventResult.handled;
    },
    child: buildContent(context),
  );

  Widget buildContent(BuildContext context) {
    if (p == null) {
      if (loaded) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Sallunio'),
            actions: [themeButton()],
          ),
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
      return Scaffold(
        appBar: AppBar(title: const Text('Sallunio'), actions: [themeButton()]),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final review = planReview();
    final alerts = review.alerts;
    final geometry = review.geometry;
    final stats = review.stats;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/branding/sallunio.png', width: 32, height: 32),
            const SizedBox(width: 10),
            const Text('Sallunio'),
            const SizedBox(width: 24),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ReorderableListView.builder(
                        key: const ValueKey('event-tabs'),
                        scrollDirection: Axis.horizontal,
                        buildDefaultDragHandles: false,
                        itemCount: projects.length,
                        onReorderItem: reorderEvents,
                        proxyDecorator: (child, index, animation) => Material(
                          color: Colors.transparent,
                          elevation: 4,
                          child: child,
                        ),
                        itemBuilder: (context, index) {
                          final event = projects[index];
                          return ReorderableDragStartListener(
                            key: ValueKey('event-tab-${event['id']}'),
                            index: index,
                            enabled: !reorderingEvents,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Center(
                                child: Tooltip(
                                  message:
                                      'Glisser pour réorganiser les événements',
                                  child: ChoiceChip(
                                    avatar: Icon(
                                      eventIcon(event),
                                      size: 18,
                                      semanticLabel: eventIconName(event),
                                    ),
                                    showCheckmark: false,
                                    label: Text(event['name']),
                                    selected: event['id'] == p!['id'],
                                    onSelected: (_) => selectEvent(event),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
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
            onPressed:
                undo.isEmpty ||
                    eventReadOnly ||
                    (planReadOnly &&
                        protectedPlan(undo.last) != protectedPlan(p!))
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
            onPressed:
                redo.isEmpty ||
                    eventReadOnly ||
                    (planReadOnly &&
                        protectedPlan(redo.last) != protectedPlan(p!))
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
              if (v == 'Exporter CSV') {
                csvExport();
              } else {
                fileAction(v);
              }
            },
            itemBuilder: (_) => [
              'Exporter projet',
              'Importer projet',
              'Export PDF',
              'Exporter CSV',
            ].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Fichiers ▾'),
            ),
          ),
          IconButton(
            key: const ValueKey('event-lock'),
            tooltip: eventReadOnly
                ? 'Déverrouiller l’événement'
                : 'Verrouiller l’événement — lecture seule',
            onPressed: () => toggleEventLock(p!),
            icon: Icon(eventReadOnly ? Icons.lock : Icons.lock_open),
          ),
          themeButton(),
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
                if (eventReadOnly || planReadOnly)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      eventReadOnly ? 'Événement verrouillé — lecture seule' : 'Plan verrouillé — réservations et assignations modifiables',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                workspaceCounters(stats),
                Expanded(
                  child: ExcludeFocus(
                    excluding: eventReadOnly && [1, 2, 5].contains(page),
                    child: AbsorbPointer(
                      absorbing: eventReadOnly && [1, 2, 5].contains(page),
                      child: switch (page) {
                        0 => plan(),
                        1 => inventory(),
                        2 => reservations(reservationPreferenceChecks(p!)),
                        3 => controls(alerts),
                        5 => attributions(),
                        _ => events(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: surfaceFor(const Color(0xffe7eeeb)),
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
                  return SizedBox(
                    width: 330,
                    height: 40,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        [
                          if (point != null)
                            'Curseur : X ${point.dx.toStringAsFixed(2)} m • Y ${point.dy.toStringAsFixed(2)} m',
                          if (item != null)
                            '${item['label']} : X ${number(item['x']).toStringAsFixed(2)} m • Y ${number(item['y']).toStringAsFixed(2)} m',
                        ].join('\n'),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
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
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
    final choices = <String>{};
    final furnitureGroups = <String, List<Json>>{};
    for (final item in tables(p!)) {
      final model = rows(
        p!,
        'types',
      ).where((t) => t['id'] == item['type']).firstOrNull;
      final label = model != null
          ? '${model['name']}'
          : switch (item['kind']) {
              'chair' => 'Chaises sans modèle',
              'bench' => 'Bancs sans modèle',
              'pmr' => 'Emplacements PMR sans modèle',
              _ => 'Tables sans modèle',
            };
      final key = model != null
          ? 'model:${model['id']}'
          : 'kind:${item['kind']}';
      furnitureGroups.putIfAbsent(key, () => []).add({
        ...item,
        '_clearLabel': label,
      });
    }
    final selectedFurniture = <String>{};
    Set<String> furnitureIds() => {
      for (final key in selectedFurniture)
        for (final item in furnitureGroups[key]!) item['id'] as String,
    };
    var includeLocked = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final preview = clone(p!);
          clearRoom(
            preview,
            choices,
            includeLocked: includeLocked,
            furnitureIds: furnitureIds(),
          );
          final objects =
              rows(p!, 'items').length - rows(preview, 'items').length;
          final before = workspaceStats(p!), after = workspaceStats(preview);
          final assigned =
              (before['assigned'] as int) - (after['assigned'] as int);
          return KeyboardDialog(
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
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mobilier placé'),
                      tristate: true,
                      value: selectedFurniture.isEmpty
                          ? false
                          : selectedFurniture.length == furnitureGroups.length
                          ? true
                          : null,
                      onChanged: furnitureGroups.isEmpty
                          ? null
                          : (v) => update(() {
                              if (selectedFurniture.length ==
                                  furnitureGroups.length) {
                                selectedFurniture.clear();
                                choices.remove('tables');
                              } else {
                                selectedFurniture.addAll(furnitureGroups.keys);
                                choices.add('tables');
                              }
                            }),
                    ),
                    for (final entry in furnitureGroups.entries)
                      Padding(
                        padding: const EdgeInsets.only(left: 24),
                        child: CheckboxListTile(
                          title: Text(
                            '${entry.value.first['_clearLabel']} (${entry.value.length})',
                          ),
                          value: selectedFurniture.contains(entry.key),
                          onChanged: (v) => update(() {
                            if (v == true) {
                              selectedFurniture.add(entry.key);
                            } else {
                              selectedFurniture.remove(entry.key);
                            }
                            if (selectedFurniture.isEmpty) {
                              choices.remove('tables');
                            } else {
                              choices.add('tables');
                            }
                          }),
                        ),
                      ),
                    ...roomClearChoices.entries
                        .where((e) => e.key != 'tables')
                        .map(
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
                      '$objects objets retirés • $assigned personnes désattribuées.',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Les éléments verrouillés sont conservés sauf si la case est cochée. Retirer une pièce de mobilier retire aussi ses assignations, même verrouillées. L’inventaire de mobilier est toujours conservé. Annuler permet de revenir en arrière après l’opération.',
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
        clearRoom(
          p!,
          choices,
          includeLocked: includeLocked,
          furnitureIds: furnitureIds(),
        );
        if (!rows(p!, 'items').any((i) => i['id'] == selected)) selected = null;
      });
      toast('Éléments cochés retirés. Réservations conservées.');
    }
  }

  Future<void> arrangeWithOptions() async {
    if (planReadOnly) {
      toast('Plan verrouillé.');
      return;
    }
    if (arranging || arrangementDialogOpen || p == null) return;
    arrangementDialogOpen = true;
    try {
      var corner = p!['arrangementCorner'] ?? arrangementCorners.first;
      final available = parcoursAvailable(p!);
      var mode =
          p!['arrangementMode'] == 'Scène' &&
              tables(p!).any((t) => t['kind'] != 'table')
          ? 'Scène'
          : available && p!['arrangementMode'] == 'Parcours'
          ? 'Parcours'
          : 'Standard';
      final settings = p!['parcoursSettings'] as Map? ?? {};
      var orientation = settings['orientation'] ?? parcoursOrientations.first;
      var closure = settings['closure'] ?? parcoursClosures.first;
      var circulation = settings['circulation'] ?? 'Fermé';
      var wallLayout = settings['wallLayout'] ?? parcoursWallLayouts.first;
      var wall = p!['wallSupport'] ?? 'Aucun';
      var snapshot = clone(p!);
      final selectedZones = rows(p!, 'items')
          .where(
            (i) => i['kind'] == 'zone' && i['parcoursAccess'] == 'À desservir',
          )
          .map((i) => i['id'] as String)
          .toSet();
      final exhibitorGap = eventExhibitorGap(p!);
      final route = DialogRoute<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => KeyboardDialog(
            title: const Text('Disposition automatique'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (available ||
                        tables(p!).any((t) => t['kind'] != 'table'))
                      DropdownButtonFormField<String>(
                        initialValue: mode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Mode de disposition',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'Standard',
                            child: Text('Standard'),
                          ),
                          if (available)
                            const DropdownMenuItem(
                              value: 'Parcours',
                              child: Text('Parcours des exposants en S'),
                            ),
                          if (tables(p!).any((t) => t['kind'] != 'table'))
                            const DropdownMenuItem(
                              value: 'Scène',
                              child: Text('Sièges face à une scène'),
                            ),
                        ],
                        onChanged: (value) => update(() => mode = value!),
                      ),
                    if (mode == 'Standard')
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: corner,
                        decoration: const InputDecoration(
                          labelText: 'Point de départ',
                        ),
                        items: arrangementCorners
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => update(() => corner = value),
                      ),
                    if (mode == 'Parcours') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: circulation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Type de parcours',
                        ),
                        items: parcoursCirculations
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text('Parcours ${v.toLowerCase()}'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => update(() => circulation = v!),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        circulation == 'Fermé'
                            ? 'Chemin imposé : tous les exposants doivent être visités, sans raccourci. Si les tables et les appuis ne permettent pas de fermer le passage, le calcul le signale.'
                            : 'Circulation libre : disposition optimisée, avec des raccourcis possibles entre les allées.',
                      ),
                      const SizedBox(height: 12),
                      const Text('Plan actuel — choisir les zones à desservir'),
                      const SizedBox(height: 8),
                      ParcoursSnapshot(
                        project: snapshot,
                        selected: selectedZones,
                        onToggle: (id) => update(() {
                          if (!selectedZones.add(id)) selectedZones.remove(id);
                        }),
                      ),
                      const SizedBox(height: 8),
                      ...rows(snapshot, 'items')
                          .where((i) => i['kind'] == 'zone')
                          .map(
                            (zone) => CheckboxListTile(
                              key: ValueKey('parcours-zone-${zone['id']}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                (zone['label'] ?? '').toString().trim().isEmpty
                                    ? 'Zone sans libellé'
                                    : zone['label'],
                              ),
                              subtitle: Text(
                                zone['zoneFill'] == 'Invisible'
                                    ? 'Zone invisible dans le plan'
                                    : 'Passage le long d’un bord accessible',
                              ),
                              value: selectedZones.contains(zone['id']),
                              onChanged: (v) => update(() {
                                if (v == true) {
                                  selectedZones.add(zone['id']);
                                } else {
                                  selectedZones.remove(zone['id']);
                                }
                              }),
                            ),
                          ),
                      const Text(
                        'Les zones cochées sont desservies par leur bord, sans table contre elles. Les autres restent hors des étapes du parcours. Les allées traversables se règlent dans les propriétés de la zone.',
                      ),
                      ...rows(snapshot, 'items')
                          .where(
                            (zone) =>
                                zone['kind'] == 'zone' &&
                                zone['zoneFill'] == 'Invisible',
                          )
                          .map(
                            (zone) => SwitchListTile(
                              key: ValueKey('parcours-passage-${zone['id']}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Allée traversable : ${(zone['label'] ?? '').toString().trim().isEmpty ? 'zone sans libellé' : zone['label']}',
                              ),
                              subtitle: const Text(
                                'Tables interdites, visiteurs autorisés',
                              ),
                              value: zone['parcoursPassage'] == 'Oui',
                              onChanged: (value) => update(
                                () => zone['parcoursPassage'] = value
                                    ? 'Oui'
                                    : 'Non',
                              ),
                            ),
                          ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: orientation,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Orientation des rangées',
                        ),
                        items: parcoursOrientations
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => orientation = v!),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        key: const ValueKey('parcours-gap-info'),
                        'Espace exposants dos à dos : ${exhibitorGap.toStringAsFixed(2).replaceAll('.', ',')} m — réglé dans Confort de l’événement.',
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: closure,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tables de fermeture',
                        ),
                        items: parcoursClosures
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => closure = v!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: wall,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Appui au mur autorisé',
                        ),
                        items: wallModes
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => wall = v!),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: wallLayout,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Appui des rangées',
                        ),
                        items: parcoursWallLayouts
                            .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)),
                            )
                            .toList(),
                        onChanged: (v) => update(() => wallLayout = v!),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Avec une seule entrée, les rangées alternées et une rangée de liaison imposent une boucle sans demi-tour. Un appui au mur autorisé ferme les raccourcis ; les assises et le passage de retour gardent leur espace.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Tables rectangulaires ou carrées, pivotées sans redimensionnement. Les exposants se placent dans les îlots fermés. Le passage visiteurs reste celui du plan. Les positions fixées et les tables de service sont conservées.',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Entre les rangées : la longueur de la table de bout doit correspondre à l’espace choisi pour fermer sans trou. À l’extérieur : elle doit couvrir cet espace. Une fermeture est omise si le mur ferme déjà le bout.',
                      ),
                    ],
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
                  Navigator.pop(c, true);
                },
                child: const Text('Disposer'),
              ),
            ],
          ),
        ),
      );
      final accepted = await Navigator.of(context).push(route);
      await route.completed;
      if (accepted != true || !mounted) return;
      if (mode == 'Scène') {
        arrangementDialogOpen = false;
        await audienceDisposition();
        return;
      }
      final draft = clone(p!);
      draft['arrangementCorner'] = corner;
      draft['arrangementMode'] = mode;
      if (mode == 'Parcours' && parcoursFurnitureError(draft) != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => KeyboardDialog(
            title: const Text('Parcours impossible'),
            content: Text(parcoursFurnitureError(draft)!),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
        return;
      }
      if (mode == 'Parcours') {
        for (final zone in rows(
          draft,
          'items',
        ).where((i) => i['kind'] == 'zone')) {
          zone['parcoursAccess'] = selectedZones.contains(zone['id'])
              ? 'À desservir'
              : 'À exclure';
          final draft = rows(
            snapshot,
            'items',
          ).firstWhere((i) => i['id'] == zone['id']);
          zone['parcoursPassage'] =
              draft['parcoursPassage'] ?? zone['parcoursPassage'] ?? 'Non';
        }
        draft['wallSupport'] = wall;
        draft['parcoursSettings'] = {
          'orientation': orientation,
          'closure': closure,
          'exhibitorGap': exhibitorGap,
          'wallLayout': wallLayout,
          'circulation': circulation,
          'imposedLoop': circulation == 'Fermé',
        };
      }
      setState(() => arranging = true);
      final progress = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: KeyboardDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Disposition en cours…')),
              ],
            ),
          ),
        ),
      );
      unawaited(Navigator.of(context).push(progress));
      try {
        final result = await (widget.arrangementRunner ?? arrangeInBackground)(
          draft,
        );
        if (!mounted) return;
        change(() {
          p!.clear();
          p!.addAll(result);
        });
        final failed = tables(p!).where((t) => unplacedTable(p!, t)).length;
        toast(
          failed == 0
              ? (parcoursWarnings(p!).isEmpty
                    ? 'Disposition proposée. Examiner les contrôles.'
                    : 'Parcours proposé avec des points à vérifier dans Contrôles.')
              : mode == 'Parcours'
              ? '$failed tables non intégrées au parcours, placées hors salle en rouge. Vérifier les fermetures, les dimensions et les passages dans Contrôles.'
              : 'Pas assez de place : $failed tables placées hors salle, en rouge. Réduire le nombre de tables ou revoir la salle et les passages.',
        );
      } catch (error) {
        if (mounted) {
          toast(
            'Disposition impossible : $error. Le plan précédent est conservé.',
          );
        }
      } finally {
        if (progress.isActive) progress.navigator?.removeRoute(progress);
        if (mounted) setState(() => arranging = false);
      }
    } finally {
      arrangementDialogOpen = false;
    }
  }

  void movePlanDrag(Offset delta) {
    if (dragOrigins.isEmpty) return;
    dragDx += delta.dx;
    dragDy += delta.dy;
    final origins = dragOrigins.values.toList();
    final minX = origins.map((i) => number(i['x'])).reduce(min);
    final minY = origins.map((i) => number(i['y'])).reduce(min);
    var dx = max(-minX, dragDx), dy = max(-minY, dragDy);
    if (origins.length == 1) {
      final origin = origins.single;
      dx = dx.clamp(
        -minX,
        max(
          -minX,
          number(p!['room']['width']) -
              number(origin['x']) -
              number(origin['w']),
        ),
      );
      dy = dy.clamp(
        -minY,
        max(
          -minY,
          number(p!['room']['height']) -
              number(origin['y']) -
              number(origin['h']),
        ),
      );
    }
    final moving = rows(
      p!,
      'items',
    ).where((i) => dragOrigins.containsKey(i['id'])).toList();
    for (final item in moving) {
      item['x'] = number(dragOrigins[item['id']]!['x']) + dx;
      item['y'] = number(dragOrigins[item['id']]!['y']) + dy;
    }
    dragSnap = magnetismEnabled && !HardwareKeyboard.instance.isAltPressed
        ? magneticSnap(p!, dragOrigins.keys.toSet())
        : const MagneticSnap();
    for (final item in moving) {
      item['x'] = max(0.0, number(item['x']) + dragSnap.dx);
      item['y'] = max(0.0, number(item['y']) + dragSnap.dy);
    }
  }

  Widget toolFace(IconData icon, {bool active = false, bool enabled = true}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: active ? colors.primaryContainer : colors.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: active ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Icon(
        icon,
        size: 21,
        color: !enabled
            ? colors.onSurface.withValues(alpha: .35)
            : active
            ? colors.onPrimaryContainer
            : colors.onSurface,
      ),
    );
  }

  Widget planTool(
    String id,
    IconData icon,
    String label,
    VoidCallback? callback, {
    bool active = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        key: ValueKey('plan-tool-$id'),
        tooltip: label,
        onPressed:
            planReadOnly &&
                !['magnet', 'measure', 'center', 'plan-lock'].contains(id)
            ? null
            : id == 'plan-lock' && eventReadOnly
            ? null
            : callback,
        isSelected: active,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: toolFace(icon, active: active, enabled: callback != null),
      ),
    ),
  );

  Widget planMenu(
    String id,
    IconData icon,
    String label,
    List<PopupMenuEntry<String>> entries,
    ValueChanged<String> onSelected, {
    bool active = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: PopupMenuButton<String>(
      key: ValueKey('plan-tool-$id'),
      tooltip: label,
      enabled:
          entries.isNotEmpty &&
          !(planReadOnly &&
              ['rotate', 'joining', 'wall', 'settings', 'layers'].contains(id)),
      itemBuilder: (_) => entries,
      onSelected: onSelected,
      child: toolFace(icon, active: active, enabled: entries.isNotEmpty),
    ),
  );

  void rotatePlanSelection(Json? item, {bool all = false}) {
    if (all) {
      change(() => rotateTables(p!));
      return;
    }
    final ids = selectedTables
        .where((id) => tables(p!).any((t) => t['id'] == id))
        .toSet();
    final targets = ids.isNotEmpty
        ? tables(p!).where((t) => ids.contains(t['id'])).toList()
        : item == null
        ? <Json>[]
        : [item];
    if (targets.isEmpty || targets.any((i) => i['fixed'] == true)) return;
    change(() {
      if (ids.length > 1) {
        transformTableSelection(p!, ids, rotate: true);
      } else {
        rotateTable(targets.single, p!);
      }
    });
  }

  Widget planToolbar(Json? item, List<String> markerNames) {
    final targets = selectedTables.isNotEmpty
        ? tables(p!).where((t) => selectedTables.contains(t['id'])).toList()
        : item == null
        ? <Json>[]
        : [item];
    final locked =
        targets.isNotEmpty && targets.every((i) => i['fixed'] == true);
    final canRotate =
        targets.isNotEmpty && targets.every((i) => i['fixed'] != true);
    final adaptive =
        item != null && item['kind'] == 'table' && item['capacity'] > 0;
    final outsideTables = tables(p!)
        .where((t) => t['fixed'] != true && tableOutsideRoom(p!, t))
        .map((t) => t['id'] as String)
        .toSet();
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxHeight < 680 ? 96 : 52,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Scrollbar(
            controller: toolbarScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey('plan-toolbar'),
              controller: toolbarScroll,
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                runSpacing: 1,
                children: [
                  planTool(
                    'plan-lock',
                    p!['planLocked'] == true ? Icons.lock : Icons.lock_open,
                    p!['planLocked'] == true
                        ? 'Déverrouiller le plan'
                        : 'Verrouiller le plan',
                    togglePlanLock,
                    active: p!['planLocked'] == true,
                  ),
                  planTool(
                    'magnet',
                    Icons.my_location,
                    'Magnétisme — Alt pour déplacer librement',
                    () => setState(() => magnetismEnabled = !magnetismEnabled),
                    active: magnetismEnabled,
                  ),
                  planMenu(
                    'select',
                    selectRectangle
                        ? Icons.select_all
                        : moveAssembly
                        ? Icons.widgets_outlined
                        : Icons.ads_click,
                    selectRectangle
                        ? 'Sélection — rectangle'
                        : moveAssembly
                        ? 'Sélection — groupée'
                        : 'Sélection — multiple',
                    [
                      CheckedPopupMenuItem(
                        value: 'multiple',
                        checked: !moveAssembly && !selectRectangle,
                        child: const Text('Sélection multiple — Ctrl + clic'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'rectangle',
                        checked: selectRectangle,
                        child: const Text(
                          'Sélection par rectangle — Ctrl pour compléter',
                        ),
                      ),
                      CheckedPopupMenuItem(
                        value: 'group',
                        checked: moveAssembly,
                        child: const Text('Sélection groupée — Ctrl + clic'),
                      ),
                    ],
                    (value) => setState(() {
                      moveAssembly = value == 'group';
                      selectRectangle = value == 'rectangle';
                      multiSelect = false;
                    }),
                  ),
                  planMenu(
                    'display',
                    Icons.visibility_outlined,
                    'Affichage',
                    [
                      CheckedPopupMenuItem(
                        value: 'route',
                        checked: routeVisible,
                        child: const Text('Afficher le parcours proposé'),
                      ),
                      CheckedPopupMenuItem(
                        value: 'names',
                        checked: showPlaceLabels,
                        child: const Text('Afficher les noms sur le mobilier'),
                      ),
                    ],
                    (value) => setState(() {
                      if (value == 'route') {
                        if (eventReadOnly) {
                          routeVisibilityOverride = !routeVisible;
                        } else {
                          p!['showParcours'] = !routeVisible;
                        }
                      }
                      if (value == 'names') showPlaceLabels = !showPlaceLabels;
                      savePlanView();
                      persist();
                    }),
                  ),
                  planMenu(
                    'filter',
                    Icons.filter_alt_outlined,
                    'Filtrer',
                    availablePlanFilters(p!).entries
                        .map(
                          (entry) => CheckedPopupMenuItem<String>(
                            value: entry.key,
                            checked: planFilter == entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    (value) => setState(() => planFilter = value),
                    active: planFilter != planFilters.first,
                  ),
                  planMenu(
                    'layers',
                    Icons.layers_outlined,
                    'Ordre d’affichage',
                    [
                      for (final entry in planLayerActions.entries)
                        PopupMenuItem(
                          value: entry.key,
                          enabled:
                              selectedPlanIds().isNotEmpty &&
                              !planReadOnly &&
                              !rows(p!, 'items').any(
                                (i) =>
                                    selectedPlanIds().contains(i['id']) &&
                                    i['fixed'] == true,
                              ),
                          child: Text(entry.value),
                        ),
                    ],
                    reorderPlanSelection,
                  ),
                  planMenu('rotate', Icons.rotate_right, 'Pivoter 90°', [
                    PopupMenuItem(
                      value: 'selection',
                      enabled: canRotate,
                      child: Text(
                        selectedTables.length > 1
                            ? 'Pivoter la sélection 90°'
                            : 'Pivoter 90°',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'all',
                      enabled: tables(p!).isNotEmpty,
                      child: const Text('Tout le mobilier : 90°'),
                    ),
                  ], (value) => rotatePlanSelection(item, all: value == 'all')),
                  planTool(
                    'measure',
                    Icons.straighten,
                    measuring ? 'Terminer la mesure' : 'Mesurer une distance',
                    () => setState(() {
                      measuring = !measuring;
                      measureStart = measureEnd = null;
                    }),
                    active: measuring,
                  ),
                  planTool(
                    'adapted',
                    Icons.accessible,
                    'Places adaptées',
                    adaptive ? () => adaptedPlacesEdit(item) : null,
                  ),
                  planTool(
                    'fixed',
                    locked ? Icons.lock_outline : Icons.lock_open,
                    'Position fixée',
                    targets.isEmpty
                        ? null
                        : () => change(() {
                            for (final target in targets) {
                              target['fixed'] = !locked;
                            }
                          }),
                    active: locked,
                  ),
                  planTool(
                    'edit',
                    Icons.edit_outlined,
                    'Modifier l’objet',
                    item == null
                        ? null
                        : () => targets.length > 1
                              ? bulkPropertiesEditor()
                              : itemEdit(item),
                  ),
                  planTool(
                    'remove-outside',
                    Icons.delete_sweep_outlined,
                    'Retirer mobilier hors salle',
                    outsideTables.isEmpty
                        ? null
                        : () => removePlanSelection(itemIds: outsideTables),
                  ),
                  planMenu(
                    'organize',
                    Icons.more_horiz,
                    'Outils complémentaires',
                    [
                      const PopupMenuItem(
                        value: 'search',
                        child: Text('Rechercher sur le plan…'),
                      ),
                      PopupMenuItem(
                        value: 'align',
                        enabled: !planReadOnly,
                        child: const Text('Aligner / répartir…'),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        enabled: !planReadOnly,
                        child: const Text('Dupliquer la sélection'),
                      ),
                      PopupMenuItem(
                        value: 'properties',
                        enabled: !planReadOnly,
                        child: const Text('Propriétés de la sélection…'),
                      ),
                      PopupMenuItem(
                        value: 'numbers',
                        enabled: !planReadOnly,
                        child: const Text('Renuméroter volontairement…'),
                      ),
                    ],
                    organizerTool,
                  ),
                  addPlanMenu(),
                  planTool(
                    'clear-room',
                    Icons.cleaning_services_outlined,
                    'Vider la salle',
                    roomClear,
                  ),
                  planMenu(
                    'settings',
                    Icons.settings_outlined,
                    'Salle et confort',
                    [
                      const PopupMenuItem(value: 'room', child: Text('Salle')),
                      const PopupMenuItem(
                        value: 'comfort',
                        child: Text('Confort'),
                      ),
                    ],
                    (value) {
                      if (value == 'room') {
                        roomEdit();
                      } else {
                        comfortEdit(p!);
                      }
                    },
                  ),
                  planMenu(
                    'joining',
                    Icons.link,
                    'Accolement autorisé dans ce plan',
                    joiningModes
                        .map(
                          (value) => CheckedPopupMenuItem<String>(
                            value: value,
                            checked: p!['joining'] == value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    (value) => change(() => p!['joining'] = value),
                    active: p!['joining'] != 'Aucun',
                  ),
                  planMenu(
                    'wall',
                    Icons.border_outer,
                    'Appui au mur',
                    [
                      const PopupMenuItem(
                        enabled: false,
                        child: Text(
                          'Sans appui : maintien du passage. Avec appui : places côté mur retirées.',
                        ),
                      ),
                      ...wallModes.map(
                        (value) => CheckedPopupMenuItem<String>(
                          value: value,
                          checked:
                              (p!['wallSupport'] ?? 'Aucun')
                                  .toString()
                                  .replaceAll(' / allée centrale', '') ==
                              value,
                          child: Text(value),
                        ),
                      ),
                    ],
                    (value) => change(() => p!['wallSupport'] = value),
                    active: (p!['wallSupport'] ?? 'Aucun') != 'Aucun',
                  ),
                  planTool(
                    'center',
                    Icons.center_focus_strong,
                    'Recentrer la vue',
                    resetPlanView,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget plan() {
    final presentFurniture = tables(p!).map((t) => t['id']).toSet();
    selectedTables.removeWhere((id) => !presentFurniture.contains(id));
    final review = planReview();
    final geometry = review.geometry;
    final attributionRows = review.assignments;
    final conflicts = review.conflicts;
    final palette = planMarkerColors(p!);
    final markerNames = palette.keys.toList();
    if (!availablePlanFilters(p!).containsKey(planFilter)) {
      planFilter = 'Toutes les tables';
    }
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
          [],
        ),
        selectionSummary(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 10, 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: surfaceFor(const Color(0xffe4ebe7), elevated: true),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      planToolbar(t, markerNames),
                      Expanded(
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
                            planScale = scale;
                            planOrigin = Offset(
                              (constraints.maxWidth - drawingWidth * scale) / 2,
                              (constraints.maxHeight - drawingHeight * scale) /
                                  2,
                            );
                            return InteractiveViewer(
                              panEnabled: !selectRectangle && !measuring,
                              onInteractionEnd: (_) {
                                if (selectRectangle || measuring) return;
                                setState(() {});
                                savePlanView();
                                persist();
                              },
                              transformationController: transform,
                              minScale: .4,
                              maxScale: 5,
                              boundaryMargin: const EdgeInsets.all(500),
                              child: Center(
                                child: MouseRegion(
                                  onExit: (_) => cursorPosition.value = null,
                                  child: Listener(
                                    onPointerDown: (event) {
                                      additiveClick = HardwareKeyboard
                                          .instance
                                          .isControlPressed;
                                      if (event.buttons == 2) {
                                        planBackgroundContext(event);
                                      }
                                    },
                                    onPointerHover: (event) =>
                                        cursorPosition.value =
                                            event.localPosition / scale,
                                    onPointerMove: (event) =>
                                        cursorPosition.value =
                                            event.localPosition / scale,
                                    child: SizedBox(
                                      key: planCanvasSurfaceKey,
                                      width: drawingWidth * scale,
                                      height: drawingHeight * scale,
                                      child: Stack(
                                        key: const ValueKey('plan-canvas'),
                                        clipBehavior: Clip.none,
                                        children: orderedPlanWidgets([
                                          Positioned(
                                            left: 0,
                                            top: 0,
                                            width:
                                                number(room['width']) * scale,
                                            height:
                                                number(room['height']) * scale,
                                            child: CustomPaint(
                                              painter: GridPainter(
                                                scale,
                                                roomPolygon(room),
                                                dark: widget.darkMode,
                                              ),
                                            ),
                                          ),
                                          ...annotationPlanWidgets(
                                            scale,
                                            foreground: false,
                                          ),
                                          if (routeVisible &&
                                              parcoursPaths(
                                                p!,
                                                allowStale: true,
                                              ).isNotEmpty)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: ParcoursPainter(
                                                    p!,
                                                    scale,
                                                    dark: widget.darkMode,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (pending.isNotEmpty)
                                            Positioned(
                                              left:
                                                  (number(room['width']) +
                                                      max(
                                                        .6,
                                                        number(p!['aisle']),
                                                      )) *
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
                                          ...planPaintOrder(p!)
                                              .where(
                                                (i) => !isPlanAnnotation(i),
                                              )
                                              .map(
                                                (i) => positionedFurniture(
                                                  p!,
                                                  i,
                                                  geometry,
                                                  scale,
                                                  Positioned(
                                                    left:
                                                        number(i['x']) * scale,
                                                    top: number(i['y']) * scale,
                                                    child: GestureDetector(
                                                      key: ValueKey(
                                                        'plan-item-${i['id']}',
                                                      ),
                                                      behavior:
                                                          i['kind'] == 'zone'
                                                          ? HitTestBehavior
                                                                .opaque
                                                          : HitTestBehavior
                                                                .deferToChild,
                                                      onTap: () =>
                                                          selectPlanItem(
                                                            i,
                                                            toggleHandles: true,
                                                            additive:
                                                                multiSelect ||
                                                                additiveClick,
                                                          ),
                                                      onDoubleTap: planReadOnly
                                                          ? null
                                                          : () => itemEdit(i),
                                                      onSecondaryTapDown: (d) =>
                                                          planContextMenu(
                                                            d.globalPosition,
                                                            i,
                                                          ),
                                                      onPanStart: (_) {
                                                        dragBlocked =
                                                            planReadOnly ||
                                                            i['fixed'] == true;
                                                        if (!planReadOnly &&
                                                            i['fixed'] !=
                                                                true) {
                                                          if (!selectedTables
                                                              .contains(
                                                                i['id'],
                                                              )) {
                                                            selectPlanItem(i);
                                                          }
                                                          selected = i['id'];
                                                          if (moveAssembly &&
                                                              i['kind'] ==
                                                                  'table') {
                                                            final geo =
                                                                PlanGeometry(
                                                                  p!,
                                                                  rows(
                                                                    p!,
                                                                    'items',
                                                                  ),
                                                                );
                                                            selectedTables.addAll(
                                                              tables(p!)
                                                                  .where(
                                                                    (
                                                                      other,
                                                                    ) => geo
                                                                        .sameAssembly(
                                                                          i,
                                                                          other,
                                                                        ),
                                                                  )
                                                                  .map(
                                                                    (other) =>
                                                                        other['id']
                                                                            as String,
                                                                  ),
                                                            );
                                                          }
                                                          draggingTables =
                                                              isSeatingFurniture(
                                                                i,
                                                              )
                                                              ? {...selectedTables}
                                                              : {};
                                                          if (draggingTables
                                                                      .length >
                                                                  1 &&
                                                              tables(p!).any(
                                                                (t) =>
                                                                    draggingTables
                                                                        .contains(
                                                                          t['id'],
                                                                        ) &&
                                                                    t['fixed'] ==
                                                                        true,
                                                              )) {
                                                            draggingTables
                                                                .clear();
                                                            dragBlocked = true;
                                                            toast(
                                                              'Déverrouiller les tables de cet ensemble.',
                                                            );
                                                            return;
                                                          }
                                                          checkpoint();
                                                          final ids =
                                                              draggingTables
                                                                  .isEmpty
                                                              ? {
                                                                  i['id']
                                                                      as String,
                                                                }
                                                              : draggingTables;
                                                          dragOrigins.clear();
                                                          for (final item
                                                              in rows(
                                                                p!,
                                                                'items',
                                                              ).where(
                                                                (v) => ids
                                                                    .contains(
                                                                      v['id'],
                                                                    ),
                                                              )) {
                                                            dragOrigins[item['id']] =
                                                                clone(item);
                                                            item.remove(
                                                              'unplacedByArrangement',
                                                            );
                                                          }
                                                          dragDx = dragDy = 0;
                                                          dragSnap =
                                                              const MagneticSnap();
                                                        }
                                                      },
                                                      onPanUpdate: (d) {
                                                        if (i['fixed'] ==
                                                                true ||
                                                            dragBlocked) {
                                                          return;
                                                        }
                                                        setState(
                                                          () => movePlanDrag(
                                                            d.delta / scale,
                                                          ),
                                                        );
                                                      },
                                                      onPanEnd: (_) {
                                                        if (dragBlocked) return;
                                                        setState(() {
                                                          movePlanDrag(
                                                            Offset.zero,
                                                          );
                                                          dragSnap =
                                                              const MagneticSnap();
                                                        });
                                                        persist();
                                                      },
                                                      onPanCancel: () {
                                                        if (dragBlocked ||
                                                            dragOrigins
                                                                .isEmpty) {
                                                          return;
                                                        }
                                                        setState(
                                                          () => dragSnap =
                                                              const MagneticSnap(),
                                                        );
                                                        persist();
                                                      },
                                                      child: Opacity(
                                                        opacity:
                                                            i['kind'] ==
                                                                    'table' &&
                                                                !tableMatchesFilter(
                                                                  p!,
                                                                  i,
                                                                  planFilter,
                                                                  geometry,
                                                                ) &&
                                                                !conflicts
                                                                    .contains(
                                                                      i['id'],
                                                                    )
                                                            ? .22
                                                            : 1,
                                                        child: SizedBox(
                                                          width:
                                                              number(i['w']) *
                                                              scale,
                                                          height:
                                                              number(i['h']) *
                                                              scale,
                                                          child: CustomPaint(
                                                            painter: ItemPainter(
                                                              i,
                                                              i['id'] ==
                                                                      selected ||
                                                                  selectedObjects
                                                                      .contains(
                                                                        i['id'],
                                                                      ) ||
                                                                  (i['kind'] ==
                                                                          'table' &&
                                                                      selectedTables
                                                                          .contains(
                                                                            i['id'],
                                                                          )),
                                                              conflict:
                                                                  conflicts
                                                                      .contains(
                                                                        i['id'],
                                                                      ),
                                                              occupied:
                                                                  counts[i['id']] ??
                                                                  0,
                                                              capacity:
                                                                  isSeatingFurniture(
                                                                    i,
                                                                  )
                                                                  ? usableSeatCapacity(
                                                                      p!,
                                                                      i,
                                                                    )
                                                                  : 0,
                                                            ),
                                                            child: Stack(
                                                              clipBehavior:
                                                                  Clip.none,
                                                              children: [
                                                                if (furnitureUse(
                                                                      i,
                                                                    ) ==
                                                                    furnitureUses[1])
                                                                  Positioned.fill(
                                                                    child: IgnorePointer(
                                                                      child: CustomPaint(
                                                                        painter: StandPortionsPainter(
                                                                          p!,
                                                                          i,
                                                                          showNames:
                                                                              showPlaceLabels,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                if (i['kind'] ==
                                                                        'bench' ||
                                                                    i['kind'] ==
                                                                        'pmr')
                                                                  Positioned.fill(
                                                                    child: IgnorePointer(
                                                                      child:
                                                                          SeatNumbers(
                                                                            p!,
                                                                            i,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                if (isSeatingFurniture(
                                                                      i,
                                                                    ) &&
                                                                    furnitureUse(
                                                                          i,
                                                                        ) ==
                                                                        furnitureUses
                                                                            .first &&
                                                                    showPlaceLabels)
                                                                  Positioned.fill(
                                                                    child: IgnorePointer(
                                                                      child: ValueListenableBuilder<Matrix4>(
                                                                        valueListenable:
                                                                            transform,
                                                                        builder: (_, matrix, child) => CustomPaint(
                                                                          painter: PlaceLabelsPainter(
                                                                            geometry.view(
                                                                              i,
                                                                            ),
                                                                            tablePlaceLabels(
                                                                              p!,
                                                                              i,
                                                                              geometry,
                                                                            ),
                                                                            geometry.blocked[i['id']] ??
                                                                                {},
                                                                            scale,
                                                                            scale * matrix.getMaxScaleOnAxis() >=
                                                                                85,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                if (i['kind'] ==
                                                                        'table' &&
                                                                    adaptedPlaces(
                                                                      i,
                                                                    ).isNotEmpty)
                                                                  ...adaptedPlaces(
                                                                    geometry
                                                                        .view(
                                                                          i,
                                                                        ),
                                                                  ).where((a) => a['slot'] < geometry.capacity(i)).map((
                                                                    a,
                                                                  ) {
                                                                    final points = placeLabelPositions(
                                                                      geometry
                                                                          .view(
                                                                            i,
                                                                          ),
                                                                      geometry
                                                                          .capacity(
                                                                            i,
                                                                          ),
                                                                      geometry.blocked[i['id']] ??
                                                                          {},
                                                                    );
                                                                    if (a['slot'] >=
                                                                        points
                                                                            .length) {
                                                                      return const SizedBox.shrink();
                                                                    }
                                                                    final point =
                                                                        points[a['slot']];
                                                                    return Positioned(
                                                                      left: (point.x * scale - 7).clamp(
                                                                        0,
                                                                        max(
                                                                          0,
                                                                          number(i['w']) * scale -
                                                                              14,
                                                                        ),
                                                                      ),
                                                                      top: (point.y * scale - 7).clamp(
                                                                        0,
                                                                        max(
                                                                          0,
                                                                          number(i['h']) * scale -
                                                                              14,
                                                                        ),
                                                                      ),
                                                                      child: Tooltip(
                                                                        message:
                                                                            'Place ${a['slot'] + 1} adaptée : ${a['width']} × ${a['depth']} m',
                                                                        child: const Icon(
                                                                          Icons
                                                                              .accessible,
                                                                          color: Color(
                                                                            0xff1565c0,
                                                                          ),
                                                                          size:
                                                                              14,
                                                                        ),
                                                                      ),
                                                                    );
                                                                  }),
                                                                if (i['kind'] ==
                                                                    'table')
                                                                  Positioned(
                                                                    bottom: 2,
                                                                    left: 3,
                                                                    right: 3,
                                                                    child: Wrap(
                                                                      spacing:
                                                                          3,
                                                                      runSpacing:
                                                                          2,
                                                                      children: [
                                                                        ...tableMarkers(
                                                                          p!,
                                                                          i['id']
                                                                              as String,
                                                                        ).map(
                                                                          (
                                                                            name,
                                                                          ) => Tooltip(
                                                                            message:
                                                                                name,
                                                                            child: PlanMarker(
                                                                              name: name,
                                                                              color: markerColors[name]!,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                if (conflicts
                                                                    .contains(
                                                                      i['id'],
                                                                    ))
                                                                  const Positioned(
                                                                    top: -12,
                                                                    right: -8,
                                                                    child: Tooltip(
                                                                      message: 'Conflit : chevauchement, dégagement ou limite de salle. Voir Contrôles.',
                                                                      child: Icon(
                                                                        Icons
                                                                            .warning_amber,
                                                                        color: Colors
                                                                            .red,
                                                                        size:
                                                                            16,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                IgnorePointer(
                                                                  child: Center(
                                                                    child: Padding(
                                                                      padding:
                                                                          const EdgeInsets.all(
                                                                            2,
                                                                          ),
                                                                      child: FittedBox(
                                                                        fit: BoxFit
                                                                            .scaleDown,
                                                                        child: Text(
                                                                          isSeatingFurniture(i)
                                                                              ? furnitureUse(i) == furnitureUses[1] && standPortions(p!, i['id']).isNotEmpty
                                                                                    ? ''
                                                                                    : furniturePlanLabel(p!, i)
                                                                              : '${i['label']}',
                                                                          textAlign:
                                                                              TextAlign.center,
                                                                          style: TextStyle(
                                                                            fontSize: max(
                                                                              8,
                                                                              min(
                                                                                12,
                                                                                scale * .2,
                                                                              ),
                                                                            ),
                                                                            fontWeight:
                                                                                FontWeight.bold,
                                                                            color:
                                                                                widget.darkMode &&
                                                                                    i['kind'] == 'zone' &&
                                                                                    [
                                                                                      'Invisible',
                                                                                      'Contour seul',
                                                                                    ].contains(i['zoneFill'])
                                                                                ? Theme.of(context).colorScheme.onSurface
                                                                                : const Color(0xff123c38),
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
                                                  ),
                                                ),
                                              ),
                                          ...annotationPlanWidgets(
                                            scale,
                                            foreground: true,
                                          ),
                                          if (dragSnap.active)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: MagneticGuidePainter(
                                                    dragSnap.guides,
                                                    scale,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (dragSnap.active)
                                            Positioned(
                                              top: 8,
                                              right: 8,
                                              child: IgnorePointer(
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surface,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    dragSnap.label!,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurface,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (selectRectangle && !measuring)
                                            Positioned.fill(
                                              child: Listener(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onPointerDown: (d) {
                                                  if (d.buttons !=
                                                      kPrimaryMouseButton) {
                                                    return;
                                                  }
                                                  selectionStart =
                                                      selectionEnd =
                                                          d.localPosition /
                                                          scale;
                                                  selectionBase =
                                                      HardwareKeyboard
                                                          .instance
                                                          .isControlPressed
                                                      ? selectedPlanIds()
                                                      : <String>{};
                                                  selectionRectangle.value =
                                                      Rect.fromPoints(
                                                        d.localPosition,
                                                        d.localPosition,
                                                      );
                                                },
                                                onPointerMove: (d) {
                                                  if (selectionStart == null) {
                                                    return;
                                                  }
                                                  selectionEnd =
                                                      d.localPosition / scale;
                                                  selectionRectangle.value =
                                                      Rect.fromPoints(
                                                        selectionStart! * scale,
                                                        d.localPosition,
                                                      );
                                                },
                                                onPointerUp: (_) =>
                                                    endRectanglePointer(),
                                                onPointerCancel: (_) {
                                                  selectionStart =
                                                      selectionEnd = null;
                                                  selectionRectangle.value =
                                                      null;
                                                },
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onPanStart: (_) {},
                                                  onPanUpdate: (_) {},
                                                  onPanEnd: (_) =>
                                                      finishRectangleSelection(),
                                                  onTap:
                                                      finishRectangleSelection,
                                                  onDoubleTap:
                                                      rectangleDoubleClick,
                                                  child: RepaintBoundary(
                                                    child: CustomPaint(
                                                      painter:
                                                          SelectionRectanglePainter(
                                                            selectionRectangle,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (t != null &&
                                              !planReadOnly &&
                                              !rotationModeActive &&
                                              canResizePlanObject(t) &&
                                              !measuring)
                                            ...objectResizeHandles(t, scale),
                                          ...annotationResizeHandles(scale),
                                          ...planRotationControls(scale),
                                          if (measuring)
                                            Positioned.fill(
                                              child: GestureDetector(
                                                key: const ValueKey(
                                                  'distance-overlay',
                                                ),
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTapDown: (d) => setState(() {
                                                  final point =
                                                      d.localPosition / scale;
                                                  if (measureStart == null ||
                                                      measureEnd != null) {
                                                    measureStart = point;
                                                    measureEnd = null;
                                                  } else {
                                                    measureEnd = point;
                                                  }
                                                }),
                                                child: CustomPaint(
                                                  painter: DistancePainter(
                                                    measureStart,
                                                    measureEnd,
                                                    scale,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: showLegend ? 250 : 165,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 20, 16),
                  child: SingleChildScrollView(
                    key: const ValueKey('plan-sidebar'),
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonal(
                            key: const ValueKey('plan-arrange-button'),
                            onPressed: arranging || planReadOnly
                                ? null
                                : arrangeWithOptions,
                            child: arranging
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text('Disposition en cours…'),
                                      ),
                                    ],
                                  )
                                : const Text('Disposer mobilier'),
                          ),
                        ),
                        if (showLegend) ...[
                          if (measuring)
                            Text(
                              measureEnd == null
                                  ? 'Cliquer deux points pour mesurer.'
                                  : 'Distance : ${(measureEnd! - measureStart!).distance.toStringAsFixed(2)} m',
                            ),
                          const Text(
                            'Légende',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (parcoursActive(p!)) ...[
                            if (!parcoursCurrent(p!))
                              Text(
                                parcoursPaths(p!, allowStale: true).isEmpty
                                    ? 'Aucun tracé disponible.'
                                    : 'Dernier tracé en pointillés. Vous pouvez recalculer le parcours ou garder le plan actuel.',
                              ),
                            if (!parcoursCurrent(p!))
                              TextButton(
                                onPressed: arrangeWithOptions,
                                child: const Text('Recalculer… (facultatif)'),
                              ),
                            const Text(
                              'Trait bleu : passage visiteurs. Les espaces entre les rangées sont réservés aux exposants.',
                            ),
                            if (parcoursWarnings(p!).isNotEmpty)
                              Text(
                                parcoursWarnings(p!).join('\n'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            const SizedBox(height: 8),
                          ],
                          ...[
                            (const Color(0xffd7ddda), 'Vide'),
                            (const Color(0xffffd9ad), 'Partiellement occupée'),
                            (const Color(0xffa9d8bf), 'Pleine'),
                          ].map(
                            (state) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  Container(
                                    width: 18,
                                    height: 12,
                                    color: state.$1,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(state.$2)),
                                ],
                              ),
                            ),
                          ),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.warning_amber,
                              color: Colors.red,
                            ),
                            title: Text(
                              'Rouge : conflit de place ou de couloir',
                            ),
                          ),
                          for (final id in conflicts)
                            TextButton(
                              onPressed: () => focusPlanItem(
                                rows(
                                  p!,
                                  'items',
                                ).firstWhere((i) => i['id'] == id),
                              ),
                              child: Text(
                                'Conflit : ${rows(p!, 'items').firstWhere((i) => i['id'] == id)['label']}',
                              ),
                            ),
                          ...markerNames.map(
                            (name) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                children: [
                                  PlanMarker(
                                    name: name,
                                    color: markerColors[name]!,
                                    size: 16,
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
                            if (selectedTables.length > 1)
                              Text(
                                '${selectedTables.length} tables sélectionnées',
                              ),
                            if ((t['note'] ?? '').toString().isNotEmpty)
                              Text('Note : ${t['note']}'),
                            TextButton(
                              onPressed: removePlanSelection,
                              child: const Text('Retirer mobilier'),
                            ),
                          ],
                          const Divider(),
                          const Text(
                            'Molette : zoom. Couleurs des tables : occupation. Gris : obstacles. Bleu : zones. Accès libellés en clair.\nÉcart entre tables mesuré bord à bord, une seule fois. Assises contrôlées aux limites de salle. Pas de distance imposée avec les autres objets ; chevauchements signalés.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ],
                    ),
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
        'Mobilier',
        'Stock et dimensions par type, réservés à cet événement.',
        [
          FilledButton(
            onPressed: () => typeEdit(),
            child: const Text('+ Type'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => addTables(
              rows(p!, 'types').where((t) => t['enabled'] == true).toList(),
              all: true,
            ),
            child: const Text('Ajouter tout le mobilier sélectionné'),
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
                    '${t['source']} • ${t['shape'] == 'banc'
                        ? (max(number(t['w']), number(t['h'])) / number(eventComfort(p!)['benchSeatWidth'])).floor()
                        : ['chaise', 'chaise enfant', 'emplacement PMR'].contains(t['shape'])
                        ? 1
                        : t['capacity']} places • ${t['shape'] == 'banc' ? 'selon Confort' : t['seating']}\n${rows(p!, 'items').where((i) => i['type'] == t['id']).length} utilisées / ${t['limit']} autorisées / ${t['quantity']} disponibles',
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
                                  isStandBooking(g)
                                      ? '${g['name']} • ${g['standUnit'] == 'Mètres linéaires' ? '${g['requestedMetres']} m' : '${g['requestedTables'] ?? 1} tables'}'
                                      : '${g['name']} • ${g['count']} personnes',
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
      if (freeSeating(p!))
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Placement libre : capacité vérifiée, sans attribution automatique. Les préférences de proximité sont conservées pour un futur placement attribué. Les places réservées manuellement restent occupées.',
          ),
        ),
      if (rows(p!, 'groups').any(isStandBooking))
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(standSummaryLabel(p!)),
        ),
      heading('Réservations', 'Groupes par référent, sans noms individuels.', [
        if (mealsEnabled(p!))
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
                  rows(p!, 'groups').isNotEmpty &&
                          rows(p!, 'groups').every(isStandBooking)
                      ? '${standSummaryLabel(p!)} Préparer les tables de stand dans Plan de salle ; corriger chaque réservation avec Stand. Les attributions verrouillées restent conservées.'
                      : '${allocationSummary(p!)['assigned']} / ${allocationSummary(p!)['requested']} personnes attribuées. Préparer le mobilier et les passages dans Plan de salle ; corriger chaque groupe avec Tables. Les attributions verrouillées restent conservées.',
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
            labelText: 'Rechercher un groupe, une personne ou un contact',
          ),
          onChanged: (v) => setState(() => search = v),
        ),
      ),
      reservationFilterBar(),
      const SizedBox(height: 12),
      ...rows(
        p!,
        'groups',
      ).where((g) => reservationMatchesFilter(p!, g, reservationFilter, search)).map((
        g,
      ) {
        final places = isStandBooking(g)
            ? standAllocationText(p!, g)
            : (g['alloc'] as List)
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
                      if ((g['childChairs'] as int? ?? 0) > 0)
                        Text('Chaises enfant : ${g['childChairs']}'),
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
                            isStandBooking(g)
                                ? '${g['count']} personnes présentes (information) • ${standAllocationText(p!, g)}'
                                : '${g['count']} personnes réservées • $assigned attribuées • $remaining à placer',
                            style: TextStyle(
                              color: remaining > 0 ? Colors.deepOrange : null,
                            ),
                          );
                        },
                      ),
                      Text(
                        '${mealsEnabled(p!) ? '${g['meal']} • ' : ''}${g['needs']}${mealsEnabled(p!) ? ' ${g['allergy']}' : ''}',
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
                      if (g['waiting'] == true)
                        const Text(
                          'Liste d’attente — non attribuée automatiquement',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      if (similarReservations(p!, g).isNotEmpty)
                        Text(
                          'Nom ou contact similaire : ${similarReservations(p!, g).map((v) => v['name']).join(', ')}',
                        ),
                      ...reservationAllocationReasons(p!, g).map(
                        (reason) =>
                            Text(reason, style: const TextStyle(fontSize: 12)),
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
                SizedBox(
                  width: 360,
                  child: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => groupEdit(g),
                        child: const Text('Modifier'),
                      ),
                      TextButton(
                        onPressed: () => anonymousSeats(g),
                        child: const Text('Préférences'),
                      ),
                      TextButton(
                        onPressed: () => proximityEdit(g),
                        child: const Text('Proximité'),
                      ),
                      TextButton(
                        onPressed: g['waiting'] == true
                            ? null
                            : () => allocationEdit(g),
                        child: const Text('Tables'),
                      ),
                      TextButton(
                        onPressed: () => waitingStatusEditor(g),
                        child: Text(
                          g['waiting'] == true
                              ? 'Confirmer la réservation'
                              : 'Mettre en attente',
                        ),
                      ),
                      TextButton(
                        onPressed: g['waiting'] == true
                            ? null
                            : () => swapReservationsEditor(g),
                        child: const Text('Échanger…'),
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
        [],
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Les repères de passage et de confort se règlent dans les préférences de l’événement. Les collisions sont conservatrices (boîtes englobantes). Les portes sont traitées comme zones réservées rectangulaires : saisir toute la surface du débattement. Le sens est annoté, sans calcul de l’arc.\nAccessibilité : aucun calcul de trajet continu dans cette version. Vérifier l’entrée, toute l’allée jusqu’à la place, le bout de table, l’espace fauteuil et l’accompagnant. Les besoins restent signalés.',
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      selected: v['id'] == p!['id'],
                      leading: Icon(
                        eventIcon(v),
                        semanticLabel: eventIconName(v),
                      ),
                      title: Text(v['name']),
                      subtitle: Text(
                        '${v['room']['name']} • ${rows(v, 'groups').length} groupes',
                      ),
                      onTap: () => setState(() {
                        p = v;
                        selected = null;
                        selectedObjects.clear();
                        selectedTables.clear();
                        undo.clear();
                        redo.clear();
                        transform.value = Matrix4.identity();
                      }),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Wrap(
                        children: [
                          TextButton(
                            onPressed:
                                v['eventLocked'] == true ||
                                    v['planLocked'] == true
                                ? null
                                : () => comfortEdit(v),
                            child: const Text('Confort'),
                          ),
                          TextButton(
                            onPressed: v['eventLocked'] == true
                                ? null
                                : () => eventProperties(v),
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
                              copy['eventLocked'] = false;
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
                            onPressed: v['eventLocked'] == true
                                ? null
                                : () async {
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
                  ],
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
          ],
        ),
      ),
    ],
  );
}

class GridPainter extends CustomPainter {
  final double scale;
  final List<Point<double>> polygon;
  final bool dark;
  GridPainter(this.scale, this.polygon, {this.dark = false});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dark ? const Color(0xff1c2623) : Colors.white,
    );
    final line = Paint()
      ..color = dark ? const Color(0xff34493f) : const Color(0xffe5ebe7)
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
        ..color = dark ? const Color(0xff91ad9e) : const Color(0xff536a61)
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
      canvas.drawPath(
        outside,
        Paint()
          ..color = dark ? const Color(0xff101613) : const Color(0xffbdc8c1),
      );
      canvas.drawPath(
        contour,
        Paint()
          ..color = dark ? const Color(0xff91ad9e) : const Color(0xff536a61)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.scale != scale || old.polygon.toString() != polygon.toString();
}

class MagneticGuidePainter extends CustomPainter {
  final List<SnapGuide> guides;
  final double scale;
  MagneticGuidePainter(this.guides, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff2196f3)
      ..strokeWidth = 2;
    for (final guide in guides) {
      canvas.drawLine(
        Offset(guide.start.x, guide.start.y) * scale,
        Offset(guide.end.x, guide.end.y) * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(MagneticGuidePainter oldDelegate) => true;
}

class DistancePainter extends CustomPainter {
  final Offset? start, end;
  final double scale;
  DistancePainter(this.start, this.end, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    if (start == null) return;
    final paint = Paint()
      ..color = const Color(0xff1565c0)
      ..strokeWidth = 2;
    canvas.drawCircle(start! * scale, 5, paint);
    if (end == null) return;
    canvas.drawCircle(end! * scale, 5, paint);
    canvas.drawLine(start! * scale, end! * scale, paint);
    final text = TextPainter(
      text: TextSpan(
        text: '${(end! - start!).distance.toStringAsFixed(2)} m',
        style: const TextStyle(
          color: Color(0xff123c38),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = (start! + end!) * scale / 2;
    final rect = Rect.fromCenter(
      center: center,
      width: text.width + 12,
      height: text.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = Colors.white,
    );
    text.paint(canvas, rect.topLeft + const Offset(6, 4));
  }

  @override
  bool shouldRepaint(DistancePainter oldDelegate) => true;
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
    if (item['kind'] == 'zone' &&
        item['zoneFill'] == 'Invisible' &&
        !selected) {
      return;
    }
    final color = item['unplacedByArrangement'] == true && conflict
        ? const Color(0xffffcccc)
        : switch (item['kind']) {
            'table' || 'chair' || 'bench' || 'pmr' =>
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
      ..color = ['Contour seul', 'Invisible'].contains(style)
          ? Colors.transparent
          : color;
    final border = Paint()
      ..color = conflict
          ? Colors.red
          : selected
          ? const Color(0xff1565c0)
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
    if (selected && conflict) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & s).inflate(4),
          const Radius.circular(6),
        ),
        Paint()
          ..color = const Color(0xff1565c0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
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
