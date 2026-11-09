# Why these five engines

`sb` did not pick its engines by preference. They are the survivors of a
measurement sweep run on 2026-11-09: **15,974 repositories** discovered through
120 English and 32 Chinese search phrases plus topics and name queries, cut to
90 read by hand, 16 downloaded and actually run against 24 hostile sites, 7
public challenge pages, a capability fixture, two real forms and a TLS
fingerprint oracle.

This file records the numbers behind the choice, and the biases in them, so a
later reader can decide whether to move a pin. The full corpus is separate; a
summary of it is in [docs/corpus.md](docs/corpus.md).

## Hostile-site sweep (24 URLs, one process per run, no proxy)

Counting only outcomes that are real page content, not a bot wall, not a login
wall, not an empty shell:

| engine | real content | bot walls | login walls | timeouts | avg s |
|---|---|---|---|---|---|
| curl-impersonate (Chrome 152) | **15** | 9 | 0 | 0 | 0.6 |
| curl-impersonate (Firefox 147) | 14 | 9 | 0 | 0 | 0.6 |
| plain curl + Chrome UA | 13 | 10 | 0 | 0 | 0.7 |
| **nokk** 0.1.49-alpha | 13 | **2** | 9 | 0 | 5.5 |
| lightpanda 1.0.3 | 12 | 3 | 9 | 0 | 1.5 |
| obscura 0.2.6 | 8 | 4 | 9 | 0 | 7.1 |
| moli 1.1.22 | 4 | 6 | 9 | 0 | 2.3 |

The bot-wall column is the one that matters. **nokk at 2 is the only engine in
single digits** — the rest of the field sits at 3–6, and a real Chromium with
no stealth patches is at 4. The "login wall" column is not a failure: LinkedIn,
X, Instagram and Zhihu serve a login page to any client, bot or not.

Two findings decide the top of the recommendation:

1. **curl-impersonate beats every actual browser on raw content retrieval**,
   because it never runs the JavaScript that *creates* the bot wall. On sites
   where the content is server-rendered and only the fingerprint is checked, an
   impersonating HTTP client is simply better: faster, 3× lighter, no wall to
   clear. That is why it is first in `sb get`'s text chain.
2. **It loses exactly where a browser is needed** — the two Cloudflare rows
   that require *executing* the challenge. nokk wins those. The real decision
   is not "browser vs not", it is "does the target gate on the handshake or on
   the JavaScript".

## Challenge clearing, isolated (7 public challenge pages)

| tool | scrapingcourse shield | nopecha interstitial | nowsecure | chess.com | `cf_clearance` ever |
|---|---|---|---|---|---|
| **nokk** `--solve-challenge 30` | **cleared** | **cleared** | **cleared** | **cleared** | **yes** |
| nokk, no flag | cleared | wall | cleared | cleared | yes (cached) |
| obscura `--stealth` | wall | wall | cleared | cleared | no |
| moli | wall | wall | wall | cleared | no |
| a real Chromium | wall | wall | cleared | cleared | no |

`cf_clearance` is the only durable proof, and only nokk produces it. This is
the single capability that makes nokk non-optional, and the reason `sb get`
escalates to a solver pass rather than returning a challenge page as content.

The interesting failure is **obscura**: with `--stealth` it reaches Cloudflare's
*"Verification successful. Waiting for &lt;site&gt; to respond"* state and stops.
The interstitial's JavaScript ran; the gate's second half did not. That is
neither a clean pass nor a clean fail, and a report that counted it either way
would be wrong.

## Capability probe

| engine | JS ran | canvas 2D | `localStorage` | cookie | screenshot | PDF |
|---|---|---|---|---|---|---|
| obscura | yes | yes | yes | yes | PNG | no CLI |
| moli | yes | yes | yes | yes | PNG | yes |
| nokk | yes | yes | yes | yes | **no** | no |
| lightpanda | yes | **stub (hash 0)** | yes | yes | stub | stub |
| curl-impersonate | **no** | — | — | — | no | no |

