# The corpus behind the engine choice

`sb` is the executable part of a research bundle about single-binary headless
browsers. This file says what that bundle contained, so the numbers in
[RESEARCH.md](../RESEARCH.md) can be checked rather than trusted.

The bundle is not vendored here — it is 2.3 MB of evidence plus 775 MB of
binaries, and shipping other people's builds is not this repo's job. What
follows is the index, and the exact commands to regenerate it.

## What was searched

Three independent sources, because repository search alone misses the long
tail and web search alone misses the code.

| stage | what | rows |
|---|---|---|
| 1. GitHub repository search | 120 English phrases, 32 Chinese phrases, 20 topics, 12 name queries — each pinned to `pushed:>2026-01-01` | **15,974 unique repos** |
| 2. Web search | 50 English/Chinese queries for articles and comparisons | **500 rows** |
| 3. Scoring | browser/stealth/single-binary terms minus slop terms | 345 repos at score ≥ 14 |
| 4. Manual read | README plus release assets | 90 repos |
| 5. Downloaded and run | see below | **16** |

Cut criteria, in order: no upstream source → out; a wrapper around a
pre-installed Chrome or Node → out (not a single binary); a service that needs
`bind(2)` → unmeasurable, recorded separately; a library rather than a runnable
program → out. Deliberately **not** cut: zero-star projects. Four of the
sixteen that were actually run have under 50 stars, and one had zero.

## What was run

| tool | language | what it is |
|---|---|---|
| **obscura** `h4ckf0r0day/obscura` | Rust | V8 + own layout/paint engine, CDP server, MCP server, `fetch`/`scrape` CLI |
| **lightpanda** `lightpanda-io/browser` | Zig | own HTML/CSS engine + V8, CDP; **no** paint |
| **nokk** `koloss777/nokk` | Rust | V8 + DOM + Chrome TLS/JA4, CDP, **no** paint, ships a Cloudflare solver |
| **moli** `lexmount/moli` | Rust | V8 + DOM + CSS layout, on-demand paint, CDP + WebDriver + BiDi |
| **curl-impersonate** `lexiforest/curl-impersonate` | C | exact Chrome/Firefox ClientHello, no JS |
| plus | | telemaco (an obscura fork), servo-fetch, kuri-fetch, B4n1Web, ClawBrowser, headless-engine, clearcote (a real Chromium, as the control), chromium-headless-shell, koon, carbonyl, anoa, hwatu |

## The six harnesses

Each takes the tool list as argv and writes one JSONL row per probe plus the
literal stdout and stderr behind it.

| harness | what | rows |
|---|---|---|
| `hostile.py` | 24 URLs × tool: exit, latency, bytes, wall/login verdict | 384 |
| `challenge.py` | 7 challenge pages, solver verdict + `cf_clearance` | 42 |
| `fixture.py` | one capability fixture (JS, canvas, WebGL, storage, cookies, form) | 11 |
| `forms.py` | two real forms, fill → submit → look for the server echo | 22 |
| `tls_probe.py` | JA3/JA4/UA as seen by `tls.browserleaks.com` | 16 |
| `mem_probe.py` | cold start + peak RSS via `wait4(2)`, 3 runs | 15 |

`reclassify.py` recomputes wall/login verdicts from the raw bodies, so a
keyword in an engine's own JSON metadata can never be misread as a bot wall.
`gen_data.py` renders the data tables from the JSONL only — no number in the
report is typed by hand.

## The verdict rules

These are the same rules `sb get` uses, which is the point:

* **real content** — not a wall, not a login page, ≥ 200 bytes, exit not
  `timeout`.
* **wall** — the body or stderr contains a strong positive marker
  (`just a moment...`, `cf-mitigated`, `challenge-platform/h/`,
  `enable javascript and cookies`, `unusual traffic`, `身份核实`,
  `滑块验证`, …). The engine's own JSON keys are stripped first.
* **login wall** — sign-in / register / password markers. Counted separately,
  never as a bypass.
* **pass** (challenge probes only) — the content *behind* the gate, with no
  wall marker anywhere in the body, **and** for Cloudflare rows, a
  `cf_clearance` cookie.

`sb get` applies the first and second of these directly (see `SB_WALL_RE`), so
a wall that escalated in the corpus escalates here too.

## The sandbox it ran in

* no `bind(2)` at all — not loopback, not `AF_UNIX`-via-TCP. Anything that is
  "start a CDP server on 127.0.0.1:9222" cannot be run there.
* outbound TCP only on 443.
* no root, no package manager.
* `/tmp` volatile, `$HOME` writable.

So the tests are **one process, one URL, stdout** — the shape an agent actually
uses — not a driver session. That is also the shape `sb get` has.

## Reproducing

The bundle's own entry points, for anyone who has it:

```sh
cat FILES.md                 # what each file is
cat DATA.md                  # every result table, generated from the corpus
./verify.sh                  # 3 live checks with whatever obscura you have
python3 test/hostile.py nokk obscura     # 24-site sweep
python3 test/challenge.py nokk           # challenge pages
python3 test/tls_probe.py nokk           # JA3/JA4
python3 test/mem_probe.py nokk           # wall time + peak RSS
python3 gen_data.py                      # regenerate DATA.md
```

Without the bundle, the same measurements can be re-taken against the engines
`sb` installs:

```sh
sb install
sb doctor --live                          # every engine, one real fetch
sb solve https://www.scrapingcourse.com/cloudflare-challenge
sb run curl-impersonate -- --impersonate chrome152 -sS https://tls.browserleaks.com/json
sb run nokk -- --load https://tls.browserleaks.com/json --json
```
