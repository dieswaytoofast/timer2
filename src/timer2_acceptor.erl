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

-export([start_link/1]).
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

-record(state, {
            id                      :: integer(),
            timer2_table            :: atom(),
            timer2_ref_table        :: atom(),
            timer2_pid_table        :: atom()
            }).

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Id) ->
    gen_server:start_link(?MODULE, Id, []).

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

init(Id) ->
    process_flag(trap_exit, true),
    AcceptorName = make_ref(),

    Timer2TableName = list_to_atom(atom_to_list(?TIMER2_TAB) ++ integer_to_list(Id)),
    Timer2RefTableName = list_to_atom(atom_to_list(?TIMER2_REF_TAB) ++ integer_to_list(Id)),
    Timer2PidTableName = list_to_atom(atom_to_list(?TIMER2_PID_TAB) ++ integer_to_list(Id)),


    Timer2TableName = ets:new(Timer2TableName, [named_table, protected]),
    Timer2RefTableName = ets:new(Timer2RefTableName, [named_table, protected]),
    Timer2PidTableName = ets:new(Timer2PidTableName, [bag, named_table, protected]),
    
    _ = timer2_manager:register_process(timer2_acceptor, AcceptorName),
    State = #state{
            id = Id,
            timer2_table = Timer2TableName,
            timer2_ref_table = Timer2RefTableName,
            timer2_pid_table = Timer2PidTableName},
    {ok, State}.

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
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    % Need to look up the TRef, because it might have changed due to *_interval usage
    Reply = case ets:lookup(Timer2RefTable, Timer2Ref) of
        [{_, FinalTRef}] ->
            erlang:cancel_timer(FinalTRef),
            _ = ets:delete(Timer2Table, FinalTRef),
            _ = ets:delete(Timer2RefTable, Timer2Ref),
            {ok, cancel};
        _ ->
            {error, badarg}
    end,
    {reply, Reply, State};

%
% Debugging
% 
handle_call(show_tables, _From, State) ->
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    Timer2PidTable = State#state.timer2_pid_table,
    Timer2Tab = ets:tab2list(Timer2Table),
    Timer2RefTab = ets:tab2list(Timer2RefTable),
    Timer2PidTab = ets:tab2list(Timer2PidTable),
    {reply, {ok,{Timer2Tab,Timer2RefTab, Timer2PidTab}}, State};

handle_call(ping, _From, State) ->
    {reply, {ok, ping}, State};

handle_call(_Request, _From, State) ->
    {noreply, ok, State}.

%% Deletes always come from the processor.  
handle_cast({delete, Timer2Ref} = _Args, State) ->
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    case ets:lookup(Timer2RefTable, Timer2Ref) of
        [{_, OldETRef}] ->
            case ets:lookup(Timer2Table, OldETRef) of
                %% The delete might refer to an interval, in which case, redo the timer
                [{_, {apply_interval, Timer2Ref, Time, {FromPid, _}} = Message}] ->
                    local_do_interval(FromPid, Timer2Ref, Time, Message, State);
                [{_, {send_interval, Timer2Ref, Time, {FromPid, _}} = Message}] ->
                    local_do_interval(FromPid, Timer2Ref, Time, Message, State);
                %% The delete is for a oneshot, or bad data
                _Other ->
                    _ = ets:delete(Timer2RefTable, Timer2Ref)
            end,
            %% Regardless, delete the original timer
            _ = ets:delete(Timer2Table, OldETRef);
        _Other ->
            ok
    end,
    {noreply, State};


handle_cast(_Msg, State) ->
    {noreply, State}.

% If one of the linked procs dies, cleanup all timers associated with it
handle_info({'EXIT',  Pid, _Reason}, State) -> 
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    Timer2PidTable = State#state.timer2_pid_table,
    case ets:lookup(Timer2PidTable, Pid) of
        PidList when is_list(PidList) ->
            lists:map(fun({_, Timer2Ref}) ->
                        case ets:lookup(Timer2RefTable, Timer2Ref) of
                            [{_, TRef}] ->
                                _ = erlang:cancel_timer(TRef),
                                _ = ets:delete(Timer2Table, TRef);
                            _ ->
                                ok
                        end,
                        _ = ets:delete(Timer2RefTable, Timer2Ref)
                end, PidList);
        _ ->
            ok
    end,
    _ = ets:delete(Timer2PidTable, Pid),
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

local_do_after(Timer2Ref, Time, Message, State) ->
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    case timer2_manager:get_process(timer2_processor) of
        Pid when is_pid(Pid) ->
            case erlang:send_after(Time, Pid, Message) of
                badarg ->
                    {error, badarg};
                NewETRef ->
                    _ = ets:insert(Timer2RefTable, {Timer2Ref, NewETRef}),
                    _ = ets:insert(Timer2Table, {NewETRef, Message}),
                    {ok, {NewETRef, Timer2Ref}}
            end;
        Error ->
            Error
    end.

local_do_interval(FromPid, Timer2Ref, Time, Message, State) ->
    Timer2Table = State#state.timer2_table,
    Timer2RefTable = State#state.timer2_ref_table,
    Timer2PidTable = State#state.timer2_pid_table,
    case timer2_manager:get_process(timer2_processor) of
        ToPid when is_pid(ToPid) ->
            case erlang:send_after(Time, ToPid, Message) of
                badarg ->
                    {error, badarg};
                ETRef ->
		            % Need to link to the FromPid so we can remove these entries
		            catch link(FromPid),
		            _ = ets:insert(Timer2Table, {ETRef, Message}),
		            _ = ets:insert(Timer2RefTable, {Timer2Ref, ETRef}),
		            _ = ets:insert(Timer2PidTable, {FromPid, Timer2Ref}),
		            {ok, {ETRef, Timer2Ref}}
            end;
        Error ->
            Error
    end.

process_request(delete, {Pid, _TRef} = Timer2Ref) when is_pid(Pid) ->
    %% Could have this go through gproc, but why do so if not necessary?
    gen_server:cast(Pid, {delete, Timer2Ref});

process_request(delete, _) ->
    {error, badarg}.
