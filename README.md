# Tableo

<img src="assets/branding/tableo-modules.png" alt="Icône officielle de Tableo — Modules" width="96">

**Tableo 1.2.1** est une application Windows en français pour préparer les événements : plans de salle, mobilier, réservations, attribution des places, accueil et service.

L’application fonctionne **localement, sans compte**. Vos événements restent sur votre ordinateur. Android, la sauvegarde en ligne, le travail collaboratif et les rôles sont envisagés pour une future version 2 et ne sont pas inclus dans cette version.

## Télécharger la dernière version

**[Télécharger Tableo pour Windows — ZIP](https://github.com/freakbn777/Tableo/releases/latest/download/Tableo-Windows.zip)**

Ce lien permanent télécharge la dernière version publiée. Le paquet est destiné à Windows 64 bits.

- [Nouveautés de la dernière version](https://github.com/freakbn777/Tableo/releases/latest)
- [Guide utilisateur en français — Wiki](https://github.com/freakbn777/Tableo/wiki)
- [Historique complet en français](CHANGELOG.md)
- [Signaler un problème ou proposer une amélioration](https://github.com/freakbn777/Tableo/issues)

Les retours des organisateurs sont les bienvenus : ce qui fonctionne bien, ce qui manque et ce qui gagnerait à être simplifié. Ne joignez pas de réservations réelles ou de données personnelles dans un signalement public ; un exemple fictif suffit généralement à reproduire un problème.

## Installer et mettre à jour

1. Télécharger le ZIP et le décompresser dans un dossier dédié.
2. Lancer **tableo.exe**, en conservant tous les fichiers du paquet ensemble.
3. Pour une mise à jour, fermer l’ancienne application, décompresser la nouvelle version dans un autre dossier, puis lancer son exécutable.

Les événements sont conservés séparément dans **%APPDATA%\Tableo\tableo.sqlite**. Le ZIP ne contient aucune base personnelle et une mise à jour n’écrase pas cette base. Avant une mise à jour importante, **Fichiers → Exporter projet** permet de garder une copie indépendante des événements choisis.

Le numéro de version, en bas à droite, donne accès à la vérification des mises à jour et aux changements publiés. La vérification consulte GitHub et n’envoie aucun événement, nom, plan ou logo. Elle ne télécharge ni n’installe automatiquement de version ; les fonctions locales restent disponibles hors ligne.

Voir [Données et mises à jour](DONNEES-ET-MISES-A-JOUR.md) pour les détails du stockage, de la confidentialité et de la fabrication des livraisons.

## Identité visuelle — version 1.2.1

Le logo officiel « Modules », violet et corail sur fond bleu nuit, remplace l’icône Flutter dans l’application Windows. Il est commun aux distributions GitHub et Microsoft Store. Les fonctions et le format des événements restent ceux de la version 1.2.0.

La même version 1.2.1 a été envoyée au Microsoft Store ; sa disponibilité dépend de la certification et de la publication Microsoft. [Fiche Microsoft Store](https://apps.microsoft.com/detail/9PNHKMRHHJML).

Les sources et règles de conservation du logo sont dans [l’identité officielle](assets/branding/IDENTITE.md).

## Principales fonctions

- Plusieurs événements, avec onglets et profils **Personnalisé, Loto, Soirée, Marché de Noël et Brocante**. Le repas et les côtés d’assise sont liés à l’événement.
- Salles à l’échelle, dimensions en mètres et contour facultatif pour une salle non rectangulaire.
- Stock de mobilier, formes et capacités configurables, places adaptées, tables de service et propagation des propriétés aux pièces existantes.
- Placement manuel ou automatique, rotation, choix du point de départ et appui aux murs autorisés.
- Barre d’outils du plan : sélection, filtres, déplacement d’ensembles, rotation, mesure, édition, ajout et recentrage. Magnétisme vers les tables, murs et objets.
- Zones libres, obstacles, entrées, sorties et portes. Couleurs et remplissages des zones, dont un mode invisible ; ordre d’affichage personnalisable.
- Réservations par groupe, noms individuels facultatifs, repas, allergies et besoins de mobilité. Import CSV et attribution automatique ou manuelle, avec verrouillage.
- Noms des personnes/groupes affichables sur les places à un zoom suffisant. Tables grises lorsqu’elles sont vides, orange pâle lorsqu’elles sont partiellement occupées, vert pâle lorsqu’elles sont pleines.
- Légende avec formes et couleurs distinctes pour les repas, les allergies et la mobilité/PMR.
- Préférences de proximité avec les autres groupes et les lieux activés sur le plan, règles de public autorisé pour les accès et confort configurable par événement.
- Modes **parcours ouvert et fermé** pour les événements compatibles, avec aperçu et étapes à desservir.
- Contrôles de préparation, compteur d’alertes, annuler/rétablir et notes d’organisation.
- Mode clair ou sombre, basculable depuis l’icône en haut à droite.
- Sauvegardes de projets, restauration complète ou apport sélectif dans l’événement courant ; exports PDF et CSV.

## Préparer un événement

1. Créer l’événement et choisir son type, puis définir le repas, les côtés d’assise et l’objectif de participants.
2. Choisir ou créer la salle et placer les zones, obstacles et accès.
3. Définir le mobilier et ses quantités. Une capacité de **zéro** identifie une table de service, exclue de la disposition automatique.
4. Ouvrir **Confort** de l’événement pour conserver ou ajuster les repères et les valeurs proposées.
5. Placer les tables manuellement ou utiliser **Disposer mobilier**. Pour un marché ou une brocante, choisir éventuellement un parcours.
6. Saisir/importer les réservations, les besoins individuels et les souhaits de proximité, puis attribuer les groupes aux tables.
7. Examiner les contrôles et vérifier les conditions réelles avant d’exporter les documents utiles.

Enregistrer un réglage ne déplace pas automatiquement les tables déjà placées. Relancer la disposition ou l’attribution lorsque le changement doit être appliqué à leur organisation. Les pièces fixées et attributions verrouillées sont conservées ; les conflits restent signalés.

## Plan, zones et accolements

Les zones sont libres : nom, taille, couleur et remplissage. Une zone peut représenter un bar, une cuisine, une scène, des toilettes ou une allée. Une zone invisible reste sélectionnable dans l’éditeur mais ne figure pas dans le plan PDF. Les zones, entrées, sorties et portes sont redimensionnables ; les tables gardent les dimensions de leur mobilier.

Le contour facultatif de salle est une liste de sommets **x,y**, séparés par des points-virgules, en mètres. Exemple : **0,0;12,0;12,6;8,6;8,9;0,9**. Utiliser le point pour les décimales ; le contour se ferme automatiquement.

L’accolement est autorisé selon les petits côtés, les grands côtés, les deux ou aucun. Les tables rondes restent séparées. Deux tables de tailles différentes s’alignent par leur centre sur une jonction autorisée ; le magnétisme tient compte des écarts configurés.

### Écarts de jonction

Dans **Mobilier**, le bouton **Écart** règle la valeur générale. Chaque type de mobilier puis chaque table du plan peut **Hériter** ou **Personnaliser**. La priorité est : **table du plan → type de mobilier → réglage général**.

- Valeurs en mètres : **0,60 = 60 cm**. Zéro personnalisé signifie un contact direct.
- Premier bord, second bord ou les deux. Les bords suivent la rotation ; seuls les côtés autorisés peuvent former une jonction.
- Si les deux tables demandent des écarts différents sur la même jonction, la plus grande valeur est retenue **une seule fois**.
- Dans les propriétés d’une table, **Appliquer l’écart aux jonctions existantes maintenant** décale localement les voisines. La table éditée garde sa position, sans redisposition globale ni modification des dimensions ou des attributions.
- Une pièce fixée, un mur ou un obstacle empêchant l’ouverture annule tous les déplacements proposés. L’opération est annulable. Choisir **Non** pour enregistrer le réglage en conservant les positions.

Ces écarts sont distincts des allées et des réserves d’assise. Les zones et autres objets n’imposent pas de marge de passage supplémentaire avec les tables ; leurs chevauchements physiques restent contrôlés. Les chevauchements entre zones ne créent pas d’alerte.

## Parcours des exposants

Disponible uniquement pour **Personnalisé, Marché de Noël et Brocante**, depuis **Disposer mobilier**.

- **Ouvert** : disposition optimisée avec des allées reliées et des raccourcis possibles. Une rangée simple garde une réserve pour un seul exposant ; le calcul peut ajouter une rangée sur le mur opposé.
- **Fermé** : recherche d’un parcours imposé, sans raccourci permettant de manquer des exposants. Le tracé bleu seul ne prouve pas la fermeture ; les variantes non réalisables sont signalées sans remplacement silencieux par un parcours ouvert.

Les options règlent l’orientation, les tables de fermeture entre les rangées ou à l’extérieur et les murs autorisés, dont **Tous les murs**. Les tables peuvent pivoter automatiquement sans changer leurs dimensions. En parcours, seuls les bords de connexion peuvent toucher un mur autorisé ; les côtés où les exposants s’assoient gardent leur réserve.

L’aperçu reprend le plan actuel. Sélectionner les zones à desservir, par exemple un bar : le parcours doit rejoindre un bord accessible, sans traverser la zone ni placer une table devant son accès. Une zone servant d’allée peut être déclarée traversable pour les visiteurs et reste interdite aux tables. Ces choix sont distincts des préférences privées de proximité.

Une entrée seule permet de rechercher un retour à cette entrée ; les entrées et sorties multiples sont raccordées lorsque la configuration le permet. Les objets fixés, tables de service et accès restent en place. Les tables incompatibles ou en excédent restent hors salle avec une explication.

Le calcul affiche une animation et bloque les clics répétés. Les tracés peuvent être masqués, y compris dans le PDF. Après une modification, le dernier tracé peut rester affiché en pointillés. Recalculer est une suggestion facultative ; garder le plan actuel reste possible.

## Réservations, proximité et accès PMR

Dans les propriétés d’une **zone libre, entrée ou sortie**, activer **Inclure dans les préférences de proximité → Oui**. L’élément apparaît sous son nom dans **Réservations → Proximité**, avec **Sans préférence / Proche / Loin**, en plus des autres groupes.

Renommer un lieu conserve les souhaits ; le désactiver ou le supprimer retire les souhaits associés. Une préférence se rapporte à l’élément choisi : avec plusieurs bars ou accès, chaque élément activé apparaît séparément. Les préférences sont des souhaits pris en compte selon les places disponibles.

Les entrées et sorties proposent **Public autorisé** :

| Réglage | Groupes concernés lorsqu’il y a plusieurs accès de cette catégorie |
|---|---|
| Tous publics | Tous les groupes |
| PMR avec accompagnants | Groupe comprenant au moins une personne ayant un besoin de mobilité |
| Non-PMR uniquement | Groupe sans besoin de mobilité déclaré |

Une entrée unique ou une sortie unique reste commune à tous, indépendamment du réglage mémorisé. Les entrées et sorties sont comptées séparément : avec deux entrées et une sortie, seules les entrées sont filtrées. Les souhaits devenus incompatibles sont signalés dans les réservations et ignorés par l’attribution.

**Les souhaits de proximité et leurs vérifications restent privés dans les réservations et ne sont jamais affichés dans les PDF publics. Aucune justification personnelle n’est demandée.**

## Confort de l’événement

La rubrique **Confort** de l’événement regroupe :

- largeur d’une place ordinaire et d’une place PMR ;
- profondeur réservée derrière une assise et pour un fauteuil ;
- largeur libre des allées courantes et des allées avec PMR ;
- distance entre les bords des tables hors jonctions et entre table et mur hors appui autorisé ;
- réserve dos à dos pour les exposants et réserve entre une rangée simple et un mur en parcours.

**Proposer des valeurs confortables** prépare des valeurs adaptées au repas ou aux autres activités, sans les enregistrer automatiquement. Les recommandations expliquent les repères : 60 à 65 cm par personne, 90 cm pour une place PMR avec 1,30 m de profondeur, 1,20 m d’allée courante et 1,50 m avec PMR.

Une allée libre n’inclut pas les assises. Par exemple, un écart de **2,40 m** entre tables permet de prévoir deux profondeurs d’assise de **60 cm** et une allée de **1,20 m**. La disposition conserve au moins la réserve nécessaire ; l’écart entre les bords n’est pas additionné deux fois. Les capacités utilisables et les contrôles suivent les valeurs choisies.

Une zone libre peut être marquée **Allée principale pour le placement PMR**. Les places adaptées proches de ces allées sont privilégiées lors de l’attribution ; à défaut, le parcours et les passages larges repérés servent d’indications. Les places individuelles imposées et les groupes verrouillés sont préservés.

Enregistrer conserve les positions et les attributions : relancer la disposition ou l’attribution applique les nouveaux repères. Les anciens plans gardent leurs valeurs tant que le confort n’est pas configuré. Les contrôles de préparation présentent les résultats ; ils ne règlent plus le passage.

Ces repères aident à organiser la salle sans certifier la continuité du cheminement ni l’accessibilité. Vérifier les conditions réelles et les espaces de manœuvre. Le menu contient un lien vers les [repères officiels d’accessibilité](https://www.legifrance.gouv.fr/jorf/id/JORFARTI000034485474).

## Exports, sauvegardes et import

### Documents PDF et CSV

Le menu d’export PDF permet de combiner dans un même document les éléments choisis : **plan**, **récapitulatif**, **fiches de table**, **liste d’accueil** et **fiche cuisine/service**.

Les fiches de table utilisent des cadres A6, **quatre par feuille A4**, avec les groupes/noms et le nombre de places attribuées à la table. Les tables vides sont omises. Le logo et le message des fiches se définissent dans les **propriétés de l’événement** et sont réutilisés aux exports suivants.

L’affichage du parcours, des zones invisibles et des noms par place est respecté dans le plan exporté. Les réservations, attributions et repas peuvent aussi être exportés en CSV. L’import CSV des réservations reste accessible depuis Réservations ; [un modèle fictif](examples/modele-reservations.csv) est fourni.

### Sauvegarder ou apporter des données

**Fichiers → Exporter projet** sauvegarde les événements choisis, ou tous les événements, avec leur contenu complet.

À l’import :

- **Restauration complète** : réimporter les événements sélectionnés avec leur plan, mobilier, réservations, zones, obstacles, accès et paramètres.
- **Apport sélectif** : apporter les salles, le mobilier, les réservations ou une combinaison dans l’événement actuellement ouvert. Avec plusieurs sources, sélectionner les événements à utiliser et résoudre les éléments communs proposés à la fusion.

Les liens entre réservations et objets sont conservés dans une restauration complète. Un apport partiel ne conserve que les références aux éléments effectivement présents/importés.

**Vider la salle** propose les catégories à supprimer et une option pour inclure les éléments verrouillés. Les éléments non cochés sont conservés. Cette action peut être annulée.

## Développement et publication

Le projet utilise **Flutter 3.47.6**, Dart et les outils de compilation Windows.

```text
flutter pub get
flutter analyze
flutter test
python tools/test_publication.py
flutter build windows --release --no-tree-shake-icons --dart-define=TABLEO_GITHUB_REPOSITORY=freakbn777/Tableo
python tools/package_release.py
```

La liste des fichiers autorisés se consulte avec **python tools/publication_files.py**. Les bases, sauvegardes, PDF, dossiers de travail et livraisons locales sont exclus du dépôt. Le paquet Windows est fabriqué à partir d’une liste fermée et accompagné d’une empreinte SHA-256.

GitHub vérifie le code et compile Windows. Un tag **vX.Y.Z** correspondant au numéro du logiciel publie une livraison avec les notes extraites du changelog français et un ZIP au nom permanent **Tableo-Windows.zip**.

Les essais locaux utilisent **python tools/package_release.py --local**, qui actualise uniquement **dist/Tableo-test**. Leur numéro reste celui de la dernière publication jusqu’à une publication suivante autorisée ; aucune suite de versions locales intermédiaires n’est créée.

## Évolutions envisagées

La version 2 pourrait proposer Android avec un périmètre adapté aux petits écrans, une sauvegarde en ligne, le travail en équipe et des rôles à définir. Les fonctionnalités en ligne pourraient nécessiter une option payante ; l’objectif est de conserver autant que possible une utilisation locale gratuite. Le périmètre et le financement restent à préciser selon l’intérêt et les retours des organisateurs.

## Sièges, stands et outils de la version 1.2.0

La version 1.2.0 étend la gestion aux stands, sièges autonomes et plans annotés. Le [changelog](CHANGELOG.md#120) détaille les nouveautés depuis 1.1.1.

- Dans **Événements → Propriétés → Attribution**, choisir places assises ou exposants/stands, l’unité des stands (tables ou mètres) et le placement libre ou attribué. Ces réglages définissent les nouveaux éléments ; les événements peuvent conserver un mélange d’usages.
- Dans **Mobilier**, ajouter des tables, des chaises, des chaises enfant, des bancs ou des emplacements PMR sans chaise. La capacité des bancs suit la largeur par personne de **Confort**. Sur le plan, **Modifier** permet de régler l’usage d’une pièce ; avec plusieurs pièces sélectionnées, l’outil de modification propose un changement d’usage collectif.
- Dans **Réservations → Modifier**, choisir places assises ou stand, la demande et, pour le métrage, le partage éventuel d’une table. **Tables** permet d’attribuer les tables ou portions manuellement ; l’attribution automatique garde les éléments verrouillés. Le métrage ne comprend ni les allées ni les écarts de jonction.
- Double-cliquer une chaise ou un banc, ou choisir **Places numérotées et réservées** dans les propriétés d’une table, pour fixer une personne à une place ou bloquer cette place. Le placement libre conserve ces choix et compare les effectifs à la capacité sans attribuer le reste automatiquement.
- Avec des chaises, bancs ou emplacements PMR sur le plan, **Disposer mobilier → Sièges face à une scène** propose les rangées droites, l’éventail et l’arc partiel. Choisir une zone libre représentant la scène. Les modes et angles appartiennent à Disposer ; toutes les distances restent dans Confort.
- Les noms et portions de stands apparaissent sur le plan et dans les fiches PDF. Les sauvegardes et apports conservent les nouvelles attributions ; les préférences privées de proximité restent absentes des PDF.

L’option **Prévoir des repas** de l’événement commande toujours les préférences et légendes de repas, quel que soit l’usage du mobilier.

Les stands par tables entières ou en mètres linéaires utilisent par défaut un seul modèle de table (dimensions identiques), sur une suite contiguë. Dans les propriétés de l’événement, ouvrir « Attribution : sièges, stands et placement libre » pour autoriser la mixité si nécessaire. La disposition regroupe les modèles de stands, sous réserve des contraintes de fermeture et de l’espace disponible.

Dans la barre d’outils du plan, Ajouter → Image permet d’insérer des images PNG ou JPEG (10 Mo maximum par fichier). Répéter l’action pour ajouter plusieurs images. Les images sont incorporées au projet et aux PDF, sous les zones et le mobilier, sans bloquer les placements. Double-cliquer pour modifier leur nom, leurs dimensions et leur verrouillage ; utiliser les poignées pour redimensionner, l’outil rotation pour pivoter et Suppr pour retirer. Vider la salle propose une catégorie Images indépendante.

Ajouter → Espace informatif propose cinq formes : rectangle, carré, cercle, ovale et triangle, avec un remplissage ou un contour seul. Le cercle et le carré conservent leurs proportions. Ajouter → Flèche crée une flèche décorative avec couleur, opacité, dimensions et angle réglables. Ces objets se déplacent, se redimensionnent, se verrouillent et se suppriment ; les flèches restent au-dessus du mobilier. Ils sont inclus dans les sauvegardes complètes et les plans PDF et n’influencent aucun calcul de disposition.

Les poignées de redimensionnement des images, espaces informatifs et flèches sont affichées au-dessus de tout le plan lorsque l’objet est sélectionné et modifiable. La barre d’outils « Ordre d’affichage », ainsi que le clic droit, proposent Avancer d’un niveau, Reculer d’un niveau, Mettre au premier plan et Mettre à l’arrière-plan. Ces commandes concernent aussi le mobilier et les zones et peuvent s’appliquer à une sélection ; elles sont annulables et leur résultat est sauvegardé et repris dans les PDF. Elles ne changent aucune position ni règle de collision.

Sur le plan, un premier clic sélectionne un objet et affiche les poignées disponibles. Un deuxième clic sur cette sélection, suffisamment espacé pour ne pas être un double-clic, affiche un cadre et des ancres rondes de rotation ; un clic supplémentaire revient au mode précédent. Faire glisser une ancre pour tourner librement, ou maintenir Maj pour des pas de 15°. Les emplacements PMR et les sélections multiples sont pris en charge. Le double-clic rapide ouvre toujours les propriétés. Les objets fixés et les plans verrouillés restent protégés ; les dimensions des modèles de mobilier ne sont pas modifiées par la rotation.

Maintenir Maj en faisant glisser une poignée de redimensionnement conserve les proportions initiales de l’objet, même incliné ; relâcher Maj autorise de nouveau une largeur et une hauteur indépendantes. Les cercles et les carrés gardent toujours leur forme. Lors d’une rotation, Maj reste associé aux pas de 15°.

Les réservations peuvent porter une adresse e-mail et un téléphone facultatifs. La liste d’attente dispose de ses propres exports PDF et CSV ; les coordonnées sont conservées dans les sauvegardes complètes.

Le mobilier propose aussi les chaises enfant (une place, repère CE), avec dimensions initiales réglables dans Confort et espacements communs aux autres sièges.

Chaque réservation peut demander un nombre de chaises enfant, limité au nombre de personnes et au stock autorisé encore disponible. Les réservations en attente conservent leur demande sans réserver le stock avant confirmation.

Les besoins de chaise enfant apparaissent sur le plan et son PDF avec un repère carré. Les exports récapitulatif, accueil et liste d’attente détaillent les fauteuils roulants, autres besoins de mobilité et chaises enfant avec leurs quantités.

## Raccourcis, filtres et protection du plan

- **Suppr** ou **Retirer** enlève la sélection immédiatement ; Annuler restaure les objets et leurs assignations sans modifier le stock.
- **Échap** ferme une fenêtre de propriétés ; **Entrée** enregistre ; **Tab** et **Maj+Tab** parcourent les champs.
- **Filtrer** propose les catégories présentes et les états libre, partiellement attribué, entièrement attribué ou disponibilité restante, pour les sièges et les stands.
- **Verrouiller le plan** protège la disposition tout en permettant les réservations. **Verrouiller l’événement** passe l’ensemble en lecture seule.
- L’outil **Vider la salle** permet de retirer les catégories choisies ; les modèles de l’inventaire sont conservés.
- La renumérotation est facultative, précédée d’un aperçu et annulable. Si des étiquettes sont déjà imprimées, conserver les numéros ou protéger ceux qui doivent rester fixes.

Pour exporter la liste d’attente, cocher **Liste d’attente** dans **Fichiers → Export PDF**, ou choisir ce contenu dans **Exporter en CSV**. Les PDF d’organisation récapitulent les besoins spéciaux ; vérifier le destinataire avant de partager des documents contenant des coordonnées ou des besoins personnels.
