# Migration Tableo → Sallunio

## État et périmètre
Publication 1.2.2+48 autorisée par l’utilisateur le 16 octobre 2026, après vérification des tags distants (dernier : v1.2.1). L’ancien paquet Sallunio-1.2.1 est une prévalidation non publiable, à ne pas envoyer. La livraison publique 1.2.2 utilise un nouveau numéro commun GitHub/Store.
L’audit source préalable figure dans docs/migration-sallunio-references.json. Les anciens changelogs décrivent volontairement Tableo.

## Réalisé localement
Libellés d’application, titre Windows, notifications de version, erreurs, métadonnées PDF et noms par défaut des nouveaux exports renommés. Le runner produit sallunio.exe. Métadonnées de fichier : Sallunio / LC Software Workshop. L’image originale RGBA est conservée dans assets/branding/sallunio.png ; seul son redimensionnement/conversion est effectué pour l’ICO et les ressources Store. Les anciens Modules restent des archives.
Scripts ZIP/MSIX et workflow préparés pour Sallunio ; le ZIP historique Tableo-Windows.zip est conservé comme alias de téléchargement des futures releases.

## Références volontairement stables
- Données : %APPDATA%\Tableo\tableo.sqlite ; aucune migration de dossier, de schéma ou suppression.
- Sauvegardes : format tableo-backup version 1 et suffixe .tableo.json ; nom suggéré projet-sallunio.tableo.json. Les anciens documents continuent à être acceptés.
- Identifiants Dart : package:tableo, classe interne Tableo, paramètre TABLEO_GITHUB_REPOSITORY et infrastructure de tests historique.
- Store : Identity Name Tableo.Tableo ; Publisher CN=CE91D67B-D21B-468A-A345-78D2FF2FC0FF ; Application Id Tableo ; PFN Tableo.Tableo_9ra78wet4ps1a ; Store ID 9PNHKMRHHJML. Le chemin Executable change, pas l’identité d’application.
- Dépôt actif LC-Soft-Workshop/Sallunio après renommages autorisés et effectués le 16 octobre 2026. Ancienne adresse : freakbn777/Tableo. Les anciens clients doivent continuer à recevoir les futures releases via les redirections GitHub. Ne jamais recréer un dépôt Tableo après renommage : cela pourrait casser les redirections.
- Dossier local dist/Tableo-test conservé pour respecter le dossier d’essais unique. Son exécutable devient sallunio.exe ; l’ancien binaire contrôlé tableo.exe est retiré seulement après copie réussie.

## Éditeur : informations distinctes
1. Windows CompanyName et copyright : LC Software Workshop (métadonnées locales).
2. Nom public du compte Store : LC Software Workshop, enregistré le 16 octobre 2026 ; la page Verification Summary affiche Authorized. Le contact légal reste inchangé.
3. PublisherDisplayName du manifeste : LC Software Workshop, conforme à la valeur officielle vérifiée du compte.
4. Publisher technique CN et certificat : conserver les valeurs officielles ci-dessus. Microsoft signe la distribution Store ; aucun certificat local de test n’est installé.
Les pages Microsoft sur les comptes de programmes différents ne sont pas uniformes sur la possibilité de modifier le nom public. Le formulaire Legal info → Developer → Contact info → Update a finalement été accessible : compte individuel actif, champ Publisher name modifiable. La modification autorisée est enregistrée et Verification Summary indique Authorized. Pour le compte individuel décrit par l’utilisateur, essayer uniquement la procédure de consultation ci-dessous et demander confirmation au support si le champ est absent/verrouillé. Ne pas créer un nouveau compte pour contourner la restriction : la continuité n’est pas démontrée.

