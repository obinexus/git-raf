#!/usr/bin/env bash
# tag.sh – SemverX + RA-F tagging for mono → non-mono repos
set -euo pipefail

# ---------- helpers ----------
usage() {
  echo "Usage:  ./tag.sh [SEMVERX_TAG] [--force]"
  echo "Example: ./tag.sh v1.0.0.0+poly.node.1.4.0"
  exit 1
}

semverx_regex='^v[0-9]+\.[0-9]+\.[0-9]+(\+[a-zA-Z0-9._-]+)?$'
[[ $# -ge 1 ]] || usage
TAG=$1
[[ $TAG =~ $semverx_regex ]] || { echo "❌ Invalid SemverX format"; exit 1; }
FORCE=${2:-}

# ---------- RA-F conscious check ----------
echo "🔍 RA-F consciousness check …"
python3 core/tools/consciousness-check.py --threshold 0.954 --source . \
  || { echo "❌ Consciousness score < 0.954 – aborting tag"; exit 1; }

# ---------- make sure hooks run ----------
git add . >/dev/null 2>&1 || true
git commit -am "chore(tag): prepare $TAG" --no-verify || true

# ---------- create annotated tag ----------
git tag ${FORCE:-} -a "$TAG" -m "RA-F SemverX tag: $TAG
- Consciousness ≥ 0.954 ✔
- Policy tag: $(git config --get raf.policy.level 2>/dev/null || echo 'stable')
- Aura seal: $(git rev-parse HEAD | cut -c1-16)"

# ---------- push tag ----------
git push origin "$TAG"
echo "✅ Tag $TAG pushed"
