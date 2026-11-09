#!/bin/sh
# test.sh - the checks I run before calling sb finished.
#
#   ./test.sh              # offline checks only (fast, no network)
#   ./test.sh --live       # also fetch real pages through every engine
#   ./test.sh --install    # also do a clean install into a throwaway SB_HOME
#
# Nothing here touches the real $SB_HOME: every run gets its own directory
# under a temp root, which is removed on exit. Set SB_TEST_ROOT to choose
# where that root goes; --install needs about 600 MB.
#
# SPDX-License-Identifier: 0BSD
set -u

SB_SRC=$(cd "$(dirname "$0")" && pwd)/sb
LIVE=0
INSTALL=0
for a in "$@"; do
	case "$a" in
		--live) LIVE=1 ;;
		--install) INSTALL=1; LIVE=1 ;;
		--help|-h) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	esac
done

# A full --install suite needs ~600 MB (four engines plus their archives).
# /tmp is often a small tmpfs, so prefer TMPDIR when the caller set one and
# fall back to the current directory, which is writable by definition.
_root_base=${SB_TEST_ROOT:-${TMPDIR:-.}}
# mktemp -d with a relative -p yields a relative path, and a relative ROOT then
# makes every $ROOT/... in this script resolve from whatever directory a later
# cd leaves us in. Anchor it once, here.
mkdir -p "$_root_base" 2>/dev/null
_root_base=$(cd "$_root_base" && pwd) || exit 1
ROOT=$(mktemp -d "$_root_base/sb-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT INT TERM
export HOME="$ROOT/home"
export SB_HOME="$ROOT/sb"
mkdir -p "$HOME"
unset XDG_DATA_HOME

pass=0
fail=0
skip=0

ok()   { pass=$((pass + 1)); printf 'ok    %s\n' "$*"; }
no()   { fail=$((fail + 1)); printf 'FAIL  %s\n' "$*"; }
miss() { skip=$((skip + 1)); printf 'skip  %s\n' "$*"; }

# run sb with the source, capturing stdout, stderr and status separately
run() { # args... -> sets OUT ERR RC
	OUT=$("$@" 2>"$ROOT/.err")
	RC=$?
	ERR=$(cat "$ROOT/.err")
}

expect_rc() { # want desc
	if [ "$RC" = "$1" ]; then ok "$2 (exit $RC)"; else no "$2 (exit $RC, wanted $1)"; fi
}

expect_out() { # pattern desc
	if printf '%s' "$OUT" | grep -qE "$1"; then ok "$2"; else no "$2 (got: $(printf '%s' "$OUT" | head -c 120))"; fi
}

expect_err() { # pattern desc
	if printf '%s' "$ERR" | grep -qE "$1"; then ok "$2"; else no "$2 (err: $(printf '%s' "$ERR" | head -c 120))"; fi
}

section() { printf '\n-- %s\n' "$*"; }

SB="sh $SB_SRC"

# ---------------------------------------------------------------------------
section "syntax and portability"
# ---------------------------------------------------------------------------
if sh -n "$SB_SRC"; then ok "sh -n"; else no "sh -n"; fi
if command -v dash >/dev/null 2>&1; then
	if dash -n "$SB_SRC"; then ok "dash -n (strict POSIX)"; else no "dash -n"; fi
else
	miss "dash -n (dash not installed)"
fi
if head -n 1 "$SB_SRC" | grep -qx '#!/bin/sh'; then ok "shebang is /bin/sh"; else no "shebang"; fi
# no bashisms that dash rejects are already caught above; catch the common
# silent ones that dash accepts but POSIX sh does not guarantee
# POSIX character classes ([[:space:]]) and $(( )) arithmetic are both POSIX.
# Only genuinely non-POSIX constructs are flagged: [[ followed by a space or
# end (never "[[" as the inside of a character class), <<< here-strings,
# $'...' quoting, and declare/local as commands.
bashism() {
	grep -qE '<<<|\$'"'"'[^'"'"']*'"'"'|(^|[;[:space:]])declare[[:space:]]|(^|[;[:space:]])local[[:space:]]' "$SB_SRC" && return 0
	grep -qE '(^|[^[:alnum:]_\[])\[\][[:space:]]' "$SB_SRC" && return 0
	return 1
}
if bashism; then no "bashism"; else ok "no bashisms"; fi


if grep -q 'set -e' "$SB_SRC" && ! grep -q 'set -u' "$SB_SRC"; then :; fi
if grep -q 'set -u' "$SB_SRC"; then ok "set -u (unset variables are errors)"; else no "set -u missing"; fi

# ---------------------------------------------------------------------------
section "dispatch and exit codes"
# ---------------------------------------------------------------------------
run $SB version
expect_rc 0 "sb version"
expect_out '^sb [0-9]' "version prints sb <semver>"

run $SB help
expect_rc 0 "sb help"
expect_out 'sb get' "help mentions get"

run $SB man
expect_rc 0 "sb man"
expect_out 'SYNOPSIS' "man has a SYNOPSIS"

for sub in get solve install run; do
	run $SB help "$sub"
	expect_rc 0 "sb help $sub"
done

run $SB nosuchcommand
expect_rc 2 "unknown command exits 2"

run $SB get
expect_rc 2 "get with no URL exits 2"

run $SB get https://example.com --as nonsense
expect_rc 2 "unknown --as exits 2"
expect_err "unknown --as" "unknown --as says so"

run $SB get https://example.com --engine nonsense
expect_rc 2 "unknown engine exits 2"
expect_err "unknown engine" "unknown engine says so"

run $SB install nonsense
expect_rc 2 "install of an unknown engine exits 2"

run $SB run
expect_rc 2 "run with no engine exits 2"

run $SB run obscura
expect_rc 2 "run with no args exits 2"

run $SB env
expect_rc 0 "sb env"
expect_out 'export PATH=' "env exports PATH"
expect_out "SB_HOME=\"$SB_HOME\"" "env exports the right SB_HOME"

# ---------------------------------------------------------------------------
section "manifest and capability data"
# ---------------------------------------------------------------------------
run $SB engines
expect_rc 0 "sb engines"
for e in nokk obscura lightpanda curl-impersonate moli; do
	expect_out "^$e" "engines lists $e"
done
expect_out 'nokk+.*yes' "nokk is marked as able to solve"

run $SB list
expect_rc 0 "sb list on an empty prefix"
expect_out 'pinned' "list reports pins when nothing is installed"

# every manifest line must be well formed and every digest 64 hex chars
bad=0
grep '^[a-z-]*|v\?[0-9]' "$SB_SRC" | while IFS='|' read -r e tag ver os arch kind tmpl sha; do
	[ "$(printf '%s' "$sha" | wc -c | tr -d ' ')" = "64" ] || echo "bad digest: $e $os $arch"
done > "$ROOT/.bad"
if [ -s "$ROOT/.bad" ]; then no "manifest digests: $(cat "$ROOT/.bad")"; else ok "every manifest digest is 64 hex chars"; fi

# ---------------------------------------------------------------------------
section "classification (offline, stub engine)"
	# A deterministic probe of the wall/exit-code contract, with no network and
	# no download: a stub engine that prints a wall body is installed under a
	# throwaway prefix, so `sb get` sees exactly one outcome.
	_stub="$ROOT/stub"
	mkdir -p "$_stub/home" "$_stub/sb/engines/curl-impersonate/1.0"
	printf '#!/bin/sh\nprintf "Just a moment...\\nEnable JavaScript and cookies to continue\\n"\n' \
		> "$_stub/sb/engines/curl-impersonate/1.0/curl-impersonate"
	chmod 755 "$_stub/sb/engines/curl-impersonate/1.0/curl-impersonate"
	ln -s 1.0 "$_stub/sb/engines/curl-impersonate/current"
	printf 'ENGINE=curl-impersonate\nVERSION=1.0\nBIN=curl-impersonate\nBIN_SHA256=x\n' \
		> "$_stub/sb/engines/curl-impersonate/1.0/.sb-install"
	_sout=$(HOME="$_stub/home" SB_HOME="$_stub/sb" SB_SOLVE=0 sh "$SB_SRC" \
		get https://example.invalid/ --engine curl-impersonate --no-solve 2>/dev/null)
	_src=$?
	if [ "$_src" = 7 ]; then
		ok "a wall body with nothing behind it exits 7, not 6"
	else
		no "wall-only outcome exited $_src, wanted 7"
	fi
	if printf '%s' "$_sout" | grep -q 'Just a moment'; then
		ok "the wall page is still printed on exit 7"
	else
		no "exit 7 printed no body ($_sout)"
	fi

	# a clean body must not be mistaken for a wall
	printf '#!/bin/sh\nprintf "A real page with several lines of ordinary content, long enough to pass the minimum.\\n"\n' \
		> "$_stub/sb/engines/curl-impersonate/1.0/curl-impersonate"
	_cout=$(HOME="$_stub/home" SB_HOME="$_stub/sb" sh "$SB_SRC" \
		get https://example.invalid/ --engine curl-impersonate 2>/dev/null)
	_crc=$?
	if [ "$_crc" = 0 ]; then ok "a clean body exits 0"; else no "clean body exited $_crc"; fi
	rm -rf "$_stub"

section "failure modes that must not look like success"
# ---------------------------------------------------------------------------
if [ "$INSTALL" = 0 ]; then
	# with nothing installed and auto-install disabled, get must fail cleanly
	SB_AUTO_INSTALL=0 run $SB get https://example.com
	if [ "$RC" = 6 ]; then ok "get with no engine installed exits 6"; else no "get with no engine exits $RC, wanted 6"; fi
else
	miss "no-engine failure (install mode installs engines)"
fi

run $SB doctor
expect_rc 0 "doctor on a fresh prefix"
expect_out 'platform' "doctor reports the platform"

run $SB doctor --json
expect_rc 0 "doctor --json"
if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
	ok "doctor --json is valid JSON"
else
	no "doctor --json is not valid JSON"
fi

run $SB verify
expect_rc 0 "verify with nothing installed"

# ---------------------------------------------------------------------------
if [ "$INSTALL" = 1 ]; then
section "clean install"
	# shellcheck disable=SC2086
	OUT=$($SB install 2>"$ROOT/.err"); RC=$?
	ERR=$(cat "$ROOT/.err")
	if [ "$RC" = 0 ]; then ok "sb install"; else no "sb install (exit $RC)"; fi
	# stdout must stay clean: sb get pipes into jq, and an install message on
	# stdout would corrupt that
	if [ -z "$OUT" ]; then ok "install writes nothing to stdout"; else no "install wrote to stdout: $(printf '%s' "$OUT" | head -c 80)"; fi

	for e in nokk obscura lightpanda curl-impersonate; do
		if [ -x "$SB_HOME/bin/$e" ]; then ok "wrapper $SB_HOME/bin/$e"; else no "wrapper $e missing"; fi
	done

	# the install must leave a usable sb on PATH, or an agent that used the
	# one-line start has engines but no command
	if [ -x "$SB_HOME/bin/sb" ] && "$SB_HOME/bin/sb" version >/dev/null 2>&1; then
		ok "install leaves $SB_HOME/bin/sb runnable"
	else
		no "install did not leave a runnable sb"
	fi
	if [ "$("$SB_HOME/bin/sb" version 2>/dev/null | head -n 1)" = "sb $("$SB_HOME/bin/sb" version 2>/dev/null | sed -n '1s/^sb //p')" ]; then
		ok "installed sb runs itself"
	else
		no "installed sb cannot report its own version"
	fi

	run $SB verify
	expect_rc 0 "verify after install"

	# idempotency: the second install must not download anything
	before=$(find "$SB_HOME/cache/dl" -type f 2>/dev/null | wc -l | tr -d ' ')
	run $SB install
	after=$(find "$SB_HOME/cache/dl" -type f 2>/dev/null | wc -l | tr -d ' ')
	expect_rc 0 "second sb install"
	if [ "$before" = "$after" ]; then ok "install is idempotent (no new downloads)"; else no "install re-downloaded ($before -> $after files)"; fi

	# hermeticity: every engine must have its HOME inside SB_HOME
	missing=0
	for e in nokk obscura lightpanda curl-impersonate; do
		[ -d "$SB_HOME/state/$e/home" ] || missing=1
	done
	if [ "$missing" = 0 ]; then ok "each engine has a private HOME under SB_HOME/state"; else no "engine HOME dirs missing"; fi

	# wrappers must set the hermetic environment
	if grep -q "HOME='$SB_HOME/state/nokk/home'" "$SB_HOME/bin/nokk"; then
		ok "wrapper pins HOME into SB_HOME"
	else
		no "wrapper does not pin HOME"
	fi

	# Regression: install_self runs inside cmd_get on the bootstrap path. If it
	# clobbers cmd_get's scratch variables (POSIX sh has no `local`), the very
	# first fetch after install fails with the wrong timeout or URL.
	# This must run in a genuinely empty prefix, so it unsets SB_HOME for the
	# child rather than inheriting the suite's.
	_fresh="$ROOT/fresh"
	mkdir -p "$_fresh/home"
	# reuse the suite's download cache so this does not pull 300 MB twice
	mkdir -p "$_fresh/sb/cache"
	cp -R "$SB_HOME/cache/dl" "$_fresh/sb/cache/" 2>/dev/null || true
	if ( unset SB_HOME XDG_DATA_HOME; export HOME="$_fresh/home" SB_HOME="$_fresh/sb"
	     env | grep SB_HOME > "$_fresh/env"
	     sh "$SB_SRC" get https://example.com ) \
		>"$_fresh/out" 2>"$_fresh/err"; then
		if grep -qi 'example' "$_fresh/out"; then
			ok "cold first fetch after a bootstrap install works (variable isolation)"
		else
			no "cold first fetch produced no page: $(head -c 120 "$_fresh/out")"
		fi
	else
		no "cold first fetch failed: $(tail -3 "$_fresh/err" | tr '\n' ' ')"
	fi
	if [ -x "$_fresh/sb/bin/sb" ]; then
		ok "bootstrap left sb at \$SB_HOME/bin/sb"
	else
		no "bootstrap did not leave sb behind"
	fi
	rm -rf "$_fresh"

	# Regression: CI ran test.sh with TMPDIR unset, mktemp -d produced a
	# relative ROOT, and every $ROOT/... check then resolved from the wrong
	# directory. Anchor the root and assert it is absolute.
	case "$ROOT" in
		/*) ok "test root is an absolute path" ;;
		*) no "test root is relative ($ROOT)" ;;
	esac

	# Regression: a relative SB_HOME used to record a binary path that leaked
	# the staging directory (".stage.NNN"), so every wrapper and every
	# `sb verify` after it was wrong. The prefix is anchored to $PWD now.
	_relhome="$ROOT/relhome"
	mkdir -p "$_relhome/home"
	if ( cd "$_relhome" && HOME="$_relhome/home" SB_HOME="./rel/sb" sh "$SB_SRC" install ) \
		>"$_relhome/out" 2>"$_relhome/err"; then
		_bin=$(sed -n 's/^BIN=//p' "$_relhome/rel/sb/engines/nokk/current/.sb-install" 2>/dev/null)
		case "$_bin" in
			*stage*) no "relative SB_HOME recorded a staging path ($_bin)" ;;
			''|/*)   no "relative SB_HOME recorded a bad path ($_bin)" ;;
			*)       ok "relative SB_HOME records a clean binary path ($_bin)" ;;
		esac
		if [ -x "$_relhome/rel/sb/bin/nokk" ]; then
			ok "relative SB_HOME still writes engine wrappers"
		else
			no "relative SB_HOME wrote no wrapper"
		fi
		if ( cd "$_relhome" && HOME="$_relhome/home" SB_HOME="./rel/sb" sh "$SB_SRC" verify ) \
			>"$_relhome/vout" 2>&1; then
			ok "relative SB_HOME verifies clean"
		else
			no "relative SB_HOME verify failed: $(head -c 150 "$_relhome/vout")"
		fi
	else
		no "install with a relative SB_HOME failed: $(tail -2 "$_relhome/err" | tr '\n' ' ')"
	fi
	rm -rf "$_relhome"

	# a tampered binary must be detected
	_lt="$SB_HOME/engines/lightpanda/current/bin/lightpanda"
	if [ -f "$_lt" ]; then
		printf 'x' >> "$_lt"
		run $SB verify
		if [ "$RC" = 5 ]; then ok "verify detects a modified binary (exit 5)"; else no "verify missed a modified binary (exit $RC)"; fi
		rm -rf "$SB_HOME/engines/lightpanda"
		run $SB install lightpanda
		expect_rc 0 "reinstall repairs the damaged engine"
	fi
fi

# ---------------------------------------------------------------------------
if [ "$LIVE" = 1 ]; then
section "live: every engine can load a page"
	for e in nokk obscura lightpanda curl-impersonate; do
		if [ ! -x "$SB_HOME/bin/$e" ]; then miss "live $e (not installed)"; continue; fi
		run $SB get https://example.com --engine "$e" --timeout 60
		if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qi 'example'; then
			ok "live $e returns example.com"
		else
			no "live $e (exit $RC): $(printf '%s' "$OUT" | head -c 100)"
		fi
	done

section "live: formats"
	run $SB get https://example.com --as markdown --timeout 60
	if [ "$RC" = 0 ] && [ -n "$OUT" ]; then ok "markdown"; else no "markdown"; fi

	run $SB get https://example.com --as links --timeout 60
	if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'iana.org'; then ok "links"; else no "links"; fi

	_png="$ROOT/shot.png"
	run $SB get https://example.com --as png --out "$_png" --timeout 60
	if [ "$RC" = 0 ] && head -c 4 "$_png" 2>/dev/null | od -An -c | grep -q 'P   N   G'; then
		ok "png is a real PNG"
	else
		no "png"
	fi

	_pdf="$ROOT/out.pdf"
	run $SB get https://example.com --as pdf --out "$_pdf" --timeout 60
	if [ "$RC" = 0 ] && head -c 4 "$_pdf" 2>/dev/null | grep -q '%PDF'; then ok "pdf is a real PDF"; else no "pdf"; fi

section "live: JSON envelope"
	run $SB get https://en.wikipedia.org/wiki/Headless_browser --json --max-bytes 200 --timeout 90
	expect_rc 0 "get --json"
	if printf '%s' "$OUT" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["ok"] is True
assert d["engine"] in ("nokk","obscura","lightpanda","curl-impersonate","moli")
assert isinstance(d["attempts"], list) and d["attempts"]
assert d["bytes"] > 0
' 2>/dev/null; then
		ok "JSON envelope has ok, engine, attempts, bytes"
	else
		no "JSON envelope malformed: $(printf '%s' "$OUT" | head -c 200)"
	fi

section "live: the wall the corpus is about"
	run $SB solve https://www.scrapingcourse.com/cloudflare-challenge --wait 30
	if [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -qi 'cleared'; then
		ok "solve clears a Cloudflare managed challenge"
	elif printf '%s' "$ERR" | grep -qi 'not cleared\|no cf_clearance'; then
		miss "solve did not clear (IP-dependent; a miss is not a bug)"
	else
		no "solve (exit $RC): $(printf '%s' "$OUT$ERR" | head -c 150)"
	fi

	# After the solve above, a cached cf_clearance can make the very first
	# attempt succeed, in which case nothing escalated and nothing should.
	# Either "the content behind the gate came back" or "stopped at the wall"
	# is a correct outcome; "some other page, quietly" is not.
	run $SB get https://www.scrapingcourse.com/cloudflare-challenge --timeout 90
	case "$RC" in
		0)
			if printf '%s' "$OUT" | grep -qi 'bypassed the cloudflare'; then
				ok "get returns the content behind the challenge"
			else
				no "get returned something that is not the gated page: $(printf '%s' "$OUT" | head -c 120)"
			fi
			;;
		7)
			miss "get stopped at the wall (solver missed; IP-dependent)"
			;;
		*)
			no "get escalation (exit $RC): $(printf '%s' "$OUT" | head -c 150)"
			;;
	esac

section "live: a page that must not be mistaken for a wall"
	run $SB get https://example.com --timeout 60
	if [ "$RC" = 0 ] && ! printf '%s' "$ERR" | grep -qi 'bot wall'; then
		ok "clean page is not reported as a wall"
	else
		no "clean page classification (exit $RC)"
	fi
fi

# ---------------------------------------------------------------------------
printf '\n%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ] || exit 1
exit 0
