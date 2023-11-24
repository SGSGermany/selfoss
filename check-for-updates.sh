#!/bin/bash
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

[ -v CI_TOOLS ] && [ "$CI_TOOLS" == "SGSGermany" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS' not set or invalid" >&2; exit 1; }

[ -v CI_TOOLS_PATH ] && [ -d "$CI_TOOLS_PATH" ] \
    || { echo "Invalid build environment: Environment variable 'CI_TOOLS_PATH' not set or invalid" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/common-traps.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"
source "$CI_TOOLS_PATH/helper/chkupd.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

TAG="${TAGS%% *}"

# check whether the base image was updated
chkupd_baseimage "$REGISTRY/$OWNER/$IMAGE" "$TAG" || exit 0

# check whether the image is using the latest Selfoss dev version
if [ -z "${VERSION:-}" ]; then
    # check whether the Git repository indicates a new version
    echo + "SOURCE_DIR=\"\$(mktemp -d)\"" >&2
    SOURCE_DIR="$(mktemp -d)"

    trap_exit rm -rf "$SOURCE_DIR"

    git_clone "$GIT_REPO" "$GIT_REF" \
        "$SOURCE_DIR" "$SOURCE_DIR"

    echo + "VERSION=\"\$(jq -re '.ver | sub(\"(-SNAPSHOT|-[0-9a-f]+)$\"; \"\")' -C $(quote "$SOURCE_DIR/package.json")\"" >&2
    VERSION="$(jq -re '.ver | sub("(-SNAPSHOT|-[0-9a-f]+)$"; "")' "$SOURCE_DIR/package.json")"

    if [ -z "$VERSION" ]; then
        echo "Unable to read Selfoss version from '$SOURCE_DIR/package.json': Version not found" >&2
        exit 1
    elif ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "Unable to read Selfoss version from '$SOURCE_DIR/package.json': '$VERSION' is no valid version" >&2
        exit 1
    fi

    echo + "HASH_SHORT=\"\$(git -C $(quote "$SOURCE_DIR") rev-parse --short HEAD)\"" >&2
    HASH_SHORT="$(git -C "$SOURCE_DIR" rev-parse --short HEAD)"

    echo + "VERSION=\"$VERSION-$HASH_SHORT\"" >&2
    VERSION="$VERSION-$HASH_SHORT"
fi

chkupd_image_version "$REGISTRY/$OWNER/$IMAGE:$TAG" "$VERSION" || exit 0
