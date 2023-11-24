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

[ -x "$(which jq 2>/dev/null)" ] \
    || { echo "Missing build script dependency: jq" >&2; exit 1; }

source "$CI_TOOLS_PATH/helper/common.sh.inc"
source "$CI_TOOLS_PATH/helper/container.sh.inc"
source "$CI_TOOLS_PATH/helper/container-alpine.sh.inc"
source "$CI_TOOLS_PATH/helper/git.sh.inc"
source "$CI_TOOLS_PATH/helper/php.sh.inc"

BUILD_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
source "$BUILD_DIR/container.env"

readarray -t -d' ' TAGS < <(printf '%s' "$TAGS")

# build Selfoss
echo + "BUILD_CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
BUILD_CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "BUILD_MOUNT=\"\$(buildah mount $(quote "$BUILD_CONTAINER"))\"" >&2
BUILD_MOUNT="$(buildah mount "$BUILD_CONTAINER")"

if [ -n "${VERSION:-}" ] && [ -n "${HASH:-}" ]; then
    echo + "[[ $(quote "$VERSION") =~ ^([0-9]+\.[0-9]+-([a-f0-9]+))([+~-]|$) ]]" >&2
    if ! [[ "$VERSION" =~ ^([0-9]+\.[0-9]+-([a-f0-9]+))([+~-]|$) ]]; then
        echo "Invalid build environment: Environment variable 'VERSION' is invalid: $VERSION" >&2
        exit 1
    fi

    echo + "HASH_SHORT=\"\${BASH_REMATCH[2]}\"" >&2
    HASH_SHORT="${BASH_REMATCH[2]}"

    echo + "[[ $(quote "$HASH") =~ ^[a-f0-9]{40}[a-f0-9]{24}?$ ]]" >&2
    if ! [[ "$HASH" =~ ^[a-f0-9]{40}[a-f0-9]{24}?$ ]]; then
        echo "Invalid build environment: Environment variable 'HASH' is invalid: $HASH" >&2
        exit 1
    fi

    echo + "[[ $(quote "$HASH") == $(quote "$HASH_SHORT")* ]]" >&2
    if [[ "$HASH" != "$HASH_SHORT"* ]]; then
        echo "Invalid build environment: Environment variables 'VERSION' (${VERSION@Q})" \
            "and 'HASH' (${HASH@Q}) contradict each other" >&2
        exit 1
    fi

    git_clone "$GIT_REPO" "$HASH" \
        "$BUILD_MOUNT/usr/src/selfoss" "<builder> …/usr/src/selfoss"
else
    git_clone "$GIT_REPO" "$GIT_REF" \
        "$BUILD_MOUNT/usr/src/selfoss" "<builder> …/usr/src/selfoss"

    echo + "HASH=\"\$(git -C '<builder> …/usr/src/selfoss' rev-parse HEAD)\"" >&2
    HASH="$(git -C "$BUILD_MOUNT/usr/src/selfoss" rev-parse HEAD)"

    echo + "HASH_SHORT=\"\$(git -C '<builder> …/usr/src/selfoss' rev-parse --short HEAD)\"" >&2
    HASH_SHORT="$(git -C "$BUILD_MOUNT/usr/src/selfoss" rev-parse --short HEAD)"

    echo + "VERSION=\"\$(jq -re '.ver | sub(\"(-SNAPSHOT|-[0-9a-f]+)$\"; \"\")' '<builder> …/usr/src/selfoss/package.json')-\$HASH_SHORT\"" >&2
    VERSION="$(jq -re '.ver | sub("(-SNAPSHOT|-[0-9a-f]+)$"; "")' "$BUILD_MOUNT/usr/src/selfoss/package.json")-$HASH_SHORT"
fi

pkg_install "$BUILD_CONTAINER" \
    curl \
    gnupg \
    git \
    python3 \
    npm

echo + "mkdir <builder> …/usr/src/composer" >&2
mkdir "$BUILD_MOUNT/usr/src/composer"

cmd buildah run "$BUILD_CONTAINER" -- \
    curl -L -f -o "/usr/src/composer/composer.phar" "$COMPOSER_PHAR"

cmd buildah run "$BUILD_CONTAINER" -- \
    curl -L -f -o "/usr/src/composer/composer.phar.asc" "$COMPOSER_PHAR_ASC"

