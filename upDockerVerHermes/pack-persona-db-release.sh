#!/bin/bash
# ============================================================
# pack-persona-db-release.sh
# Generate persona-db-rel-1.0.tar.gz for deployment
# Run this from ~/persona-db/ after making changes
# ============================================================

set -e

SRC_DIR="${1:-$(pwd)}"
OUTPUT="${2:-$SRC_DIR/persona-db-rel-1.0.tar.gz}"

echo "📦 Packing persona-db release from: $SRC_DIR"
echo "   Output: $OUTPUT"

cd "$SRC_DIR"

tar czf "$OUTPUT" \
  --exclude='.git' \
  --exclude='worklogs' \
  --exclude='references' \
  --exclude='concepts' \
  --exclude='api/test-*.json' \
  --exclude='api/debug*.py' \
  --exclude='api/run_*.py' \
  --exclude='api/bank-*.json' \
  --exclude='api/multi-*.json' \
  --exclude='setup-gitea-mirror.sh' \
  --exclude='deploy-from-mirror.sh' \
  --exclude='pack-persona-db-release.sh' \
  --transform='s|^|persona-db-rel-1.0/|' \
  .

echo "✅ Release packed: $(ls -lh "$OUTPUT" | awk '{print $5}')"
