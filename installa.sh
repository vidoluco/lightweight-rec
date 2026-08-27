#!/bin/bash
# Back-compat wrapper for the old Italian name.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh" "$@"
