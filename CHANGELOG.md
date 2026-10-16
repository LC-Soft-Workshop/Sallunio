# Historique de Sallunio (anciennement Tableo)

Historique en français, établi à partir des validations conservées du projet.
Les anciennes versions ne constituent pas des livraisons GitHub rétroactives.

## 1.2.2

- Identité GitHub harmonisée : compte LC-Soft-Workshop, dépôt Sallunio et liens de mise à jour actualisés. Les anciennes adresses du dépôt, du wiki et des téléchargements restent redirigées.

- Migration de l’identité publique Tableo vers Sallunio et métadonnées Windows LC Software Workshop.
- Intégration de l’image officielle fournie, sans redessin, en PNG transparent et ICO multi-tailles ; application, exécutable et ressources Store harmonisés.
- Nouvel exécutable sallunio.exe et futurs artefacts Sallunio ; chemins de données, formats de sauvegarde et identifiants MSIX historiques conservés.
- Procédure documentée pour la fiche Store existante, le renommage du dépôt, les validations et le retour arrière. Publication autorisée pour la version 1.2.2 ; le changement du nom public d’éditeur Microsoft reste soumis aux possibilités du compte.

## 1.2.1

- Identité officielle « Modules » : trois blocs violet/corail sur fond bleu nuit, commune à l’exécutable Windows et au paquet Microsoft Store. Remplacement du logo Flutter par défaut, avec sept tailles d’icône Windows.
- Ajout des sources du logo et de ses règles de conservation pour garantir une identité identique sur les différents supports.
- Préparation Microsoft Store : génération d’un paquet MSIX x64 avec identité officielle, contrôle fermé des fichiers, logos séparés et validation par le SDK Windows. Aucun certificat de test installé et aucune donnée utilisateur incluse.
- Fonctions et format des événements inchangés par rapport à 1.2.0. La distribution GitHub est publiée en 1.2.1 ; la mise à jour Store suit le circuit de certification Microsoft.

## 1.2.0

Évolutions depuis **1.1.1**. Version Windows locale, sans compte ni envoi des événements sur Internet.

### Mobilier, sièges et stands

- Tables, chaises, bancs, chaises enfant et emplacements PMR autonomes ; création par catégorie avec dimensions et noms adaptés. La capacité d’un banc dépend de sa longueur et de la largeur par personne définie dans Confort.
- Usage du mobilier : places assises, stand/exposition ou service, réglable individuellement ou sur une sélection. La propagation d’un modèle transmet aussi son usage aux pièces existantes ; les nouveaux déploiements conservent cet usage.
- Réservations pour des places assises ou pour un stand, en tables entières ou mètres linéaires. Les événements peuvent mêler les usages ; Personnalisé conserve les possibilités des autres activités.
- Attribution des stands par portions colorées, noms affichables, tables exclusives ou partagées, modèle souhaité, attribution manuelle/automatique et verrouillage. Une demande de métrage reste contiguë et ne franchit ni allée ni portion déjà attribuée ; les jonctions ne sont pas comptées.
- Un seul modèle de table par stand par défaut, en tables comme en mètres. Mixité autorisable dans les paramètres d’attribution ; la disposition regroupe les modèles sous réserve des contraintes géométriques.
- Sièges et places numérotés, réservables ou bloquables individuellement. Placement libre possible, avec contrôle du nombre de réservations sans assignation automatique.
- Disposition devant une zone scène : rangées droites, éventail à trois blocs ou arc partiel. Inclinaisons orientées vers la scène, réglages d’angles dans Disposer mobilier, distances dans Confort, dégagement des blocs latéraux et dimensions conservées.
- Ordre naturel des numéros lorsque les dimensions permettent de le respecter. Chaises repérées C et chaises enfant CE ; libellés adaptés aux petits objets et infobulles détaillées sur tout le mobilier.
- Nombre de chaises enfant par réservation, limité au nombre de personnes et au stock autorisé restant. Les demandes en attente ne consomment pas le stock ; la confirmation vérifie la disponibilité. Dimensions proposées réglables dans Confort.
- Parcours réservés aux tables Stand / exposition : message explicite si seules des tables Places assises sont disponibles, sans déplacer le plan.

