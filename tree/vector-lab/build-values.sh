#!/usr/bin/env bash
# build-values.sh — regenerate the MITRE map embedded in values.yaml
# from a kubescape default-rules.yaml. Run when rules change.
#
# Usage:
#   ./build-values.sh /path/to/default-rules.yaml
#
# The script extracts (id, mitreTactic, mitreTechnique) per rule and
# rewrites the `mitre_map = {...}` block inside values.yaml in place.
# A timestamped backup is saved as values.yaml.bak-<epoch>.
#
# Why this exists: armoapi-go's BaseRuntimeAlert struct does not carry
# MitreTactic / MitreTechnique fields, so node-agent never propagates
# them to its exporters. Until that is fixed upstream, vector enriches
# the alert with values looked up by RuleID. Rules change rarely, so a
# static map regenerated on demand is enough.

set -euo pipefail

RULES=${1:?usage: $0 <default-rules.yaml>}
DIR=$(cd "$(dirname "$0")" && pwd)
VALUES=$DIR/values.yaml

[[ -f $RULES  ]] || { echo "FATAL: rules file not found or not a regular file: $RULES" >&2; exit 1; }
[[ -f $VALUES ]] || { echo "FATAL: values.yaml not at $VALUES" >&2; exit 1; }
command -v python3 >/dev/null || { echo "FATAL: python3 not found" >&2; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "FATAL: PyYAML missing — apt install python3-yaml" >&2; exit 1; }

FRAGMENT=$(python3 - "$RULES" <<'PY'
import yaml, sys
with open(sys.argv[1]) as f:
    d = yaml.safe_load(f)
rows = []
for r in d.get('spec', {}).get('rules', []):
    rid = r['id']
    t   = r.get('mitreTactic',   '')
    tt  = r.get('mitreTechnique','')
    rows.append(f'          "{rid}": {{"tactic": "{t}", "technique": "{tt}"}}')
print('        mitre_map = {')
print(',\n'.join(rows))
print('        }')
PY
)

cp "$VALUES" "$VALUES.bak-$(date +%s)"

python3 - "$VALUES" "$FRAGMENT" <<'PY'
import re, sys
path, fragment = sys.argv[1], sys.argv[2]
src = open(path).read()
# Replace the existing mitre_map block (10-spaces indent, opens with
# "mitre_map = {", closes at the matching brace on its own line).
new = re.sub(
    r'        mitre_map = \{[\s\S]*?^        \}',
    fragment,
    src,
    count=1,
    flags=re.MULTILINE,
)
if new == src:
    sys.stderr.write("FATAL: mitre_map block not found in values.yaml; edit it manually first.\n")
    sys.exit(1)
with open(path, 'w') as f:
    f.write(new)
PY

echo "rewrote $VALUES (backup: $VALUES.bak-*)"