Lightpanda's canvas hash is `0`: it returns a blank surface, so anything that
fingerprints by canvas sees a value no browser has ever produced — a stealth
liability disguised as a pass. Its `--dump png` produces a large file that
paints no CSS (measured: a 1920×284 image whose 546,240 pixels are 50 colours,
98% white). `sb engines` marks those as `stub`, not `yes`.

## What the wire sees (tls.browserleaks.com)

| engine | JA4 | verdict |
|---|---|---|
| curl-impersonate Chrome 152 | `t13d1517h2_8daaf6152771_cb7bf5808d99` | a real Chrome ClientHello |
| nokk | `t13d1516h2_8daaf6152771_806a8c22fdea` | Chrome-family, second hash differs |
| obscura `--stealth` | `t13d1516h2_8daaf6152771_d8a2da3f94cd` | Chrome-family |
| obscura (default build) | `t13d1011h1_61a7ad8aa9b6_3fcd1a44f3e3` | **`h1` + 10 ciphers: no Chrome ever sent this** |
| moli | `t13d2010h2_a8347f2c98c8_08b0b9cb7c24` | Chrome-shaped, own cipher set |
| lightpanda | `t13d1710h2_5b57614c22b0_95ca0cbbc74b` | own fingerprint |

This is why `sb` installs obscura's **stealth** asset, not the default one. The
default build presents an HTTP/1.1-only, 10-cipher handshake under a
`Chrome/143` User-Agent — a guaranteed inconsistency for any TLS-fingerprint
checker.

## Cost

| engine | cold start (median) | peak RSS (median) |
|---|---|---|
| lightpanda | 0.37 s | **24.8 MiB** |
| obscura | 0.10 s | 38.1 MiB |
| obscura `--stealth` | 0.14 s | 40.0 MiB |
| moli | 0.09 s | 54.9 MiB |
| nokk | 0.19 s | 84.9 MiB |
| a bundled Chromium | 0.57 s | 211.5 MiB *lower bound* |

nokk costs ~85 MiB because it keeps a V8 isolate plus a solver in one process.
That is the price of the only working solver in the field, and it is why `sb`
puts it after curl-impersonate rather than first.

## Known biases — read these before quoting a number

1. **One IP, one datacenter, one hour.** Every result is from a single
   Hetzner-class address. A residential IP would change the Cloudflare rows,
   possibly not in the engines' favour.
2. **Single run per (engine, URL).** Challenge solving is stochastic.
3. **No proxy** was used, though most engines support one.
4. **Wall detection is regex-based**, tuned to under-report a wall rather than
   over-report. `sb` uses the same marker set so its classification matches the
   corpus.
5. **Chromium's memory is a lower bound** — `ru_maxrss` of the direct child only.
6. The fixture's cross-origin `fetch()` check was invalid on every engine
   (the host's CSP blocked it), so it is not evidence and is not used.

## What was not measured, and why

Anything that is a **server first** could not be timed in the sandbox the
corpus was built in, because `bind(2)` is denied there: diting, mimic, kuri's
server half, bobby-browser, webrain, hwatu, anoa. This is a limitation of that
sandbox, not a judgement on those tools, and the same limitation is why `sb`
tells you that `obscura serve` will not start in such a cage.

Also not measured: the camoufox/fortress/ghostfox Chromium-and-Firefox bundles
(1.3 GB each; the control — a real Chromium — already scored 4 real pages and
4 walls, so the result was predictable), and browser_oxide, whose Linux MCP
binary completes its handshake and then hits its own 25 s deadline on every
navigation.

## Outcome

```
text      curl-impersonate -> nokk -> obscura -> lightpanda -> moli
markdown  obscura -> lightpanda -> moli -> curl-impersonate+strip
html      curl-impersonate -> obscura -> lightpanda -> moli
links     obscura -> nokk -> curl-impersonate
png       obscura -> moli -> lightpanda
pdf       moli -> lightpanda
```

Every entry is justified by the tables above. If a future release changes one
of those numbers, the pin is what moves — see `sb install <engine> --latest`.
