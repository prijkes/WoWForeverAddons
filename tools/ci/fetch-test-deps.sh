#!/usr/bin/env bash
# Downloads the pinned third-party addons that Forever Addon Fixes' smoke tests run against, checks
# each file's sha256, and unpacks it into <dest>/<name>/. These addons are not part of this
# repository; only their CurseForge files are referenced here.
# Usage: tools/ci/fetch-test-deps.sh <dest>
set -euo pipefail
dest=${1:?usage: fetch-test-deps.sh <dest>}
mkdir -p "$dest"

# name | CurseForge file id | file name (URL-encoded) | sha256 | path that must exist after unpacking
PINS=(
  "GearQuestForever-0.2.11-beta|8974792|GearQuestForever-v0.2.11-beta.zip|389c5bf70e490a9512389caf55c4c58206037279a9d9ae648bd3f0c1c06a601c|GearQuestForever/GearQuestForever.toc"
  "GearQuestForever-0.2.6-beta|8934503|GearQuestForever-v0.2.6-beta.zip|fe6f8c75a2f700b19a436e31e7229ae448221a4b2311c02a31ab8655cfec5fda|GearQuestForever/GearQuestForever.toc"
  "AtlasLootClassic-1.1.1|8967063|AtlasLoot%20Classic%20Forever%201.1.1-240926-11601-11509.zip|68b259c1f432b46546a56784b1b3cd74efcebba3ea26d732c93d32c2ab68ca02|AtlasLootClassic/Data/VendorPrice.lua"
  "AtlasLootClassic-1.0.7|8922115|AtlasLoot%20Classic%20Forever%201.0.7-190926-11601-11509.zip|f219e49d1d4d1f2f470bc6fb1d4e74332f368cfc004d78f9c947c283e620ea63|AtlasLootClassic/Data/VendorPrice.lua"
)
# edge.forgecdn.net currently redirects to mediafilez; it stays as a second entry in case that changes.
HOSTS=(mediafilez.forgecdn.net edge.forgecdn.net)

for pin in "${PINS[@]}"; do
  IFS='|' read -r name fid file sha check <<<"$pin"
  zip="$dest/$name.zip"
  # CurseForge's CDN path: files/<id / 1000>/<id % 1000>/<file name>, e.g. 8967063 -> files/8967/63/.
  path="files/$((fid / 1000))/$((fid % 1000))/$file"
  ok=
  for host in "${HOSTS[@]}"; do
    if curl -fsSL --retry 3 --retry-delay 5 --max-time 300 -o "$zip" "https://$host/$path"; then
      got=$(sha256sum "$zip" | cut -d' ' -f1)
      if [ "$got" = "$sha" ]; then ok=1; break; fi
      echo "warning: $name from $host has sha256 $got, expected $sha" >&2
    else
      echo "warning: downloading $name from $host failed" >&2
    fi
  done
  if [ -z "$ok" ]; then
    echo "error: could not download $name with the pinned sha256" >&2
    exit 1
  fi
  rm -rf "${dest:?}/$name"
  mkdir -p "$dest/$name"
  unzip -q "$zip" -d "$dest/$name"
  if [ ! -f "$dest/$name/$check" ]; then
    echo "error: $name has no $check after unpacking" >&2
    exit 1
  fi
  echo "$name -> $dest/$name"
done
