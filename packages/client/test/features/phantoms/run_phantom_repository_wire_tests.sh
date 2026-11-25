#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.."
exec scripts/run_tests.sh client-files test/features/phantoms/phantom_repository_wire_contract_test.dart "$@"
