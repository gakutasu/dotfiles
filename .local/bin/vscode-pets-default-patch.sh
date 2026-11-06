#!/bin/sh
# Patch vscode-pets defaults:
# - the webview starts a workspace without saved pet state with the pets
#   listed below instead of one random pet from the settings
# - the settings in DEFAULT_SETTINGS get new defaults, which apply to every
#   profile that does not set them
# Extension updates replace the patched files, so this re-runs from
# vscode-pets-default-patch.path whenever ~/.vscode/extensions changes.
# Safe to re-run: already patched files are skipped.
set -eu

# type:color:name (one per line)
DEFAULT_PETS='cat:ginger_tabby:ベガ
cat:silver_tabby:ポポ'
# vscode-pets.<setting>=<JSON value> (one per line)
DEFAULT_SETTINGS='petSize="medium"
throwBallWithMouse=true'

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
    DEFAULT_SETTINGS="$DEFAULT_SETTINGS" python3 - "$manifest" <<'PY' || status=1
import json, os, sys

TYPES = {'string': str, 'boolean': bool}

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    manifest = json.load(f)

config = manifest['contributes']['configuration']
props = {}
for section in (config if isinstance(config, list) else [config]):
    props.update(section.get('properties', {}))

changed = False
for line in os.environ['DEFAULT_SETTINGS'].splitlines():
    key, value = line.strip().split('=', 1)
    key, value = f'vscode-pets.{key}', json.loads(value)
    prop = props.get(key)
    if (prop is None or not isinstance(value, TYPES.get(prop.get('type'), ()))
            or value not in prop.get('enum', [value])):
        print(f'{key} not found or {value!r} invalid, skipped: {path}', file=sys.stderr)
        sys.exit(1)
    if prop.get('default') != value:
        prop['default'] = value
        changed = True
if not changed:
    sys.exit(0)

with open(path, 'w', encoding='utf-8') as f:
    json.dump(manifest, f, ensure_ascii=False, indent='\t')
    f.write('\n')
print(f'patched: {path}')
PY
done
exit "$status"
