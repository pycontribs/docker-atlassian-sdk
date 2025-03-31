#!/bin/bash -e
# cspell: ignore exuo,outdir,aarch64,iname,buildx
set -exuo pipefail


CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}

# Identify the architecture in format used by the container engines because
# `arch` command returns either arm64 or aarch64 depending on the system
ARCH=$(arch)
if [ "$ARCH" == "aarch64" ] || [ "$ARCH" == "arm64" ]; then
    ARCH="arm64"
elif [ "$ARCH" == "x86_64" ]; then
    ARCH="amd64"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

REPO_DIR=$(git rev-parse --show-toplevel)

ORG=pycontribs
CONTAINER_NAME=atlassian-sdk
TAG_BASE=${CONTAINER_NAME}:latest
# keep the localhost/ prefix on image name all the time or we will face various
# problems related to docker/podman differences when this is missing.
IMAGE_NAME=localhost/${CONTAINER_NAME}:test

# BUILD_CMD="podman build --squash-all"
BUILD_CMD="${CONTAINER_ENGINE} buildx build --progress=plain"

# Publish should run on CI only on main branch, with or without release tag
if [ "--publish" == "${1:-}" ]; then
    if [ -z "${2:-}" ]; then
        echo "Please also pass the tag to be published for the merged image. Source image will use the sha tag."
        exit 1
    fi

    if [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${GITHUB_ACTOR:-}" ]; then
        echo "${GITHUB_TOKEN:-}" | ${CONTAINER_ENGINE} login ghcr.io -u "${GITHUB_ACTOR:-}" --password-stdin
    fi
    if [ -z "${GITHUB_SHA:-}" ]; then
        echo "Unable to find GITHUB_SHA variable."
        exit 1
    fi
    ${CONTAINER_ENGINE} pull -q "ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA:-}-arm64"
    ${CONTAINER_ENGINE} pull -q "ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA:-}-amd64"

    for TAG in ghcr.io/$ORG/${CONTAINER_NAME}:${2:-} ghcr.io/$ORG/${CONTAINER_NAME}:latest; do
        ${CONTAINER_ENGINE} manifest create "$TAG" --amend "ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA:-}-amd64" --amend "ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA:-}-arm64"
        ${CONTAINER_ENGINE} manifest annotate --arch arm64 "$TAG" "ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA:-}-arm64"

        # We push only when there is a release, and that is when $2 is not the same as GITHUB_SHA
        if [ "--dry" != "${3:-}" ]; then
            ${CONTAINER_ENGINE} manifest push "$TAG"
        fi
    done
    exit 0
fi

# # Code for building the container (call script again with --publish to merge and push already build container)
# if [ -d "$REPO_DIR/final/dist/" ]; then
#     find "$REPO_DIR/final/dist/" -type f -delete
# fi
# $BUILD_CMD -f context/Containerfile context/ --tag "${TAG_BASE}"
# ln -f tools/setup-image.sh final/
$BUILD_CMD . --tag "${IMAGE_NAME}"

# We save local image in order to import it inside the container later for c-in-c testing
# Do not try to gzip the image because there is no notable change in size and
# it seems to add ~20% more in total test execution time.
$CONTAINER_ENGINE save $IMAGE_NAME > image.tar

# Check container size and layers
# mk containers check "$IMAGE_NAME" --engine="${CONTAINER_ENGINE}" --max-size=1500 --max-layers=22

if [[ -n "${GITHUB_SHA:-}" && "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
    FQ_IMAGE_NAME="ghcr.io/$ORG/${CONTAINER_NAME}-tmp:${GITHUB_SHA}-$ARCH"
    $CONTAINER_ENGINE tag $IMAGE_NAME "${FQ_IMAGE_NAME}"
    # https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_ACTOR" --password-stdin
    fi
    $CONTAINER_ENGINE push "${FQ_IMAGE_NAME}"
fi
