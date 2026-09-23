%%% @doc The embed procedure: what a caller sends and what it gets back.
%%%
%%% This is the contract mcl-rag and any other caller builds against. Runs on
%%% mcl_embed's deterministic stub (the default build), so it pins shape and
%%% routing, not embedding quality.
-module(serve_embed_tests).

-include_lib("eunit/include/eunit.hrl").

embed_test_() ->
    {setup,
     fun() -> {ok, Apps} = application:ensure_all_started(mcl_embed), Apps end,
     fun(Apps) -> [application:stop(A) || A <- lists:reverse(Apps)] end,
     [fun one_text_gets_one_vector/0,
      fun many_texts_get_many_vectors/0,
      fun kind_selects_the_retrieval_prefix/0,
      fun every_key_and_text_form_is_accepted/0,
      fun a_request_with_no_text_is_refused/0]}.

one_text_gets_one_vector() ->
    {reply, #{vector := V}, _} = serve_embed:handle_request(#{text => <<"hello">>}, state()),
    ?assertEqual(384, length(V)),
    ?assert(lists:all(fun is_float/1, V)).

many_texts_get_many_vectors() ->
    {reply, #{vectors := Vs}, _} =
        serve_embed:handle_request(#{texts => [<<"a">>, <<"b">>, <<"c">>]}, state()),
    ?assertEqual(3, length(Vs)).

%% `query' and `passage' apply the model's asymmetric-retrieval prefixes, so
%% the same text embeds differently under each; anything else is raw.
kind_selects_the_retrieval_prefix() ->
    Q = vector(#{text => <<"leak">>, kind => <<"query">>}),
    P = vector(#{text => <<"leak">>, kind => <<"passage">>}),
    R = vector(#{text => <<"leak">>}),
    ?assertNotEqual(Q, P),
    ?assertNotEqual(Q, R),
    ?assertEqual(R, vector(#{text => <<"leak">>, kind => <<"raw">>})).

%% macula hands a key over as an atom only when the atom exists, otherwise as
%% text, and a text value as {text, Bin}. A non-BEAM caller's string must work.
every_key_and_text_form_is_accepted() ->
    Plain = vector(#{text => <<"hello">>, kind => <<"query">>}),
    ?assertEqual(Plain, vector(#{<<"text">> => {text, <<"hello">>},
                                 {text, <<"kind">>} => {text, <<"query">>}})),
    ?assertEqual(Plain, vector(#{text => <<"hello">>, kind => query})).

a_request_with_no_text_is_refused() ->
    ?assertMatch({error, bad_request, _}, serve_embed:handle_request(#{}, state())),
    ?assertMatch({error, bad_request, _},
                 serve_embed:handle_request(#{text => 42}, state())).

%% --- helpers ---

state() ->
    {ok, S} = serve_embed:init([]),
    S.

vector(Request) ->
    {reply, #{vector := V}, _} = serve_embed:handle_request(Request, state()),
    V.
