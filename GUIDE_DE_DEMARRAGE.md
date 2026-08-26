# 📖 GUIDE DE DÉPLOIEMENT ET D'INITIALISATION - FRONT OFFICE (`MonarcAppFO`)

> **Application Hôte :** `MonarcAppFO` (Port HTTP `5001`)  
> **Racine de l'application :** `./MonarcAppFO`  
> **Structure des dépôts :** Dépôts frères à la racine de `v_current` (`../zm-core`, `../zm-client`, `../ng-anr`, `../ng-client`)  

---

## 📌 Table des Matières
- [🏗️ 1. Architecture & Dépendances du FrontOffice](#️-1-architecture--dépendances-du-frontoffice)
- [🛠️ 2. Configuration & Points d'Intégration Clés](#️-2-configuration--points-dintégration-clés)
  - [A. Configuration Environnement (`.env`)](#a-configuration-environnement-env)
  - [B. Montage des Dépôts Locaux (`docker-compose.dev.yml`)](#b-montage-des-dépôts-locaux-docker-composedevyml)
  - [C. Liens Symboliques Dynamiques (`docker-entrypoint.sh`)](#c-liens-symboliques-dynamiques-docker-entrypointsh)
- [🚀 3. Procédure Automatisée de Démarrage (PowerShell)](#-3-procédure-automatisée-de-démarrage-powershell)
- [🌐 4. Accès & Identifiants Administrateur](#-4-accès--identifiants-administrateur)
- [⚠️ 5. Guide de Dépannage & Correctifs Historiques](#-5-guide-de-dépannage--correctifs-historiques)
  - [Bug 1 : Erreur 500 / Identifiants invalides (`actions_history` manquant)](#bug-1--erreur-500--identifiants-invalides-actions_history-manquant)
  - [Bug 2 : Erreur SQL `Column not found: are_scales_updatable`](#bug-2--erreur-sql-column-not-found-are_scales_updatable)
  - [Bug 3 : Fins de ligne Windows (`\r / bad interpreter`)](#bug-3--fins-de-ligne-windows-r--bad-interpreter)
  - [Bug 4 : Erreur d'unicité `1062 Duplicate entry` au reset](#bug-4--erreur-dunicité-1062-duplicate-entry-au-reset)

---

## 🏗️ 1. Architecture & Dépendances du FrontOffice

L'application `MonarcAppFO` s'appuie sur 4 modules situés dans le répertoire parent :
- **`../zm-core`** ➔ Core Backend PHP (`module/Monarc/Core`)
- **`../zm-client`** ➔ FrontOffice Backend PHP (`module/Monarc/FrontOffice`)
- **`../ng-anr`** ➔ Frontend Angular ANR (`node_modules/ng_anr`)
- **`../ng-client`** ➔ Frontend Angular Client FO (`node_modules/ng_client`)

Bases de données associées :
- **`monarc_cli`** : Données de l'instance client (analyses de risques, utilisateurs, logs d'actions).
- **`monarc_common`** : Catalogue commun partagé (modèles ISO/ROLF, menaces, vulnérabilités, mesures).

---

## 🛠️ 2. Configuration & Points d'Intégration Clés

### A. Configuration Environnement (`.env`)
Dans `MonarcAppFO/.env` :
```ini
DBHOST=fodb
DBPORT_HOST=3307
DBNAME_COMMON=monarc_common
DBNAME_CLI=monarc_cli
DBUSER_MONARC=sqlmonarcuser
DBPASSWORD_MONARC=sqlmonarcuser
DBPASSWORD_ADMIN=root
USE_BO_COMMON=0
```
> 💡 `USE_BO_COMMON=0` permet l'import initial automatique de `monarc_structure.sql` et `monarc_data.sql` sur une base neuve.

### B. Montage des Dépôts Locaux (`docker-compose.dev.yml`)
```yaml
    volumes:
      - ./:/var/www/html/monarc
      - type: bind
        source: ../zm-core
        target: /var/www/html/zm-core
      - type: bind
        source: ../zm-client
        target: /var/www/html/zm-client
      - type: bind
        source: ../ng-anr
        target: /var/www/html/ng-anr
      - type: bind
        source: ../ng-client
        target: /var/www/html/ng-client
      - vendor_data:/var/www/html/monarc/vendor
      - node_modules_data:/var/www/html/monarc/node_modules
```

### C. Liens Symboliques Dynamiques (`docker-entrypoint.sh`)
```bash
    mkdir -p module/Monarc
    cd module/Monarc
    ln -sfn /var/www/html/zm-core Core
    ln -sfn /var/www/html/zm-client FrontOffice
    cd /var/www/html/monarc
```

---

## 🚀 3. Procédure Automatisée de Démarrage (PowerShell)

Exécutez ce script pour initialiser et lancer le FrontOffice de manière 100% propre :

```powershell
# 1. Se positionner dans le dossier MonarcAppFO
cd d:\QSIN\Monarc\Draft\v_current\MonarcAppFO

# 2. Copier le fichier d'environnement .env s'il n'existe pas
if (-not (Test-Path ".env")) { Copy-Item ".env.dev" ".env" }

# 3. Assurer la conversion des scripts .sh au format UNIX (LF)
Get-ChildItem -Path "." -Recurse -Filter "*.sh" | Where-Object { $_.FullName -notmatch '\\(node_modules|vendor|\.git)\\' } | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $content, (New-Object System.Text.UTF8Encoding($false)))
}

# 4. Pré-créer les répertoires de données requis
New-Item -ItemType Directory -Path "data\cache", "data\logs", "data\import\files", "data\LazyServices\Proxy", "data\DoctrineORMModule\Proxy" -Force | Out-Null

# 5. Réinitialiser et purger les anciens volumes (si réinitialisation souhaitée)
docker compose -f docker-compose.dev.yml down -v
Remove-Item -Recurse -Force .\docker\db_data\* -ErrorAction SilentlyContinue
Remove-Item -Force ".\.docker-initialized" -ErrorAction SilentlyContinue

# 6. Construire et démarrer le conteneur
docker compose -f docker-compose.dev.yml up -d --build
```

---

## 🌐 4. Accès & Identifiants Administrateur

- **URL FrontOffice :** [http://localhost:5001](http://localhost:5001)
- **Identifiant / Email :** `admin@admin.localhost`
- **Mot de passe :** `admin`

---

## ⚠️ 5. Guide de Dépannage & Correctifs Historiques

### Bug 1 : Erreur 500 / Identifiants invalides (`actions_history` manquant)
* **Cause :** Sous MariaDB 10.11, la migration Phinx `20230901112005` échouait sur l'instruction `RENAME TABLE anr_metadatas_on_instances` avec `errno 194 (Tablespace is missing)`, bloquant l'exécution des migrations suivantes (dont la création de `actions_history`).
* **Correction :** Dans `zm-client/migrations/db/20230901112005_fix_positions_cleanup_db.php`, encapsulation avec `SET FOREIGN_KEY_CHECKS=0;` et remplacement de `rename` par `CREATE TABLE ... LIKE`, `INSERT IGNORE` et `DROP TABLE`.

### Bug 2 : Erreur SQL `Column not found: are_scales_updatable`
* **Cause :** L'entité Doctrine `Model` sélectionne `are_scales_updatable`, qui est renommée depuis `is_scales_updatable` par la migration `20230901112005` dans `zm-core` sur `monarc_common`.
* **Correction :** Exécution complète des migrations de `zm-core` sur `monarc_common` après import de la structure et des données.

### Bug 3 : Fins de ligne Windows (`\r / bad interpreter`)
* **Solution :** Toujours exécuter la conversion UNIX (`LF`) sur les scripts `.sh` avant de builder.

### Bug 4 : Erreur d'unicité `1062 Duplicate entry` au reset
* **Solution :** Supprimer le fichier marqueur `.docker-initialized` et purger `docker/db_data/` avant de relancer.
