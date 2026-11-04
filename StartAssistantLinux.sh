#!/bin/sh
set -eu

# Run from the mod root even when launched from another directory.
CDPATH= cd -P "$(dirname "$0")"

if ! command -v python3 >/dev/null 2>&1 || ! python3 -B -c 'import sys; sys.exit(sys.version_info < (3, 10))'; then
    printf '%s\n' 'The companion assistant requires Python 3.10 or newer. Install python3 on the server and try again.' >&2
    exit 1
fi

exec python3 -B -m tools.companion_bridge --headless --provider deepseek-api "$@"
