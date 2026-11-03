#!/bin/bash
set -euo pipefail

# Test-only encrypted, uncompressed ZIPs: large enough for overlapping extraction.
# Usage: bash Tests/create-parallel-zip-fixtures.sh [size-in-MiB]
size_mib=${1:-512}
[[ "$size_mib" =~ ^[1-9][0-9]*$ ]] || exit 2
fixture_dir=$(mktemp -d /tmp/EasyUnpack-ParallelZIP.XXXXXX)
mkdir -p "$fixture_dir/source" "$fixture_dir/A" "$fixture_dir/B"
mkfile -n "${size_mib}m" "$fixture_dir/source/parallel-A.bin"
mkfile -n "${size_mib}m" "$fixture_dir/source/parallel-B.bin"
for name in A B; do
    (cd "$fixture_dir/source" && zip -q -0 -P EasyUnpack-Test-2026 \
        "$fixture_dir/$name/parallel-$name.zip" "parallel-$name.bin")
done
shasum -a 256 "$fixture_dir/source/parallel-A.bin" "$fixture_dir/source/parallel-B.bin" > "$fixture_dir/expected-sha256.txt"
printf 'Fixtures: %s\nPassword: EasyUnpack-Test-2026\n' "$fixture_dir"
