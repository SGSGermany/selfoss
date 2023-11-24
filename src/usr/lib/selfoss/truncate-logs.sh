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

SELFOSS_DATADIR="/var/www/html/data"

SELFOSS_LOGGER_FILE="${SELFOSS_LOGGER_FILE:-$SELFOSS_DATADIR/logs/default.log}"
SELFOSS_LOGGER_SIZE_TARGET="${SELFOSS_LOGGER_SIZE_TARGET:-250000}"
SELFOSS_LOGGER_SIZE_MAX="${SELFOSS_LOGGER_SIZE_MAX:-2000000}"

SELFOSS_LOGGER_FILE="$(echo "$SELFOSS_LOGGER_FILE" \
    | sed -e "s/%datadir%/$(printf '%s\n' "$SELFOSS_DATADIR" | sed -e 's/[\/&]/\\&/g')/g")"

REGEX_DATETIME="([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{6}\+[0-9]{2}:[0-9]{2})"
REGEX_LOGLEVEL="(EMERGENCY|ALERT|CRITICAL|ERROR|WARNING|NOTICE|INFO|DEBUG|NONE)"

if [ -f "$SELFOSS_LOGGER_FILE" ]; then
    if [ "$(stat -c %s "$SELFOSS_LOGGER_FILE")" -gt "$SELFOSS_LOGGER_SIZE_MAX" ]; then
        if [ $SELFOSS_LOGGER_SIZE_TARGET -ne -1 ]; then
            SELFOSS_LOGGER_TMPFILE="$(mktemp)"

            tac "$SELFOSS_LOGGER_FILE" | while IFS= read -r LINE; do
                if echo "$LINE" | grep -q -E "^\[$REGEX_DATETIME\] selfoss.$REGEX_LOGLEVEL: "; then
                    if [ "$(stat -c %s "$SELFOSS_LOGGER_TMPFILE")" -gt "$SELFOSS_LOGGER_SIZE_TARGET" ]; then
                        break
                    fi
                fi

                printf '%s\n' "$LINE" >> "$SELFOSS_LOGGER_TMPFILE"
            done || true

            tac "$SELFOSS_LOGGER_TMPFILE" > "$SELFOSS_LOGGER_FILE"
            rm "$SELFOSS_LOGGER_TMPFILE"
        else
            printf '' > "$SELFOSS_LOGGER_FILE"
        fi
    fi
fi