### Plan de salle et outils

- Barre d’outils réorganisée : menus Sélection, Ajouter, Affichage et outils complémentaires. Icône correspondant au mode de sélection actif, retour à la cible pour le magnétisme, ressources d’icônes complètes et retrait des cases vides.
- Ajout de mobilier avec quantité et disponibilité autorisée restante ; dernière pièce ajoutée directement, modèles épuisés grisés avec explication. Vider la salle est accessible dans les outils et Disposer mobilier au-dessus de la légende.
- Filtres adaptés aux catégories présentes ; libres, partiellement attribués, entièrement attribués et disponibilité restante fonctionnent pour les places assises et les stands partagés. Outil désactivé sans mobilier.
- Sélection multiple, rectangle et groupée avec Ctrl. Rectangle de sélection accéléré, recherche, alignement, répartition, déplacement précis et duplication dans la limite du stock.
- Retirer et Suppr agissent sans confirmation, avec annulation. Le retrait des objets hors salle et Vider la salle conservent toujours les modèles et quantités de l’inventaire. Le vidage permet de choisir les modèles placés et les catégories d’objets.
- Renumérotation volontaire avec aperçu, avertissement pour les étiquettes déjà imprimées, numéros protégés et annulation.
- Premier clic pour sélectionner ; clic supplémentaire espacé pour alterner redimensionnement et rotation libre, y compris pour les emplacements PMR et sélections multiples. Double-clic rapide conservé pour les propriétés.
- Maj conserve les proportions pendant le redimensionnement et applique des pas de 15° pendant la rotation. Poignées alignées sur les objets inclinés et toujours visibles au-dessus du plan lorsque la sélection est modifiable.
- Ordre d’affichage : avancer/reculer d’un niveau, premier/arrière-plan, dans les outils et le menu contextuel. Ordre sauvegardé et repris dans les PDF, sans modifier la géométrie.
- Espaces informatifs rectangulaires, carrés, ronds, ovales ou triangulaires, avec remplissage ou contour. Nom centré en bas et déplaçable séparément ; aucun effet sur les placements.
- Textes libres avec taille, gras, italique, souligné, orientation et rotation ; flèches décoratives ; images PNG/JPEG intégrées. Déplacement, dimensions, verrouillage, retrait, sauvegarde et export PDF.
- Verrou du plan permettant de poursuivre les réservations et assignations sans changer la disposition ; verrou d’événement en lecture seule avec navigation et exports accessibles.
- Vue mémorisée par événement ; dernier parcours modifié affichable en pointillés et recalcul présenté comme facultatif.
- Échap ferme les propriétés, Entrée valide, Tab/Maj+Tab parcourent les champs. Suppr reste une touche de saisie dans les champs.

### Réservations et événements

- Onglets d’événements réorganisables par glisser-déposer ; icône automatique selon l’activité ou choix parmi 14 icônes.
- Menu Préférences stable : champs et légendes de repas/allergies affichés uniquement si Prévoir des repas est activé. Les données restent conservées pour une réactivation ultérieure.
- Adresse e-mail et téléphone facultatifs par réservation, recherchables et conservés dans les sauvegardes. Libellé Nombre de personnes dans les propriétés.
- Liste d’attente exclue des attributions automatiques, filtres de réservations, détection de noms/contacts similaires, échange contrôlé des assignations et explications des demandes incomplètes.
- Repère carré Chaise enfant sur le plan et son PDF ; besoins de fauteuil roulant, autre mobilité et chaises enfant récapitulés avec quantités dans le récapitulatif, l’accueil et la liste d’attente.
- Titres et commandes harmonisés autour de Mobilier et Assignations ; retrait du lien redondant d’effacement des réservations.
- Lien vers les repères officiels d’accessibilité corrigé dans les recommandations de Confort.

### Exports et sauvegardes

