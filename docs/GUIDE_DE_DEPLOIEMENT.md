# 🚀 GUIDE DE DÉPLOIEMENT — FRONT OFFICE (`MonarcAppFO`)

> **Branche de déploiement :** `master-asin`
> **Organisation GitHub :** [ASINBenin](https://github.com/ASINBenin)
> **Image Docker :** `ghcr.io/asinbenin/monarcappfo:master-asin`

> ✅ **État de validation** : l'application (image, base de données, migrations,
> page de login) ET Traefik (reverse proxy) ont été testés avec succès en local
> — routage par nom d'hôte via les labels Docker confirmé (redirection
> HTTP→HTTPS 302 fonctionnelle). Seul le HTTPS/Let's Encrypt lui-même n'a pas
> pu être testé localement (il faut un vrai domaine public joignable) — teste-le
> en premier sur la VM (§3, étape 6).
>
> **Détail du bug Traefik rencontré et corrigé** : sur Docker Engine ≥ 29 (API
> 1.55, très récent), le client Docker embarqué dans Traefik v3.1/v3.5 échoue
> la négociation de version d'API (`API returned a 400 (Bad Request)`), alors
> que le socket Docker lui-même fonctionne parfaitement (confirmé via
> `curl --unix-socket`). **Traefik v2.11 négocie correctement** avec cet Engine
> — c'est la version épinglée dans `docker-compose.prod.yml`. Peu probable sur
> une VM Linux standard (Engine plus classique), mais si `docker logs
> monarc-traefik` remontre ce 400, c'est confirmé comme le même bug (voir §6).

---

