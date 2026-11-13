#!/usr/bin/env bash
#
# Check a toolchain installed by build-phoenix-toolchain.sh, then run the
# standard library's tests on a Phoenix-RTOS target under QEMU.
#
#   ./check-phoenix-toolchain.sh [options] [paths] [-- x.py test arguments]
#
#   --prefix DIR      the installed toolchain (default: <build-dir>/install)
#   --build-dir DIR   build-phoenix-toolchain.sh's build directory
#                     (default: build/phoenix-toolchain)
#   --project DIR     Phoenix-RTOS project with --phoenix-target built, the
#                     image included; the library tests run on it
#   --phoenix-target T  Phoenix target to test on (default: riscv64-generic-qemu)
#   --stage N         compiler stage of the library tests (default: 1)
#   --no-library-tests  only check the installed toolchain
#   -j N              bootstrap jobs
#
# The library tests link with the project's cross compiler, which has to be in
# PATH, and run through phoenix-rtos-tests/cargo-runner.py. Paths select what
# `x.py test` runs (default: library/std), arguments
# after `--` are added to it, e.g. `library/std -- --test-args fs::`.
set -euo pipefail

RUST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PHOENIX_TARGETS=(
	riscv64gc-unknown-phoenix
	i586-unknown-phoenix
	aarch64-unknown-phoenix
	armv7a-unknown-phoenix
	armv7r-unknown-phoenix
	armv8r-unknown-phoenix
	sparc-unknown-phoenix
)

# library/core and library/alloc do not link yet: their tests call libm
# functions libphoenix does not have (acosh, exp2, log2f, tgamma, ...)
LIBRARY_TESTS=(library/std)

BUILD_DIR="$RUST_DIR/build/phoenix-toolchain"
PREFIX=""
PROJECT=""
PHOENIX_TARGET=riscv64-generic-qemu
STAGE=1
LIBRARY=y
JOBS=()
TEST_PATHS=()
TEST_ARGS=()

die() {
	echo "check-phoenix-toolchain.sh: $*" >&2
	exit 1
}

log() {
	printf '\n=== %s\n' "$*"
}

fail() {
	echo "check failed: $*" >&2
	exit 1
}

while [ $# -gt 0 ]; do
	case "$1" in
		--prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
		--build-dir) BUILD_DIR="${2:?--build-dir needs a directory}"; shift ;;
		--project) PROJECT="${2:?--project needs a directory}"; shift ;;
		--phoenix-target) PHOENIX_TARGET="${2:?--phoenix-target needs a target}"; shift ;;
		--stage) STAGE="${2:?--stage needs a number}"; shift ;;
		--no-library-tests) LIBRARY=n ;;
		-j) JOBS=(-j "${2:?-j needs a number}"); shift ;;
		--) shift; TEST_ARGS=("$@"); break ;;
		-h|--help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; exit 0 ;;
		-*) die "unknown option '$1' (see --help)" ;;
		*) TEST_PATHS+=("$1") ;;
	esac
	shift
done

[ -d "$BUILD_DIR" ] || die "no build directory $BUILD_DIR (run build-phoenix-toolchain.sh first)"
BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
PREFIX="${PREFIX:-$BUILD_DIR/install}"
[ -x "$PREFIX/bin/rustc" ] || die "no toolchain installed in $PREFIX"
PREFIX="$(cd "$PREFIX" && pwd)"

if [ "$LIBRARY" = y ]; then
	[ -n "$PROJECT" ] || die "the library tests need a Phoenix-RTOS project (--project DIR, or --no-library-tests)"
	PROJECT="$(cd "$PROJECT" && pwd)"
	[ -x "$PROJECT/phoenix-rtos-build/build.sh" ] || die "$PROJECT is not a Phoenix-RTOS project"
	[ -d "$PROJECT/_boot/$PHOENIX_TARGET" ] ||
		die "no $PROJECT/_boot/$PHOENIX_TARGET (build it: TARGET=$PHOENIX_TARGET ./phoenix-rtos-build/build.sh all)"
	[ -f "$BUILD_DIR/bootstrap.toml" ] || die "no $BUILD_DIR/bootstrap.toml (run build-phoenix-toolchain.sh first)"
fi