- Export PDF configurable : plan, récapitulatif, fiches, accueil, cuisine/service et liste d’attente. Option indépendante de légende sur le plan, profils Organisation/Visiteurs/Exposants, plan sur plusieurs feuilles A4 avec repères d’assemblage.
- Export CSV séparé de la liste d’attente ; coordonnées, statut et demande de chaises enfant dans les CSV de réservations.
- Formes et couleurs des repères cohérentes entre le plan et le PDF. Noms des stands masquables via Affichage, en conservant numéros et portions colorées.
- Sauvegardes complètes et apports adaptés aux stands, sièges, annotations, images intégrées, ordre d’affichage, icônes et nouveaux paramètres. Préférences privées de proximité absentes des PDF.

## 1.1.1

- Correction du parcours fermé lorsqu’une zone près du mur rétrécit le passage de retour : la rangée de liaison réserve désormais toute la largeur nécessaire devant les zones et obstacles périphériques.
- L’espace exposants dos à dos se règle uniquement dans le confort de l’événement ; la disposition affiche la valeur à titre d’information sans la modifier.
- La case d’affichage du parcours peut réafficher le dernier tracé après une modification du plan. Un tracé obsolète apparaît en pointillés, avec une invitation à recalculer ; il n’est pas utilisé comme parcours validé.
- L’ouverture locale d’une jonction suit uniquement la rangée concernée et ne déplace plus les branches perpendiculaires reliées à son îlot.

## 1.1.0

Évolutions depuis la dernière version publiée, **1.0.43**. Cette version reste une application Windows locale, sans compte ni envoi des événements sur Internet.

### Parcours des exposants

- Nouveau mode de disposition **Parcours des exposants en S**, disponible pour les événements **Personnalisé, Marché de Noël et Brocante**. Rangées dos à dos, rotations automatiques et tables de fermeture entre les rangées ou à l’extérieur, selon les dimensions disponibles.
- Deux modes mémorisés : **parcours ouvert**, avec des allées reliées et des raccourcis possibles ; **parcours fermé**, recherchant un chemin imposé sans possibilité de contourner les exposants. Les propositions non réalisables sont signalées sans être remplacées silencieusement par un parcours ouvert.
- Avec une entrée seule, recherche d’un retour à cette entrée ; avec des entrées et sorties, raccordement des accès au parcours. Les accès multiples et les étapes choisies sont pris en compte, dans les limites des variantes de disposition disponibles.
- Aperçu du plan actuel dans les options de disposition : les zones à desservir se sélectionnent sur la carte ou dans la liste. Un bar ou une autre étape est rejoint par un bord accessible, sans traverser la zone ni coller une table devant son accès. Une zone libre peut aussi servir d’allée traversable, toujours interdite aux tables.
- Amélioration du remplissage avec des tailles de tables différentes, comparaison des orientations, disposition autour des zones et rangées simples complémentaires. Une rangée simple réserve de la place pour un seul exposant ; le mode ouvert peut ajouter une rangée sur le mur opposé.
- Nouvel appui **Tous les murs**. En parcours, seuls les bords de connexion peuvent toucher les murs autorisés ; les côtés d’assise gardent leur réserve. Les petites tables s’alignent du côté visiteurs. Les fermetures restent nécessaires si un bout n’est pas effectivement fermé par un mur.
- Correction des parcours après redimensionnement d’une entrée et des régressions avec une sortie. Les accès, objets fixés et tables de service conservent leur position. Les tables incompatibles ou en excédent restent hors salle avec une explication, sans créer de chevauchement.
- Tracé bleu, flèches et réserves exposants affichables ou masquables, également dans le PDF. Un plan modifié demande un recalcul des repères devenus obsolètes. Les tables restent au premier plan et les zones visibles restent sélectionnables au-dessus des zones invisibles.
- Calcul de disposition en arrière-plan, animation visible et blocage des clics répétés. En cas d’échec, le plan précédent est conservé ; annuler une disposition reste possible.

### Écarts de jonction

