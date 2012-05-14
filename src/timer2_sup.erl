%% Copyright (c) 2011 Mahesh Paolini-Subramanya (mahesh@dieswaytoofast.com)
-module(timer2_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(Id, Type, Module, Args), {Id, {Module, start_link, Args}, permanent, 5000, Type, [Module]}).

%% ===================================================================
%% API functions
%% ===================================================================

-spec start_link() -> {ok, pid()} | ignore | {error, Error :: any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

-spec init(_Args::any()) -> {ok, any()} | {ok, any(), Timeout :: integer()} | ignore | {stop, Reason :: any()}.
init([]) ->
    NumAcceptors = timer2:get_env(timer2_acceptors, 1),
    NumProcessors = timer2:get_env(timer2_processors, 1),
    Timer2Acceptors = lists:foldl(fun(X, Acc) -> 
                    [?CHILD({X, make_ref()}, worker, timer2_acceptor, [X])| Acc]
            end, [], lists:seq(1, NumAcceptors)),
    Timer2Processors = lists:foldl(fun(X, Acc) -> 
                    [?CHILD({X, make_ref()}, worker, timer2_processor, [])| Acc]
            end, [], lists:seq(1, NumProcessors)),
    {ok, { {one_for_all, 5, 10}, Timer2Acceptors ++ Timer2Processors} }.

