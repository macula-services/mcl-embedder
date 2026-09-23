%% @doc The `mcl-embedder/embed' procedure: text in, vectors out.
%%
%%   #{text => Text, kind => <<"query">> | <<"passage">> | <<"raw">>}
%%       -> #{vector => [float()]}
%%   #{texts => [Text]}
%%       -> #{vectors => [[float()]]}
%%
%% `kind' applies the model's asymmetric-retrieval prefix (e5's `query:' and
%% `passage:'), so a caller does not need to know the model's convention;
%% anything else, or none, embeds the text as it is.
%%
%% Fields are read through mcl_om_wire:field/2: macula hands a key over as an
%% atom only when that atom already exists, and a text value from a non-BEAM
%% caller as `{text, Bin}'.
-module(serve_embed).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(Request, State) ->
    answer(served(text(mcl_om_wire:field(text, Request)),
                  mcl_om_wire:field(texts, Request),
                  kind(mcl_om_wire:field(kind, Request))),
           State).

served(Text, _Texts, Kind) when is_binary(Text) ->
    one(embedded(Kind, Text));
served(_Text, Texts, _Kind) when is_list(Texts) ->
    many(all_text([text(T) || T <- Texts]));
served(_Text, _Texts, _Kind) ->
    {error, bad_request}.

answer({ok, Reply}, State)      -> {reply, Reply, State};
answer({error, Reason}, State)  -> {error, Reason, State}.

embedded(<<"query">>, Text)   -> mcl_embed:embed_query(model(), Text);
embedded(<<"passage">>, Text) -> mcl_embed:embed_passage(model(), Text);
embedded(_Raw, Text)          -> mcl_embed:embed(model(), Text).

one({ok, Vector})      -> {ok, #{vector => Vector}};
one({error, _} = Err)  -> Err.

many({ok, Texts})       -> vectors(mcl_embed:embed_many(model(), Texts));
many({error, _} = Err)  -> Err.

vectors({ok, Vectors})  -> {ok, #{vectors => Vectors}};
vectors({error, _} = Err) -> Err.

model() ->
    {ok, Model} = mcl_embed:default_model(),
    Model.

text({text, Bin}) when is_binary(Bin) -> Bin;
text(Bin) when is_binary(Bin)         -> Bin;
text(_)                               -> undefined.

all_text(Texts) -> all_text(lists:member(undefined, Texts), Texts).

all_text(true, _Texts) -> {error, bad_request};
all_text(false, Texts) -> {ok, Texts}.

kind(K) when is_atom(K), K =/= undefined -> atom_to_binary(K, utf8);
kind(K) -> text(K).
