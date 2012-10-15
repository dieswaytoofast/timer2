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
-module(timer2).

-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-define(APP, ?MODULE).

-compile([{parse_transform, lager_transform}]).

-export([apply_after/4,
	 send_after/3, send_after/2,
	 exit_after/3, exit_after/2, kill_after/2, kill_after/1,
	 apply_interval/4, send_interval/3, send_interval/2,
	 cancel/1, sleep/1, tc/1, tc/2, tc/3, now_diff/2,
	 seconds/1, minutes/1, hours/1, hms/3]).

-export([get_env/0, get_env/1, get_env/2]).

-export([add_child/1]).

-export([start/0, stop/0]).

%%
%% Custom Types for compatibility
%%
%% @doc The returned reference is {ErlangTimerRef, {AcceptorPid, AcceptorRef}}
%%
-opaque tref()    :: {reference(), timer2_server_ref()}.

% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").


%% @doc Start the application and all its dependencies.
-spec start() -> ok.
start() ->
    application:start(compiler),
    application:start(syntax_tools),
    application:start(lager),
    application:start(gproc),
    application:start(timer2).


%% @doc Stop the application and all its dependencies.
-spec stop() -> ok.
stop() ->
    application:stop(timer2),
    application:stop(gproc),
    application:stop(lager),
    application:start(syntax_tools),
    application:stop(compiler).


