# How sb is put together, and why

One file, ~1650 lines of POSIX `sh`. This note is for whoever changes it.

## The shape

```
manifest tables      SB_MANIFEST, SB_META, SB_CAPS   data, not code
manifest readers     mf_get, mf_meta, mf_caps, cap   parse those tables
install              dl, install_engine, write_wrappers, install_self,
                     bootstrap, ensure_engine
adapters             ad_fetch, ad_eval, ad_solve, ad_meta, strip_html
                     the only code that knows an engine's flags
classification       is_wall, failed_out, verdict, chain_for
commands             cmd_*                           one per verb
dispatch             a case at the bottom of the file
```

Engine knowledge is confined to two places: the tables at the top and the
adapters. Nothing else branches on an engine name.

## Design decisions worth keeping

**Pins are data lines.** `engine|tag|version|os|arch|kind|template|sha256`.
`@T@` in the template is the tag as upstream spells it, because these projects
are not consistent (`v0.2.6` for one, `1.0.3` for another). Moving a pin is
adding a line, never editing logic — and `--latest` prints the line for you.

**Calibration, not "$?".** Four of the five engines exit `0` after printing a
navigation error. `verdict()` therefore reads the output: a structured error
key, a known failure phrase, a wall marker, or a byte count. This is the
single most important function for an agent, because the alternative is
handing an agent an error page that looks like content.

**Subshells instead of `local`.** POSIX `sh` has no `local`, and a callee
overwrites the caller's `_url`, `_pf` etc. Every function that has scratch
variables runs its body in `( ... )`. This was a real bug: `install_engine`
clobbered `cmd_get`'s `_url` and `sb get` fetched a tarball URL.

**stdin is `/dev/null` for engines, passed through for `sb run`.** When `sb` is
piped into `sh`, the script itself is on fd 0. An engine that reads stdin eats
the rest of the script. `sb run` is the deliberate exception, so
`sb run curl-impersonate -- -d @- ...` works.

**Hermetic by environment, not by chroot.** `engine_exec` points `HOME`,
`XDG_CACHE_HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `TMPDIR` at
`$SB_HOME/state/<engine>`. nokk writes `~/.cache/nokk`; this is what stops it
landing in the caller's real home.

**Installs are atomic.** Extract to `$SB_HOME/engines/<e>/.stage.$$`, verify,
then `mv` into `engines/<e>/<version>` and repoint the `current` symlink. A
failed download or a bad checksum leaves the previous version active.

**Two digests, not one.** The archive's sha256 is checked before extraction;
the extracted binary's own sha256 is recorded in `.sb-install`. `sb verify`
compares the binary, because that is what actually runs — comparing the archive
would pass even if the binary had been swapped afterwards.

**`--latest` is deliberately unpinned and says so.** It prints the computed
sha256 and a paste-ready manifest line. Anything else would be a tool that
silently installs unverified code.

## Deliberate non-goals

* **No daemon, no server, no state machine.** Every command is one process that
  exits. The CDP/MCP servers are reachable through `sb run`, not wrapped.
* **No vendored binaries.** `sb` fetches upstream release assets at install
  time. Shipping other people's builds is a different job with a different
  licence story (see THIRD-PARTY.md).
* **No attempt at full markdown fidelity.** Where an engine has no markdown
  dumper, `sb` says so in `sb engines` and in the chain order, and falls back to
  text rather than pretending.
* **No silent retries.** An attempt is one attempt with a timeout. Escalation
  is visible on stderr, and `attempts[]` in the JSON records why each engine
  was passed over.

## Adding an engine

1. Add a row to `SB_META` (repo, binary name, what it is for) and `SB_CAPS`.
2. Add a manifest row per platform.
3. Add the flag knowledge to `ad_fetch` / `ad_eval` / `ad_solve` — and nowhere
   else.
4. Put it in `SB_CORE` or `SB_EXTRA`, and in the `chain_for` order where it
   belongs, justified by a measurement, not a preference.
5. `./test.sh --install` and add a live check.

## Moving a pin

```sh
sb install obscura --latest --no-verify
# ... prints: obscura|v0.2.7|0.2.7|linux|x86_64|tar|obscura-x86_64-linux-stealth.tar.gz|<sha>
```

Paste over the old row. If the asset name changed too, the template needs
editing — that is data, so it is still a one-line change. Then run
`./test.sh --install` before pushing: a pin that resolves but whose binary has
moved a flag is exactly what the live checks are for.

## Testing philosophy

The offline suite exists so a change cannot regress the contract (exit codes,
stdout purity, POSIX syntax). The `--install` suite exists so a change cannot
regress the installation (idempotency, hermeticity, tamper detection). The
`--live` checks exist because every engine here talks to the Electrosphere and
can change under us. A test that fails only because an IP got a challenge it
did not get before is reported as `skip`, not `FAIL` — being honest about which
failures are ours matters more than a green number.
