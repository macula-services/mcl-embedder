%% @doc The service contract, asserted locally.
%%
%% mcl_om resolves its six callbacks BY NAME at startup, on a live node, so a
%% service that forgets one dies with `undef' where nobody is watching. The
%% primary defence is the `-behaviour(mcl_om_service)' attribute on the
%% service module, which turns a missing callback into a compile error under
%% warnings_as_errors.
%%
%% What this suite adds is everything the compiler cannot see: that the attribute
%% has not been quietly dropped, that the values inside those callbacks are the
%% shapes mcl_om will destructure, and that the names and version this service
%% reports are the ones it actually has. Nothing local boots mcl_om, so
%% asserting the shape by hand is the closest available thing to a rehearsal.
-module(mcl_embedder_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(APP, mcl_embedder).
-define(SERVICE, mcl_embedder_service).

%% Belt and braces with the behaviour attribute, and it survives the attribute
%% being removed. If mcl_om ever adds a SEVENTH required callback this test
%% keeps passing and the deploy still breaks, which is the honest limit of a
%% local assertion about a remote contract.
exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1},
                {health, 0}, {capabilities, 0}, {identity_spec, 0}],
    Missing = [F || {N, A} = F <- Required,
                    not erlang:function_exported(?SERVICE, N, A)],
    ?assertEqual([], Missing).

info_carries_the_three_keys_test() ->
    #{name := Name, version := Vsn, description := Desc} = ?SERVICE:info(),
    ?assert(is_binary(Name)),
    ?assert(is_binary(Vsn)),
    ?assert(is_binary(Desc)),
    ?assertEqual(<<"mcl-embedder">>, Name).

%% THE TWO NAMES MUST AGREE. The OTP application is snake_case because it is an
%% Erlang atom; the repository, the container image and the name this service
%% answers to on the mesh are kebab-case. They describe one service, so a
%% scaffold generated with a mismatched pair is caught here on the first eunit
%% run rather than by a puzzled reader months later.
mesh_name_matches_the_application_test() ->
    #{name := Wire} = ?SERVICE:info(),
    Snake = atom_to_binary(?APP, utf8),
    ?assertEqual(binary:replace(Snake, <<"_">>, <<"-">>, [global]), Wire).

%% The version in info/0 is what a peer reads off /health, so it disagreeing with
%% the application it describes is a lie that nothing else would catch.
info_version_matches_the_application_test() ->
    _ = application:load(?APP),
    {ok, Vsn} = application:get_key(?APP, vsn),
    #{version := Reported} = ?SERVICE:info(),
    ?assertEqual(list_to_binary(Vsn), Reported).

%%==============================================================================
%% The contract callers dial
%%==============================================================================

%% One procedure, `mcl-embedder/embed', the way mcl_om registers it. mcl-rag
%% builds against this name. A change is a new name, not an edit.
the_procedure_is_the_published_contract_test() ->
    ?assertEqual([<<"mcl-embedder/embed">>],
                 [mcl_om_capabilities:org_procedure(<<"mcl-embedder">>, Name)
                  || #{name := Name} <- ?SERVICE:capabilities()]).

the_procedure_is_served_by_serve_embed_test() ->
    ?assertMatch([#{handler := {serve_embed, []}}], ?SERVICE:capabilities()).

the_shipped_config_names_the_org_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assertNotEqual(nomatch, binary:match(Text, <<"{org,               <<\"mcl-embedder\">>}">>)).

%%==============================================================================
%% Health: whether callers can reach it
%%==============================================================================

%% A missing D25 provider grant is reported by mcl_om itself (>= 0.26.3),
%% combined with this service's own verdict, which is ok.
the_service_itself_is_healthy_test() ->
    ?assertEqual(ok, ?SERVICE:health()).

%% A build that resolved an mcl_om older than 0.26.3 would compile and lose the
%% grant check without a word, so the function it rests on must exist.
the_resolved_mcl_om_reports_provider_grants_test() ->
    {module, _} = code:ensure_loaded(mcl_om_capabilities),
    ?assert(erlang:function_exported(mcl_om_capabilities, provider_grants, 0)).

identity_spec_asks_for_nothing_test() ->
    #{actions := Actions, resources := Resources} = ?SERVICE:identity_spec(),
    ?assertEqual([], Actions),
    ?assertEqual([], Resources).

%% Nothing to supervise: the procedure is served by mcl_om's provider path and
%% the model by mcl_embed's own supervisor.
supervisor_has_no_children_test() ->
    {ok, {_Flags, Children}} = mcl_embedder_sup:init([]),
    ?assertEqual([], Children).

%%==============================================================================
%% The image: glibc, the real model, baked in
%%==============================================================================

%% fastembed's ONNX Runtime is prebuilt against glibc, so the runtime image
%% is the team's macula-pq-runtime (Debian trixie), never Alpine (musl): an
%% Alpine image would build and then fail to load the model.
the_runtime_image_is_glibc_test() ->
    Runtime = runtime_stage(),
    ?assertEqual(nomatch, binary:match(Runtime, <<"alpine">>)),
    ?assertMatch(<<"ghcr.io/macula-io/macula-pq-runtime:", _/binary>>, Runtime).

%% Built with the real embedder, not the deterministic stub, and the model is
%% baked into the image where the library is told to look for it.
the_image_builds_the_real_model_test() ->
    {ok, Text} = file:read_file(alongside("Containerfile")),
    ?assertNotEqual(nomatch, binary:match(Text, <<"CARGO_FEATURES=real-embed">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"COPY --from=builder /models /models">>)),
    ?assertNotEqual(nomatch, binary:match(Text, <<"MCL_EMBED_MODEL_DIR=/models">>)).

runtime_stage() ->
    {ok, Text} = file:read_file(alongside("Containerfile")),
    Parts = binary:split(Text, <<"\nFROM ">>, [global]),
    lists:last(Parts).

%%==============================================================================
%% The runtime is pinned in two places, and neither is the one you are running
%%==============================================================================

%% ⚠ THIS GUARD EXISTS BECAUSE A SIBLING SERVICE DID NOT HAVE IT, AND IT COST
%% THREE COMMITS AND AN IMAGE THAT SHIPPED ANYWAY.
%%
%% Its `Containerfile' said 27 while development ran on 28. So `rebar3 eunit'
%% passing locally meant "passing on 28" and nothing more, CI failed on a crash
%% that does not occur on 28 at all, and because the image build is a separate
%% workflow the image went to the fleet regardless.
%%
%% The release is pinned in TWO files, and the version actually running is a
%% third thing that agrees with neither by default. **A comment in each file
%% saying they must match is not a mechanism**, and both files carried one.
%%
%% ⚠⚠ IT FAILS RATHER THAN WARNS WHEN YOUR VM DIFFERS, AND THAT IS DELIBERATE.
%% Developing on a release you do not ship makes a green suite mean less than it
%% appears to. If you want to work on another release, move both pins and find
%% out what breaks, which is the whole point of having them.
the_runtime_agrees_between_the_image_the_ci_and_this_vm_test() ->
    %% The team images' tags name a date, not a release, so the builder and
    %% lint each assert the release in a check step; this compares those, the
    %% .tool-versions pin and this VM, to the patch.
    Check = "\\{<<\"([0-9]+\\.[0-9]+\\.[0-9]+)\">>, true\\} -> halt\\(0\\);",
    Image = pinned("Containerfile", Check),
    CiCheck = pinned(".github/workflows/lint.yml", Check),
    Tools = pinned(".tool-versions", "^erlang ([0-9]+\\.[0-9]+\\.[0-9]+)$"),
    %% Sorted and deduplicated, so a failure prints every version rather than
    %% the first pair that happened to be compared.
    ?assertEqual([Image], lists:usort([Image, CiCheck, Tools, running_otp()])).

