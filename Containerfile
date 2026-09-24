# mcl-embedder
#
# Multilingual sentence embeddings as a mesh procedure, for callers that cannot
# run the ONNX model themselves.
#
# ⚠ GLIBC, NOT ALPINE, IN BOTH STAGES. fastembed links an ONNX Runtime that is
# prebuilt against glibc; on musl it builds and then fails to load the model.
# This is why the image departs from the mcl_service scaffold's Alpine base.
# A generated test asserts the runtime stage stays glibc.
#
# ⚠ THE HOST NEEDS AVX2. The ONNX Runtime SIGILLs on a CPU without it (the
# Celeron J4105 nodes, for example). Run this image on an AVX2 host and reach
# it over the mesh; that is what the service is for.
#
# ⚠ THE TEAM IMAGE PAIR, PINNED BY DATED TAG AND DIGEST. macula-ci-otp is
# macula-io/macula-ci-images' build image: OTP 28.4.3 on Debian trixie with an
# OpenSSL carrying ML-DSA, rebar3 3.27.0 and Rust, all pinned. The release runs
# on macula-pq-runtime of the same date, the same Debian, so its ERTS and NIFs
# match the runtime's glibc. 20260923-1444 is the pair the rocksdb images are
# derived from, so every mcl service sits on one base. lint.yml pins the same
# build image, and the service tests guard all three pins.
FROM ghcr.io/macula-io/macula-ci-otp:20260923-1444@sha256:dd2ba6eb858a0eacedf0179300323fe5c6da46fb308d22da0ca8cfcd1f0718dc AS builder

# ⚠ THE OTP RELEASE, ASSERTED HERE because the image tag names a date, not a
# release. The same check as lint.yml's toolchain step; the service tests read
# this line and compare it with .tool-versions and lint's.
RUN erl -noshell -eval ' \
    Otp = string:trim(element(2, file:read_file(filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"])))), \
    Mldsa = lists:member(mldsa87, crypto:supports(public_keys)), \
    io:format("OTP ~s, mldsa87 ~p~n", [Otp, Mldsa]), \
    case {Otp, Mldsa} of \
        {<<"28.4.3">>, true} -> halt(0); \
        _                    -> halt(1) \
    end.'

WORKDIR /build

COPY rebar.config ./
RUN rebar3 get-deps

# The REAL embedder, not the deterministic stub: mcl_embed's own build hook
# reads this when it compiles its NIF.
ENV CARGO_FEATURES=real-embed

COPY config ./config
COPY apps ./apps
RUN rebar3 compile

# Bake the model into the image, so a container never downloads it at start
# and a box with no route to the model host still serves. Loading it through
# the NIF is what fetches it, which also proves the real backend was built.
RUN mkdir -p /models && erl -noshell -pa _build/default/lib/mcl_embed/ebin \
      -eval 'case mcl_embed_nif:load(<<"intfloat/multilingual-e5-small">>, 384, <<"/models">>) of {ok, _} -> io:format("baked model into /models~n"); E -> io:format(standard_error, "model bake failed: ~p~n", [E]), halt(1) end' \
      -s init stop

RUN rebar3 as prod release

FROM ghcr.io/macula-io/macula-pq-runtime:20260923-1444@sha256:15a5501b7277804c5a62c93121d157773d1401d238a1bf630ef4b50fc2f1df09
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-embedder"
# The runtime image is Debian trixie (glibc, which the ONNX Runtime needs) and
# carries what the release loads: OpenSSL 3.5, libz, libzstd, libstdc++,
# libtinfo, and curl for the healthcheck below. The embed NIF links libssl,
# libcrypto, libz and libzstd, all present.
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/mcl_embedder ./
COPY --from=builder /models /models

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true

ENV MCL_NODE_NAME=mcl_embedder
ENV MCL_NODE_HOST=127.0.0.1
ENV MCL_COOKIE=mcl_embedder
ENV MCL_HEALTH_PORT=8480
# Where mcl_embed finds the baked model.
ENV MCL_EMBED_MODEL_DIR=/models

# The node identity key: a NAMED volume in deploy/docker-compose.yml. It is the
# node the realm grants provider authorization to.
VOLUME ["/etc/mcl/secrets"]

EXPOSE 8480
# A longer start period: the first embed loads the model.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${MCL_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/mcl_embedder", "foreground"]