## Actions Partner Center — validation requise
1. Ouvrir l’application existante 9PNHKMRHHJML, Product management → Manage app names.
2. Vérifier la disponibilité de Sallunio, puis réserver ce nom pour cette même application après accord. Conserver la réservation Tableo pour le moment.
3. Settings → Account settings → Legal info → Developer → Contact info : examiner si Update permet le changement de Publisher display name. Le nom du compte Microsoft, le contact légal et le nom d’éditeur public ne sont pas interchangeables.
4. Si le changement est bloqué : Contact Support depuis Partner Center, demander « changement du nom public éditeur Tableo vers LC Software Workshop pour compte individuel, sans modifier Publisher ID/CN ni perdre les mises à jour du produit 9PNHKMRHHJML ». Ne pas transmettre de nouveaux justificatifs ni accepter de changement de compte sans validation de l’éditeur.
5. Créer une mise à jour du produit existant, choisir Sallunio dans Product name de la fiche française, actualiser descriptions, Developed by, confidentialité et visuels. Les textes préparés se trouvent dans output/store/sallunio-* ; relire l’identité de l’éditeur avant toute mise en ligne.
6. Le fichier sallunio-identity-prepared.json conserve l’identité technique et ne change que DisplayName. Après confirmation du compte seulement, recopier la valeur officielle PublisherDisplayName. Comparer Name/Publisher/Application Id/PFN à la version installée.
7. Compiler au numéro supérieur autorisé, créer le MSIX avec --identity output/store/sallunio-identity-prepared.json --assets output/store/sallunio-assets. Vérifier la validation Microsoft ; demander un test de mise à jour signé sur un compte Windows de test/VM avec événements fictifs. makeappx et le test natif ne prouvent pas la mise à jour installée Store.
8. Soumettre puis publier seulement après accord explicite. Éviter une publication automatique si elle empêche l’alignement voulu avec GitHub.

## GitHub — renommages effectués, publication de version encore distincte
1. Avec l’accord explicite de l’utilisateur, le compte freakbn777 a été renommé LC-Soft-Workshop et son nom affiché initial est LC Soft Workshop. Le dépôt existant Tableo a été renommé Sallunio. Aucun dépôt n’a été recréé ; historique, tags, issues, wiki et releases sont conservés. La description publique du dépôt est harmonisée.
2. Les anciennes adresses du dépôt, de l’API de mises à jour, du téléchargement ZIP et du wiki répondent HTTP 200 après redirection ; résultat dans output/migration-sallunio/github-redirects.json. L’ancien profil personnel n’est pas redirigé. Ne pas réutiliser les anciens noms. Noter que GitHub Pages et les appels à une action hébergée dans un dépôt renommé ont des exceptions.
3. Origin et les références actives locales sont actualisés vers https://github.com/LC-Soft-Workshop/Sallunio.git (documentation, métadonnées Store préparées et valeur par défaut de lib/github_updates.dart). Le paramètre historique TABLEO_GITHUB_REPOSITORY reste accepté ; le workflow utilise github.repository et suivra le nouveau nom.
4. Rechercher les références externes : liens Facebook, site, wiki, raccourcis, bookmarks. Maintenir l’alias Tableo-Windows.zip en plus de Sallunio-Windows.zip pour les liens existants.
5. Attribuer le prochain numéro public commun, mettre à jour pubspec/app_version/changelog, vérifier tests et compilation, commit explicite des seuls fichiers autorisés. Ne pas inclure AGENTS.md, identités de compte locales, captures ou bases réelles.
6. Après certification Store, publier GitHub par tag autorisé ; vérifier le workflow, les fichiers et sommes SHA256. Publier la fiche Store coordonnée selon la stratégie choisie.

## Retour arrière
Avant publication : restaurer les fichiers de marque depuis le commit 178bf2e ou la copie locale conservée, recompiler, réactualiser le dossier de test ; les événements restent au même endroit. Ne pas supprimer les fichiers inconnus ni les bases.
Après une publication Store : ne pas essayer d’envoyer un numéro inférieur. Préparer un nouveau paquet de version supérieure rétablissant les anciens visuels, avec la même identité technique, puis certification/publication autorisées. Une ancienne version doit être testée sur une copie fictive avant tout retour arrière de données.
Après renommage GitHub : un retour du nom nécessite validation et vérification des redirections ; préserver tout l’historique. Aucune action de retour arrière externe n’est automatisée ici.

## Documentation officielle consultée le 16 octobre 2026
- Noms Store (MSIX) : https://learn.microsoft.com/en-us/windows/apps/publish/partner-center/pwa/manage-app-name-reservations
- Compte Developer, Contact info/Update : https://learn.microsoft.com/en-gb/partner-center/account-settings/manage-account
- Restrictions indiquées pour certains comptes : https://learn.microsoft.com/en-us/partner-center/partner-center-account-setup
- Renommage GitHub et redirections : https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository

## Validation
Les résultats précis sont consignés dans output/migration-sallunio/validation.md et fichiers de logs tmp/sallunio-*. Aucun résultat de certification ou de mise à jour MSIX installée ne doit être déduit de la simple compilation.
