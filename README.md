# sb

*Greetings from Port Edwards.*

**One command to a working single-binary headless browser.** `sb` installs,
configures and drives the four tools that came out on top of a 16-tool,
24-site measurement sweep, and gives them one honest interface. POSIX `sh`,
0BSD, no root, no package manager, writes nothing outside `$SB_HOME`.

```sh
curl -fsSL https://raw.githubusercontent.com/Nemo-010/sb/main/sb | sh -s -- get https://example.com
```

That is the whole start-up: it installs what it needs, then fetches the page
and prints its text. Nothing is patched, nothing is configured by hand.

```
$ sb get https://example.com
Example Domain
This domain is for use in documentation examples without needing permission.
This is not a service; avoid relying on it for testing and monitoring purposes.
```

## What it installs

| engine | pinned | why it is here |
|---|---|---|
| **curl-impersonate** | 2.3.2 | No JavaScript at all, but a byte-exact Chrome 152 ClientHello at 12 MiB and 0.6 s. In the sweep it retrieved real content from **15 of 24** hostile sites — more than any actual browser. First attempt, for text. |
| **nokk** | 0.1.49-alpha | The only tool measured that **clears a Cloudflare gate by itself** and keeps `cf_clearance` in a cookie jar. 13/24 real content, 2 bot walls (nothing else was under 3). No pixels, no screenshot. |
| **obscura** `--stealth` | 0.2.6 | The best full engine: V8, own layout, screenshots, CDP, MCP, Chrome-family JA4, 40 MiB, 0.14 s. It does **not** solve challenges. |
| **lightpanda** | 1.0.3 | Smallest peak RSS of the engines (25 MiB), good for bulk text. Self-identifies as `Lightpanda/1.0` and its canvas is a stub, so never trust it where anything is fingerprinting. |
| **moli** *(optional)* | 1.1.22 | Best one-shot form automation, UA consistent at HTTP and JS level, real PDF. Heaviest of the four. `sb install moli`. |

Every download is pinned to an exact release and verified against the
upstream sha256 before it is extracted. Installs are staged and moved into
place atomically, so a failed install leaves the previous version working.

## Commands

```
sb install [ENGINE...] [--latest] [--no-verify]   ensure engines are present
sb get URL [--as FMT] [--engine E] [--out FILE]   fetch a page
sb solve URL [--wait S] [--session NAME]          clear a challenge
sb shot URL [--out FILE]                          screenshot
sb eval URL JS [--engine E]                       run JavaScript, print result
sb run ENGINE [--] ARGS...                        raw upstream flags
sb engines | list | where | env                   what is installed, and where
sb doctor [--live] [--json]                       health, machine-readable
sb verify                                         re-check installed files
sb update [--check] [--self]                      pins, and the script itself
sb uninstall ENGINE... | --all                    remove engines
sb version | help | man                           documentation
```

### `sb get` — one verb, escalating only when it must

```sh
sb get https://example.com                      # text
sb get https://example.com --as markdown
sb get https://example.com --as links
sb get https://example.com --as png --out p.png
sb get https://example.com --as pdf --out p.pdf
sb get https://example.com --engine obscura     # one engine, no escalation
sb get https://example.com --json               # envelope for a program
```

Without `--engine` it walks a chain, cheapest first:

| format | chain |
|---|---|
| `text` | curl-impersonate → nokk → obscura → lightpanda → moli |
| `markdown` | obscura → lightpanda → moli → curl-impersonate+strip |
| `html` | curl-impersonate → obscura → lightpanda → moli |
| `links` | obscura → nokk → curl-impersonate |
| `png` | obscura → moli → lightpanda |
| `pdf` | moli → lightpanda |

An attempt is rejected and the chain moves on when the result is a **bot
wall** (the same markers the corpus used: `just a moment`, `cf-mitigated`,
`challenge-platform`, `验证码`, …), when it is **too thin** to be content
(`--min-chars`, default 40), or when the **engine itself reported a failure**
— which matters, because moli, lightpanda, nokk and obscura all exit `0` after
printing an error. If a browser comes back with a challenge page, `sb get`
gives nokk's solver one pass before it gives up (`--no-solve` disables that).

Exit codes: `0` ok · `6` no engine produced anything · `7` the wall is still up
(the best attempt is printed anyway).

```sh
$ sb get https://www.scrapingcourse.com/cloudflare-challenge
nokk: solving the challenge
nokk: cleared, retrying
Scraping Course
 Cloudflare Challenge
 You bypassed the Cloudflare challenge! :D
```

### `sb solve` — the one thing only nokk can do

```sh
sb solve https://www.scrapingcourse.com/cloudflare-challenge
# cleared: cf_clearance obtained
# verdict: cleared

sb solve URL --session warm --save-cookies jar.txt   # keep the clearance
sb solve URL --json                                  # nokk's own verdict object
```

Exit `0` only when a `cf_clearance` cookie was actually obtained (or when
there was no challenge to solve at all). Clearing is probabilistic and depends
on your exit IP; a miss is not a bug.

### `sb run` — the escape hatch that makes patching unnecessary

```sh
sb run obscura  -- fetch https://example.com --dump cookies
sb run nokk     -- --load https://example.com --solve-challenge 30 --json
sb run lightpanda -- serve --unix-socket /tmp/cdp.sock
sb run curl-impersonate -- --impersonate firefox147 -sSL https://example.com
```

