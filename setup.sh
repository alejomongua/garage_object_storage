#!/usr/bin/env bash
set -euo pipefail

TEMPLATE=config/garage.toml.tpl
OUT=config/garage.toml
ENV_FILE=.env

# Backup existing .env if present
if [ -f "$ENV_FILE" ]; then
  cp "$ENV_FILE" "${ENV_FILE}.bak.$(date +%s)"
fi

# Load existing variables (auto-export)
set -a
if [ -f "$ENV_FILE" ]; then
  . "$ENV_FILE"
fi
set +a

# Generators
generate_rpc() { openssl rand -hex 32; }
generate_token() { openssl rand -base64 32; }

RPC_SECRET="${RPC_SECRET:-}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
METRICS_TOKEN="${METRICS_TOKEN:-}"

# Generate missing secrets
if [ -z "$RPC_SECRET" ]; then
  RPC_SECRET="$(generate_rpc)"
fi
if [ -z "$ADMIN_TOKEN" ]; then
  ADMIN_TOKEN="$(generate_token)"
fi
if [ -z "$METRICS_TOKEN" ]; then
  METRICS_TOKEN="$(generate_token)"
fi

# Write exported variables to .env (idempotent replacement)
cat > "$ENV_FILE" <<EOF
export RPC_SECRET=$RPC_SECRET
export ADMIN_TOKEN=$ADMIN_TOKEN
export METRICS_TOKEN=$METRICS_TOKEN
EOF

echo "Wrote $ENV_FILE (previous file backed up if it existed)."

# Export and render template
set -a
. "$ENV_FILE"
set +a

if command -v envsubst >/dev/null 2>&1; then
  envsubst < "$TEMPLATE" > "$OUT"
  echo "Rendered $OUT with envsubst"
else
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import os
from string import Template
tpl_path = "config/garage.toml.tpl"
out_path = "config/garage.toml"
tpl = Template(open(tpl_path).read())
open(out_path, "w").write(tpl.safe_substitute(os.environ))
print("Rendered {} with python3".format(out_path))
PY
  else
    echo "Error: neither envsubst nor python3 available to render template" >&2
    exit 1
  fi
fi

# Basic validation
len=$(printf "%s" "$RPC_SECRET" | wc -c)
if [ "$len" -ne 64 ]; then
  echo "Warning: RPC_SECRET length is $len characters; expected 64 (32 bytes hex)" >&2
fi

echo "Setup complete. Start services with: docker-compose up -d"