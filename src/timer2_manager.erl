%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Mahesh Paolini-Subramanya
%%% @doc Module providing timer management helper function
%%% @end
%%%-------------------------------------------------------------------
-module(timer2_manager).

-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-compile([{parse_transform, lager_transform}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([get_process/1]).
-export([register_process/2]).
-export([create_reference/0]).
-export([safe_cast/2, safe_call/2, safe_call/3]).

%%
%% For testing
%%
-export([send_message_to_pid/2]).


%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").

%% ------------------------------------------------------------------
%% Defines
%% ------------------------------------------------------------------


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

%% @doc Register a process locally
-spec register_process(Type::atom(),Name:: binary() | reference()) -> true.
register_process(Type, Name) ->
    gproc:reg({p, l, Type}, Name).

%% @doc Get the Pid for a given process type, or {Type, Name}
-spec get_process({Type::atom(), Name::reference()} | atom()) -> pid() | error().
get_process(Key) ->
    get_child_pid(Key).

%% @doc Get a reference that is usable to identify gen_servers and requests
-spec create_reference() -> timer2_server_ref().
create_reference() ->
    {self(), make_ref()}.

%% @doc Unified mechanism to send a gen_server call request to a supervised rune /
%%      user / session
-spec safe_call({Type :: atom(), Name :: any()}, Request :: any()) -> {ok, pid()} | {ok, Result :: any(), pid()} | error().
safe_call({_Type, _Name} = Key, Request) ->
    safe_call(Key, Request, ?DEFAULT_TIMER_TIMEOUT).


-spec safe_call({Type :: atom(), Name :: any()}, Request::any(), timeout()) -> {ok, pid()} | {ok, Result :: any(), pid()} | error().
safe_call({Type, Name} = Key, Request, Timeout) ->
    % Send the request to the process
    case is_reference(Name) of 
        true ->
            case get_child_pid(Key) of
                Pid when is_pid(Pid) ->
                    gen_server:call(Pid, Request, Timeout);
                Error ->
                    Error
            end;
        _ ->
            case get_child_pid(Type) of
                Pid when is_pid(Pid) ->
                    gen_server:call(Pid, Request, Timeout);
                Error ->
                    Error
            end
    end.

%% @doc Unified mechanism to send a gen_server cast request to a supervised rune /
%%      user / session
-spec safe_cast({Type :: atom(), Name :: any()}, Request :: any()) -> ok | error().
safe_cast({Type, Name} = Key, Request) ->
    % Send the request to the process
    case is_reference(Name) of 
        true ->
            case get_child_pid(Key) of
                Pid when is_pid(Pid) ->
                    gen_server:cast(Pid, Request);
                Error ->
                    Error
            end;
        _ ->
            case get_child_pid(Type) of
                Pid when is_pid(Pid) ->
                    gen_server:cast(Pid, Request);
                Error ->
                    Error
            end
    end.

-spec send_message_to_pid(Pid::pid(), Message::atom()) -> ok.
send_message_to_pid(Pid, Message) ->
    Pid ! Message.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

get_child_pid({Type, Name}) ->
    % If the process was started, it will be registered in gproc
    case gproc:select({local, all}, [{{{p, l, Type}, '$1', Name}, [], ['$1']}]) of
        [Pid] when is_pid(Pid) ->
            Pid;
        [] ->
            {error, ?GPROC_UNKNOWN_PROCESS}
    end;

get_child_pid(Type) ->
    % For one Pid, just return it
    case gproc:lookup_pids({p, l, Type}) of
        [Pid] ->
            Pid;
        PidList when is_list(PidList) ->
            random:seed(os:timestamp()),
            Index = random:uniform(length(PidList)),
            lists:nth(Index, PidList)
    end.