# the one non-Phoenix entry in bootstrap.phoenix.toml's build.target
HOST="$(sed -n '/^build.target = \[/,/^\]/s/^ *"\([^"]*\)",*$/\1/p' "$RUST_DIR/bootstrap.phoenix.toml" | grep -v -- '-phoenix$' || true)"
[ "$(printf '%s\n' "$HOST" | grep -c .)" = 1 ] || die "expected exactly one host in bootstrap.phoenix.toml's build.target, got: '$HOST'"

CHECK_DIR="$(mktemp -d)"
trap 'rm -rf "$CHECK_DIR"' EXIT

### the installed toolchain

log "Checking the toolchain in $PREFIX"

RUSTC="$PREFIX/bin/rustc"
"$RUSTC" -vV
TARGET_LIST="$("$RUSTC" --print target-list)"
[ -x "$PREFIX/lib/rustlib/$HOST/bin/gcc-ld/ld.lld" ] || fail "no rust-lld (lib/rustlib/$HOST/bin/gcc-ld/ld.lld)"
[ -f "$PREFIX/lib/rustlib/src/rust/library/Cargo.lock" ] || fail "rust-src has no library/Cargo.lock"

# loading std's metadata needs no linker
printf 'pub fn hello() { std::println!("{:?}", std::thread::current().id()); }\n' >"$CHECK_DIR/lib.rs"
for t in "${PHOENIX_TARGETS[@]}"; do
	grep -qx "$t" <<<"$TARGET_LIST" || fail "rustc does not know $t"
	compgen -G "$PREFIX/lib/rustlib/$t/lib/libstd-*.rlib" >/dev/null || fail "no std for $t"
	"$RUSTC" --edition 2024 --target "$t" --crate-type lib --emit metadata -o "$CHECK_DIR/$t.rmeta" "$CHECK_DIR/lib.rs" ||
		fail "std for $t does not load"
	echo "ok  $t"
done
printf 'fn main() { println!("ok  %s (runs)"); }\n' "$HOST" >"$CHECK_DIR/main.rs"
"$RUSTC" --edition 2024 -o "$CHECK_DIR/main" "$CHECK_DIR/main.rs" || fail "host hello world does not build"
"$CHECK_DIR/main" || fail "host hello world does not run"

# -Zbuild-std from rust-src with an empty CARGO_HOME, as the release variant
# does on a clean machine
CARGO_BIN="$PREFIX/bin/cargo"
[ -x "$CARGO_BIN" ] || CARGO_BIN="$(command -v cargo || true)"
if [ -n "$CARGO_BIN" ]; then
	mkdir -p "$CHECK_DIR/crate/src"
	printf '[package]\nname = "check"\nedition = "2024"\n' >"$CHECK_DIR/crate/Cargo.toml"
	cp "$CHECK_DIR/lib.rs" "$CHECK_DIR/crate/src/lib.rs"
	CARGO_HOME="$CHECK_DIR/cargo-home" RUSTC="$RUSTC" RUSTC_BOOTSTRAP=1 CARGO_TARGET_DIR="$CHECK_DIR/target" "$CARGO_BIN" check -q \
		--manifest-path "$CHECK_DIR/crate/Cargo.toml" --target "${PHOENIX_TARGETS[0]}" \
		-Zbuild-std=std,panic_abort -Zbuild-std-features=panic-unwind ||
		fail "-Zbuild-std from rust-src"
	echo "ok  -Zbuild-std (${PHOENIX_TARGETS[0]})"
else
	echo "no cargo found, skipping the -Zbuild-std check"
fi

[ "$LIBRARY" = y ] || exit 0

### the library tests

log "Running the library tests on $PHOENIX_TARGET"

# How the project links and runs a Rust program for the target, from its build
# system: the checked variant, whose flags do not depend on the toolchain.
cat >"$CHECK_DIR/rust-env.mk" <<EOF
include $PROJECT/phoenix-rtos-build/Makefile.common
.PHONY: rust-env
rust-env:
	@printf 'rust-env:%s=%s\n' rust-target "\$(RUST_TARGET)" linker "\$(CC)" \\
		rustflags "\$(strip \$(RUSTFLAGS_TARGET))" runner "\$(RUST_RUNNER)" strip "\$(STRIP)"
EOF
# "env" starts a shell with the target's build environment, reading stdin
RUST_ENV="$(cd "$PROJECT" && env -u USER_RUSTFLAGS SHELL=bash TARGET="$PHOENIX_TARGET" \
	./phoenix-rtos-build/build.sh env <<<"RUST_VARIANT=checked make -s -C phoenix-rtos-build -f $CHECK_DIR/rust-env.mk rust-env")" ||
	die "could not read the Rust settings of $PHOENIX_TARGET from $PROJECT"
rust_env() {
	sed -n "s/^rust-env:$1=//p" <<<"$RUST_ENV"
}
RUST_TARGET="$(rust_env rust-target)"
[ -n "$RUST_TARGET" ] || die "$PHOENIX_TARGET has no RUST_TARGET (phoenix-rtos-build/target/*.mk)"
LINKER="$(command -v "$(rust_env linker)")" || die "no $(rust_env linker) in PATH (the cross toolchain of $PHOENIX_TARGET)"
TARGET_ENV="$(tr 'a-z-' 'A-Z_' <<<"$RUST_TARGET")"

[ "${#TEST_PATHS[@]}" -gt 0 ] || TEST_PATHS=("${LIBRARY_TESTS[@]}")

# Doctests are left out: each would boot the target. The std test binary runs
# over a thousand tests in one boot, hence the longer run timeout. The linker
# goes through the config: bootstrap passes cargo its own, `cc` by default.
# One x.py call per path: bootstrap tests the paths with one cargo, so a crate
# that does not build would stop the others.
FAILED=()
for path in "${TEST_PATHS[@]}"; do
	log "Testing $path"
	(cd "$RUST_DIR" && env \
		"CARGO_TARGET_${TARGET_ENV}_RUSTFLAGS=$(rust_env rustflags)" \
		"CARGO_TARGET_${TARGET_ENV}_RUNNER=$(rust_env runner)" \
		"RUST_RUNNER_STRIP=$(rust_env strip)" \
		"RUST_RUNNER_RUN_TIMEOUT=${RUST_RUNNER_RUN_TIMEOUT:-1800}" \
		"TARGET=$PHOENIX_TARGET" \
		./x.py test --config "$BUILD_DIR/bootstrap.toml" --build-dir "$BUILD_DIR" "${JOBS[@]}" \
		--set "target.$RUST_TARGET.linker=$LINKER" --stage "$STAGE" --target "$RUST_TARGET" \
		--no-doc --no-fail-fast "$path" "${TEST_ARGS[@]}") ||
		FAILED+=("$path")
done
[ "${#FAILED[@]}" = 0 ] || fail "library tests on $PHOENIX_TARGET: ${FAILED[*]}"
echo "ok  library tests ($RUST_TARGET on $PHOENIX_TARGET)"