for COMPOSER_GPG_KEY in $COMPOSER_GPG_KEYS; do
    cmd buildah run "$BUILD_CONTAINER" -- \
        gpg --keyserver "keyserver.ubuntu.com" --recv-keys "$COMPOSER_GPG_KEY"
done

cmd buildah run "$BUILD_CONTAINER" -- \
    gpg --verify "/usr/src/composer/composer.phar.asc" "/usr/src/composer/composer.phar"

cmd buildah run "$BUILD_CONTAINER" -- \
    mv "/usr/src/composer/composer.phar" "/usr/local/bin/composer"

cmd buildah run "$BUILD_CONTAINER" -- \
    chmod +x "/usr/local/bin/composer"

cmd buildah config \
    --env COMPOSER_ALLOW_SUPERUSER=1 \
    --env COMPOSER_IGNORE_PLATFORM_REQS=1 \
     "$BUILD_CONTAINER"

cmd buildah run --workingdir "/usr/src/selfoss" "$BUILD_CONTAINER" -- \
    npm run dist

cmd buildah run "$BUILD_CONTAINER" -- \
    test -f "/usr/src/selfoss/selfoss-$VERSION.zip"

# setup target image
echo + "CONTAINER=\"\$(buildah from $(quote "$BASE_IMAGE"))\"" >&2
CONTAINER="$(buildah from "$BASE_IMAGE")"

echo + "MOUNT=\"\$(buildah mount $(quote "$CONTAINER"))\"" >&2
MOUNT="$(buildah mount "$CONTAINER")"

echo + "rsync -v -rl --exclude .gitignore ./src/ …/" >&2
rsync -v -rl --exclude '.gitignore' "$BUILD_DIR/src/" "$MOUNT/"

# runtime setup
pkg_install "$CONTAINER" --virtual .selfoss-run-deps \
    rsync

php_install_ext "$CONTAINER" \
    pdo_mysql \
    gd

user_add "$CONTAINER" mysql 65538

echo + "rm …/etc/crontabs/root" >&2
rm "$MOUNT/etc/crontabs/root"

echo + "echo '5-59/10 * * * * php -f /var/www/html/cliupdate.php > /dev/null 2>&1' > …/etc/crontabs/www-data" >&2
echo '5-59/10 * * * * php -f /var/www/html/cliupdate.php > /dev/null 2>&1' > "$MOUNT/etc/crontabs/www-data"

# copy Selfoss sources to target image
echo + "cp $(quote "<builder> …/usr/src/selfoss/selfoss-$VERSION.zip") …/usr/src/selfoss/selfoss.zip" >&2
cp "$BUILD_MOUNT/usr/src/selfoss/selfoss-$VERSION.zip" "$MOUNT/usr/src/selfoss/selfoss.zip"

cmd buildah run --workingdir "/usr/src/selfoss" "$CONTAINER" -- \
    unzip "selfoss.zip"

cmd buildah run "$CONTAINER" -- \
    rm "/usr/src/selfoss/selfoss.zip"

# finalize image
cmd buildah run "$CONTAINER" -- \
    /bin/sh -c "printf '%s=%s\n' \"\$@\" > /usr/src/selfoss/version_info" -- \
        VERSION "$VERSION" \
        HASH "$HASH"

cleanup "$CONTAINER"

cmd buildah config \
    --env SELFOSS_VERSION="$VERSION" \
    --env SELFOSS_HASH="$HASH" \
    "$CONTAINER"

cmd buildah config \
    --entrypoint '[ "/entrypoint.sh" ]' \
    "$CONTAINER"

cmd buildah config \
    --volume "/var/www" \
    --volume "/run/mysql" \
    "$CONTAINER"

cmd buildah config \
    --annotation org.opencontainers.image.title="Selfoss" \
    --annotation org.opencontainers.image.description="A php-fpm container running Selfoss, a RSS reader and feed aggregator." \
    --annotation org.opencontainers.image.version="$VERSION" \
    --annotation org.opencontainers.image.url="https://github.com/SGSGermany/php-fpm_u007" \
    --annotation org.opencontainers.image.authors="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.vendor="SGS Serious Gaming & Simulations GmbH" \
    --annotation org.opencontainers.image.licenses="proprietary" \
    --annotation org.opencontainers.image.base.name="$BASE_IMAGE" \
    --annotation org.opencontainers.image.base.digest="$(podman image inspect --format '{{.Digest}}' "$BASE_IMAGE")" \
    "$CONTAINER"

con_commit "$CONTAINER" "$IMAGE" "${TAGS[@]}"
