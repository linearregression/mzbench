-module(mzb_bench_sup).
-export([start_link/0, is_ready/0, connect_nodes/1, run_bench/2, get_results/0, start_pool/1]).

-behaviour(supervisor).
-export([init/1]).

-include_lib("mzbench_language/include/mzbl_types.hrl").

%%%===================================================================
%%% API
%%%===================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

run_bench(ScriptPath, DefaultEnv) ->
    try
        {Body0, Env0} = read_and_validate(ScriptPath, mzbl_script:normalize_env(DefaultEnv)),
        Env1 = mzb_script_hooks:pre_hooks(Body0, Env0),
        {Body2, Env2} = read_and_validate(ScriptPath, Env1),
        PostHookFun = fun () ->
                mzb_script_hooks:post_hooks(Body2, Env2)
            end,

        Nodes = retrieve_worker_nodes(),

        case start_director(Body2, Nodes, Env2, PostHookFun) of
            {ok, _, _} -> ok;
            {ok, _} -> ok;
            {error, Error} -> erlang:error({error, [mzb_string:format("Unable to start director supervisor: ~p", [Error])]})
        end
    catch _C:{error, Errors} = E when is_list(Errors) -> E;
          C:E ->
              ST = erlang:get_stacktrace(),
              system_log:error("Failed to run benchmark ~p:~p~n~p", [C, E, ST]),
              {error, [mzb_string:format("Failed to run benchmark", [])]}
    end.

read_and_validate(Path, Env) ->
    case mzb_script_validator:read_and_validate(Path, Env) of
        {ok, Body, NewEnv} -> {Body, NewEnv};
        {error, _, _, _, Errors} -> erlang:error({error, Errors})
    end.

is_ready() ->
    try
        Apps = application:which_applications(),
        false =/= lists:keyfind(mzbench, 1, Apps)
    catch
        _:Error ->
            system_log:error("is_ready exception: ~p~nStacktrace: ~p", [Error, erlang:get_stacktrace()]),
            false
    end.

connect_nodes(Nodes) ->
    lists:filter(
        fun (N) ->
            pong == net_adm:ping(N)
        end, Nodes).

get_results() ->
    try
        mzb_director:attach()
    catch
        _:E ->
            ST = erlang:get_stacktrace(),
            Str = mzb_string:format("Unexpected error: ~p~n~p", [E, ST]),
            {error, {unexpected_error, E, ST}, Str}
    end.

start_pool(Args) ->
    supervisor:start_child(?MODULE, child_spec(make_ref(), mzb_pool, Args, transient)).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================
init([]) ->
    system_log:info("[ mzb_bench_sup ] I'm at ~p", [self()]),
    {ok, {{one_for_all, 0, 1}, [
        child_spec(signaler, mzb_signaler, [], permanent)
    ]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
child_spec(Name, Module, Args, Restart) ->
    {Name, {Module, start_link, Args}, Restart, 5000, worker, [Module]}.

start_director(Body, Nodes, Env, Continuation) ->
    BenchName = mzbl_script:get_benchname(mzbl_script:get_real_script_name(Env)),
    system_log:info("[ mzb_bench_sup ] Loading ~p Nodes: ~p", [BenchName, Nodes]),
    supervisor:start_child(?MODULE,
                            child_spec(director, mzb_director,
                                       [whereis(?MODULE), BenchName, Body, Nodes, Env, Continuation],
                                       transient)).

retrieve_worker_nodes() ->
    Nodes = erlang:nodes(),
    case erlang:length(Nodes) of
        0   ->  [erlang:node()];    % If no worker node is available, use the director node
        _ -> Nodes
    end.
