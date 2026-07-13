#!/usr/bin/env bash
# Build the DEPLOYED regional merchant index from the full global index.
# The full 461MB/30-country index is too large for a Cloud Function; we ship a
# region-filtered subset (Baltics + Nordics + Poland — the LT user base + travel)
# that is ~51MB on disk (~7MB gzipped) and disk-read (no RAM cost).
# Re-run whenever the full index is rebuilt.
set -euo pipefail
SRC="${1:-tools/kb_build/cache/prod/merchant_index.sqlite}"
OUT="functions/kb/merchant_index.sqlite"
COUNTRIES="'LT','LV','EE','PL','NO','SE','FI','DK'"
rm -f "$OUT"
sqlite3 "$OUT" "ATTACH '$SRC' AS src;
  CREATE TABLE merchants (norm TEXT PRIMARY KEY, n3 TEXT, entity TEXT);
  INSERT INTO merchants SELECT norm,n3,entity FROM src.merchants
    WHERE json_extract(entity,'\$.country_coverage[0]') IN ($COUNTRIES);
  CREATE INDEX i_n3 ON merchants(n3);"
sqlite3 "$OUT" "VACUUM;"
echo "built $OUT: $(sqlite3 "$OUT" 'SELECT COUNT(*) FROM merchants;') rows, $(ls -lh "$OUT" | awk '{print $5}')"
