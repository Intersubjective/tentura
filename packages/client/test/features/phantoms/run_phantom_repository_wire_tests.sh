#!/usr/bin/env bash
# Bind the wire contract to the actual repository when it exists. Keeping the
# import in a temporary test entry point lets the pre-feature baseline fail at
# the unavailable repository, while the same command runs the real calls later.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
cd "$repo_root/packages/client"
test_dir="$PWD/test/features/phantoms"
driver_dir="$(mktemp -d "$test_dir/.wire-driver.XXXXXX")"
trap 'rm -f "$driver_dir/phantom_repository_wire_test.dart"; rmdir "$driver_dir"' EXIT
driver="$driver_dir/phantom_repository_wire_test.dart"

data_dir=lib/features/phantoms/data
repository_file=""
if [[ -d "$data_dir" ]]; then
  if repository_file="$(rg -l --glob '*.dart' '\bclass\s+PhantomRepository\b' "$data_dir")"; then
    :
  else
    status=$?
    if [[ "$status" != 1 ]]; then
      exit "$status"
    fi
  fi
fi

if [[ -n "$repository_file" ]]; then
  if [[ ! -f "$repository_file" ]]; then
    printf 'Expected one PhantomRepository declaration in %s\n' "$data_dir" >&2
    exit 1
  fi
  cat > "$driver" <<DART
import 'package:tentura/${repository_file#lib/}';

import '../phantom_repository_wire_contract.dart';

void main() => registerPhantomRepositoryWireTests(PhantomRepository.new);
DART
else
  cat > "$driver" <<'DART'
import '../phantom_repository_wire_contract.dart';

void main() => registerPhantomRepositoryWireTests((_) => null);
DART
fi

cd "$repo_root"
scripts/run_tests.sh client-files "${driver#"$repo_root/packages/client/"}" "$@"
