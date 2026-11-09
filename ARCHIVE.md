# Where else this repo lives

`sb` is published to every lane that works from the host it was archived on,
and each lane was verified by asking the host what it serves — not by trusting
the push. Re-check with `ghless status --check`.

| lane | where | state |
|---|---|---|
| GitHub | https://github.com/Nemo-010/sb | head `f83512f` |
| Nostr (ngit/GRASP) | `nostr://npub15a8d7sdksj773eu7vtgxda4s34w7g3u8vagvgqvcsrn80ck9ymwqg7d97z/relay.ngit.dev/sb` | head `f83512f`, clone verified |
| Arweave | `arweave://TlAQ65mkOntVSRBiw9K8213c6vVrNqn8NUwpC3Mxvdg/sb` (tx `_Jv4rXkdwKeNcSyqq2Bbie54GfUsAT9FBBVhBmzNtPo`) | head `f83512f`, clone verified |
| Software Heritage | `swh:1:snp:810294ccdc983447bef69f00cc1ae831b0bbc4aa` | full visit |
| Local archive | git bundles, patch series, tarball, SHA-256 manifest, zip | in the ghless data dir |

Two lanes did not land from the archiving host, for host reasons rather than
project ones:

* **Radicle** needs a raw TCP seed connection and a local listener; that host
  denies `bind(2)` and every outbound port except 443, so no seed was
  reachable. Re-running `ghless publish --lanes radicle` from a host with
  normal egress completes it.
* **Wayback** answered HTTP 523 to every Save Page Now request and its CDX
  index has no capture. That is the archive refusing the request, not a
  missing URL.

Both are retried by re-running `ghless publish` / `ghless archive`; neither
needs a change to this repo.

## Recovering from a lane

```sh
git clone https://github.com/Nemo-010/sb
git clone "nostr://npub15a8d7sdksj773eu7vtgxda4s34w7g3u8vagvgqvcsrn80ck9ymwqg7d97z/relay.ngit.dev/sb"
git clone "arweave://TlAQ65mkOntVSRBiw9K8213c6vVrNqn8NUwpC3Mxvdg"
```

Software Heritage serves the whole history by content hash without any of the
above being reachable:

```
https://archive.softwareheritage.org/swh:1:snp:810294ccdc983447bef69f00cc1ae831b0bbc4aa
```