%% Build, CI and runtime are the team pair, named by dated tag AND digest, so a
%% re-pushed tag cannot change what builds or what runs.
images_are_the_digest_pinned_team_pair_test() ->
    Digest = ":[0-9]{8}-[0-9]{4}@sha256:[0-9a-f]{64}",
    ?assertMatch(<<_/binary>>,
                 pinned("Containerfile",
                        "^FROM (ghcr\\.io/macula-io/macula-ci-otp)" ++ Digest ++ " AS builder$")),
    ?assertMatch(<<_/binary>>,
                 pinned("Containerfile",
                        "^FROM (ghcr\\.io/macula-io/macula-pq-runtime)" ++ Digest ++ "$")),
    ?assertMatch(<<_/binary>>,
                 pinned(".github/workflows/lint.yml",
                        "^\\s+image: (ghcr\\.io/macula-io/macula-ci-otp)" ++ Digest ++ "$")).

%% The full release, 28.4.3 and not 28: `otp_release' names only the major.
running_otp() ->
    {ok, Version} = file:read_file(filename:join([code:root_dir(), "releases",
                                                  erlang:system_info(otp_release),
                                                  "OTP_VERSION"])),
    string:trim(Version).

pinned(Relative, Pattern) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    {match, [Version]} = re:run(Text, Pattern,
                                [multiline, {capture, all_but_first, binary}]),
    Version.

%% Relative to the beam rather than the working directory, because eunit runs
%% from wherever the developer happens to be standing.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) ->
    climb(filename:dirname(Dir), Name, Left - 1).

%%==============================================================================
%% The boot claim names the service and its box
%%==============================================================================

%% Every node that claims on the realm shows its service and host on the
%% Providers desk: mcl_om 0.27 reads MCL_SERVICE_NAME and MCL_BOX. The service
%% name is ours; the box is the deploying host's to say.
the_claim_names_the_service_and_its_box_test() ->
    {ok, Text} = file:read_file(alongside("deploy/docker-compose.yml")),
    ?assertMatch({match, _}, re:run(Text, <<"- MCL_SERVICE_NAME=mcl-embedder\\n">>)),
    ?assertMatch({match, _}, re:run(Text, <<"- MCL_BOX=\\$\\{MCL_BOX:-\\}\\n">>)).

%% ⚠ NOT IN sys.config. mcl_om prefers its app env to the OS variables, so a
%% `service_name' or `box' line there, even an empty one, would hide the two
%% variables above (until mcl_om 0.27.1 treats empty as unset).
the_claim_labels_are_not_shadowed_by_app_env_test() ->
    {ok, Text} = file:read_file(alongside("config/sys.config.src")),
    ?assertEqual(nomatch, re:run(Text, <<"^\\s*\\{(service_name|box),">>, [multiline])).

%% The image says which commit IT was built from. Without its own label it
%% inherited the base image's (macula-ci-images' own commit), which names the
%% wrong repository; build-push passes the sha, the runtime stage labels it.
the_image_carries_its_revision_test() ->
    ?assertEqual(<<"REVISION">>, pinned("Containerfile", "^ARG (REVISION)=unknown$")),
    ?assertEqual(<<"${REVISION}">>,
                 pinned("Containerfile",
                        "^LABEL org\\.opencontainers\\.image\\.revision=\"([^\"]+)\"$")),
    ?assertEqual(<<"${{ github.sha }}">>,
                 pinned(".github/workflows/build-push.yml", "^\\s+REVISION=(.+)$")).

