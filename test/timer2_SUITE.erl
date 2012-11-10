
-module(timer2_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("../src/defaults.hrl").
-include_lib("common_test/include/ct.hrl").

%% ------------------------------------------------------------------
%% Defines
%% ------------------------------------------------------------------

-define(PROP_TIME_MIN, 0).
-define(PROP_TIME_MAX, 5000).
-define(TIME_BOUNDS, [?PROP_TIME_MIN, ?PROP_TIME_MAX]).

%% ------------------------------------------------------------------
%% Test Function Definitions
%% ------------------------------------------------------------------

%%
%% Test Descriptions
%%

suite() ->
    [{ct_hooks,[cth_surefire]}, {timetrap,{minutes,1}}].

init_per_suite(Config) ->
    start(),
    Config.

end_per_suite(_Config) ->
    stop(),
    ok.

init_per_group(_, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

%%
%% Setup Functions
%%
start() ->
    timer2:start().

stop() ->
    timer2:stop().

groups() ->
    [{start_test, [],
      [t_acceptor_start,
       t_processor_start,
       t_start_child,
       t_acceptor_ping,
       t_processor_ping
      ]},
     {after_unit_test, [parallel, {repeat, 1}], 
      [t_exit_after,
       t_kill_after,
       t_apply_after,
       t_cancel_send_after,
       t_cancel_apply_after
      ]},
     {interval_unit_test, [parallel, {repeat, 1}], 
      [t_send_interval,
       t_apply_interval,
       t_apply_after_many,
       t_send_after_many
      ]},
     {unit_test , [parallel, {repeat, 5}],
      [t_send_after,
       t_pid,
       t_table_check,
       t_exit_after,
       t_kill_after,
       t_apply_after,
       t_cancel_send_after,
       t_cancel_apply_after,
       t_send_after_many,
       t_apply_after_many,
       t_send_interval,
       t_apply_interval
      ]}
    ].

all() ->
    [{group, start_test},
     %{group, interval_unit_test},
     %{group, after_unit_test},
     {group, unit_test}
    ].

%%
%% Helper Functions
%%
t_acceptor_start(_In) ->
    Pid = timer2_manager:get_process(timer2_acceptor),
    true = is_process_alive(Pid).

t_processor_start(_In) ->
    Pid = timer2_manager:get_process(timer2_processor),
    true = is_process_alive(Pid).

t_acceptor_ping(_In) ->
    Res = timer2_manager:safe_call({timer2_acceptor, undefined}, ping),
    {ok, ping} = Res.

t_processor_ping(_In) ->
    Res = timer2_manager:safe_call({timer2_processor, undefined}, ping),
    {ok, ping} = Res.

t_start_child(_In) ->
    {ok, APid} = timer2_sup:add_child(timer2_acceptor),
    {ok, PPid} = timer2_sup:add_child(timer2_processor),
    Res = timer2_sup:add_child(dummy_type),
    {error,{{'EXIT',{undef,_}},_}} = Res,
    true = is_process_alive(APid),
    true = is_process_alive(PPid).

%% ------------------------------------------------------------------
%% Unit Tests
%% ------------------------------------------------------------------
t_send_after(_In) ->
    [begin
         Message = make_ref(),
         Res = timer2:send_after(Time, self(), Message),
         {ok, {_ETRef, _Timer2Ref}} = Res,
         RetMessage = wait_for_message(self(), Message, Time+500),
         RetMessage = Message
    end || Time <- ?TIME_BOUNDS].

t_table_check(_In) ->
    t_send_after(dummy_message),
    % Cleanup
    {ok, {Match}} = timer2_acceptor:match_send_after(),
    false = lists:any(fun(M)->{self(),dummy_message}=:=M end, lists:flatten(Match)).

t_pid(_In) ->
    [begin
         Message = make_ref(),
         process_flag(trap_exit, true),
         Pid = spawn_link(fun() ->
                         _ = timer2:send_interval(Time, self(), Message),
                         timer2:sleep(20000)
                 end),
         exit(Pid, some_reason),
         wait_for_exit(Pid, 5000),
         {ok, {Match}} = timer2_acceptor:match_send_interval(),
         false = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match))
    end || Time <- ?TIME_BOUNDS].

t_apply_after(_In) ->
    [begin
         Message = make_ref(),
         Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
         {ok, {_ETRef, _Timer2Ref}} = Res,
         Message = wait_for_message(self(), Message, Time+1000),
         Message = Message
     end || Time <- ?TIME_BOUNDS].

t_exit_after(_In) ->
    [begin
         process_flag(trap_exit, true),
         Message = make_ref(),
         Res = timer2:exit_after(Time, self(), Message),
         {ok, {_ETRef, _Timer2Ref}} = Res,
         Response = wait_for_exit(self(), Time+500),
         Response = Message
     end || Time <- ?TIME_BOUNDS].

t_kill_after(_In) ->
    [begin
         process_flag(trap_exit, true),
         Pid = spawn_link(fun() -> timer2:sleep(10000) end),
         Res = timer2:kill_after(Time, Pid),
         {ok, {_ETRef, _Timer2Ref}} = Res,
         Message = wait_for_exit(Pid, Time+500),
         killed = Message
     end || Time <- ?TIME_BOUNDS].

t_cancel_send_after(_In) ->
    [begin
         Message = make_ref(),
         SRes = timer2:send_after(Time, self(), Message),
         {ok, {_ETRef, _Timer2Ref}} = SRes,
         {ok, TRef} = SRes,
         % if Time is short, ets table could be cleaned
         case timer2:cancel(TRef) of
             false ->
                 ct:log("TimerRef was never a timer, that it has already delivered its message");
             _Time ->
                 ct:log("left until the timer would have expired:~pms",[_Time])
         end,
         {ok, {Match}} = timer2_acceptor:match_send_after(),
         false = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match))
     end || Time <- ?TIME_BOUNDS].

