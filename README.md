# Tableo

Tableo est une application Windows en français pour organiser des événements :
plans de salle, mobilier, réservations, attribution des places et préparation du service.
La version 1 fonctionne localement, sans compte.

## Fonctions

- Plusieurs événements et salles, profils loto, soirée, marché de Noël et brocante.
- Plans à l'échelle, zones, accès, obstacles, rotation et placement manuel ou automatique.
- Accolement selon les côtés autorisés, contrôle des chevauchements et des passages.
- Réservations, groupes, repas et besoins particuliers, import CSV, attribution des places.
- Exports PDF au choix : plan, récapitulatif, fiches A6 par table sur A4,
  liste d'accueil et fiche cuisine/service.
- Sauvegarde et restauration d'événements, import de mobilier ou réservations dans l'événement courant.
- Annuler/rétablir, notes d'organisation et contrôles de préparation.

Les préférences privées de proximité entre groupes restent dans les réservations
et ne sont jamais imprimées dans les PDF.

## Installation et mises à jour

Télécharger le ZIP Windows dans les versions GitHub, le décompresser puis lancer
`tableo.exe`. Garder tous les fichiers du paquet ensemble.
Une nouvelle version se décompresse dans un nouveau dossier ; les événements
restent dans le dossier personnel Windows, indépendamment des exécutables.
Voir [les protections des données](DONNEES-ET-MISES-A-JOUR.md).

Le numéro de version en bas à droite donne accès à la vérification des mises à jour
et aux changements. La vérification nécessite une connexion et un dépôt GitHub
public configuré lors de la compilation ; elle ne transmet aucun événement.
Le fonctionnement des événements reste local.

L'[historique des versions](CHANGELOG.md) est en français.
Le fichier `examples/modele-reservations.csv` contient uniquement des exemples fictifs.

## Développement

Flutter 3.47.6, Dart et les outils de compilation Windows sont nécessaires.

```text
flutter pub get
flutter analyze
flutter test
python tools/test_publication.py
flutter build windows --release --dart-define=TABLEO_GITHUB_REPOSITORY=compte/depot
python tools/package_release.py
```

Remplacer `compte/depot` par le véritable dépôt public de versions.
Le processus GitHub vérifie le projet, compile Windows et publie une livraison
pour un tag `vX.Y.Z` correspondant au numéro du logiciel. Les notes sont extraites
du changelog français. Les anciennes versions ne doivent pas recevoir de tags
pointant vers le code actuel.

Avant le premier envoi, relire les fichiers de la liste produite par
`python tools/publication_files.py`. Les bases, exports et dossiers de travail
ne font pas partie du projet public.

## Évolutions envisagées

Une version Android adaptée et des options de sauvegarde en ligne, collaboration
et rôles sont envisagées pour une version 2. Leur périmètre et leur financement
restent à définir ; elles ne font pas partie de la version 1.
