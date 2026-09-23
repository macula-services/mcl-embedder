# Changelog

## 0.1.0 (unreleased)

Ported from `hecate-services/hecate-embedder` 0.1.3 onto `mcl_om`, macula 12
and `mcl_embed` 0.1.

- **The procedure is `mcl-embedder/embed`**, advertised through mcl_om's
  standard provider path. The hand-rolled advertiser of the bare
  `io.hecate.embed` is gone.
- **Health reports a missing provider grant** instead of `ok`.
- The request and reply are unchanged; text is accepted as a binary or as CBOR
  text under any key form.