- Espacement hiérarchique : **réglage général du mobilier → type de mobilier → table du plan**, cette dernière étant prioritaire. Une valeur personnalisée de zéro signifie un contact direct, et non un héritage.
- Choix du premier bord, du second ou des deux, suivant la rotation et les côtés d’accolement autorisés. Une jonction utilise la plus grande des deux valeurs demandées, une seule fois. Le magnétisme et les dispositions tiennent compte de ces réglages.
- Saisie en **mètres**, avec virgule acceptée : **0,60 = 60 cm**. Les valeurs précédemment sauvegardées sont conservées.
- Dans les propriétés d’une table, ouverture immédiate des jonctions existantes par déplacement local des voisins, sans redisposition globale. La table éditée reste ancrée ; dimensions, rotations et attributions sont conservées. Les déplacements sont refusés ensemble si un objet fixé, un mur ou un obstacle bloque l’ouverture, et restent annulables.

### Proximité et accès PMR

- Les **zones libres, entrées et sorties** proposent **Inclure dans les préférences de proximité : Oui / Non**. Les éléments activés apparaissent sous leur nom dans les réservations, avec les choix **Sans préférence / Proche / Loin**. Une zone peut ainsi représenter librement un bar, une cuisine, une scène ou des toilettes.
- Renommer un élément conserve les souhaits ; le désactiver ou le supprimer retire les souhaits associés. Les sauvegardes complètes conservent ces liens. L’import partiel ne conserve que les références aux éléments effectivement présents/importés.
- Entrées et sorties : **Tous publics**, **PMR avec accompagnants** ou **Non-PMR uniquement**. Une entrée unique ou une sortie unique reste commune à tous. Avec plusieurs accès de la même catégorie, les choix suivent les besoins de mobilité des personnes du groupe, accompagnants compris. Les souhaits devenus incompatibles sont signalés en privé et ignorés par l’attribution.
- Les entrées et sorties gardent leur rôle dans les parcours. Les anciens objets Toilettes des essais sont conservés comme zones libres ; aucun nouveau type Toilettes n’est imposé.
- Les souhaits de proximité et leurs vérifications restent dans les réservations et sont absents de tous les PDF publics. Aucune justification personnelle n’est demandée.

### Confort propre à chaque événement

- Nouveau menu **Confort** dans le plan et la vue Événements : largeur des places ordinaires/PMR, profondeur des assises/fauteuils, allées libres ordinaires/PMR, écarts entre tables et murs, réserves dos à dos et au mur en parcours.
- Bouton **Proposer des valeurs confortables**, adapté au repas ou aux autres activités, avec explications écrites et lien vers les repères officiels d’accessibilité. Les allées libres sont distinguées des profondeurs d’assise ; la distance entre tables est mesurée bord à bord une seule fois.
- Capacités utilisables, enveloppes d’assise, dispositions, magnétisme et contrôles suivent ces valeurs. Les plans existants conservent leurs anciens réglages tant que le confort n’est pas configuré. Enregistrer ne déplace pas les tables : relancer la disposition ou l’attribution applique les nouveaux repères.
- Priorité aux places adaptées et aux places proches des allées principales pour les personnes en fauteuil ou ayant un autre besoin de mobilité. Une zone peut être marquée **Allée principale pour le placement PMR** ; à défaut, le parcours et les passages larges repérés servent d’indications. Les places imposées et attributions verrouillées restent conservées. Ce placement aide à organiser la salle sans certifier la continuité du trajet.
- Retrait du réglage Passage des contrôles de préparation : les espacements se règlent uniquement au niveau du confort de l’événement.

### Fichiers, publication et données

- Retrait de l’entrée isolée CSV dans Fichiers ; **Exporter CSV** reste disponible. L’import CSV des réservations reste accessible depuis Réservations.
- README réorganisé avec les fonctions, les nouveautés, les étapes d’utilisation, les précautions de mise à jour et le téléchargement permanent de la dernière version.
- Validation du code, tests fonctionnels et contrôles de publication ; paquet Windows construit à partir d’une liste fermée de fichiers, accompagné d’une empreinte SHA-256. Aucune base, réservation, sauvegarde ou export utilisateur n’est inclus dans le dépôt ou le ZIP.
- Les mises à jour conservent la base personnelle séparée des exécutables. Les essais locaux continuent d’utiliser un seul dossier Tableo-test, sans créer de numéros de version supplémentaires.

