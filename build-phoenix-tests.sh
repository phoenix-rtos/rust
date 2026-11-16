#!/usr/bin/env bash
#
# Build the standard library's tests (std, core, alloc) for Phoenix-RTOS
# targets without linking them, for phoenix-rtos-project to link against its
# libphoenix and run. Uses the compiler build-phoenix-toolchain.sh built.
#
#   ./build-phoenix-tests.sh --out DIR [options] [TARGET...]
#
#   --out DIR        output: DIR/<target>/, see phoenix-test-link
#   --build-dir DIR  build-phoenix-toolchain.sh's build directory
#                    (default: build/phoenix-toolchain)
#   --stage N        compiler stage (default: 1)
#   TARGET           Rust targets (default: all in bootstrap.phoenix.toml)
#
# A crate whose tests do not build is reported and skipped.
set -euo pipefail

RUST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIBRARY_TESTS=(library/std library/core library/alloc)

BUILD_DIR="$RUST_DIR/build/phoenix-toolchain"
STAGE=1
OUT=""
TARGETS=()

die() {
	echo "build-phoenix-tests.sh: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--out) OUT="${2:?--out needs a directory}"; shift ;;
		--build-dir) BUILD_DIR="${2:?--build-dir needs a directory}"; shift ;;
		--stage) STAGE="${2:?--stage needs a number}"; shift ;;
		-h|--help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; exit 0 ;;
		-*) die "unknown option '$1' (see --help)" ;;
		*) TARGETS+=("$1") ;;
	esac
	shift
done
[ -n "$OUT" ] || die "--out is required"
[ -f "$BUILD_DIR/bootstrap.toml" ] || die "no $BUILD_DIR/bootstrap.toml: run build-phoenix-toolchain.sh first"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

# build.target in bootstrap.phoenix.toml: the host and the Phoenix targets
TOML_TARGETS="$(sed -n '/^build.target = \[/,/^\]/s/^ *"\([^"]*\)",*$/\1/p' "$RUST_DIR/bootstrap.phoenix.toml")"
HOST="$(grep -v -- '-phoenix$' <<<"$TOML_TARGETS")"
[ ${#TARGETS[@]} -gt 0 ] || mapfile -t TARGETS < <(grep -- '-phoenix$' <<<"$TOML_TARGETS")

RUST_LLD="$BUILD_DIR/$HOST/stage$STAGE/lib/rustlib/$HOST/bin/rust-lld"
[ -x "$RUST_LLD" ] || die "no rust-lld at $RUST_LLD"
SPARC_LD="${SPARC_LD:-sparc64-linux-gnu-ld}"

FAILED=()
for target in "${TARGETS[@]}"; do
	rm -rf "${OUT:?}/$target"
	case "$target" in
		sparc-*)
			if ! command -v "$SPARC_LD" > /dev/null; then
				echo "build-phoenix-tests.sh: $target: no $SPARC_LD (SPARC_LD)" >&2
				FAILED+=("$target")
				continue
			fi
			ld="$SPARC_LD -m elf32_sparc"
			;;
		*) ld="$RUST_LLD -flavor gnu" ;;
	esac
	# phoenix-test-link's placeholders of an earlier run: cargo links again
	# only test binaries that are missing
	find "$BUILD_DIR/$HOST/stage$STAGE-std/$target" -type f -size -100c \
		-exec grep -lxq 'phoenix-test-link placeholder' {} \; -delete 2>/dev/null || true
	for path in "${LIBRARY_TESTS[@]}"; do
		printf '\n=== %s: %s\n' "$target" "$path"
		# one x.py call per crate: a crate that does not build would stop the others
		if ! (cd "$RUST_DIR" && env \
			PHOENIX_TESTS="$OUT/$target" PHOENIX_TEST_LD="$ld" \
			"CARGO_TARGET_$(tr 'a-z-' 'A-Z_' <<<"$target")_RUNNER=true" \
			./x.py test --config "$BUILD_DIR/bootstrap.toml" --build-dir "$BUILD_DIR" --stage "$STAGE" \
			--target "$target" --set "target.$target.linker=$RUST_DIR/phoenix-test-link" \
			--no-doc --no-fail-fast "$path"); then
			FAILED+=("$target $path")
		fi
	done
done

echo
du -sh "$OUT"/*
[ ${#FAILED[@]} -eq 0 ] || die "did not build: ${FAILED[*]}"
