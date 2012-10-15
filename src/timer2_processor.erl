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
-module(timer2_processor).

-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-compile([{parse_transform, lager_transform}]).

-behaviour(gen_server).
-define(SERVER, ?MODULE).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------


-export([start_link/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").


%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link(?MODULE, [], []).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    process_flag(trap_exit, true),
    ProcessorName = make_ref(),
    timer2_manager:register_process(timer2_processor, ProcessorName),
    {ok, []}.

handle_call(ping, _From, State) ->
  {reply, {ok, ping}, State};

handle_call(_Request, _From, State) ->
  {noreply, ok, State}.

handle_cast(_Msg, State) ->
  {noreply, State}.

handle_info({send_after, FromRef, {Pid, Message} = _Args}, State) ->
    send(Pid, Message),
    timer2_acceptor:delete(FromRef),
    {noreply, State};

handle_info({apply_after, FromRef, {M, F, A} = _Args}, State) ->
    do_apply({M, F, A}),
    timer2_acceptor:delete(FromRef),
    {noreply, State};

handle_info({apply_interval, FromRef, _Time, {_Pid, {M, F, A}} = _Args}, State) ->
    do_apply({M, F, A}),
    timer2_acceptor:delete(FromRef),
    {noreply, State};

handle_info({send_interval, FromRef, _Time, {Pid, Message} = _Args}, State) ->
    send(Pid, Message),
    timer2_acceptor:delete(FromRef),
    {noreply, State};

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

send(Pid, Msg) ->
    catch Pid ! Msg.

do_apply({M,F,A}) ->
    case {M, F, A} of
	{erlang, exit, [Name, Reason]} ->
	    catch exit(get_pid(Name), Reason);
	_ -> 
	    %% else spawn process with the operation
	    catch spawn(M,F,A)      
    end.

get_pid(Name) when is_pid(Name) ->
    Name;
get_pid(undefined) ->
    undefined;
get_pid(Name) when is_atom(Name) ->
    get_pid(whereis(Name));
get_pid(_) ->
    undefined.
