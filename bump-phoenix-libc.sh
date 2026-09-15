#!/bin/sh
# Re-pin std's libc to the head of the libc fork's branch.
#
#   ./bump-phoenix-libc.sh [LOCAL_LIBC]
#
# LOCAL_LIBC: libc checkout to fetch from (unpushed commits).
set -e

local_libc=
if [ $# -gt 1 ]; then
	echo "usage: bump-phoenix-libc.sh [LOCAL_LIBC]" >&2
	exit 1
fi
if [ $# -eq 1 ]; then
	[ -d "$1" ] || { echo "bump-phoenix-libc.sh: no libc checkout at '$1'" >&2; exit 1; }
	local_libc=$(realpath "$1")
fi

cd "$(dirname "$0")"

grep -q "^libc = .*branch = '" library/Cargo.toml || {
	echo "bump-phoenix-libc.sh: library/Cargo.toml does not take libc from a git branch:" >&2
	grep "^libc = " library/Cargo.toml >&2
	exit 1
}

precise=
if [ -n "$local_libc" ]; then
	export CARGO_NET_GIT_FETCH_WITH_CLI=true GIT_CONFIG_COUNT=1 \
		GIT_CONFIG_KEY_0="url.$local_libc.insteadOf" \
		GIT_CONFIG_VALUE_0=https://github.com/phoenix-rtos/libc-rs
	# an exact commit: for a branch cargo asks the GitHub API and skips the
	# fetch if GitHub's head is unchanged
	branch=$(sed -n "s/^libc = .*branch = '\([^']*\)'.*/\1/p" library/Cargo.toml)
	precise="--precise $(git -C "$local_libc" rev-parse "$branch")"
fi

pin() { grep -A2 '^name = "libc"$' library/Cargo.lock | sed -n 's/^source = "\(.*\)"$/\1/p'; }
old=$(pin)
(cd library && cargo update -p libc $precise)
new=$(pin)
sed -i "s|$old|$new|" src/tools/tidy/src/extdeps.rs
