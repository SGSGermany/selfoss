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
{
    printf '[globals]\n';
    printf 'env_prefix=selfoss_\n';
} > "/var/www/html/config.ini"

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
        printf '\n';
        printf 'db_type=mysql\n';
        printf 'db_socket=/run/mysql/mysql.sock\n';
        [ -z "$MYSQL_USER" ] || printf "db_username=%s\n" "$MYSQL_USER";
        [ -z "$MYSQL_PASSWORD" ] || printf "db_password=%s\n" "$MYSQL_PASSWORD";
        [ -z "$MYSQL_DATABASE" ] || printf "db_database=%s\n" "$MYSQL_DATABASE";
        [ -z "$MYSQL_TABLE_PREFIX" ] || printf "db_prefix=%s\n" "$MYSQL_TABLE_PREFIX";
    } >> "/var/www/html/config.ini"
else
    {
        printf '\n';
        printf 'db_type=sqlite\n';
        printf 'db_file=%%datadir%%/sqlite/selfoss.db\n';
    } >> "/var/www/html/config.ini"
fi

# auth config
AUTH_PUBLIC="$(read_secret "selfoss_auth_public")"
AUTH_USER="$(read_secret "selfoss_auth_user")"
AUTH_PASSWORD="$(read_secret "selfoss_auth_password")"

if [ -n "$AUTH_PUBLIC" ]; then
    [ "$AUTH_PUBLIC" == "1" ] \
        && AUTH_PUBLIC=1 \
        || AUTH_PUBLIC=0
fi

if [ -n "$AUTH_PUBLIC" ] || [ -n "$AUTH_USER" ] || [ -n "$AUTH_PASSWORD" ]; then
    {
        printf '\n';
        [ -z "$AUTH_PUBLIC" ] || printf "public=%s\n" "$AUTH_PUBLIC";
        [ -z "$AUTH_USER" ] || printf "username=%s\n" "$AUTH_USER";
        [ -z "$AUTH_PASSWORD" ] || printf "password=%s\n" "$AUTH_PASSWORD";
    } >> "/var/www/html/config.ini"
fi