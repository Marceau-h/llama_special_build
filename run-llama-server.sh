#!/usr/bin/env bash
set -euo pipefail
D="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$D/../lib:${LD_LIBRARY_PATH:-}"
exec "$D/llama-server" "$@"
