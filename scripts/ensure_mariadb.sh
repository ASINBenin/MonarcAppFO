#!/bin/bash
# Vérifie qu'un serveur MariaDB natif (hors conteneur) est disponible sur la
# machine. S'il n'est pas installé, l'installe et le configure avec les bases
# et l'utilisateur attendus par MONARC. À exécuter directement sur la VM
# (pas dans un conteneur), avant "docker compose -f docker-compose.prod.yml up -d".
set -euo pipefail

DBNAME_COMMON="${DBNAME_COMMON:-monarc_common}"
DBNAME_CLI="${DBNAME_CLI:-monarc_cli}"
DBUSER_MONARC="${DBUSER_MONARC:-monarc_prod}"
DBPASSWORD_MONARC="${DBPASSWORD_MONARC:?Variable DBPASSWORD_MONARC requise (mot de passe applicatif)}"
DBPASSWORD_ADMIN="${DBPASSWORD_ADMIN:?Variable DBPASSWORD_ADMIN requise (mot de passe root MariaDB)}"

if command -v mysql >/dev/null 2>&1 && systemctl is-active --quiet mariadb 2>/dev/null; then
    echo "MariaDB déjà installé et actif, rien à installer."
else
    echo "MariaDB introuvable ou inactif — installation..."
    sudo apt-get update
    sudo apt-get install -y mariadb-server mariadb-client
    sudo systemctl enable --now mariadb

    echo "Sécurisation initiale (mot de passe root)..."
    sudo mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DBPASSWORD_ADMIN}';
FLUSH PRIVILEGES;
SQL
fi

echo "Vérification/création des bases et de l'utilisateur applicatif..."
mysql -uroot -p"${DBPASSWORD_ADMIN}" <<SQL
CREATE DATABASE IF NOT EXISTS ${DBNAME_COMMON} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS ${DBNAME_CLI} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DBUSER_MONARC}'@'%' IDENTIFIED BY '${DBPASSWORD_MONARC}';
GRANT ALL PRIVILEGES ON ${DBNAME_COMMON}.* TO '${DBUSER_MONARC}'@'%';
GRANT ALL PRIVILEGES ON ${DBNAME_CLI}.* TO '${DBUSER_MONARC}'@'%';
FLUSH PRIVILEGES;
SQL

echo "Autoriser les connexions réseau (bind-address) pour que le conteneur applicatif puisse s'y connecter..."
BIND_CONF="/etc/mysql/mariadb.conf.d/50-server.cnf"
if [ -f "$BIND_CONF" ] && grep -q "^bind-address" "$BIND_CONF"; then
    sudo sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' "$BIND_CONF"
    sudo systemctl restart mariadb
fi

echo "MariaDB prêt : bases '${DBNAME_COMMON}' et '${DBNAME_CLI}', utilisateur '${DBUSER_MONARC}'."