## 1.0.43

- Repères distincts sur les tables et dans la légende : hexagone violet pour la mobilité/PMR, triangle rouge pour les allergies, ronds pour les repas. Les emplacements adaptés utilisent un hexagone turquoise.
- Couleurs des repas plus contrastées : bleu pour le repas normal, vert pour le végétarien, orange pour le sans gluten et gris foncé pour les personnes qui ne mangent pas. Les catégories habituelles conservent leur couleur lors de l'ajout de catégories personnalisées.
- Repères agrandis pour rendre leurs formes lisibles. Les mêmes formes et couleurs sont conservées dans les plans PDF.

## 1.0.42

- Magnétisme étendu aux tables seules, sélections et ensembles accolés, ainsi qu'aux zones, obstacles, entrées, sorties et portes. Un ensemble s'accroche par une translation rigide, sans modifier les dimensions ou les positions relatives de ses tables.
- Accroche entre groupes de tables sur les côtés autorisés, avec alignement des centres. Les tables rondes restent séparées ; les tables non accolées peuvent s'aligner à la distance du passage configuré.
- Accroche aux murs, y compris aux parois d'un plan polygonal, en respectant l'appui autorisé, les assises et le passage minimum sans appui. Aucun chevauchement créé par une proposition d'accroche.
- Repères bleus temporaires pendant l'accroche. Décrochage possible en continuant à glisser, même par petits mouvements ; touche Alt ou bouton de magnétisme pour le déplacement libre.
- Barre d'outils à icônes carrées dans le bord gauche du plan : noms par place, sélection, filtres, déplacement des ensembles, rotation, mesure, places adaptées, verrouillage, édition, ajout de tables et d'objets, accolement, appui au mur et recentrage.
- Outils disposés de façon compacte sur les petites fenêtres, avec info-bulles. Rotation regroupée sous une seule icône, au choix pour la sélection ou toutes les tables.
- Déplacements et modifications toujours annulables ; objets verrouillés protégés. Les repères temporaires restent absents des exports et des sauvegardes.

## 1.0.41

- Entrées, sorties et portes redimensionnables par les quatre poignées, comme les zones. Les objets verrouillés restent protégés ; le redimensionnement est annulable. Les tables ne sont pas redimensionnables manuellement.
- Tables toujours affichées au premier plan, au-dessus des zones, obstacles, entrées, sorties et portes, quel que soit l'ordre de création des objets. Une table recouverte reste visible et sélectionnable.
- Même ordre d'affichage dans les PDF, y compris pour les libellés. Les zones invisibles restent absentes des PDF.
- Aucun changement des règles de placement : les chevauchements restent signalés, et les positions enregistrées ne sont pas modifiées par l'ordre d'affichage.

## 1.0.40

- Conservation de toutes les améliorations du plan, des places adaptées et des exports CSV ajoutées en 1.0.39.
- Correction de l'édition des personnes après retrait d'une table, modification des attributions ou réduction de capacité : les anciennes références devenues inutilisables sont retirées du formulaire, sans effacer les noms, repas, besoins ni effectifs. Annuler le formulaire conserve l'événement.

## 1.0.39

- Places adaptées configurables sur chaque table : emplacement numéroté, largeur et profondeur, réduction explicite de la capacité et signalement des besoins non couverts. Repère d'organisation à vérifier sur place.
- Sélection de plusieurs tables par Ctrl + clic ou case dédiée ; déplacement et rotation rigides de la sélection. Option pour déplacer les tables accolées ensemble, en respectant les verrouillages. Opérations annulables.
- Outil de mesure temporaire entre deux points du plan, en mètres, sans modifier l'événement ni les exports.
- Noms individuels facultatifs dans les réservations, en conservant le fonctionnement par groupes et effectifs. Choix d'un emplacement après attribution, repère des fauteuils et vérification de l'accompagnant.
- Filtres visuels pour les tables vides, places disponibles, mobilité, allergies et repas. Les autres tables sont atténuées ; les conflits restent visibles.
- Exports CSV des réservations, attributions et totaux des repas depuis Fichiers. Les notes internes et préférences privées de proximité sont exclues.
- Sélection bleue distincte des conflits rouges, y compris pour les zones invisibles sélectionnées.
- Poignées de redimensionnement des zones utilisables sur toute leur surface, même dans la moitié dépassant de la zone.
- Conservation des noms, réglages adaptés et références des emplacements lors des sauvegardes et imports.

