# Historique de Tableo

Historique en français, établi à partir des validations conservées du projet.
Les anciennes versions ne constituent pas des livraisons GitHub rétroactives.

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
