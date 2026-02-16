#!/bin/bash
# Install git hooks for this repository.
# Run once after cloning: ./scripts/install-hooks.sh

set -euo pipefail
cd "$(dirname "$0")/.."

cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo "Git hooks installed:"
echo "  .git/hooks/pre-commit -> auto-bumps template version on blueprint changes"
