%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2011-2012 Juan Jose Comellas, Mahesh Paolini-Subramanya
%%% @doc High performance timer module
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(timer2_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, add_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(Id, Type, Module, Args), {Id, {Module, start_link, Args}, permanent, 5000, Type, [Module]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec add_child(Type::child_type()) -> {ok, pid()} | error().
add_child(Type) ->
    supervisor:start_child(?MODULE, ?CHILD(make_ref(), worker, Type, [])).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    NumAcceptors = timer2:get_env(timer2_acceptors, 1),
    NumProcessors = timer2:get_env(timer2_processors, 1),

    _ = create_tables(),

    Timer2Acceptors = lists:foldl(fun(_X, Acc) -> 
                    [?CHILD(make_ref(), worker, timer2_acceptor, [])| Acc]
            end, [], lists:seq(1, NumAcceptors)),
    Timer2Processors = lists:foldl(fun(_X, Acc) -> 
                    [?CHILD(make_ref(), worker, timer2_processor, [])| Acc]
            end, [], lists:seq(1, NumProcessors)),
    {ok, { {one_for_all, 5, 10}, Timer2Acceptors ++ Timer2Processors} }.

%% ===================================================================
%% Internal Functions
%% ===================================================================
create_tables() ->
    _ = ets:new(?TIMER2_TAB, [named_table, public]),
    _ = ets:new(?TIMER2_REF_TAB, [named_table, public]),
    _ = ets:new(?TIMER2_PID_TAB, [bag, named_table, public]).
