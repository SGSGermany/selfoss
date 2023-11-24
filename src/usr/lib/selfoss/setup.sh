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

if [ -e "/var/www/selfoss_version_info" ]; then
    OLD_HASH="$(sed -ne 's/^HASH=\(.*\)$/\1/p' /var/www/selfoss_version_info)"
    NEW_HASH="$(sed -ne 's/^HASH=\(.*\)$/\1/p' /usr/src/selfoss/version_info)"

    if [ -n "$OLD_HASH" ] && [ "$OLD_HASH" == "$NEW_HASH" ]; then
        exit
    fi

    OLD_VERSION="$(sed -ne 's/^VERSION=\(.*\)$/\1/p' /var/www/selfoss_version_info)"
else
    OLD_VERSION=""
fi

NEW_VERSION="$(sed -ne 's/^VERSION=\(.*\)$/\1/p' /usr/src/selfoss/version_info)"

if [ -z "$OLD_VERSION" ]; then
    echo "Initializing Selfoss $NEW_VERSION..."
else
    echo "Upgrading Selfoss $OLD_VERSION to $NEW_VERSION..."

    TMPDIR_DATA="$(mktemp -d)"
    rsync -rlptog \
        "/var/www/html/data/" \
        "$TMPDIR_DATA/"
fi

rsync -rlptog --delete --chown www-data:www-data \
    "/usr/src/selfoss/selfoss/" \
    "/var/www/html/"

rsync -lptog --chown www-data:www-data \
    "/usr/src/selfoss/version_info" \
    "/var/www/selfoss_version_info"

if [ -n "$OLD_VERSION" ]; then
    rsync -rlptog \
        "$TMPDIR_DATA/" \
        "/var/www/html/data/"
    rm -rf "$TMPDIR_DATA"
fi
