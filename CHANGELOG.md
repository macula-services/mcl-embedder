# Changelog

## 0.1.0 (unreleased)

Ported from `hecate-services/hecate-embedder` 0.1.3 onto `mcl_om`, macula 12
and `mcl_embed` 0.1.

- **On `mcl_om` 0.28 with macula 12.2.** The service answers `mcl-embedder/info`,
  which mcl_om adds (public facts: versions, labels, health word, procedures),
  and a test sends that reply through macula's frame codec and checks it names
  this service and the mcl_om 0.28 / macula 12.2 pair. 0.28 is the release
  macula 12.2 needs: under 12.2 an older mcl_om lets a failed publish
  announcement kill the publishing process.
- **On `mcl_om` 0.27; the boot claim says which service, which box.** The claim
  carries `MCL_SERVICE_NAME=mcl-embedder` and the host's `MCL_BOX`, shown on the
  realm's Providers desk. 0.27 no longer brings barrel_docdb or rocksdb, so the
  image drops their codec libraries.
- **The team image pair.** Builds in `macula-ci-otp` and runs on
  `macula-pq-runtime` (Debian trixie, glibc), both pinned by dated tag and
  digest, instead of floating `erlang:28` and `debian:trixie-slim`. CI runs in
  the same build image and adds dialyzer; `.tool-versions` moves to 28.4.3.

- **The procedure is `mcl-embedder/embed`**, advertised through mcl_om's
  standard provider path. The hand-rolled advertiser of the bare
  `io.hecate.embed` is gone.
- **Health reports a missing provider grant** instead of `ok`.
- The request and reply are unchanged; text is accepted as a binary or as CBOR
  text under any key form.
