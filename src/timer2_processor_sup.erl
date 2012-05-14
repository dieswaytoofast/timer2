%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Mahesh Paolini-Subramanya
%%% @doc Supervisor module for timers
%%% @end
%%%-------------------------------------------------------------------
-module(timer2_processor_sup).

-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').
-behaviour(supervisor).

-compile([{parse_transform, lager_transform}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_timer/1]).

%% ------------------------------------------------------------------
%% supervisor Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([init/1]).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

-spec start_link() -> {ok, pid()} | ignore | error().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% @doc Start a timer under this supervisor with the given name
-spec start_timer(timer_name()) -> {ok, pid()} | error().
start_timer(TimerName) ->
    lager:debug("Starting timer:~p~n", [TimerName]),
    case supervisor:start_child(?MODULE, [TimerName]) of
        {error, already_present} ->
            supervisor:restart_child(?MODULE, [TimerName]);
        {error, {already_started, Pid}} ->
            {ok, Pid};
        {ok, Pid, _Info} ->
            {ok, Pid};
        {ok, _Pid} = Result ->
            Result;
        {error, _Reason} = Error ->
            lager:warning("Could not start process for user '~s': ~p~n", [TimerName, _Reason]),
            Error
    end.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

-spec init(_Args::any()) -> {ok, any()} | {ok, any(), timeout()} | ignore | {stop, Reason :: any()}.
init([]) ->
    Timer = ?CHILD(timer2_processor, worker),
    {ok, { {simple_one_for_one, 5, 10}, [Timer]} }.