t_cancel_apply_after(_In) ->
    [begin
         Message = make_ref(),
         SRes = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
         {ok, {_ETRef, _Timer2Ref}} = SRes,
         {ok, TRef} = SRes,
         % if Time is short, ets table could be cleaned
         case timer2:cancel(TRef) of
             false ->
                 ct:log("TimerRef was never a timer, that it has already delivered its message");
             _Time ->
                 ct:log("left until the timer would have expired:~pms",[_Time])
         end,
         {ok, {Match}} = timer2_acceptor:match_apply_after(),
         false = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match))
     end || Time <- ?TIME_BOUNDS].

t_send_after_many(_In) ->
    [begin
         List = lists:map(fun(Id) ->
                                  T = Id*100+Time,
                                  Message = {make_ref(), Id},
                                  {T, Message} end, lists:seq(1,4)) ++ [{Time+500, last_message}],
         MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
         lists:map(fun({AbsTime, Message}) -> Res = timer2:send_after(AbsTime, self(), Message),
                                              {ok, {_ETRef, _Timer2Ref}} = Res
                   end, List),
         RetList = lists:sort(do_loop([], Time*5+3000, error)),
         %% Cleanup
         % wait for clean table
         timer2:sleep(500),
         {ok, {Match}} = timer2_acceptor:match_send_after(),
         false = lists:any(fun(M)->self()=:=M end, lists:flatten(Match)),
         RetList = MessageList
     end || Time <- ?TIME_BOUNDS].

t_apply_after_many(_In) ->
    [begin
         List = lists:map(fun(Id) ->
                                  T = Id*100+Time,
                                  Message = {make_ref(), Id},
                                  {T, Message} end, lists:seq(1,4)) ++ [{Time+500, last_message}],
         MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
         lists:map(fun({AbsTime, Message}) -> Res = timer2:apply_after(AbsTime, timer2_manager, send_message_to_pid, [self(), Message]),
                                              {ok, {_ETRef, _Timer2Ref}} = Res
                   end, List),
         RetList = lists:sort(do_loop([], Time*5+3000, error)),
         %% Cleanup
         % wait for clean table
         timer2:sleep(500),
         {ok, {Match}} = timer2_acceptor:match_apply_after(),
         false = lists:any(fun(M)->self()=:=M end, lists:flatten(Match)),
         RetList = MessageList
     end || Time <- ?TIME_BOUNDS].

t_send_interval(_In) ->
    [begin
         Count = 4,
         Message = make_ref(),
         IRes = {ok, TRef} = timer2:send_interval(Time, self(), Message),
         {ok, {_ETRef, _Timer2Ref}} = IRes,
         %% Cancel the timer
         _ = spawn_link(fun() ->
                                timer2:sleep((Time * Count) + interval_constant(Time)),
                                % if Time is short, ets table could be cleaned
                                _ = timer2:cancel(TRef)
                        end),
         RetList = lists:filter(fun(X) -> X =:= Message end,
                                do_loop([], (Time * Count) + 100, normal)), 
         % wait for clean table
         timer2:sleep(500),
         {ok, {Match}} = timer2_acceptor:match_send_interval(),
         false = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
         true = (length(RetList) >= Count)
     end || Time <- ?TIME_BOUNDS].

t_apply_interval(_In) ->
    [begin
         Count = 4,
         Message = make_ref(),
         IRes = {ok, TRef} = timer2:apply_interval(Time, timer2_manager, send_message_to_pid, [self(), Message]),
         {ok, {_ETRef, _Timer2Ref}} = IRes,
         % Cancel the timer
         _ = spawn_link(fun() ->
                                timer2:sleep((Time * Count) + interval_constant(Time)),
                                _ = timer2:cancel(TRef)
                        end),
         RetList = lists:filter(fun(X) -> X =:= Message end,
                                do_loop([], (Time * Count) + 100, normal)), 
         % wait for clean table
         timer2:sleep(500),
         {ok, {Match}} = timer2_acceptor:match_apply_interval(),
         false = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
         true = (length(RetList) >= Count)
     end || Time <- ?TIME_BOUNDS].

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
do_loop(Acc, Time, ExitType) ->
    receive
        last_message ->
            [last_message|Acc];
        % For some spurious EXIT that I keep getting. need to figure this out
        {'EXIT', _, _} ->
            do_loop(Acc, Time, ExitType);
        Message ->
            do_loop([Message|Acc], Time, ExitType)
    after Time ->
            case ExitType of 
                error -> 
                    erlang:error(timeout);
                _ ->
                    Acc
            end
    end.

wait_for_message(Pid, Message, Timeout) ->
    receive
        {'EXIT', Pid, _Reason} ->
            wait_for_message(Pid, Message, Timeout);
        Message ->
            Message;
        OtherMessage ->
            ct:log(info, "Recived strange message OtherMessage:~p~n", [OtherMessage]),
        wait_for_message(Pid, Message, Timeout)
    after Timeout ->
            erlang:error(timeout)
    end.

wait_for_exit(Pid, Timeout) ->
    receive
        {'EXIT', _Pid, Reason} ->
            Reason;
        OtherMessage -> 
            ct:log(info, "Recived strange message OtherMessage:~p~n", [OtherMessage]),
        wait_for_exit(Pid, Timeout)
    after Timeout ->
            erlang:error(timeout)
    end.

interval_constant(Time) ->
    % Time domain(integer): -576460752303423489 < d < 576460752303423488
    % range: 12 < r < 16725
    round(math:pow(math:log(abs(Time)+3),2)*10).
