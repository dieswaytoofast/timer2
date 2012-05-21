%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Mahesh Paolini-Subramanya
%%% @doc Module providing timer acceptor gen_server
%%% @end
%%%-------------------------------------------------------------------
-module(timer2_acceptor).

-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-compile([{parse_transform, lager_transform}]).

-behaviour(gen_server).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([delete/1]).

%% For debugging
-export([show_tables/0]).

%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("defaults.hrl").

-record(state, {}).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link(?MODULE, [], []).

-spec delete(Timer2Ref) -> {'ok', 'delete'} | {'error', Reason} when
      Timer2Ref :: timer2_server_ref(),
      Reason :: term().

delete(Timer2Ref) ->
    process_request(delete, Timer2Ref).

show_tables() ->
        timer2_manager:safe_call({timer2_acceptor, undefined}, show_tables).


%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

init(_Args) ->
    process_flag(trap_exit, true),
    AcceptorName = make_ref(),

    _ = timer2_manager:register_process(timer2_acceptor, AcceptorName),

    {ok, #state{}}.

handle_call({apply_after, Time, Args}, _From, State) ->
    Timer2Ref = timer2_manager:create_reference(),
    Message = {apply_after, Timer2Ref, Args},
    Reply = local_do_after(Timer2Ref, Time, Message, State),
    {reply, Reply, State};


handle_call({send_after, Time, Args}, _From, State) ->
    Timer2Ref = timer2_manager:create_reference(),
    Message = {send_after, Timer2Ref, Args},
    Reply = local_do_after(Timer2Ref, Time, Message, State),
    {reply, Reply, State};

handle_call({apply_interval, Time, {FromPid, _} = Args}, _From, State) ->
    Timer2Ref = timer2_manager:create_reference(),
    Message = {apply_interval, Timer2Ref, Time, Args},
    Reply = local_do_interval(FromPid, Timer2Ref, Time, Message, State),
    {reply, Reply, State};


handle_call({send_interval, Time, {FromPid, _} = Args}, _From, State) ->
    Timer2Ref = timer2_manager:create_reference(),
    Message = {send_interval, Timer2Ref, Time, Args},
    Reply = local_do_interval(FromPid, Timer2Ref, Time, Message, State),
    {reply, Reply, State};

handle_call({cancel, {_ETRef, Timer2Ref} = _Args}, _From, State) ->
    % Need to look up the TRef, because it might have changed due to *_interval usage
    Reply = case ets:lookup(?TIMER2_REF_TAB, Timer2Ref) of
        [{_, FinalTRef}] ->
            erlang:cancel_timer(FinalTRef),
            _ = ets:delete(?TIMER2_TAB, FinalTRef),
            _ = ets:delete(?TIMER2_REF_TAB, Timer2Ref),
            {ok, cancel};
        _ ->
            {error, badarg}
    end,
    {reply, Reply, State};

%
% Debugging
% 
handle_call(show_tables, _From, State) ->
    Timer2Tab = ets:tab2list(?TIMER2_TAB),
    Timer2RefTab = ets:tab2list(?TIMER2_REF_TAB),
    Timer2PidTab = ets:tab2list(?TIMER2_PID_TAB),
    {reply, {ok,{Timer2Tab,Timer2RefTab, Timer2PidTab}}, State};

handle_call(ping, _From, State) ->
    {reply, {ok, ping}, State};

handle_call(_Request, _From, State) ->
    {noreply, ok, State}.

%% Deletes always come from the processor.  
handle_cast({delete, Timer2Ref} = _Args, State) ->
    case ets:lookup(?TIMER2_REF_TAB, Timer2Ref) of
        [{_, OldETRef}] ->
            case ets:lookup(?TIMER2_TAB, OldETRef) of
                %% The delete might refer to an interval, in which case, redo the timer
                [{_, {apply_interval, Timer2Ref, Time, {FromPid, _}} = Message}] ->
                    local_do_interval(FromPid, Timer2Ref, Time, Message, State);
                [{_, {send_interval, Timer2Ref, Time, {FromPid, _}} = Message}] ->
                    local_do_interval(FromPid, Timer2Ref, Time, Message, State);
                %% The delete is for a oneshot, or bad data
                _Other ->
                    _ = ets:delete(?TIMER2_REF_TAB, Timer2Ref)
            end,
            %% Regardless, delete the original timer
            _ = ets:delete(?TIMER2_TAB, OldETRef);
        _Other ->
            ok
    end,
    {noreply, State};


handle_cast(_Msg, State) ->
    {noreply, State}.

% If one of the linked procs dies, cleanup all timers associated with it
handle_info({'EXIT',  Pid, _Reason}, State) -> 
    PidList = ets:lookup(?TIMER2_PID_TAB, Pid),
    lists:map(fun({_, Timer2Ref}) ->
                case ets:lookup(?TIMER2_REF_TAB, Timer2Ref) of
                    [{_, TRef}] ->
                        _ = erlang:cancel_timer(TRef),
                        _ = ets:delete(?TIMER2_TAB, TRef);
                    _ ->
                        ok
                end,
                _ = ets:delete(?TIMER2_REF_TAB, Timer2Ref)
        end, PidList),
    _ = ets:delete(?TIMER2_PID_TAB, Pid),
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

local_do_after(Timer2Ref, Time, Message, _State) ->
    case timer2_manager:get_process(timer2_processor) of
        Pid when is_pid(Pid) ->
            NewETRef =  erlang:send_after(Time, Pid, Message),
            _ = ets:insert(?TIMER2_REF_TAB, {Timer2Ref, NewETRef}),
            _ = ets:insert(?TIMER2_TAB, {NewETRef, Message}),
            {ok, {NewETRef, Timer2Ref}};
        Error ->
            Error
    end.

local_do_interval(FromPid, Timer2Ref, Time, Message, _State) ->
    case timer2_manager:get_process(timer2_processor) of
        ToPid when is_pid(ToPid) ->
            ETRef = erlang:send_after(Time, ToPid, Message),
            % Need to link to the FromPid so we can remove these entries
            catch link(FromPid),
            _ = ets:insert(?TIMER2_TAB, {ETRef, Message}),
            _ = ets:insert(?TIMER2_REF_TAB, {Timer2Ref, ETRef}),
            _ = ets:insert(?TIMER2_PID_TAB, {FromPid, Timer2Ref}),
            {ok, {ETRef, Timer2Ref}};
        Error ->
            Error
    end.

process_request(delete, {Pid, _TRef} = Timer2Ref) when is_pid(Pid) ->
    %% Could have this go through gproc, but why do so if not necessary?
    gen_server:cast(Pid, {delete, Timer2Ref});

process_request(delete, _) ->
    {error, badarg}.
