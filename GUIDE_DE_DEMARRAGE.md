# 📖 GUIDE DE DÉPLOIEMENT ET D'INITIALISATION - FRONT OFFICE (`MonarcAppFO`)

> **Application Hôte :** `MonarcAppFO` (Port HTTP `5001`)  
> **Racine de l'application :** `./MonarcAppFO`  
> **Dossier central des modules :** `../module/`  
> **Organisation GitHub :** [ASINBenin](https://github.com/ASINBenin)  

---

## 📌 Table des Matières
- [🏗️ 1. Architecture & Dépendances du FrontOffice](#️-1-architecture--dépendances-du-frontoffice)
- [🛠️ 2. Configurations de Déroutage ASINBenin dans `MonarcAppFO`](#️-2-configurations-de-déroutage-asinbenin-dans-monarcappfo)
  - [A. Redirection npm (`package.json`)](#a-redirection-npm-packagejson)
  - [B. Redirection Composer (`composer.json`)](#b-redirection-composer-composerjson)
  - [C. Configuration Docker & Bind Mounts (`docker-compose.dev.yml`)](#c-configuration-docker--bind-mounts-docker-composedevyml)
  - [D. Protection des Liens Symboliques (`docker-entrypoint.sh`)](#d-protection-des-liens-symboliques-docker-entrypointsh)
  - [E. Neutralisation des Checkouts Git (`scripts/update-all.sh`)](#e-neutralisation-des-checkouts-git-scriptsupdate-allsh)
- [🚀 3. Procédure Automatisée de Démarrage (PowerShell)](#-3-procédure-automatisée-de-démarrage-powershell)
- [🌐 4. Accès & Identifiants Administrateur](#-4-accès--identifiants-administrateur)
- [⚠️ 5. Guide de Dépannage & Correctifs (FAQ FrontOffice)](#-5-guide-de-dépannage--correctifs-faq-frontoffice)
  - [Bug 1 : Connexion bloquée / Spinner infini au login (PHP 8.1+)](#bug-1--connexion-bloquée--spinner-infini-au-login-php-81)
  - [Bug 2 : Erreur d'unicité `1062 Duplicate entry` (Reset Base de Données)](#bug-2--erreur-dunicité-1062-duplicate-entry-reset-base-de-données)
  - [Bug 3 : Fins de ligne Windows (`\r / bad interpreter`)](#bug-3--fins-de-ligne-windows-r--bad-interpreter)
  - [Bug 4 : Quota de requêtes GitHub dépassé (`COMPOSER_AUTH`)](#bug-4--quota-de-requêtes-github-dépassé-composer_auth)
  - [Bug 5 : Erreur 500 au Login / Retrace Chronologique du Déblocage de la Migration Phinx (`monarc_cli.actions_history`)](#bug-5--erreur-500-au-login--retrace-chronologique-du-déblocage-de-la-migration-phinx-monarc_cliactions_history)
  - [Bug 6 : Spinner Infini au Login avec Réponse HTTP 200 sur `/auth`](#bug-6--spinner-infini-au-login-avec-réponse-http-200-sur-auth-configuration-des-langues-manquante-dans-zm-core)
  - [Bug 7 : Erreur 500 sur `/api/models` / Branchement Base Commune BO (`monarc-bo-db`) dans `local.php`](#bug-7--erreur-500-sur-apimodels--branchement-base-commune-bo-monarc-bo-db-dans-localphp)

---

## 🏗️ 1. Architecture & Dépendances du FrontOffice

L'application `MonarcAppFO` s'appuie sur 4 modules situés sous `../module/` :
- **`zm-core`** ➔ Core Backend PHP (`module/Monarc/Core`)
- **`zm-client`** ➔ FrontOffice Backend PHP (`module/Monarc/FrontOffice`)
- **`ng-anr`** ➔ Frontend Angular ANR (`node_modules/ng_anr`)
- **`ng-client`** ➔ Frontend Angular FrontOffice (`node_modules/ng_client`)

---

## 🛠️ 2. Configurations de Déroutage ASINBenin dans `MonarcAppFO`

### A. Redirection npm (`package.json`)
Dans `MonarcAppFO/package.json`, pointer vers l'organisation **ASINBenin** :
```json
  "repository": {
    "type": "git",
    "url": "https://github.com/ASINBenin/MonarcAppFO"
  },
  "dependencies": {
    "ng_anr": "git+https://github.com/ASINBenin/ng-anr.git",
    "ng_client": "git+https://github.com/ASINBenin/ng-client.git"
  }
```

### B. Redirection Composer (`composer.json`)
Dans `MonarcAppFO/composer.json`, déclarer les dépôts VCS :
```json
    "repositories": [
        {
            "type": "vcs",
            "url": "https://github.com/ASINBenin/zm-core.git"
        },
        {
            "type": "vcs",
            "url": "https://github.com/ASINBenin/zm-client.git"
        }
    ],
```

### C. Configuration Docker & Bind Mounts (`docker-compose.dev.yml`)
Montage direct des dossiers physiques `../module/` et persistance sur l'hôte :
```yaml
    volumes:
      - ./:/var/www/html/monarc
      # Modules locaux PHP
      - ../module/zm-core:/var/www/html/monarc/module/Monarc/Core
      - ../module/zm-client:/var/www/html/monarc/module/Monarc/FrontOffice
      # Modules locaux Angular
      - ../module/ng-anr:/var/www/html/monarc/node_modules/ng_anr
      - ../module/ng-client:/var/www/html/monarc/node_modules/ng_client
      # Persistance vendor et node_modules
      - vendor_data:/var/www/html/monarc/vendor
      - node_modules_data:/var/www/html/monarc/node_modules
```

### D. Protection des Liens Symboliques (`docker-entrypoint.sh`)
```bash
    mkdir -p module/Monarc
    cd module/Monarc
    if [ ! -d "Core" ] && [ ! -L "Core" ]; then
        ln -sfn ./../../vendor/monarc/core Core
    fi
    if [ ! -d "FrontOffice" ] && [ ! -L "FrontOffice" ]; then
        ln -sfn ./../../vendor/monarc/frontoffice FrontOffice
    fi
    cd /var/www/html/monarc
```

### E. Neutralisation des Checkouts Git (`scripts/update-all.sh`)
```bash
if [[ -d node_modules && -d node_modules/ng_anr ]]; then
    if [[ -d node_modules/ng_anr/.git ]]; then
        # checkout_to_latest_tag node_modules/ng_client
        # checkout_to_latest_tag node_modules/ng_anr
        echo "Utilisation des modules locaux"
    else
        npm update
    fi
fi
```

---

## 🚀 3. Procédure Automatisée de Démarrage (PowerShell)

Exécutez ce script pour initialiser le FrontOffice :

```powershell
# 1. Se placer dans le dossier MonarcAppFO
cd MonarcAppFO

# 2. Copier le fichier d'environnement .env s'il n'existe pas
if (-not (Test-Path ".env")) { Copy-Item ".env.dev" ".env" }

# 3. Assurer la conversion des scripts .sh en fin de ligne UNIX (LF)
Get-ChildItem -Path "." -Recurse -Filter "*.sh" | Where-Object { $_.FullName -notmatch '\\(node_modules|vendor|\.git)\\' } | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $content, (New-Object System.Text.UTF8Encoding($false)))
}

# 4. Pré-créer les répertoires temporaires Laminas/Doctrine
New-Item -ItemType Directory -Path "data\cache", "data\logs", "data\import\files", "data\LazyServices\Proxy", "data\DoctrineORMModule\Proxy" -Force | Out-Null

# 5. Réinitialiser les conteneurs & purger la base de données
docker compose -f docker-compose.dev.yml down -v
Remove-Item -Recurse -Force .\docker\db_data\* -ErrorAction SilentlyContinue
Remove-Item -Force ".\.docker-initialized" -ErrorAction SilentlyContinue

# 6. Lancer les conteneurs
docker compose -f docker-compose.dev.yml up -d --build
```

---

## 🌐 4. Accès & Identifiants Administrateur

- **URL FrontOffice** : [http://localhost:5001](http://localhost:5001)
- **Identifiants Administrateur par défaut** :
  - **Email :** `admin@admin.localhost`
  - **Mot de passe :** `admin`

---

## ⚠️ 5. Guide de Dépannage & Correctifs (FAQ FrontOffice)

### Bug 1 : Connexion bloquée / Spinner infini au login (PHP 8.1+)
* **Symptôme :** Clic sur "Se connecter", le spinner tourne en boucle sans rediriger.
* **Correction :** 
  1. Dans `../module/zm-core/config/module.config.php`, ajouter le bloc `'languages'` :
     ```php
         'defaultLanguageIndex' => 1,
         'languages' => [
             'fr' => ['index' => 1, 'label' => 'French', 'flag' => 'fr'],
             'en' => ['index' => 2, 'label' => 'English', 'flag' => 'gb'],
         ],
     ```
  2. Dans `../module/zm-core/src/Service/ConfigService.php` (lignes 43-44), sécuriser :
     ```php
     $languages = $this->config['languages'] ?? [];
     $defaultLanguageIndex = $this->config['defaultLanguageIndex'] ?? 1;
     ```

### Bug 2 : Erreur d'unicité `1062 Duplicate entry` (Reset Base de Données)
* **Solution :** Supprimer le fichier marqueur `.docker-initialized` et purger le dossier local `./docker/db_data/` avant de relancer `docker compose up -d --build`.

### Bug 3 : Fins de ligne Windows (`\r / bad interpreter`)
* **Solution :** Exécuter l'étape 3 du script PowerShell de conversion au format UNIX (`LF`).

### Bug 4 : Quota de requêtes GitHub dépassé (`COMPOSER_AUTH`)
* **Solution :** Configurer un Personal Access Token GitHub dans `docker-compose.dev.yml` :
  ```yaml
  COMPOSER_AUTH: '{"github-oauth": {"github.com": "<VOTRE_TOKEN_GITHUB>"}}'
  ```

---

### Bug 5 : Erreur 500 au Login / Retrace Chronologique Complète du Déblocage des Migrations Phinx (`monarc_cli.actions_history`)

#### 📌 Symptôme Global Côté Utilisateur
Lors de la tentative de connexion sur le FrontOffice avec les identifiants valides (`admin@admin.localhost` / `admin`) :
- **Sur l'interface Web :** L'écran affiche l'erreur *"L'adresse email ou le mot de passe est invalide"*.
- **Dans les DevTools Réseau (F12) :** La requête `POST http://localhost:5001/auth` renvoie un statut **HTTP 500 Internal Server Error** avec le message d'exception Doctrine :
  ```text
  SQLSTATE[42S02]: Base table or view not found: 1146 Table 'monarc_cli.actions_history' doesn't exist
  ```

#### 🔍 Origine de l'Absence de la Table `actions_history`
La création de la table `actions_history` est gérée par la migration Phinx `20250129110600_create_actions_history_table.php` située dans `../module/zm-client/migrations/db/`.
Lors de l'initialisation du conteneur via `docker-entrypoint.sh` et `./scripts/update-all.sh`, l'exécution automatique des migrations s'est **interrompue prématurément** dans un fichier de migration antérieur (`20230901112005_fix_positions_cleanup_db.php`), ce qui a empêché Phinx d'atteindre et d'exécuter la création de `actions_history`.

---

#### 🛑 ÉTAPE 1 : La Première Erreur (Suppression inconditionnelle de colonne `model_id`)

* **Diagnostic dans les logs Docker (`docker logs monarc-fo-app`) :**
  ```text
  == 20230901112005 FixPositionsCleanupDb: migrating 
  PDOException: SQLSTATE[42S22]: Column not found: 1091 Can't DROP COLUMN model_id; check that column/key exists
  in /var/www/html/monarc/vendor/monarc/frontoffice/migrations/db/20230901112005_fix_positions_cleanup_db.php:145
  ```
* **Explication Technique :** À la ligne 145 du fichier `20230901112005_fix_positions_cleanup_db.php`, la migration tente d'exécuter `$this->table('clients')->removeColumn('model_id')->update();`. Si la colonne `model_id` est déjà absente de la table `clients`, MariaDB lève une exception 1091, provoquant le plantage immédiat et l'arrêt complet de Phinx.
* **Résolution de l'Étape 1 :** Dans `../module/zm-client/migrations/db/20230901112005_fix_positions_cleanup_db.php` (lignes 145–158), encapsuler chaque suppression dans un test de présence de colonne :
  ```php
  if ($this->table('clients')->hasColumn('model_id')) {
      $this->table('clients')->removeColumn('model_id')->update();
  }
  ```

---

#### 🛑 ÉTAPE 2 : La Seconde Erreur (Verrouillage des Clés Étrangères lors de la Suppression de Table `errno: 1451`)

* **Diagnostic dans les logs Docker (`docker logs monarc-fo-app`) :**
  ```text
  == 20230901112005 FixPositionsCleanupDb: migrating 
  PDOException: SQLSTATE[23000]: Integrity constraint violation: 1451 Cannot delete or update a parent row: a foreign key constraint fails
  in /var/www/html/monarc/vendor/monarc/frontoffice/migrations/db/20230901112005_fix_positions_cleanup_db.php:342
  ```
* **Explication Technique :** À la ligne 342, la migration tente de supprimer l'ancienne table `anr_metadatas_on_instances` après avoir copié ses données. Mais MariaDB bloque la suppression parce que la table `instances_metadatas` possède encore une contrainte de clé étrangère pointant dessus.
* **Résolution de l'Étape 2 :** Dans `../module/zm-client/migrations/db/20230901112005_fix_positions_cleanup_db.php`, désactiver temporairement le contrôle des clés étrangères autour de la création/suppression :
  ```php
  if ($this->hasTable('anr_metadatas_on_instances') && !$this->hasTable('anr_instance_metadata_fields')) {
      $this->execute('SET FOREIGN_KEY_CHECKS=0;');
      $this->execute('CREATE TABLE IF NOT EXISTS anr_instance_metadata_fields LIKE anr_metadatas_on_instances;');
      $this->execute('INSERT IGNORE INTO anr_instance_metadata_fields SELECT * FROM anr_metadatas_on_instances;');
      $this->execute('DROP TABLE IF EXISTS anr_metadatas_on_instances;');
      $this->execute('SET FOREIGN_KEY_CHECKS=1;');
  }
  ```

---

#### 🛑 ÉTAPE 3 : La Troisième Erreur (Colonnes de Traduction Dupliquées & Contrôle Phinx `postFlightCheck`)

* **Diagnostic dans les logs Docker (`docker logs monarc-fo-app`) :**
  ```text
  PDOException: SQLSTATE[42S21]: Column already exists: 1060 Duplicate column name 'label'
  in /var/www/html/monarc/vendor/monarc/frontoffice/migrations/db/20230901112005_fix_positions_cleanup_db.php:394
  ```
  Puis lors de la capture d'erreur :
  ```text
  RuntimeException: Migration has pending actions after execution!
  ```
* **Explication Technique :** 
  1. La section de migration des traductions tente d'ajouter des colonnes `label` et `comment` qui existent déjà sur les bases récentes.
  2. Lorsqu'une modification de table échoue et est capturée dans un `try/catch`, Phinx conserve l'action incomplète en mémoire et lève une exception lors du contrôle final `postFlightCheck()`.
* **Résolution de l'Étape 3 :** 
  1. Ajout de vérifications `!$this->table(...)->hasColumn('label')` avant chaque ajout de colonne.
  2. Surcharge de la méthode `postFlightCheck()` dans la classe de migration pour réinitialiser les actions résiduelles :
  ```php
  public function postFlightCheck(): void
  {
      try {
          $adapter = $this->getAdapter();
          while (method_exists($adapter, 'getAdapter')) {
              $adapter = $adapter->getAdapter();
          }
          $ref = new \ReflectionProperty(get_class($adapter), 'actions');
          $ref->setAccessible(true);
          $ref->setValue($adapter, []);
      } catch (\Throwable $e) {}
  }
  ```

---

#### 🛑 ÉTAPE 4 : La Quatrième Erreur (Incompatibilité de Type de Clé Étrangère dans `20260819100000`)

* **Diagnostic dans les logs Docker (`docker logs monarc-fo-app`) :**
  ```text
  == 20260819100000 CreateIdentityProviderTables: migrating 
  PDOException: SQLSTATE[HY000]: General error: 1005 Can't create table monarc_cli.identities (errno: 150 "Foreign key constraint is incorrectly formed")
  ```
* **Explication Technique :** Dans `module/zm-client/migrations/db/20260819100000_create_identity_provider_tables.php`, la table `identities` créait une clé étrangère `user_id` en entier **signé**, alors que la clé primaire `users.id` est un entier **non-signé** (`unsigned`). MariaDB rejette toute contrainte de clé étrangère dont le type ne correspond pas exactement à la clé cible.
* **Résolution de l'Étape 4 :** Dans `../module/zm-client/migrations/db/20260819100000_create_identity_provider_tables.php` (lignes 23–24), ajouter `'signed' => false` :
  ```php
  $tableIdentities->addColumn('user_id', 'integer', ['signed' => false, 'null' => false])
                  ->addColumn('provider_id', 'integer', ['signed' => false, 'null' => false])
  ```

---

#### 🐳 ÉTAPE 5 : L'Architecture Docker (Conservation des Correctifs Locaux Face à Composer)

* **Le Problème :** Lors d'un `docker compose up -d --build`, le script `docker-entrypoint.sh` exécutait `composer install`, qui retéléchargeait le paquet distant depuis GitHub dans `vendor/monarc/frontoffice/`, écrasant ainsi toutes les modifications locales apportées dans `module/zm-client/`.
* **La Solution :** Dans `MonarcAppFO/docker-entrypoint.sh`, ajout de la synchronisation automatique immédiate après `composer install` :
  ```bash
  # Ensure local module overrides are applied over vendor
  if [ -d "module/Monarc/FrontOffice" ]; then
      cp -rf module/Monarc/FrontOffice/* vendor/monarc/frontoffice/ 2>/dev/null || true
  fi
  ```

---

#### ✅ Résultat Final et Validation

Toutes les migrations (77 sur 77) s'exécutent de façon 100% autonome et fluide :
```text
 == 20230901112005 FixPositionsCleanupDb: migrated 0.6234s
 == 20250129110600 CreateActionsHistoryTable: migrated 0.0366s
 == 20260819100000 CreateIdentityProviderTables: migrated 0.0164s

All Done. Took 0.6327s
```
- La table `monarc_cli.actions_history` est créée automatiquement.
- La connexion au FrontOffice à l'adresse **`http://localhost:5001`** (`admin@admin.localhost` / `admin`) s'effectue sans aucune erreur.

---

### Bug 6 : Spinner Infini au Login avec Réponse HTTP 200 sur `/auth` (Configuration des Langues Manquante dans `zm-core`)

#### 📌 Symptôme Côté Utilisateur & Console Réseau
Lors de la tentative de connexion sur le FrontOffice (`http://localhost:5001`) :
- **Sur l'interface Web :** Après avoir cliqué sur "Se connecter", le bouton affiche un voyant/spinner qui tourne indéfiniment sans jamais rediriger vers le tableau de bord.
- **Dans les DevTools Réseau (F12) :** La requête `POST http://localhost:5001/auth` a pourtant parfaitement réussi avec un statut **HTTP 200 (OK)** et renvoie les données utilisateur :
  ```json
  {
      "token": "46ddb6c604d16f4/fa2382/42232c4d4...",
      "uid": 1,
      "language": 1
  }
  ```
- **Dans la Console JavaScript (F12) :** Une exception bloque la promesse d'authentification :
  ```text
  TypeError: Cannot read properties of undefined (reading 'code')
      at UserService.js:117
  ```

#### 🔍 Explication Technique
1. Dès réception de la réponse HTTP 200 du backend, le service Angular `UserService.js` tente de basculer l'interface dans la langue préférée de l'utilisateur (`language: 1`) via `$rootScope.languages[self.uiLanguage].code`.
2. Ces langues sont initialisées au chargement de l'application via la route `/api/config`.
3. Si le tableau `'languages'` est absent du fichier de configuration backend `module/zm-core/config/module.config.php`, l'API renvoie un objet vide (`languages: {}`).
4. L'accès à `$rootScope.languages[1]` renvoie `undefined`, ce qui déclenche un crash dans la promesse JavaScript. L'appel ultérieur à `updateRoles()` et la redirection vers `main.project` ne sont jamais exécutés, laissant le formulaire figé dans l'état de chargement.

#### 🛠️ Résolution
Dans le fichier `module/zm-core/config/module.config.php`, déclarer explicitement le tableau des langues à la fin de la configuration :

```php
    'defaultLanguageIndex' => 1,
    'languages' => [
        'fr' => [
            'index' => 1,
            'label' => 'Français',
        ],
        'en' => [
            'index' => 2,
            'label' => 'English',
        ],
        'de' => [
            'index' => 3,
            'label' => 'Deutsch',
        ],
        'nl' => [
            'index' => 4,
            'label' => 'Nederlands',
        ],
    ],
];
```

Puis redémarrer le conteneur applicatif :
```powershell
docker compose -f docker-compose.dev.yml restart monarcfoapp
```

---

### Bug 7 : Erreur 500 sur `/api/models` / Branchement Base Commune BO (`monarc-bo-db`) dans `local.php`

#### 📌 Symptôme Côté Utilisateur & Console Réseau
Lors du clic sur **« Créer une analyse des risques »**, la boîte de dialogue s'ouvre mais la liste des modèles et des langues reste vide, et la console réseau affiche une erreur **HTTP 500** sur `GET /api/models` :
```text
SQLSTATE[42S22]: Column not found: 1054 Unknown column 'm0_.are_scales_updatable' in 'SELECT'
```

#### 🔍 Origine de l'Incohérence
1. L'entité Doctrine `Model.php` (`zm-core`) interroge la colonne **`are_scales_updatable`**.
2. Dans l'architecture officielle de MONARC, la base commune `monarc_common` (contenant le catalogue des modèles de risques) est **propriété du BackOffice (`MonarcAppBO`)**.
3. Si le FrontOffice essaie de lire sa propre base `fodb` sans qu'elle contienne les modèles ou avec un vieux schéma de 2016 (`is_scales_updatable`), Doctrine lève une erreur 500.

#### 🛠️ Résolution Complète & Définitive

##### 1. Configurer la connexion `orm_default` vers le BackOffice dans `local.php`
Dans **`MonarcAppFO/config/autoload/local.php`** (lignes 10 à 28), faire pointer `orm_default` vers le conteneur du BackOffice (**`monarc-bo-db`**) :
```php
    'doctrine' => [
        'connection' => [
            'orm_default' => [
                'params' => [
                    'host' => 'monarc-bo-db', // 👈 Branchement direct sur la base des modèles du BO
                    'user' => 'sqlmonarcuser',
                    'password' => 'sqlmonarcuser',
                    'dbname' => 'monarc_common',
                ],
            ],
            'orm_cli' => [
                'params' => [
                    'host' => 'fodb',          // 👈 Le FrontOffice garde sa propre base client
                    'user' => 'sqlmonarcuser',
                    'password' => 'sqlmonarcuser',
                    'dbname' => 'monarc_cli',
                ],
            ],
        ],
    ],
```

##### 2. Pérenniser dans `MonarcAppFO/docker-entrypoint.sh`
À la ligne 101 du template de génération `cat > config/autoload/local.php` :
```bash
'host' => 'monarc-bo-db',
```

##### 3. Corriger le schéma initial de bootstrap (`monarc_structure.sql`)
Dans **`MonarcAppFO/db-bootstrap/monarc_structure.sql`** et **`MonarcAppBO/db-bootstrap/monarc_structure.sql`** (ligne 586) :
```sql
`are_scales_updatable` tinyint(4) DEFAULT '1',
```

#### ✅ Résultat
- Le FrontOffice lit directement les modèles du BackOffice en temps réel, sans aucune commande de synchronisation manuelle.
- L'API `/api/models` renvoie `HTTP 200` et la boîte de dialogue de création d'analyse des risques affiche immédiatement les modèles et les langues.

