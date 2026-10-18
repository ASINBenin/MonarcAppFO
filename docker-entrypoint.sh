#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting MONARC FrontOffice setup...${NC}"

# Wait for database to be ready
echo -e "${YELLOW}Waiting for MariaDB to be ready...${NC}"
while ! mysqladmin ping -h"${DBHOST}" -u"${DBUSER_MONARC}" -p"${DBPASSWORD_MONARC}" --silent 2>/dev/null; do
    echo "Waiting for MariaDB..."
    sleep 2
done
echo -e "${GREEN}MariaDB is ready!${NC}"

is_true() {
    case "$1" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Serializes the entities that bootstrap and migrate a shared monarc_common (standalone mode).
# GET_LOCK belongs to the MySQL session, so the session is kept open (coprocess) until the lock is released.
COMMON_LOCK_HELD=0
acquire_common_lock() {
    coproc COMMON_LOCK { MYSQL_PWD="${DBPASSWORD_MONARC}" mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -N --unbuffered; }
    echo "SELECT GET_LOCK('monarc_common_bootstrap', 600);" >&"${COMMON_LOCK[1]}"
    read -r lock_ok <&"${COMMON_LOCK[0]}"
    if [ "$lock_ok" != "1" ]; then
        echo -e "${RED}Could not acquire the monarc_common bootstrap lock.${NC}"
        exit 1
    fi
    COMMON_LOCK_HELD=1
}
release_common_lock() {
    if [ "$COMMON_LOCK_HELD" -eq 1 ]; then
        local pid="$COMMON_LOCK_PID"
        echo "SELECT RELEASE_LOCK('monarc_common_bootstrap');" >&"${COMMON_LOCK[1]}"
        read -r _ <&"${COMMON_LOCK[0]}"
        eval "exec ${COMMON_LOCK[1]}>&-"
        wait "$pid" 2>/dev/null || true
        COMMON_LOCK_HELD=0
    fi
}

CAPTCHA_ENABLED_PHP=false
if is_true "${CAPTCHA_ENABLED:-false}"; then
    CAPTCHA_ENABLED_PHP=true
fi

TWO_FACTOR_AUTH_ENFORCED_PHP=false
if is_true "${TWO_FACTOR_AUTH_ENFORCED:-false}"; then
    TWO_FACTOR_AUTH_ENFORCED_PHP=true
fi

# Development (APP_ENV=development): sources are mounted, dependencies and frontend are built at first start.
# Any other environment uses the image prebuilt by the CI (vendor, node_modules, public resources): nothing is rebuilt.
IS_DEV_ENV=0
if [ "${APP_ENV:-production}" = "development" ]; then
    IS_DEV_ENV=1
fi
if [ "$IS_DEV_ENV" -eq 0 ] && [ ! -f "/var/www/html/monarc/vendor/autoload.php" ]; then
    echo -e "${RED}APP_ENV=${APP_ENV:-production} but the application is not prebuilt (vendor/autoload.php missing).${NC}"
    echo -e "${RED}Use an image built by the CI, or set APP_ENV=development to build at startup.${NC}"
    exit 1
fi

# Check if this is the first run
if [ ! -f "/var/www/html/monarc/.docker-initialized" ]; then
    echo -e "${GREEN}First run detected, initializing application...${NC}"

    cd /var/www/html/monarc

    if [ "$IS_DEV_ENV" -eq 1 ]; then
        # Install composer dependencies (always, to ensure binaries like Phinx are present)
        echo -e "${YELLOW}Installing Composer dependencies...${NC}"
        composer install --ignore-platform-req=php --no-interaction

        if [ -d "module/Monarc/FrontOffice" ] && [ ! -L "module/Monarc/FrontOffice" ]; then
            cp -rf module/Monarc/FrontOffice/* vendor/monarc/frontoffice/ 2>/dev/null || true
        fi
        if [ -d "module/Monarc/Core" ] && [ ! -L "module/Monarc/Core" ]; then
            cp -rf module/Monarc/Core/* vendor/monarc/core/ 2>/dev/null || true
        fi

        # Create module symlinks
        echo -e "${YELLOW}Creating module symlinks...${NC}"
        mkdir -p module/Monarc
        cd module/Monarc

        if [ ! -d "Core" ] && [ ! -L "Core" ]; then
            ln -sfn ./../../vendor/monarc/core Core
        fi
        if [ ! -d "FrontOffice" ] && [ ! -L "FrontOffice" ]; then
            ln -sfn ./../../vendor/monarc/frontoffice FrontOffice
        fi

        cd /var/www/html/monarc

        # Clone frontend repositories
        echo -e "${YELLOW}Setting up frontend repositories...${NC}"
        mkdir -p node_modules
        cd node_modules

        # Use the sibling repositories when they are mounted and not already mounted in node_modules
        # (linking over an existing directory would create a stray link inside that repository).
        if [ ! -e "ng_client" ] && [ -d "/var/www/html/ng-client" ]; then
            ln -s /var/www/html/ng-client ng_client
        fi
        if [ ! -e "ng_anr" ] && [ -d "/var/www/html/ng-anr" ]; then
            ln -s /var/www/html/ng-anr ng_anr
        fi

        if [ ! -d "ng_client" ]; then
            git clone --config core.fileMode=false -b master-asin https://github.com/ASINBenin/ng-client.git ng_client
        fi

        if [ ! -d "ng_anr" ]; then
            git clone --config core.fileMode=false -b master-asin https://github.com/ASINBenin/ng-anr.git ng_anr
        fi

        cd /var/www/html/monarc
    else
        echo -e "${YELLOW}Prebuilt image: skipping Composer, frontend clone and build.${NC}"
    fi

    # Check if CLI database exists and create it if needed
    echo -e "${YELLOW}Setting up databases...${NC}"
    DB_EXISTS=$(mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -p"${DBPASSWORD_MONARC}" -e "SHOW DATABASES LIKE '${DBNAME_CLI}';" | grep -c "${DBNAME_CLI}" || true)
    USE_BO_COMMON_ENABLED=0
    if is_true "${USE_BO_COMMON}"; then
        USE_BO_COMMON_ENABLED=1
    fi

    if [ "$DB_EXISTS" -eq 0 ]; then
        echo -e "${YELLOW}Creating database ${DBNAME_CLI}...${NC}"
        mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -p"${DBPASSWORD_MONARC}" -e "CREATE DATABASE IF NOT EXISTS ${DBNAME_CLI} DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;"
    fi

    # Populate monarc_common based on its own state (table count), not DBNAME_CLI's —
    # a DB-provisioning script (init-mariadb.sh) may have already created it empty
    # ahead of time, which must not be mistaken for "already populated". A MySQL
    # advisory lock prevents two entities bootstrapping it at the same time.
    if [ "$USE_BO_COMMON_ENABLED" -eq 0 ]; then
        mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -p"${DBPASSWORD_MONARC}" -e "CREATE DATABASE IF NOT EXISTS ${DBNAME_COMMON} DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;"

        export MYSQL_PWD="${DBPASSWORD_MONARC}"
        acquire_common_lock

        COMMON_TABLE_COUNT=$(mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DBNAME_COMMON}';")
        if [ "$COMMON_TABLE_COUNT" -eq 0 ]; then
            echo -e "${YELLOW}Populating common database...${NC}"
            mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" ${DBNAME_COMMON} < db-bootstrap/monarc_structure.sql
            mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" ${DBNAME_COMMON} < db-bootstrap/monarc_data.sql
        else
            echo -e "${YELLOW}Common database already populated, skipping.${NC}"
        fi

        # The lock stays held until the monarc_common migrations below are done.
    else
        echo -e "${YELLOW}USE_BO_COMMON is enabled; skipping monarc_common creation and bootstrap.${NC}"
    fi

    # Privileges are not granted here: the entity's SQL account receives its rights when it is created
    # (monarc-deploy/scripts/db/create-entity-dbs.sh, or docker/db-init/10-dev-grants.sh in development).

    if [ "$USE_BO_COMMON_ENABLED" -eq 1 ]; then
        COMMON_EXISTS=$(mysql -h"${DBHOST}" -u"${DBUSER_MONARC}" -p"${DBPASSWORD_MONARC}" -e "SHOW DATABASES LIKE '${DBNAME_COMMON}';" | grep -c "${DBNAME_COMMON}" || true)
        if [ "$COMMON_EXISTS" -eq 0 ]; then
            echo -e "${RED}USE_BO_COMMON is enabled, but ${DBNAME_COMMON} was not found on ${DBHOST}.${NC}"
            echo -e "${RED}Ensure the BackOffice database is reachable and contains ${DBNAME_COMMON}.${NC}"
            exit 1
        fi
    fi

    # Scope the session cookie to this entity's path prefix, to avoid cross-entity cookie collisions when multiple entities share one domain.
    if [ -n "${PATH_PREFIX:-}" ]; then
        echo "session.cookie_path = ${PATH_PREFIX}" > /etc/php/8.1/apache2/conf.d/session-path.ini
    fi

    # Emit smtpOptions only if SMTP_HOST is set (empty array still passes !empty()).
    SMTP_CONFIG_BLOCK=""
    if [ -n "${SMTP_HOST:-}" ]; then
        SMTP_CONFIG_BLOCK="
    'smtpOptions' => [
        'name'              => '${DOMAIN_FO:-localhost}',
        'host'              => '${SMTP_HOST}',
        'port'              => ${SMTP_PORT:-587},
        'connection_class'  => 'login',
        'connection_config' => [
            'username' => '${SMTP_USER}',
            'password' => '${SMTP_PASSWORD}',
            'ssl'      => 'tls',
        ],
    ],"
    fi

    # Generate local config (always override to match container DB)
    echo -e "${YELLOW}Creating local configuration...${NC}"
    cat > config/autoload/local.php <<EOF
<?php
\$appdir = getenv('APP_DIR') ? getenv('APP_DIR') : '/var/www/html/monarc';
\$string = file_get_contents(\$appdir.'/package.json');
if(\$string === FALSE) {
    \$string = file_get_contents('./package.json');
}
\$package_json = json_decode(\$string, true);

return [
    'doctrine' => [
        'connection' => [
            'orm_default' => [
                'params' => [
                    'host' => '${DBHOST}',
                    'user' => '${DBUSER_MONARC}',
                    'password' => '${DBPASSWORD_MONARC}',
                    'dbname' => '${DBNAME_COMMON}',
                ],
            ],
            'orm_cli' => [
                'params' => [
                    'host' => '${DBHOST}',
                    'user' => '${DBUSER_MONARC}',
                    'password' => '${DBPASSWORD_MONARC}',
                    'dbname' => '${DBNAME_CLI}',
                ],
            ],
        ],
    ],

    'defaultLanguageIndex' => 1,

     // Languages available for the analysis / DB data.
    'languages' => [
        'fr' => ['index' => 1, 'label' => 'Français'],
        'en' => ['index' => 2, 'label' => 'English'],
        'de' => ['index' => 3, 'label' => 'Deutsch'],
        'nl' => ['index' => 4, 'label' => 'Dutch'],
    ],

    // Languages available for the user interface.
    'activeLanguages' => ['fr', 'en', 'de', 'nl', 'es', 'ro', 'it', 'ja', 'pl', 'pt', 'zh'],

    'appVersion' => \$package_json['version'],

    'checkVersion' => false,
    'appCheckingURL' => 'https://version.monarc.lu/check/MONARC',

    // Per-entity settings, as in the official ansible-ubuntu client configuration
    'instanceName' => '${INSTANCE_NAME:-${DBNAME_CLI}}', // label of the 2FA QR code
    'twoFactorAuthEnforced' => ${TWO_FACTOR_AUTH_ENFORCED_PHP},
    'terms' => '${TERMS_URL:-}',

    'email' => [
        'name' => 'MONARC',
        'from' => '${EMAIL_FROM:-info@monarc.lu}',
    ],
${SMTP_CONFIG_BLOCK}

    'mospApiUrl' => 'https://objects.monarc.lu/api/',

    'monarc' => [
        'ttl' => 60, // timeout
    ],

    'statsApi' => [
        'baseUrl' => '${STATS_API_BASE_URL:-http://stats-service:5005}',
        'apiKey' => '${STATS_API_KEY:-}',
    ],

    'deliverable' => [
        'pdfConverterBinary' => '${PDF_CONVERTER_BINARY:-/usr/bin/soffice}',
    ],

    'sso_providers' => [
        'trustedx_pki' => [
            'name'                  => 'Identité Numérique PKI (TrustedX)',
            'is_active'             => true,
            'type'                  => 'oauth2',
            'base_url'              => '${TRUSTEDX_URL}',
            'authorize_url'         => '${TRUSTEDX_URL}/trustedx-authserver/oauth/main-as',
            'token_url'             => '${TRUSTEDX_URL}/trustedx-authserver/oauth/token',
            'userinfo_url'          => '${TRUSTEDX_URL}/trustedx-resources/openid/v1/users/me',
            'esignsp_processes_url' => '${TRUSTEDX_URL}/trustedx-resources/esignsp/v2/signer_processes',
            'esignsp_ui_url'        => '${TRUSTEDX_URL}/trustedx-resources/esignsp/v2/ui',
            'esignsp_documents_url' => '${TRUSTEDX_URL}/trustedx-resources/esignsp/v2/documents',
            'logout_url'            => '${TRUSTEDX_URL}/trustedx-authserver/gob-idp/logout',
            'client_id'             => '${TRUSTEDX_CLIENT_ID}',
            'client_secret'         => '${TRUSTEDX_CLIENT_SECRET}',
            'scope'                 => 'urn:gob:basic:profile urn:safelayer:eidas:sign:process:document',
            'acr_values'            => 'urn:gob:authentication:flow:password',
            'identifier_claim'      => 'npi',
        ],
    ],

    'captcha' => [
        'enabled' => ${CAPTCHA_ENABLED_PHP},
        'failedLoginAttempts' => 3,
        'params' => [
            'name' => 'MonarcCaptcha',
            'font' => \$appdir . '/data/fonts/arial.ttf',
            'fontSize' => 30,
            'height' => 60,
            'wordLen' => 6,
            'timeout' => 300,
            'imgDir' => \$appdir . '/public/captcha',
            'imgUrl' => 'captcha/',
        ],
    ],

    'import' => [
        'uploadFolder' => \$appdir . '/data/import/files',
        'isBackgroundProcessActive' => false,
    ],
];
EOF

    if [ "$IS_DEV_ENV" -eq 1 ]; then
        # Update and build frontend and run DB migrations
        echo -e "${YELLOW}Building frontend and running DB migrations...${NC}"
        ./scripts/update-all.sh
    else
        # Same database steps as update-all.sh, without rebuilding what the image already contains
        echo -e "${YELLOW}Running DB migrations...${NC}"
        # monarc_common belongs to the BackOffice when USE_BO_COMMON is enabled (as in ansible-ubuntu):
        # the FrontOffice only migrates it in standalone mode.
        if [ "$USE_BO_COMMON_ENABLED" -eq 0 ]; then
            php ./vendor/robmorgan/phinx/bin/phinx migrate -c ./module/Monarc/Core/migrations/phinx.php
        fi
        php ./vendor/robmorgan/phinx/bin/phinx migrate -c ./module/Monarc/FrontOffice/migrations/phinx.php
        ./scripts/update_config_variables.sh
        mkdir -p ./data/cache && touch ./data/cache/upgrade && chmod 777 ./data/cache/upgrade
    fi
    release_common_lock

    # Seed database with initial user. Disabled (MONARC_SEED_ADMIN=0) for the entities created from the
    # BackOffice: their first user is inserted by the entity deployment service, as ansible-ubuntu does.
    if is_true "${MONARC_SEED_ADMIN:-1}"; then
        echo -e "${YELLOW}Creating initial user and client...${NC}"
        if ! php ./vendor/robmorgan/phinx/bin/phinx seed:run -c ./module/Monarc/FrontOffice/migrations/phinx.php; then
            echo -e "${YELLOW}Initial user/client seed failed. update-all completed successfully, so initialization will continue.${NC}"
            echo -e "${YELLOW}If needed, rerun the seed manually after startup.${NC}"
        fi
    else
        echo -e "${YELLOW}MONARC_SEED_ADMIN disabled: the first user is created by the BackOffice deployment.${NC}"
    fi

    # Set permissions
    echo -e "${YELLOW}Setting permissions...${NC}"
    mkdir -p /var/www/html/monarc/public/captcha
    chown -R www-data:www-data /var/www/html/monarc/data
    chown -R www-data:www-data /var/www/html/monarc/public/captcha
    chmod -R 775 /var/www/html/monarc/data

    # Mark initialization as complete
    touch /var/www/html/monarc/.docker-initialized
    echo -e "${GREEN}Initialization complete!${NC}"
else
    echo -e "${GREEN}Application already initialized, starting services...${NC}"
fi

# PHP limits, applied at every start (defaults = official values of the ansible-ubuntu deployment)
cat > /etc/php/8.1/apache2/conf.d/99-monarc-limits.ini <<EOF
memory_limit = ${PHP_MEMORY_LIMIT:-4096M}
max_execution_time = ${PHP_MAX_EXECUTION_TIME:-520}
upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE:-200M}
post_max_size = ${PHP_POST_MAX_SIZE:-200M}
EOF

# Apache prefork sized for one entity per container (Ubuntu defaults allow 150 workers per container)
cat > /etc/apache2/conf-enabled/zz-monarc-prefork.conf <<EOF
<IfModule mpm_prefork_module>
    StartServers            ${APACHE_START_SERVERS:-2}
    MinSpareServers         ${APACHE_MIN_SPARE_SERVERS:-1}
    MaxSpareServers         ${APACHE_MAX_SPARE_SERVERS:-3}
    MaxRequestWorkers       ${APACHE_MAX_REQUEST_WORKERS:-20}
    MaxConnectionsPerChild  ${APACHE_MAX_CONNECTIONS_PER_CHILD:-500}
</IfModule>
EOF

# Execute the main command
exec apachectl -D FOREGROUND
