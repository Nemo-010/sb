# Third-party programs sb installs

`sb` downloads and runs other people's programs as separate processes. It does
not modify, bundle or redistribute them; it fetches the upstream release
assets at install time and verifies them against the sha256 pinned in `sb`.

Their licences are theirs, not `sb`'s 0BSD:

| engine | pinned | licence | upstream |
|---|---|---|---|
| nokk | 0.1.49-alpha | Apache-2.0 | https://github.com/koloss777/nokk |
| obscura | 0.2.6 | Apache-2.0 | https://github.com/h4ckf0r0day/obscura |
| lightpanda | 1.0.3 | AGPL-3.0 | https://github.com/lightpanda-io/browser |
| moli | 1.1.22 | Apache-2.0 | https://github.com/lexmount/moli |
| curl-impersonate | 2.3.2 | MIT | https://github.com/lexiforest/curl-impersonate |

Note on lightpanda: it is AGPL-3.0, not 0BSD/Apache. `sb` runs it as a
separate executable over its CLI and never links against it, but if you
redistribute a bundle that contains it, the AGPL's terms come with it.

The Apache-2.0 engines ship their own `LICENSE`/`NOTICE` files inside the
release assets, which `sb` extracts alongside the binary.
