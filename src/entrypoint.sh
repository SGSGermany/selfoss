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

set -e

[ $# -gt 0 ] || set -- php-fpm "$@"
if [ "$1" == "php-fpm" ]; then
    # setup Selfoss, if necessary
    /usr/lib/selfoss/setup.sh

    # unset forbidden Selfoss env variables
    # use container secrets instead
    unset \
        SELFOSS_DB_TYPE selfoss_db_type \
        SELFOSS_DB_HOST selfoss_db_host \
        SELFOSS_DB_PORT selfoss_db_port \
        SELFOSS_DB_FILE selfoss_db_file \
        SELFOSS_DB_SOCKET selfoss_db_socket \
        SELFOSS_DB_USERNAME selfoss_db_username \
        SELFOSS_DB_PASSWORD selfoss_db_password \
        SELFOSS_DB_DATABASE selfoss_db_database \
        SELFOSS_DB_PREFIX selfoss_db_prefix \
        SELFOSS_PUBLIC selfoss_public \
        SELFOSS_USERNAME selfoss_username \
        SELFOSS_PASSWORD selfoss_password \
        SELFOSS_SALT selfoss_salt

    # initialize config
    /usr/lib/selfoss/config.sh

    # truncate logfile
    /usr/lib/selfoss/truncate-logs.sh

    # run crond
    crond -f -l 7 -L /dev/stdout &

    exec "$@"
fi

exec "$@"