-spec apply_after(Time, Module, Function, Arguments) ->
                         {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      TRef :: tref(),
      Reason :: term().

apply_after(Time, M, F, A) ->
    process_request(apply_after, Time, {M, F, A}).

-spec send_after(Time, Pid, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_after(Time, Pid, Message) ->
    process_request(send_after, Time, {Pid, Message}).

-spec send_after(Time, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_after(Time, Message) ->
    send_after(Time, self(), Message).

-spec exit_after(Time, Pid, Reason1) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      TRef :: tref(),
      Reason1 :: term(),
      Reason2 :: term().
exit_after(Time, Pid, Reason) ->
    process_request(apply_after, Time, {erlang, exit, [Pid, Reason]}).

-spec exit_after(Time, Reason1) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      TRef :: tref(),
      Reason1 :: term(),
      Reason2 :: term().
exit_after(Time, Reason) ->
    exit_after(Time, self(), Reason).

-spec kill_after(Time, Pid) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      TRef :: tref(),
      Reason2 :: term().
kill_after(Time, Pid) ->
    exit_after(Time, Pid, kill).

-spec kill_after(Time) -> {'ok', TRef} | {'error', Reason2} when
      Time :: time(),
      TRef :: tref(),
      Reason2 :: term().
kill_after(Time) ->
    exit_after(Time, self(), kill).

-spec apply_interval(Time, Module, Function, Arguments) ->
                            {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      TRef :: tref(),
      Reason :: term().
apply_interval(Time, M, F, A) ->
    process_request(apply_interval, Time, {self(), {M, F, A}}).

-spec send_interval(Time, Pid, Message) ->
                           {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Pid :: pid() | (RegName :: atom()),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_interval(Time, Pid, Message) ->
    process_request(send_interval, Time, {Pid, Message}).

-spec send_interval(Time, Message) -> {'ok', TRef} | {'error', Reason} when
      Time :: time(),
      Message :: term(),
      TRef :: tref(),
      Reason :: term().
send_interval(Time, Message) ->
    send_interval(Time, {self(), Message}).

-spec cancel(TRef) -> {'ok', 'cancel'} | {'error', Reason} when
      TRef :: tref(),
      Reason :: term().
cancel(TRef) ->
    process_request(cancel, TRef).

-spec sleep(Time) -> 'ok' when
      Time :: timeout().
sleep(T) ->
    receive
    after T -> ok
    end.

%%
%% Measure the execution time (in microseconds) for Fun().
%%
-spec tc(Fun) -> {Time, Value} when
      Fun :: function(),
      Time :: integer(),
      Value :: term().
tc(F) ->
    Before = os:timestamp(),
    Val = F(),
    After = os:timestamp(),
    {now_diff(After, Before), Val}.

%%
%% Measure the execution time (in microseconds) for Fun(Args).
%%
-spec tc(Fun, Arguments) -> {Time, Value} when
      Fun :: function(),
      Arguments :: [term()],
      Time :: integer(),
      Value :: term().
tc(F, A) ->
    Before = os:timestamp(),
    Val = apply(F, A),
    After = os:timestamp(),
    {now_diff(After, Before), Val}.

%%
%% Measure the execution time (in microseconds) for an MFA.
%%
-spec tc(Module, Function, Arguments) -> {Time, Value} when
      Module :: module(),
      Function :: atom(),
      Arguments :: [term()],
      Time :: integer(),
      Value :: term().
tc(M, F, A) ->
    Before = os:timestamp(),
    Val = apply(M, F, A),
    After = os:timestamp(),
    {now_diff(After, Before), Val}.

%%
%% Calculate the time difference (in microseconds) of two
%% erlang:now() timestamps, T2-T1.
%%
-spec now_diff(T2, T1) -> Tdiff when
      T1 :: erlang:timestamp(),
      T2 :: erlang:timestamp(),
      Tdiff :: integer().
now_diff({A2, B2, C2}, {A1, B1, C1}) ->
    ((A2-A1)*1000000 + B2-B1)*1000000 + C2-C1.

%%
%% Convert seconds, minutes etc. to milliseconds.    
%%
-spec seconds(Seconds) -> MilliSeconds when
      Seconds :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
seconds(Seconds) ->
    1000*Seconds.
-spec minutes(Minutes) -> MilliSeconds when
      Minutes :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
minutes(Minutes) ->
    1000*60*Minutes.
-spec hours(Hours) -> MilliSeconds when
      Hours :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
hours(Hours) ->
    1000*60*60*Hours.
-spec hms(Hours, Minutes, Seconds) -> MilliSeconds when
      Hours :: non_neg_integer(),
      Minutes :: non_neg_integer(),
      Seconds :: non_neg_integer(),
      MilliSeconds :: non_neg_integer().
hms(H, M, S) ->
    hours(H) + minutes(M) + seconds(S).

%% 
%% Non-timer helper functions
%%

%% @doc Retrieve all key/value pairs in the env for the specified app.
-spec get_env() -> [{Key :: atom(), Value :: term()}].
get_env() ->
    application:get_all_env(?APP).

%% @doc The official way to get a value from the app's env.
%%      Will return the 'undefined' atom if that key is unset.
-spec get_env(Key :: atom()) -> term().
get_env(Key) ->
    get_env(Key, undefined).

%% @doc The official way to get a value from this application's env.
%%      Will return Default if that key is unset.
-spec get_env(Key :: atom(), Default :: term()) -> term().
get_env(Key, Default) ->
    case application:get_env(?APP, Key) of
        {ok, Value} ->
            Value;
        _ ->
            Default
    end.

%% @doc Add an addition acceptor or processor
-spec add_child(child_type()) -> {ok, pid()} | error().
add_child(Type) ->
    case Type of
        X1 when X1 =:= timer2_acceptor orelse 
                X1 =:= timer2_processor ->
            timer2_sup:add_child(Type);
        _ ->
            {error, badarg}
    end.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

process_request(cancel, TRef) ->
    %% Could have this go through gproc, but why do so if not necessary?
    timer2_manager:safe_call({timer2_acceptor, undefined}, {cancel, TRef}).

process_request(RequestType, Time, Args) when is_integer(Time) ->
    timer2_manager:safe_call({timer2_acceptor, undefined}, {RequestType, Time, Args});

process_request(_RequestType, _Time, _Args) ->
    {error, badarg}.

