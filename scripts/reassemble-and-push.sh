#!/usr/bin/env bash
# Run on a Docker-capable machine that can access repo-sec.nexus.local:31920.
# Place extracted GitHub artifacts into ./parts/ and ./metadata/ first.
set -euo pipefail
cd "$(dirname "$0")/.."
( cd parts && sha256sum -c ../metadata/parts.sha256 )
cat parts/nexus-image.tar.gz.part-* > nexus-image.tar.gz
sha256sum -c metadata/archive.sha256
IMAGE="$(cat metadata/image-name.txt)"
docker load -i nexus-image.tar.gz
TARGET="repo-sec.nexus.local:31920/${IMAGE}"
docker tag "$IMAGE" "$TARGET"
docker login repo-sec.nexus.local:31920
docker push "$TARGET"
