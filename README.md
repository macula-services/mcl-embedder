# mcl-embedder

**Multilingual sentence embeddings as a mesh procedure, for callers that cannot run the ONNX model themselves.**

This exists so every service on the mesh can embed text, even on a box that
cannot run the model, by calling the one box that can.

## Status

Built and tested locally, **not yet deployed**. Runs on macula 12 through
`mcl_om`, on [`mcl_embed`](https://github.com/macula-services/mcl-embed)
(fastembed over ONNX, `multilingual-e5-small`, 384 dimensions). It replaces
`hecate-services/hecate-embedder` and inherits nothing from it.

## The procedure

`mcl-embedder/embed`, request and reply:

| Request | Reply |
|---|---|
| `#{text => Text}` | `#{vector => [float()]}` |
| `#{text => Text, kind => <<"query">>}` | the same, with the model's query prefix applied |
| `#{text => Text, kind => <<"passage">>}` | the same, with the model's passage prefix applied |
| `#{texts => [Text]}` | `#{vectors => [[float()]]}` |

`kind` is how a caller does asymmetric retrieval without knowing the model's
convention: embed what you store as `passage` and what you search with as
`query`. Anything else, or none, embeds the text as it is. Text may be sent as a
binary or as CBOR text; a request with no text is refused with `bad_request`.

The name and the request are pinned by tests (`mcl_embedder_service_tests`,
`serve_embed_tests`). A change is a new name, not an edit.

## Requirements

⚠ **An AVX2 host.** The ONNX Runtime SIGILLs on a CPU without AVX2, taking the
node down with it. Run one embedder on an AVX2 box and let everything else call
it over the mesh.

The image is **Debian (glibc)**, not the Alpine every other mcl service uses:
the ONNX Runtime fastembed links is prebuilt against glibc. The model is baked
into the image at build time, so a container never downloads it.

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `MCL_REALM` | required | 64-hex realm tag |
| `MCL_REALM_KEY` | required | the realm's public signing key, hex |
| `MACULA_STATION_SEEDS` | required | station hosts, `host[:port]`, comma-separated |
| `MACULA_STATION_NODE_IDS` | required | the matching 64-hex station node ids |
| `MCL_HEALTH_PORT` | `8480` | health endpoint |
| `MCL_SERVICE_NAME` | `mcl-embedder` | label on the boot claim the realm's operator sees on the Providers desk |
| `MCL_BOX` | unset | label naming the host, also on the boot claim; set it where you deploy |
| `MCL_EMBED_MODEL_DIR` | `/models` | where the baked model is (set in the image) |

## Deploy

1. Run it on an **AVX2** host, with `deploy/docker-compose.yml`, which mounts
   the named identity volume `mcl-embedder-secrets`.
2. **Have the realm grant this node its provider authorization** for
   `mcl-embedder/embed` (D25). Until then nothing is advertised, every call
   resolves to nothing, and `/health` (mcl_om's own check) is degraded, naming
   `mcl-embedder/embed` under `provider_grants`. A new identity is a new,
   unadmitted node, so keep the volume.

## Health

`/health` reports whether callers can reach the procedure: a missing provider
grant is `degraded`. The model loads on the first call and is not probed.

## Build and test

    rebar3 eunit      # runs mcl_embed's deterministic stub, not the model
    rebar3 lint

A Rust toolchain is needed: `mcl_embed` builds its NIF from source. The image
builds the real model (`CARGO_FEATURES=real-embed`). OTP 28.4.3, pinned in
`.tool-versions`, the `Containerfile` and CI, and a test fails when they
disagree with the VM running it. The image builds in the team's
`ghcr.io/macula-io/macula-ci-otp` and runs on `ghcr.io/macula-io/macula-pq-runtime`
(Debian trixie, glibc, which the ONNX Runtime needs), both pinned by dated tag
and digest; CI runs in the same build image.

## License

Apache-2.0. See [LICENSE](LICENSE).
