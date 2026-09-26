#!/usr/bin/env bash
# Runs MAKO OVERLOAD logic tests and syntax-checks the engine glue.
# sq exits 0 even on script errors, so the output is checked explicitly.
set -euo pipefail
cd "$(dirname "$0")/../.."
SQ="${SQ:-/tmp/claude-1000/-home-cmer-Documents-git-NiDE-mako-v5-extra-stages/bdd48f5d-01ea-4d22-83c7-c18fe93a4163/scratchpad/squirrel/bin/sq}"
out=$("$SQ" tests/overload/test_logic.nut 2>&1 || true)
echo "$out"
if ! grep -q ', 0 failures' <<<"$out" || grep -q 'AN ERROR HAS OCCURRED' <<<"$out"; then
	echo "LOGIC TESTS FAILED"; exit 1
fi
if [ -f cstrike/scripts/vscripts/mako_overload/overload.nut ]; then
	cout=$("$SQ" -c -o /dev/null cstrike/scripts/vscripts/mako_overload/overload.nut 2>&1 || true)
	if [ -n "$cout" ]; then echo "$cout"; echo "OVERLOAD.NUT DOES NOT COMPILE"; exit 1; fi
	echo "overload.nut compiles"
fi