## 1.0.38

- Ajout des modes clair et sombre, avec un bouton soleil/lune en haut à droite de l'application, disponible même sans événement ouvert.
- Choix du thème mémorisé localement et repris au prochain lancement, séparément des données des événements.
- Adaptation des menus, dialogues, compteurs, panneaux et arrière-plans du plan pour conserver leur lisibilité en mode sombre.
- Conservation des repères de couleur des tables et d'un aperçu de fiche sur fond de papier clair. Les exports PDF gardent leur présentation imprimable.
- La bascule conserve la page courante, la disposition et les attributions.

## 1.0.37

- Le repère indicatif de confort de 60 cm par place reste une information de préparation, avant comme après attribution des groupes. Il ne devient plus une alerte lorsque la capacité définie est respectée.
- Les vrais dépassements de capacité utilisable, chevauchements, passages insuffisants et autres conflits restent contrôlés et signalés.
- Vérification de l'attribution automatique sur une table à six places d'un seul côté : conservation du plan et des informations de confort, sans création d'erreur de proximité ou de confort.

## 1.0.36

- Clarification du menu d'import : la restauration complète reprend tous les événements sélectionnés et tout leur contenu, dont le plan, la disposition, les zones, obstacles, entrées, sorties, attributions et réglages.
- L'import partiel dans l'événement courant reste limité aux salles, au mobilier et aux réservations cochés.
- Vérification de la restitution intégrale de tous les champs et des objets du plan lors d'une restauration complète, y compris les zones invisibles.

## 1.0.35

- Import partiel au choix : salles mémorisées, mobilier, réservations ou les trois avec « Tout sélectionner ». Les salles importées ne remplacent pas la salle active.
- Pour plusieurs événements sélectionnés dans une sauvegarde, choix d'un seul événement source ou d'une fusion de leur contenu dans l'événement ouvert.
- Choix explicite pour les salles, modèles de mobilier et réservations portant le même nom : garder une version ou conserver les versions séparément.
- Comparaison des origines, dimensions, capacités, stocks et effectifs dans le dialogue des éléments communs. Aucun choix de version implicite.
- Conservation des références d'attribution uniquement vers les tables retenues ; les réservations concernées par un mobilier écarté restent à réattribuer, sans lien vers une table supprimée.
- Conservation de la restauration complète comme mode distinct recréant les événements de la sauvegarde. L'import partiel reste annulable et l'annulation des dialogues ne modifie aucune donnée.

## 1.0.34

- Sans appui autorisé, maintien d'au moins la moitié du passage entre le bord des tables et les murs : passage de 1,20 m, dégagement au mur d'au moins 60 cm. L'espace nécessaire aux assises reste également respecté.
- Application de cette règle aux cinq points de départ et après retrait d'un appui au mur ; l'exception ne concerne que les murs explicitement autorisés.
- En cas de manque de place, disposition des tables qui tiennent et regroupement des autres hors salle, en rouge, sans suppression ni perte des attributions.
- Cadrage étendu pour rendre les tables non placées visibles et sélectionnables ; explication du manque de place sur le plan et dans les contrôles.
- Les tables non placées sont réessayées lors d'une nouvelle disposition. Les tables verrouillées et de service restent à leur position. L'opération reste annulable.

## 1.0.33

- Ajout du point de départ « Centre » pour remplir la salle à partir du centre vers les espaces disponibles, en respectant les accolements et les zones.
- Correction des fausses alertes de sortie de salle dues aux arrondis aux limites après une disposition en miroir depuis les coins du bas.
- Validation du plan final après le calcul en miroir : une disposition invalide n'est pas appliquée partiellement.
- Conservation des positions des tables verrouillées et des tables de service dans les cinq modes de disposition.

