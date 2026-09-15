# Equivalent Windows de scripts/ensure_mariadb.sh, pour tester en local avec
# WAMP (Linux/VM : utiliser ensure_mariadb.sh). Ne fait PAS l'installation -
# WAMP installe deja MariaDB - seulement la creation des bases et de
# l'utilisateur applicatif attendus par MONARC. A lancer depuis la racine du
# projet (memes variables que le fichier .env), avant
# "docker compose -f docker-compose.prod.yml up -d". Necessite que WAMP
# tourne (icone WAMP verte).
#
# Usage : charge d'abord ton .env dans l'environnement, puis lance ce script :
#   Get-Content .env | ForEach-Object { if ($_ -match '^([^#][^=]*)=(.*)$') { Set-Item "env:$($matches[1])" $matches[2] } }
#   .\scripts\ensure_mariadb_windows.ps1
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
if (-not $DBPasswordMonarc) {
    throw "DBPASSWORD_MONARC requis (mot de passe applicatif). Charge ton .env d'abord (voir l'usage en tete de ce script)."
}

$mysqlExe = Get-ChildItem "C:\wamp64\bin\mariadb\*\bin\mysql.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $mysqlExe) {
    throw "mysql.exe introuvable sous C:\wamp64\bin\mariadb\*\bin - WAMP est-il installe a cet emplacement ? Adapte le chemin dans ce script sinon."
}

Write-Output "Utilisation de $($mysqlExe.FullName)"

# Mot de passe root WAMP par defaut : vide. Si tu l'as change, passe -DBPasswordAdmin.
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

Write-Output "Verification/creation des bases et de l'utilisateur applicatif..."
$sql | & $mysqlExe.FullName @rootAuthArgs

Write-Output "MariaDB (WAMP) pret : bases '$DBNameCommon' et '$DBNameCli', utilisateur '$DBUserMonarc'."
Write-Output "Note : le conteneur applicatif s'y connecte via host.docker.internal (voir DBHOST dans .env) - le utilisateur cree sur '%' (au lieu de 'localhost') est ce qui l'autorise depuis l'exterieur de WAMP."
