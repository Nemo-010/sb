# Where else this repo lives

`sb` is published to every lane that works from the host it was archived on,
and each lane was verified by asking the host what it serves — not by trusting
the push. Re-check any time with:

```sh
ghless status --check
```

| lane | where |
|---|---|
| GitHub | https://github.com/Nemo-010/sb |
| Nostr (ngit/GRASP) | `nostr://npub15a8d7sdksj773eu7vtgxda4s34w7g3u8vagvgqvcsrn80ck9ymwqg7d97z/relay.ngit.dev/sb` |
| Arweave | `arweave://TlAQ65mkOntVSRBiw9K8213c6vVrNqn8NUwpC3Mxvdg/sb` |
| Software Heritage | `swh:1:snp:810294ccdc983447bef69f00cc1ae831b0bbc4aa` (full visit) |
| Local archive | git bundles, patch series, tarball, SHA-256 manifest and zip, in the ghless data dir |

This file deliberately does not name a commit: writing a hash into a file
changes the commit, so it would always be one behind. The lanes are kept in
sync by re-running `ghless publish` after a push; `ghless status --check`
prints the head each host actually serves.

## Recovering from a lane

```sh
git clone https://github.com/Nemo-010/sb
git clone "nostr://npub15a8d7sdksj773eu7vtgxda4s34w7g3u8vagvgqvcsrn80ck9ymwqg7d97z/relay.ngit.dev/sb"
git clone "arweave://TlAQ65mkOntVSRBiw9K8213c6vVrNqn8NUwpC3Mxvdg/sb"
```

Software Heritage serves the whole history by content hash, without any of the
above being reachable:

```
https://archive.softwareheritage.org/swh:1:snp:810294ccdc983447bef69f00cc1ae831b0bbc4aa
```

## Two lanes that did not land from the archiving host

Both are host limitations, not project ones, and both are retried by re-running
`ghless publish` / `ghless archive` from a host with normal egress.

* **Radicle** needs a raw TCP connection to a seed and a local listener. That
  host denies `bind(2)` and every outbound port except 443, so no seed was
  reachable and `cfrs warp` could not open the local forward either.
* **Wayback** answered HTTP 523 to every Save Page Now request and its CDX
  index holds no capture for this URL. That is the archive refusing the
  request, not a missing repo.
