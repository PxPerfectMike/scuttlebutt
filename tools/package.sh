#!/usr/bin/env bash
# Packages a release: runs the test suite (real Lua 5.1, the gossip simulation and the smoke
# test), checks the CHANGELOG has an entry for the version, and zips Scuttlebutt/ into
# dist/Scuttlebutt-<version>.zip.
#   PYLIBS=<folder with lupa> tools/package.sh
set -euo pipefail

PY=${PY:-"/c/Program Files/Python313/python.exe"}
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

version=$(sed -n 's/^## Version: *\([^ \r]*\).*/\1/p' Scuttlebutt/Scuttlebutt.toc)
[ -n "$version" ] || { echo "no ## Version in Scuttlebutt.toc"; exit 1; }
grep -q "^## $version\b" CHANGELOG.md || { echo "CHANGELOG.md has no entry for $version"; exit 1; }

"$PY" tests/run.py > /dev/null 2>&1 || { "$PY" tests/run.py 2>&1 | grep -a -E "^FAIL|passed,"; exit 1; }

"$PY" - "$REPO" "$version" <<'PYEOF'
import os, sys, zipfile
repo, version = sys.argv[1], sys.argv[2]
out = os.path.join(repo, "dist", f"Scuttlebutt-{version}.zip")
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
	for root, _, files in os.walk(os.path.join(repo, "Scuttlebutt")):
		for f in sorted(files):
			full = os.path.join(root, f)
			z.write(full, os.path.relpath(full, repo).replace(os.sep, "/"))
print(f"wrote {out}: {os.path.getsize(out) / 1e3:.0f} KB")
PYEOF
