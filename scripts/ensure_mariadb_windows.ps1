# Équivalent Windows de scripts/ensure_mariadb.sh, pour tester en local avec
# WAMP (Linux/VM : utiliser ensure_mariadb.sh). Ne fait PAS l'installation —
# WAMP installe déjà MariaDB — seulement la création des bases et de
# l'utilisateur applicatif attendus par MONARC. À lancer depuis la racine du
# projet (mêmes variables que le fichier .env), avant
# "docker compose -f docker-compose.prod.yml up -d". Nécessite que WAMP
# tourne (icône WAMP verte).
param(
    [string]$DBNameCommon = $env:DBNAME_COMMON,
    [string]$DBNameCli = $env:DBNAME_CLI,
    [string]$DBUserMonarc = $env:DBUSER_MONARC,
    [string]$DBPasswordMonarc = $env:DBPASSWORD_MONARC,
    [string]$DBPasswordAdmin = $env:DBPASSWORD_ADMIN
)

$ErrorActionPreference = "Stop"

if (-not $DBNameCommon) { $DBNameCommon = "monarc_common" }
if (-not $DBNameCli) { $DBNameCli = "monarc_cli" }
if (-not $DBUserMonarc) { $DBUserMonarc = "monarc_prod" }
if (-not $DBPasswordMonarc) { throw "DBPASSWORD_MONARC requis (mot de passe applicatif) — charge ton .env d'abord, ex: Get-Content .env | ForEach-Object { if (`$_ -match '^([^#][^=]*)=(.*)`$') { Set-Item \"env:`$(`$matches[1])\" `$matches[2] } }" }

$mysqlExe = Get-ChildItem "C:\wamp64\bin\mariadb\*\bin\mysql.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mysqlExe) {
    throw "mysql.exe introuvable sous C:\wamp64\bin\mariadb\*\bin — WAMP est-il installé à cet emplacement ? Adapte le chemin dans ce script sinon."
}

Write-Output "Utilisation de $($mysqlExe.FullName)"

# Mot de passe root WAMP par défaut : vide. Si tu l'as changé, passe -DBPasswordAdmin.
$rootAuthArgs = @("-u", "root")
if ($DBPasswordAdmin) { $rootAuthArgs += "-p$DBPasswordAdmin" }

$sql = @"
CREATE DATABASE IF NOT EXISTS $DBNameCommon CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS $DBNameCli CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DBUserMonarc'@'%' IDENTIFIED BY '$DBPasswordMonarc';
GRANT ALL PRIVILEGES ON $DBNameCommon.* TO '$DBUserMonarc'@'%';
GRANT ALL PRIVILEGES ON $DBNameCli.* TO '$DBUserMonarc'@'%';
FLUSH PRIVILEGES;
"@

Write-Output "Vérification/création des bases et de l'utilisateur applicatif..."
$sql | & $mysqlExe.FullName @rootAuthArgs

Write-Output "MariaDB (WAMP) prêt : bases '$DBNameCommon' et '$DBNameCli', utilisateur '$DBUserMonarc'."
Write-Output "Note : le conteneur applicatif s'y connecte via host.docker.internal (voir DBHOST dans .env) — le '@%%' ci-dessus (au lieu de '@localhost') est ce qui l'autorise."
