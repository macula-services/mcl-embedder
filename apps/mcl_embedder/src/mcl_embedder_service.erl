%% @doc The mcl_om service contract: what this service is and may do.
%%
%% SIX CALLBACKS, ALL REQUIRED. mcl_om resolves them BY NAME at startup, on a
%% live node, so a service that forgets one dies with `undef' where nobody is
%% watching. The `-behaviour' attribute below is what turns that into a compile
%% error instead, and the generated test suite guards the attribute itself.
%%
%% IT ANNOUNCES NOTHING AND ASKS FOR NOTHING, on purpose. A service that does
%% nothing yet has no capability to offer and needs no authority from the realm.
%% Advertising a capability before it exists puts a lie on the mesh that another
%% service can find and call. Both lists grow when the thing they name exists,
%% and a generated test fails when they change, so growing them is a deliberate
%% act rather than a comment someone forgot.
-module(mcl_embedder_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).

info() ->
    #{name => <<"mcl-embedder">>,
      version => <<"0.1.0">>,
      description => <<"Multilingual sentence embeddings as a mesh procedure, for callers that cannot run the ONNX model themselves">>}.

start(_Opts) -> mcl_embedder_sup:start_link().

stop(_State) -> ok.

%% Nothing of the service's own to report: whether callers can REACH the
%% procedure (its realm-issued D25 provider grant) is reported by mcl_om's
%% /health itself, combined with this verdict. The model loads lazily on the
%% first call, so it is not probed here.
health() -> ok.

%% `mcl-embedder/embed' (the org comes from config): text in, vectors out.
%% See serve_embed for the request and reply.
capabilities() ->
    [#{name => <<"embed">>, version => 1, handler => {serve_embed, []}}].

%% The authority is the D25 provider grant, issued by the realm per procedure,
%% not something this service asks for.
identity_spec() ->
    #{scope => <<"mcl-embedder">>,
      actions => [],
      resources => [],
      ttl_days => 30}.
