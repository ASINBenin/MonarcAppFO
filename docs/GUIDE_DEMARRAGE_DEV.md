# Démarrage en développement — Front-Office (seul ou avec le Back-Office)

Environnement de **développement** sur un poste Windows avec Docker Desktop. Le code des modules est monté dans les conteneurs : une modification est visible au rafraîchissement du navigateur, sans reconstruire d'image.

Pour le test et la production, voir le dépôt `monarc-deploy` (`docs/GUIDE_DEMARRAGE_TEST.md` et `docs/GUIDE_DEMARRAGE_PROD.md`).

---

## 1. Prérequis

- Docker Desktop (moteur Linux) et Git Bash.
- Tous les dépôts clonés **côte à côte** dans le même dossier (ici `v_current/`) :

```
v_current/
├── MonarcAppFO   MonarcAppBO
├── zm-core   zm-client   zm-sign   zm-backoffice
└── ng-anr   ng-client   ng-sign   ng-backoffice
```

Le compose de dev du FO monte `../zm-core`, `../zm-client`, `../zm-sign`, `../ng-client`, `../ng-anr` et `../ng-sign` : s'il en manque un, le conteneur ne démarre pas (`bind source path does not exist`).

- Les scripts `.sh` doivent rester en fins de ligne **LF** (sinon : `$'\r': command not found` dans le conteneur). Le fichier `.gitattributes` du dépôt l'impose aux nouveaux checkouts.

---

## 2. Préparation (une seule fois)

**Réseau Docker partagé** par le FO et le BO :

```bash
docker network create monarc-network
```

**Fichier `.env`** du FO :

```bash
cd /d/QSIN/Monarc/Draft/v_current/MonarcAppFO
[ -f .env ] || cp .env.dev .env
```

Compléter `.env` avec les variables absentes de `.env.dev` si tu testes la connexion PKI ou la signature :

```
TRUSTEDX_URL=
TRUSTEDX_CLIENT_ID=
TRUSTEDX_CLIENT_SECRET=
MONARC_SSO_ENCRYPTION_KEY=      # openssl rand -base64 32
```

**Envoi de courriels (optionnel)** : le compose de dev ne transmet pas les variables SMTP au conteneur. Pour envoyer les courriels vers MailCatcher, créer un `docker-compose.override.yml` local (non versionné) :

```yaml
services:
  monarcfoapp:
    environment:
      SMTP_HOST: mailcatcher
      SMTP_PORT: 1025
      EMAIL_FROM: monarc@localhost
```

Puis lancer `docker compose -f docker-compose.dev.yml -f docker-compose.override.yml up -d`. Les courriels apparaissent sur http://localhost:1080.

**Choisir l'organisation des bases** dans `.env` :

| Mode | Réglages | Usage |
|---|---|---|
| **A — FO seul** | `DBHOST=fodb` et `USE_BO_COMMON=0` | Le FO crée et remplit lui-même `monarc_common` dans sa base `fodb`. Le plus simple. |
| **B — FO + BO** | `DBHOST=bodb` et `USE_BO_COMMON=1` | Comme en production : le FO lit `monarc_common` du BO. Le BO doit être démarré **avant** le FO (voir `MonarcAppBO/docs/GUIDE_DEMARRAGE_DEV.md`). |

> `DBHOST=fodb` avec `USE_BO_COMMON=1` ne fonctionne pas : le FO s'arrête avec `monarc_common was not found`.

---

## 3. Démarrer

```bash
cd /d/QSIN/Monarc/Draft/v_current/MonarcAppFO
docker compose -f docker-compose.dev.yml up -d --build
docker logs -f monarc-fo-app
```

Au premier démarrage, l'entrypoint (mode `APP_ENV=development`) :

1. attend MariaDB ;
2. installe les dépendances (`composer install`) et prépare les modules front ;
3. en mode A, crée et remplit `monarc_common` (protégé par un verrou si plusieurs instances démarrent en même temps) ;
4. génère `config/autoload/local.php` (base, SMTP, TrustedX, statistiques) ;
5. lance `scripts/update-all.sh` (migrations, ressources front, traductions) ;
6. crée le compte `admin@admin.localhost` / `admin`.

Attendre `Initialization complete!` (plusieurs minutes la première fois), puis ouvrir **http://localhost:5001**.

`--build` n'est utile que la première fois ou après un changement de `Dockerfile.dev`. Ensuite : `docker compose -f docker-compose.dev.yml up -d`.

---

## 4. Adresses utiles

| Service | Adresse |
|---|---|
| Front-Office | http://localhost:5001 |
| phpMyAdmin (bases `fodb` et `bodb`) | http://localhost:8081 |
| MailCatcher (courriels envoyés en dev) | http://localhost:1080 |
| Service de statistiques | http://localhost:5005 |
| MariaDB du FO (depuis le poste) | `localhost:3307` (`DBPORT_HOST`) |

Un fichier `docker-compose.override.yml` local (non versionné), passé avec un second `-f`, permet aussi de changer ces ports si l'un d'eux est déjà pris sur ta machine.

---

## 5. Travailler au quotidien

- Modifier le code dans `zm-*`, `ng-*` ou `MonarcAppFO` : il est monté dans le conteneur, rafraîchir le navigateur.
- Après une modification de `ng-client`, `ng-anr` ou `ng-sign` qui ajoute des fichiers : `docker exec monarc-fo-app ./scripts/link_modules_resources.sh`.
- Après l'ajout d'une migration : `docker exec monarc-fo-app ./scripts/update-all.sh -d`.
- Redémarrer : `docker restart monarc-fo-app`. Entrer dans le conteneur : `docker exec -it monarc-fo-app bash`.
- Les limites PHP (4 Go, 520 s, envois de 200 Mo) et le réglage d'Apache sont appliqués à chaque démarrage ; ils se changent par variables (`PHP_MEMORY_LIMIT`, `APACHE_MAX_REQUEST_WORKERS`…) dans le compose.

**Publier** : un push sur `dev-dani` ne déclenche aucune construction d'image. Un push sur `master-asin` construit l'image de test `ghcr.io/asinbenin/monarcappfo:master-asin` ; un tag `v2.14.1-rN` publie l'image de production (voir le guide de production).

---

## 6. Arrêter

```bash
docker compose -f docker-compose.dev.yml down        # garde les bases
docker compose -f docker-compose.dev.yml down -v     # repart de zéro (efface les bases de dev)
```

---

## 7. Problèmes courants

| Symptôme | Cause et solution |
|---|---|
| `network monarc-network ... could not be found` | `docker network create monarc-network` |
| `$'\r': command not found` | Script en CRLF : le repasser en LF (`dos2unix` ou l'éditeur). |
| `monarc_common was not found` | `USE_BO_COMMON=1` sans base du BO : passer en mode A, ou démarrer le BO d'abord (mode B). |
| `bind source path does not exist` | Un dépôt frère manque dans `v_current/`. |
| Le FO redémarre sur `Access denied` | Le compte MariaDB de dev n'a pas ses droits : la base `fodb` a été créée avant l'ajout de `DBUSER_MONARC` au conteneur MariaDB. Repartir de zéro (`down -v`). |
| Xdebug ne s'arrête pas aux points d'arrêt | FO et BO utilisent le même port `9003` : un seul IDE à la fois. |