## 1.0.32

- Première livraison Windows publiée sur GitHub, avec le dépôt de mises à jour configuré sur `freakbn777/Tableo`.
- Tests adaptés aux installations Flutter du serveur de compilation ; fichiers d'essai explicitement fictifs et séparés des données personnelles.
- Conservation du stockage personnel et des protections de publication de la version 1.0.31.

## 1.0.31

- Ajout de la vérification des versions publiques GitHub au démarrage et depuis le numéro de version.
- Signalement d'une nouvelle version avec accès à ses changements en français et à son téléchargement.
- Préparation du projet pour GitHub et d'un processus de validation et de publication Windows.
- Stockage personnel séparé du logiciel, sans repli dans le dossier d'installation.
- Fabrication des ZIP limitée aux fichiers autorisés ; rejet des fichiers supplémentaires et refus d'écraser une livraison existante.
- Aucune base, sauvegarde ou export utilisateur inclus dans la livraison. Aucun événement transmis par la vérification des versions.

## 1.0.30

- Liste d'accueil PDF alphabétique : référent, effectif, tables et case à cocher imprimée.
- Fiche cuisine/service en paysage : totaux des repas, répartition par table et besoins particuliers.
- Notes d'organisation pour les groupes et les tables.
- Choix du coin de départ de la disposition automatique parmi les quatre coins de la salle.
- Coordonnées du curseur et de l'objet sélectionné dans le plan.
- Plan PDF fidèle aux formes, couleurs d'occupation, remplissages, repères et légende ; zones invisibles entièrement omises.
- Les préférences privées de proximité ne figurent dans aucun PDF ni dans les contrôles généraux ; elles restent dans les réservations.

## 1.0.29

- Sauvegarde toujours complète des événements sélectionnés.
- À l'import : restauration complète dans des événements séparés, ou ajout du mobilier et/ou des réservations dans l'événement courant.
- Adaptation des identifiants et des relations pour préserver les éléments existants et éviter les collisions.
- Les réservations importées seules perdent leurs anciennes attributions étrangères à l'événement courant.
- Import partiel annulable ; protection contre le changement d'événement pendant l'enregistrement.

## 1.0.28

- Sauvegarde de plusieurs événements avec sélection individuelle ou sélection de tous.
- Lecture des événements contenus dans une sauvegarde et choix des événements à restaurer.
- Compatibilité avec les anciennes sauvegardes d'un événement et conservation des événements existants.
- Import disponible même lorsqu'aucun événement n'existe.

## 1.0.27

- Réglage des côtés assis au niveau de l'événement, avec conservation des anciens choix.
- Conservation des particularités des modèles de tables existants.
- Rubrique des réservations renommée « Besoins et repas » pour couvrir aussi la mobilité et les autres attentions particulières.

## 1.0.26

- Distinction entre alertes réelles et informations de préparation.
- Recalcul des alertes d'effectif et d'attribution à partir de la situation actuelle.
- Correction des anciens signalements persistants après résolution et des contrôles de confort à la limite exacte.

## 1.0.25

- Export PDF avec sections à cocher : plan, récapitulatif et fiches de table.
- Les sections choisies sont réunies dans un seul PDF.

## 1.0.24

- Affichage du numéro de version en bas à droite de l'application.

## 1.0.23

- Type d'activité et présence de repas déplacés de la salle vers l'événement.
- Activité « Soirée » avec choix indépendant des repas.
- Conservation des réglages existants lors du changement de salle.

## 1.0.22

- Propriétés d'événement : nom, logo et phrase personnalisée facultatifs.
- Logo conservé avec l'événement, sans dépendre du fichier d'origine.
- Logo et phrase dans les fiches de table A6.

## 1.0.21

- Suppression d'un événement depuis la vue Événements, avec confirmation.
- Après suppression du dernier événement, la liste reste vide au redémarrage.

## 1.0.20

