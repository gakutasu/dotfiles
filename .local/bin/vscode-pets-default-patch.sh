#!/bin/sh
# Patch the vscode-pets webview so a workspace without saved pet state starts
# with the pets listed below instead of one random pet from the settings.
# Extension updates replace the patched bundle, so this re-runs from
# vscode-pets-default-patch.path whenever ~/.vscode/extensions changes.
# Safe to re-run: already patched bundles are skipped.
set -eu

# type:color:name (one per line)
DEFAULT_PETS='cat:ginger_tabby:ベガ
cat:silver_tabby:ポポ'

status=0
for bundle in "$HOME"/.vscode/extensions/tonybaloney.vscode-pets-*/media/main-bundle.js; do
    [ -f "$bundle" ] || continue
    DEFAULT_PETS="$DEFAULT_PETS" python3 - "$bundle" <<'PY' || status=1
import json, os, sys

MARKER = '/* vscode-pets-default-patch */'
ANCHOR = ("exports.allPets.push(addPetToPanel(petType, basePetUri, petColor, petSize, "
          "randomStartPosition(), floor, floor, (0, names_1.randomName)(petType), stateApi));")

path = sys.argv[1]
src = open(path, encoding='utf-8').read()
if MARKER in src:
    sys.exit(0)
if src.count(ANCHOR) != 1:
    print(f'anchor not found, skipped: {path}', file=sys.stderr)
    sys.exit(1)

pets = []
for line in os.environ['DEFAULT_PETS'].splitlines():
    type_, color, name = line.strip().split(':', 2)
    pets.append({'type': type_, 'color': color, 'name': name})

# ensure_ascii keeps the bundle ASCII-only regardless of webview charset handling
replacement = (
    f"{MARKER} {json.dumps(pets)}.forEach((p) => {{ "
    "exports.allPets.push(addPetToPanel(p.type, basePetUri, p.color, petSize, "
    "randomStartPosition(), floor, floor, p.name, stateApi)); }); "
    f"petCounter = {len(pets)};"
)
open(path, 'w', encoding='utf-8').write(src.replace(ANCHOR, replacement))
print(f'patched: {path}')
PY
done
exit "$status"
