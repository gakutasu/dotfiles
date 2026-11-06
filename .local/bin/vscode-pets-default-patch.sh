#!/bin/sh
# Patch vscode-pets defaults:
# - the webview starts a workspace without saved pet state with the pets
#   listed below instead of one random pet from the settings
# - vscode-pets.petSize defaults to DEFAULT_SIZE instead of nano, in every
#   profile that does not set it
# Extension updates replace the patched files, so this re-runs from
# vscode-pets-default-patch.path whenever ~/.vscode/extensions changes.
# Safe to re-run: already patched files are skipped.
set -eu

# type:color:name (one per line)
DEFAULT_PETS='cat:ginger_tabby:ベガ
cat:silver_tabby:ポポ'
DEFAULT_SIZE='medium'

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

for manifest in "$HOME"/.vscode/extensions/tonybaloney.vscode-pets-*/package.json; do
    [ -f "$manifest" ] || continue
    DEFAULT_SIZE="$DEFAULT_SIZE" python3 - "$manifest" <<'PY' || status=1
import json, os, sys

path = sys.argv[1]
size = os.environ['DEFAULT_SIZE']
with open(path, encoding='utf-8') as f:
    manifest = json.load(f)

config = manifest['contributes']['configuration']
props = [section['properties']['vscode-pets.petSize']
         for section in (config if isinstance(config, list) else [config])
         if 'vscode-pets.petSize' in section.get('properties', {})]
if len(props) != 1 or size not in props[0].get('enum', []):
    print(f'petSize setting not found, skipped: {path}', file=sys.stderr)
    sys.exit(1)
if props[0].get('default') == size:
    sys.exit(0)

props[0]['default'] = size
with open(path, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, ensure_ascii=False, indent='\t')
    f.write('\n')
print(f'patched: {path}')
PY
done
exit "$status"