- Libellés par défaut en français adaptés au type d'objet, sans remplacer un nom personnalisé.
- Option pour inclure les éléments verrouillés lors du nettoyage de la salle.
- Tables de service à zéro place, exclues du placement et de l'attribution automatiques.

## 1.0.19

- Onglets d'événements et profils d'activité : loto, marché de Noël, brocante et soirée.
- Gestion des places sur un côté ou autour des tables ; le côté assis suit leur rotation.

## 1.0.18

- Amélioration du remplissage par secteurs autour des zones centrales et de l'association des petites et grandes tables.
- Une disposition impossible ne déplace pas partiellement les tables.
- Nettoyage sélectif de la salle : tables, attributions, zones, modèles, accès et obstacles ; opération annulable.

## 1.0.16

- Option d'affichage des noms de groupes sur les places utilisables quand le plan est suffisamment zoomé.
- Répartition des noms selon le nombre de places attribuées et repérage des places libres.

## 1.0.15

- Préférences de proximité ou d'éloignement entre groupes, prises en compte au mieux dans l'attribution automatique.
- Respect des tables verrouillées, réservées et des séparations ; préférences conservées dans les réservations.

## 1.0.14

- Zones entièrement invisibles, toujours sélectionnables et utilisables pour réserver un espace.
- Libellé de zone facultatif.

## 1.0.13

- Redimensionnement manuel des zones par leurs coins, sans redimensionnement manuel des tables.
- Chevauchement entre zones autorisé.
- Propagation des propriétés de mobilier sans réinitialisation des positions ni rotations.
- Proposition de redisposition lorsque les dimensions changent et compteur d'alertes dans le menu.

## 1.0.12

- Fiches de table A6, quatre cadres par feuille A4, avec noms des groupes et places attribuées.
- Les tables sans attribution sont omises.

## 1.0.11

- Espacement de passage appliqué uniquement entre tables.
- Contact bord à bord autorisé avec les zones et autres objets ; les chevauchements physiques restent contrôlés.

## 1.0.10

- Choix de couleurs et de remplissages pour les zones : plein, hachures, croisillons et contour.
- Allée centrale définissable par une zone manuelle plutôt qu'une bande automatique.

## 1.0.9

- Affichage explicite des effectifs réservés, attribués et restants.
- Information lors d'un changement d'effectif ; une augmentation ne crée pas automatiquement des attributions.

## 1.0.8

- Accolement centré des tables de tailles différentes sur les faces autorisées.
- Tables rondes exclues de l'accolement.
- Appui contre un mur avec prise en compte des places devenues inutilisables.

## 1.0.7

- Correction du passage entre tables : la distance est comptée une seule fois, de bord à bord.

## 1.0.6

- Couleurs d'occupation : gris pour une table vide, orange pâle pour une table partiellement occupée, vert pâle pour une table pleine.
- Maintien du signalement rouge des conflits.

## 1.0.5

- Disposition automatique sans superpositions et sans modification partielle en cas d'échec.
- Rotation collective de 90 degrés en conservant le centre des tables.
- Repères de mobilité, repas et besoins particuliers sur les tables, avec légende.

## 1.0.4

- Fenêtres Windows d'ouverture et d'enregistrement des fichiers.
- Amélioration de l'import CSV dans une liste vide.
- Gestion explicite des doublons, homonymes et modifications, sans déduire automatiquement les identités.

## 1.0.0 à 1.0.3

- Première version locale Windows : plans de salle, dimensions, mobilier, zones, accès et obstacles.
- Réservations de groupes, effectifs, repas, mobilité et allergies ; attribution manuelle ou automatique.
- Placement et rotation des tables, verrouillage, réservations de tables, séparations et places anonymes.
- Stockage SQLite local, import CSV, sauvegardes, exports PDF et annuler/rétablir.
- Exemple CSV exclusivement fictif ; export PDF utilisant la situation actuelle de l'événement.

La version 1.0.17 ne dispose pas d'une note de validation distincte dans les archives du projet ; aucun changement spécifique n'est inventé pour ce numéro.