Any upstream flag, today's or next release's, works here without touching `sb`.
stdin is passed through, so `sb run curl-impersonate -- -d @- ...` works too.

## Designed so upstream cannot break it

This is the part that matters for an agent that keeps encountering new
upstream releases.

**Pins are data, not code.** A pin is one line:

```
engine|tag|version|os|arch|kind|asset-template|sha256
```

`@T@` in the template is the release tag, as upstream spells it (`v0.2.6` for
one project, `1.0.3` for another). Moving a pin never means editing logic:

```sh
sb install obscura --latest --no-verify
# obscura: --latest is unpinned; integrity cannot be checked
# sb: computed sha256 6cf2146e...
# sb: pin it by adding this line to SB_MANIFEST:
#   obscura|v0.2.7|0.2.7|linux|x86_64|tar|obscura-x86_64-linux-stealth.tar.gz|6cf2146e...
```

**Flags are confined to seven small adapters.** `ad_fetch`, `ad_eval`,
`ad_solve`, `ad_meta`, `strip_html`, plus the manifest readers. If a release
renames `--dump`, that is one line — and until it is fixed, `sb run` and
`--engine` still work.

**Nothing is guessed from `$?`.** Four of these five engines exit `0` after a
navigation error. Failure is read from the engines' own output, so an agent
gets "no engine produced anything, exit 6" rather than an error page dressed
as content.

## Hermetic

* Everything lives under `$SB_HOME` (default `~/.local/share/sb`). No root.
* Each engine runs with `HOME`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`,
  `XDG_DATA_HOME` and `TMPDIR` pointed into `$SB_HOME/state/<engine>`, so
  nothing appears in your real `~/.cache`. Verified by the test suite: a run
  of `get`, `shot` and `solve` leaves the caller's `$HOME` byte-for-byte
  unchanged.
* Downloads land in `$SB_HOME/cache/dl` and are checked against the pinned
  sha256 before extraction.
* The installed binary's own digest is recorded in
  `$SB_HOME/engines/<e>/<v>/.sb-install`; `sb verify` re-checks it and exits
  `5` on any modification.
* Engine stdin is `/dev/null`, so `curl ... | sh` cannot be eaten by a subprocess.

## Idempotent

`sb install` any number of times: an engine already at the pinned version is
not re-downloaded (both cases are covered by the test suite). `sb doctor`,
`sb list`, `sb where`, `sb engines`, `sb verify` and `sb env` are read-only.
`sb get` and friends never modify an install.

## Agent-friendly

* `sb doctor --json` answers "what is installed, is it healthy" in one object
  with a `healthy` boolean; `--live` adds a real fetch per engine.
* `sb get --json` returns `{ok, engine, url, format, bytes, wall, meta, text,
  attempts[]}` — `attempts` records every engine it tried and why it moved on,
  so a failure is diagnosable from the envelope alone.
* `sb get --json` never writes install chatter to stdout. Diagnostics go to
  stderr, results to stdout.
* `sb help`, `sb man` and `sb help <command>` are always available offline.
* The script itself is a single file with no dependencies beyond `curl` (or
  `wget`), `tar` and a sha256 tool. It runs under `dash`.

## Environment

| variable | meaning |
|---|---|
| `SB_HOME` | install prefix (default `~/.local/share/sb`) |
| `SB_MIRROR` | replaces `https://github.com/` in asset URLs |
| `SB_AUTO_INSTALL` | `0` disables the one-time bootstrap install |
| `SB_CHAIN` | override the escalation order, e.g. `"nokk obscura"` |
| `SB_SOLVE` | `0` disables the automatic solver pass in `sb get` |
| `SB_SOLVE_WAIT` | seconds the automatic solver waits (default 30) |
| `SB_SESSION` | named nokk session for the automatic solver pass |
| `SB_CI_PROFILE` | curl-impersonate profile (default `chrome152`) |
| `SB_SELF_URL` | where `sb update --self` fetches from |

Offline installs work: drop the release assets into `$SB_HOME/cache/dl/`
yourself and `sb install` will verify and use them.

## Testing

```sh
./test.sh             # 43 offline checks, no network
./test.sh --live      # + real fetches through every engine (52)
./test.sh --install   # + a clean install into a throwaway prefix (68)
```

Each run gets its own `SB_HOME` under a temp dir and removes it on exit; the
real one is never touched. `--install` also verifies idempotency, hermeticity
and that a tampered binary is detected.

## Notes and limits

* The measurements behind the engine choice are in **[RESEARCH.md](RESEARCH.md)**:
  one datacenter IP, one hour, single run per site. A residential IP would move
  the Cloudflare numbers.
* **In a sandbox that denies `bind(2)`** the CDP servers cannot start
  (`obscura serve`, `moli serve`, `lightpanda serve`). Lightpanda can still
  serve over a unix socket: `sb run lightpanda -- serve --unix-socket /tmp/cdp.sock`.
* `sb get --as markdown` with only curl-impersonate installed falls back to
  stripped text, which loses headings. That is stated, not hidden.
* Nothing here bypasses authentication, and nothing should be pointed at a site
  whose terms forbid it. A solver that works means the site chose to issue a
  challenge, not that its operator consented.
* Upstream licences are theirs: nokk, obscura and moli are Apache-2.0,
  lightpanda is AGPL-3.0, curl-impersonate is MIT. `sb` itself is 0BSD.

---

*We aim to provide the software that shapes the world of tomorrow.*
