#!/bin/zsh
# Builds the Apple-hosted asset pack that carries the on-device model.
# Usage: Tools/ModelAssetPack/package.sh
# Output: build/AssetPacks/AquinasModel.aar, ready to upload with Transporter.
# The model file named in manifest.json must match LiteRTModelManifest.aquinas (file name, size,
# and SHA-256); the script checks the size and prints the digest to compare.
set -euo pipefail
ROOT=${0:A:h:h:h}
MANIFEST=$ROOT/Tools/ModelAssetPack/manifest.json
MODEL=$ROOT/$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['fileSelectors'][0]['fileSource'])" $MANIFEST)
OUT=$ROOT/build/AssetPacks/AquinasModel.aar

[[ -f $MODEL ]] || { echo "missing model: $MODEL" >&2; exit 1; }
EXPECTED=$(grep -A3 "static let aquinas" $ROOT/Aquinas-iOS/Services/LiteRTModelStore.swift | grep byteCount | tr -dc '0-9')
ACTUAL=$(stat -f%z $MODEL)
[[ $EXPECTED == $ACTUAL ]] || { echo "size $ACTUAL does not match manifest $EXPECTED" >&2; exit 1; }
echo "model: $MODEL ($ACTUAL bytes)"
echo "sha256: $(shasum -a 256 $MODEL | cut -d' ' -f1)"

mkdir -p ${OUT:h}
rm -f $OUT
xcrun ba-package evaluate $MANIFEST
xcrun ba-package package $MANIFEST --output-path $OUT
ls -la $OUT
