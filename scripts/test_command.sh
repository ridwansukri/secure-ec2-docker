#!/bin/bash
# Wrapper to keep compatibility with README/instructions referring to test_command.sh
# This delegates to the main local validation script.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/test_commands.sh" "$@"
