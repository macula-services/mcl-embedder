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
# ⚠ THE RUNTIME IS PINNED IN TWO PLACES AND THEY MUST AGREE: here and
# `lint.yml' beside it.
FROM docker.io/erlang:28 AS builder
WORKDIR /build

# cmake/build-essential and the compression -dev packages: mcl_om pulls in
# rocksdb (barrel_docdb) and khepri/ra transitively, even for a storeless
# service. Rust: mcl_embed and macula compile their NIFs from source.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl bash build-essential cmake \
        libsnappy-dev liblz4-dev libzstd-dev libbz2-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
ENV MACULA_FORCE_SOURCE_BUILD=1

RUN curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3

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

FROM docker.io/debian:trixie-slim
LABEL org.opencontainers.image.source="https://github.com/macula-services/mcl-embedder"
RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl3 zlib1g libbrotli1 libzstd1 libstdc++6 libncurses6 \
        libsnappy1v5 liblz4-1 libbz2-1.0 \
        ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
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
