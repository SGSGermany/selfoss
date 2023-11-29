#!/bin/sh
# Selfoss
# A php-fpm container running Selfoss, a RSS reader and feed aggregator.
#
# Copyright (c) 2023  SGS Serious Gaming & Simulations GmbH
#
# This work is licensed under the terms of the MIT license.
# For a copy, see LICENSE file or <https://opensource.org/licenses/MIT>.
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSE

set -eu -o pipefail
export LC_ALL=C.UTF-8

read_secret() {
    local SECRET="/run/secrets/$1"

    [ -e "$SECRET" ] || return 0
    [ -f "$SECRET" ] || { echo "Failed to read '$SECRET' secret: Not a file" >&2; return 1; }
    [ -r "$SECRET" ] || { echo "Failed to read '$SECRET' secret: Permission denied" >&2; return 1; }
    cat "$SECRET" || return 1
}

# reset config
rm -f "/var/www/html/config.ini"

touch "/var/www/html/config.ini"
chown www-data:www-data "/var/www/html/config.ini"
chmod 640 "/var/www/html/config.ini"

{
    printf '[globals]\n';
    printf 'env_prefix=selfoss_\n';
    printf '\n';
} >> "/var/www/html/config.ini"

# database config
MYSQL_USER="$(read_secret "selfoss_mysql_user")"
MYSQL_PASSWORD="$(read_secret "selfoss_mysql_password")"
MYSQL_DATABASE="$(read_secret "selfoss_mysql_database")"
MYSQL_TABLE_PREFIX="$(read_secret "selfoss_mysql_table_prefix")"

if [ -n "$MYSQL_USER" ] || [ -n "$MYSQL_PASSWORD" ] || [ -n "$MYSQL_DATABASE" ] || [ -n "$MYSQL_TABLE_PREFIX" ]; then
    MYSQL_USER="${MYSQL_USER:-selfoss}"
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
    MYSQL_DATABASE="${MYSQL_DATABASE:-selfoss}"
    MYSQL_TABLE_PREFIX="${MYSQL_TABLE_PREFIX:-}"

    {
        printf 'db_type=mysql\n';
        printf 'db_socket=/run/mysql/mysql.sock\n';
        printf "db_username=%s\n" "$MYSQL_USER";
        printf "db_password=%s\n" "$MYSQL_PASSWORD";
        printf "db_database=%s\n" "$MYSQL_DATABASE";
        printf "db_prefix=%s\n" "$MYSQL_TABLE_PREFIX";
        printf '\n';
    } >> "/var/www/html/config.ini"
else
    {
        printf 'db_type=sqlite\n';
        printf 'db_file=%%datadir%%/sqlite/selfoss.db\n';
        printf '\n';
    } >> "/var/www/html/config.ini"
fi

# auth config
AUTH_PUBLIC="$(read_secret "selfoss_auth_public")"
AUTH_USER="$(read_secret "selfoss_auth_user")"
AUTH_PASSWORD="$(read_secret "selfoss_auth_password")"

if [ -n "$AUTH_USER" ] || [ -n "$AUTH_PASSWORD" ]; then
    [ "$AUTH_PUBLIC" == "1" ] \
        && AUTH_PUBLIC=1 \
        || AUTH_PUBLIC=0

    if [ -z "$AUTH_USER" ]; then
        echo "Failed to setup Selfoss auth config: Invalid user provided ('selfoss_auth_user' secret)" >&2
        exit 1
    fi

    if [ -z "$AUTH_PASSWORD" ] || [ -z "$(echo "$AUTH_PASSWORD" | grep -E '^\$[0-9][a-z]?\$[0-9][0-9]?\$[./A-Za-z0-9]{53}$')" ]; then
        echo "Failed to setup Selfoss auth config: Invalid password provided ('selfoss_auth_password' secret)" >&2
        exit 1
    fi

    {
        printf "public=%s\n" "$AUTH_PUBLIC";
        printf "username=%s\n" "$AUTH_USER";
        printf "password=%s\n" "$AUTH_PASSWORD";
        printf "salt=\n";
        printf '\n';
    } >> "/var/www/html/config.ini"
fi

# misc config
env -0 | while IFS='=' read -r -d '' NAME VALUE; do
    case "$NAME" in
        "SELFOSS_VERSION"|"SELFOSS_LOGGER_DESTINATION"|"SELFOSS_LOGGER_SIZE_TARGET"|"SELFOSS_LOGGER_SIZE_MAX")
            continue
            ;;

        "SELFOSS_LOGGER_FILE")
            NAME="SELFOSS_LOGGER_DESTINATION"
            VALUE="file:$VALUE"
            ;;
    esac

    if echo "$NAME" | grep -q '^SELFOSS_[A-Z0-9][A-Z0-9_]*$'; then
        NAME="$(echo "${NAME:8}" | tr '[:upper:]' '[:lower:]')"
        printf "%s=%s\n" "$NAME" "$VALUE" >> "/var/www/html/config.ini"
    fi
done