## 📌 Table des matières
- [1. Principe général](#1-principe-général)
- [2. Ce que la CI construit automatiquement](#2-ce-que-la-ci-construit-automatiquement)
- [3. Déploiement sur une VM (test ou prod)](#3-déploiement-sur-une-vm-test-ou-prod)
- [4. Architecture (reverse proxy, base de données, scaling)](#4-architecture-reverse-proxy-base-de-données-scaling)
- [5. Bugs corrigés pendant la mise en place — pour comprendre le pourquoi](#5-bugs-corrigés-pendant-la-mise-en-place--pour-comprendre-le-pourquoi)
- [6. Dépannage](#6-dépannage)

---

## 1. Principe général

Ce projet a deux façons de tourner :
- **`docker-compose.dev.yml`** — développement local, bind-mounts des dépôts frères (`../zm-core`, etc.), reconstruit l'image sur ta machine à chaque fois. Voir [`docs/GUIDE_DE_DEMARRAGE.md`](GUIDE_DE_DEMARRAGE.md).
- **`docker-compose.prod.yml`** — déploiement réel, utilise une image **déjà construite et publiée** par la CI GitHub Actions. C'est celui-ci qui sert à déployer sur une VM. C'est l'objet de ce guide.

**Le principe clé** : on ne construit jamais l'image sur la machine de déploiement. On pousse du code sur `master-asin`, GitHub Actions construit l'image et la publie sur GHCR, et la VM se contente de la télécharger (`docker pull`) et de la lancer.

---

## 2. Ce que la CI construit automatiquement

À chaque `git push` sur `master-asin`, `.github/workflows/releases.yml` :

1. Installe les dépendances PHP (`composer install`) — **depuis notre fork `ASINBenin`**, pas le dépôt officiel `monarc-project` (voir §5 pour pourquoi c'est important).
2. Installe les modules frontend (`ng-anr`, `ng-client`, `ng-sign`) — également depuis `ASINBenin`.
3. Compile les traductions et lie les ressources des modules (`scripts/link_modules_resources.sh`).
4. Construit l'image Docker (`Dockerfile.release`) et la publie sur `ghcr.io/asinbenin/monarcappfo:master-asin`.
5. Construit l'image du service de statistiques (`Dockerfile.stats`) — **seulement si son propre code a changé**, pour ne pas perdre de temps à chaque push.

Le paquet GHCR doit être **public** (`github.com/ASINBenin/MonarcAppFO/pkgs/container/monarcappfo` → Package settings → Danger Zone → Change visibility) pour être téléchargeable sans authentification depuis la VM.

---

## 3. Déploiement sur une VM (test ou prod)

### Étape 1 — Cloner et se positionner sur la bonne branche
```bash
git clone https://github.com/ASINBenin/MonarcAppFO.git
cd MonarcAppFO
git checkout master-asin
```

### Étape 2 — Configurer les secrets
```bash
cp .env.prod.example .env
```
Édite `.env` et remplace chaque `CHANGEME` :
- `DOMAIN_FO` : le vrai nom de domaine public de cette instance (ex: `monarc.tonorganisation.lu`). **Ne pas mettre `localhost` en vraie prod** — Let's Encrypt ne pourra jamais délivrer de certificat pour un nom qui n'est pas publiquement joignable.
- `ACME_EMAIL` : email pour les notifications Let's Encrypt.
- `DBHOST`, `DBPASSWORD_MONARC`, `DBPASSWORD_ADMIN` : mots de passe de ton choix (utilisés à l'étape suivante).
- `MONARC_SSO_ENCRYPTION_KEY` : générer avec `openssl rand -base64 32`.
- `TRUSTEDX_URL`, `TRUSTEDX_CLIENT_ID`, `TRUSTEDX_CLIENT_SECRET` : les vraies valeurs de prod fournies par TrustedX (pas les valeurs de test du guide de démarrage).
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` : pour l'envoi de mail (ex: Gmail = `smtp.gmail.com`/`587` + un mot de passe d'application, pas le mot de passe du compte). Laisse vide pour désactiver l'envoi de mail.

### Étape 3 — Préparer la base de données (native, pas conteneurisée)
```bash
set -a; source .env; set +a
bash scripts/ensure_mariadb.sh
```
`set -a; source .env` charge les valeurs de `.env` (dont `DBPASSWORD_ADMIN`/`DBPASSWORD_MONARC`) comme variables d'environnement, pour que le script utilise **exactement** ce que tu as mis à l'étape 2 — pas de mot de passe à retaper une seconde fois, donc pas de risque de désynchronisation entre `.env` et la vraie base. Le script installe MariaDB si absent, crée les bases `monarc_common`/`monarc_cli` et l'utilisateur applicatif. Voir §4 pour pourquoi la base n'est volontairement pas dans un conteneur.

> **En local sur Windows** (test avant la VM) : ce script ne fonctionne pas tel quel (il utilise `apt`/`systemctl`/`sudo`, absents de Windows/Git Bash). Utilise `scripts/ensure_mariadb_windows.ps1` à la place (nécessite WAMP démarré), depuis **PowerShell** :
> ```powershell
> Get-Content .env | ForEach-Object { if ($_ -match '^([^#][^=]*)=(.*)$') { Set-Item "env:$($matches[1])" $matches[2] } }
> .\scripts\ensure_mariadb_windows.ps1
> ```

### Étape 4 — S'authentifier auprès de GHCR (paquet privé)
Le paquet `ghcr.io/asinbenin/monarcappfo` est **privé** — un `docker pull` anonyme échoue avec `denied`. Connecte-toi une seule fois sur la VM avec un [Personal Access Token GitHub](https://github.com/settings/tokens) ayant le scope `read:packages` :
```bash
echo "TON_TOKEN" | docker login ghcr.io -u TON_USERNAME_GITHUB --password-stdin
```
Les identifiants restent enregistrés (`~/.docker/config.json`) — inutile de refaire cette étape aux déploiements suivants sur la même VM. Ne mets jamais ce token dans `.env` ni dans un fichier versionné.

### Étape 5 — Lancer
```bash
docker compose -f docker-compose.prod.yml up -d
```

### Étape 6 — Vérifier
```bash
docker compose -f docker-compose.prod.yml logs -f monarcfoapp
```
Attendre que les migrations passent (tu dois voir `CreateIdentityProviderTables` et `CreateSignatureTables` parmi elles), puis `Initialization complete!`.

```bash
curl -I https://TON_DOMAINE/
```
→ doit répondre `200 OK` avec un certificat valide (Let's Encrypt, automatique via Traefik).

Ouvre ensuite le domaine dans un navigateur : page de login, bouton SSO, et onglet "Electronic signatures" dans une ANR.

---

## 4. Architecture (reverse proxy, base de données, scaling)

### Reverse proxy — Traefik
`docker-compose.prod.yml` inclut un conteneur **Traefik**, qui joue le rôle du "RPX" du schéma d'architecture officiel MONARC : point d'entrée HTTPS unique, certificat Let's Encrypt automatique, redirection HTTP→HTTPS.

**Pour ajouter un 2ᵉ client sur la même VM** (comme "Client 1 + Client 2" dans le schéma officiel) : dupliquer le bloc `monarcfoapp` du compose (voir le commentaire dans le fichier), avec son propre `DOMAIN_FO` et sa propre base.

**Pour ajouter un FO sur une autre VM** (comme "Client 3" sur son propre serveur) : voir `traefik/dynamic/README.md` — Traefik surveille ce dossier en direct, un simple fichier de route statique suffit, sans redémarrage.

### Base de données — native, jamais conteneurisée
Volontairement : une base dans un conteneur est jetable par nature (un `docker compose down -v` malencontreux efface tout), plus difficile à sauvegarder proprement, et ce n'est pas le modèle du schéma d'architecture officiel MONARC (qui installe MariaDB nativement sur le serveur Back Office). `scripts/ensure_mariadb.sh` automatise cette installation native.

La variable `USE_BO_COMMON` dans `.env` contrôle si ce FO gère sa propre base `common` (`0`, installation autonome) ou lit une base `common` centrale déjà gérée ailleurs (`1`, futur BO partagé).

### Le Back Office (BO)
**Pas encore intégré à ce pipeline.** `MonarcAppBO` existe (dépôt séparé) mais sa CI ne produit qu'une archive `.tar.gz`, pas d'image Docker — ce sera un chantier à part, sur le même principe que celui documenté ici pour le FO.

---

## 5. Bugs corrigés pendant la mise en place — pour comprendre le pourquoi

Ces correctifs sont dans l'historique Git de `master-asin` ; ils expliquent pourquoi certains fichiers sont écrits comme ils le sont.

1. **Composer résolvait `zm-core`/`zm-client` depuis le dépôt officiel `monarc-project`, pas notre fork** — la contrainte `^2.14.1` était aussi satisfaite par les vraies releases publiées sur Packagist. Tout le code SSO/signature était silencieusement absent de chaque image. Corrigé en fixant `monarc/core`/`monarc/frontoffice`/`monarc/sign` sur `dev-master-asin` explicitement.
2. **Résolution de dépendances non reproductible** — sans contrainte de plateforme figée, `composer update` sur une machine avec un PHP plus récent que celui de la CI (8.1) faisait dériver silencieusement des paquets vers des versions incompatibles. Corrigé en figeant `config.platform.php: 8.1.34` dans `composer.json`, pour toujours résoudre comme la CI, peu importe la machine.
3. **`scripts/link_modules_resources.sh` avait plusieurs régressions** par rapport à sa version d'origine (`master`), introduites par une réécriture antérieure à ce guide, jamais détectées faute d'avoir testé dans un vrai navigateur :
   - fichiers JS d'`ng-anr` placés à plat dans `public/js/` au lieu de `public/js/anr/` (page blanche, erreurs `$injector:modulerr`),
   - vues d'`ng-anr` cherchées dans un sous-dossier `views/anr` inexistant côté source,
   - liaison de `public/img/` (logos, fonds d'écran) totalement absente.
4. **Police d'icônes (`MaterialIcons-Regular.woff2`) jamais chargée** — `material-icons.css` référence ses polices en chemin relatif `css/<police>`, ce qui pointe vers `public/css/css/` une fois servi. Ce sous-dossier n'a jamais été créé, dans aucune version du script (y compris `master`) — un défaut préexistant du projet, pas une régression de notre fork, corrigé au passage.

---

## 6. Dépannage

**Traefik boucle sur `Failed to retrieve information of the docker client` / `API returned a 400 (Bad Request)`** →
C'est le bug de négociation de version d'API Docker déjà rencontré et corrigé (voir l'encart en haut de ce guide) : `docker-compose.prod.yml` épingle désormais `traefik:v2.11` (au lieu de `v3.x`), ce qui résout ce problème. Si tu le revois malgré tout (ex: après avoir changé l'image Traefik) :

1. **Vérifier que le socket lui-même fonctionne** (élimine un problème de permissions/montage) :
   ```bash
   docker run --rm --user root -v /var/run/docker.sock:/var/run/docker.sock \
     curlimages/curl -s --unix-socket /var/run/docker.sock http://localhost/version
   ```
   Si ça répond avec un JSON contenant `"ApiVersion"` → le socket est sain. Si ça échoue déjà ici → problème de droits (`ls -la /var/run/docker.sock`, vérifier que l'utilisateur est dans le groupe `docker`), pas le même bug.

2. **Regarder le message d'erreur précis** avec `docker logs monarc-traefik` :
   - `API returned a 400 (Bad Request)` → repasser (ou rester) sur `traefik:v2.11` dans `docker-compose.prod.yml`. Testé et validé avec Docker Engine 29.6.1 (API 1.55) : la connexion au provider Docker et le routage par labels (redirection HTTP→HTTPS) fonctionnent correctement avec cette version.
   - Autre chose (permission denied, connection refused...) → problème de montage/droits, voir point 1.

3. **Plan B temporaire** si besoin de débloquer vite — contourner Traefik pour valider que l'appli elle-même fonctionne, en l'exposant directement (HTTP simple, sans HTTPS) :
   ```bash
   docker compose -f docker-compose.prod.yml up -d monarcfoapp
   # ajouter un port directement sur le service le temps de diagnostiquer :
   # via un fichier override docker-compose.override.yml avec "ports: - '8090:80'"
   curl -I http://localhost:8090/
   ```

**`unauthorized` au `docker pull`** → le paquet GHCR n'est pas public. Voir §2.

**Migrations qui échouent avec `Foreign key constraint is incorrectly formed`** → le moteur de stockage par défaut de MariaDB n'est pas InnoDB (MyISAM ne supporte pas les clés étrangères). Vérifier `default_storage_engine` dans la config MariaDB.

**`Access denied for user '...'@'localhost'` alors que le mot de passe est correct** → comptes MySQL/MariaDB anonymes par défaut (`''@'localhost'`) qui interceptent l'authentification avant l'utilisateur applicatif. Les supprimer (`DROP USER ''@'localhost';`).

**Le conteneur redémarre sans rejouer les migrations** → le fichier marqueur `/var/www/html/monarc/.docker-initialized` (créé après une init réussie) empêche toute réinitialisation sur un simple `docker restart`. Il faut recréer le conteneur (`docker compose down && up -d`), pas juste le redémarrer, pour repartir de zéro.

**Page blanche / erreurs `404` sur des fichiers `js/anr/*.js`** → régression déjà corrigée dans `master-asin` (voir §5.3). Si ça revient, comparer `scripts/link_modules_resources.sh` avec `git show master:scripts/link_modules_resources.sh` pour repérer l'écart.
