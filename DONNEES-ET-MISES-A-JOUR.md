# Données et mises à jour

Les événements, réservations, plans et logos personnels sont conservés dans
`%APPDATA%\Tableo\tableo.sqlite`, séparément du dossier du logiciel. Une nouvelle
version ouvre cette même base ; elle ne fournit aucune base à remplacer.
Le stockage refuse de retomber dans le dossier du logiciel si le dossier personnel
Windows ne peut pas être trouvé. Le nettoyage des livraisons ne touche pas ce dossier.

Pour mettre à jour, décompresser la nouvelle livraison dans son propre dossier
`Tableo-numéro-de-version`, fermer l'ancienne application et lancer la nouvelle.
Ne jamais décompresser un logiciel dans le dossier des données personnelles.
La vérification de version ne télécharge ni n'installe automatiquement de logiciel.

La seule requête de vérification consulte la dernière version publique de GitHub.
Elle transmet le numéro de version du logiciel dans son en-tête ; aucun événement,
nom, réservation, plan ou logo ne lui est fourni. GitHub reçoit les informations
habituelles d'une connexion Internet, dont l'adresse IP. Sans connexion, Tableo
reste utilisable. Le menu du numéro de version permet une vérification manuelle
et l'ouverture de l'historique français.

## Publication du projet

`python tools/publication_files.py` liste les fichiers candidats autorisés.
Avant publication, leur contenu doit être relu : une liste de chemins protège des
exports accidentels, mais ne détecte pas une donnée personnelle écrite dans du code.
Ne pas employer `git add .` ni copier un dossier de données utilisateur.
`python tools/publication_files.py --tracked` refuse les fichiers suivis hors liste.
Les tests et l'exemple CSV utilisent uniquement des données fictives.

Le paquet Windows est construit à partir d'une liste fermée de fichiers compilés,
de documentation publique et d'un seul exemple fictif. Tout fichier supplémentaire
dans le dossier compilé bloque sa fabrication. Une livraison existante n'est jamais
écrasée. Une empreinte SHA-256 accompagne le ZIP.

Les futures migrations de données devront rester non destructives et être testées
sur une copie fictive d'une base existante avant livraison. La version 1.0.31 ne
modifie pas le schéma ni le contenu des événements existants.
