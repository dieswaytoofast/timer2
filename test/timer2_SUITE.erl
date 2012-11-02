
-module(timer2_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("../src/defaults.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

%% ------------------------------------------------------------------
%% Defines
%% ------------------------------------------------------------------

-define(PROPTEST(A), true = proper:quickcheck(A(),[{numtests,100}])).
-define(PROPTEST(M,F), true = proper:quickcheck(M:F(),[{numtests,100}])).

-define(PROP_TIME_MIN, 100).
-define(PROP_TIME_MAX, 500).

%% ------------------------------------------------------------------
%% Test Function Definitions
%% ------------------------------------------------------------------

%%
%% Test Descriptions
%%

suite() ->
    [{timetrap,{minutes,15}}].

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
    [{start_stop_test, [],
      [t_acceptor_start,
       t_processor_start,
       t_start_child,
       t_acceptor_ping,
       t_processor_ping
      ]},
     {send_after_test, [], [t_send_after]},
     {pid_test, [], [t_pid]},
     {table_check_test, [], [t_table_check]},
     {exit_after_test, [], [t_exit_after]},
     {kill_after_test, [], [t_kill_after]},
     {apply_after_test, [], [t_apply_after]},
     {cancel_send_after_test, [], [t_cancel_send_after]},
     {cancel_apply_after_test, [], [t_cancel_apply_after]},
     {after_test, [parallel, {repeat, 1}], 
      [t_exit_after,
       t_kill_after,
       t_apply_after,
       t_cancel_send_after,
       t_cancel_apply_after
      ]},
     {send_after_many_test, [], [t_send_after_many]},
     {apply_after_many_test, [], [t_apply_after_many]},
     {send_interval, [], [t_send_interval]},
     {apply_interval, [], [t_apply_interval]},
     %{interval_test, [parallel, {repeat_until_any_fail, forever}], [t_send_interval, t_apply_interval]},
     {interval_test, [parallel, {repeat, 1}], 
      [t_send_interval,
       t_apply_interval
      ]},
     {prop_test, [parallel],
      [t_prop_send_after,
       t_prop_pid,
       t_prop_apply_after,
       t_prop_kill_after,
       t_prop_exit_after,
       t_prop_cancel_send_after,
       t_prop_cancel_apply_after,
       t_prop_send_after_many,
       t_prop_apply_after_many,
       t_prop_send_interval,
       t_prop_apply_interval
      ]}
    ].

all() ->
    [{group, start_stop_test},
     {group, send_after_test},
     {group, pid_test},
     {group, table_check_test},
     {group, exit_after_test},
     {group, kill_after_test},
     {group, apply_after_test},
     {group, cancel_send_after_test},
     {group, cancel_apply_after_test},
     {group, after_test},
     {group, send_after_many_test},
     {group, apply_after_many_test},
     {group, send_interval},
     {group, apply_interval},
     {group, interval_test},
     {group, prop_test}
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

t_prop_send_after(_In) ->
    ?PROPTEST(prop_send_after).

prop_send_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Message = make_ref(),
                Res = timer2:send_after(Time, self(), Message),
                {ok, {_ETRef, _Timer2Ref}} = Res,
                RetMessage = wait_for_message(self(), Message, Time+1000),
                timer2:sleep(500),
                RetMessage =:= Message
            end).

t_send_after(_In) ->
    Time = 500,
    Message = make_ref(),
    Res = timer2:send_after(Time, self(), Message),
    {ok, {_ETRef, _Timer2Ref}} = Res,
    RetMessage = wait_for_message(self(), Message, 2500),
    timer2:sleep(1000),
    RetMessage = Message.

t_table_check(_In) ->
    t_send_after(dummy_message),
    % Cleanup
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables().

t_prop_pid(_In) ->
    ?PROPTEST(prop_pid).

prop_pid() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Message = make_ref(),
                process_flag(trap_exit, true),
                Pid = spawn_link(fun() ->
                                _ = timer2:send_interval(Time, self(), Message),
                                timer2:sleep(2000)
                        end),
                timer2:sleep(500),
                exit(Pid, some_reason),
                wait_for_exit(Pid, 5000),
                timer2:sleep(500),
                {ok, {Match}} = timer2_acceptor:match_send_interval(),
                Matched = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
                if
                    Matched ->
                        false;
                    true ->
                        true
                end
            end).

t_pid(_In) ->
    Time = 9000,
    Message = make_ref(),
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() ->
                    _ = timer2:send_interval(Time, self(), Message),
                    timer2:sleep(20000)
            end),
    timer2:sleep(1000),
    exit(Pid, some_reason),
    wait_for_exit(Pid, 5000),
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables().

t_prop_apply_after(_In) ->
    ?PROPTEST(prop_apply_after).

prop_apply_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Message = make_ref(),
                Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
                {ok, {_ETRef, _Timer2Ref}} = Res,
                Message = wait_for_message(self(), Message, Time+2000),
                timer2:sleep(1000),
                Message =:= Message
            end).

t_apply_after(_In) ->
    Time = 500,
    Message = make_ref(),
    Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    {ok, {_ETRef, _Timer2Ref}} = Res,
    Message = wait_for_message(self(), Message, 2500),
    timer2:sleep(1000),
    Message = Message.

t_prop_exit_after(_In) ->
    ?PROPTEST(prop_exit_after).

prop_exit_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                process_flag(trap_exit, true),
                Message = make_ref(),
                Res = timer2:exit_after(Time, self(), Message),
                {ok, {_ETRef, _Timer2Ref}} = Res,
                Response = wait_for_exit(self(), Time+500),
                timer2:sleep(1000),
                Response =:= Message
            end).

t_exit_after(_In) ->
    Time = 500,
    process_flag(trap_exit, true),
    Message = make_ref(),
    Res = timer2:exit_after(Time, self(), Message),
    {ok, {_ETRef, _Timer2Ref}} = Res,
    Response = wait_for_exit(self(), 2500),
    timer2:sleep(1000),
    Response = Message.

t_prop_kill_after(_In) ->
    ?PROPTEST(prop_kill_after).

prop_kill_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                process_flag(trap_exit, true),
                Pid = spawn_link(fun() -> timer2:sleep(10000) end),
                Res = timer2:kill_after(Time, Pid),
                {ok, {_ETRef, _Timer2Ref}} = Res,
                Message = wait_for_exit(Pid, 2500),
                timer2:sleep(1000),
                killed =:= Message
            end).

t_kill_after(_In) ->
    Time = 500,
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() -> timer2:sleep(10000) end),
    Res = timer2:kill_after(Time, Pid),
    {ok, {_ETRef, _Timer2Ref}} = Res,
    Message = wait_for_exit(Pid, 2500),
    timer2:sleep(1000),
    killed = Message.

t_prop_cancel_send_after(_In) ->
    ?PROPTEST(prop_cancel_send_after).

prop_cancel_send_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Message = make_ref(),
                SRes = timer2:send_after(Time, self(), Message),
                {ok, {_ETRef, _Timer2Ref}} = SRes,
                {ok, TRef} = SRes,
                timer2:sleep(100),
                CRes = timer2:cancel(TRef),
                _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
                {ok, cancel} = CRes,
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_send_after(),
                Matched = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
                if
                    Matched ->
                        false;
                    true ->
                        true
                end
            end).

t_cancel_send_after(_In) ->
    Time = 2000,
    Message = make_ref(),
    SRes = timer2:send_after(Time, self(), Message),
    {ok, {_ETRef, _Timer2Ref}} = SRes,
    {ok, TRef} = SRes,
    timer2:sleep(500),
    CRes = timer2:cancel(TRef),
    _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
    {ok, cancel} = CRes,
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables().

t_prop_cancel_apply_after(_In) ->
    ?PROPTEST(prop_cancel_apply_after).

prop_cancel_apply_after() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Message = make_ref(),
                SRes = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
                {ok, {_ETRef, _Timer2Ref}} = SRes,
                {ok, TRef} = SRes,
                timer2:sleep(100),
                CRes = timer2:cancel(TRef),
                _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
                {ok, cancel} = CRes,
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_apply_after(),
                Matched = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
                if
                    Matched ->
                        false;
                    true ->
                        true
                end
            end).

t_cancel_apply_after(_In) ->
    Time = 500,
    Message = make_ref(),
    SRes = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    {ok, {_ETRef, _Timer2Ref}} = SRes,
    {ok, TRef} = SRes,
    timer2:sleep(100),
    CRes = timer2:cancel(TRef),
    _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
    {ok, cancel} = CRes,
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables().

t_prop_send_after_many(_In) ->
    ?PROPTEST(prop_send_after_many).

prop_send_after_many() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                List = lists:map(fun(Id) ->
                                Message = {make_ref(), Id},
                                {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
                MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
                lists:map(fun({AbsTime, Message}) -> Res = timer2:send_after(AbsTime, self(), Message),
                    {ok, {_ETRef, _Timer2Ref}} = Res
                    end, List),
                RetList = lists:sort(do_loop([], 5000, error)),
                % Cleanup
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_send_after(),
                PidMatched = lists:any(fun(M)->self()=:=M end, lists:flatten(Match)),
                if
                    PidMatched ->
                        false;
                    true ->
                        RetList =:= MessageList
                end
            end).

t_send_after_many(_In) ->
    List = lists:map(fun(Id) ->
                    Time = Id*100,
                    Message = {make_ref(), Id},
                    {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
    MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
    lists:map(fun({Time, Message}) -> Res = timer2:send_after(Time, self(), Message),
		{ok, {_ETRef, _Timer2Ref}} = Res
        end, List),
    RetList = lists:sort(do_loop([], 5000, error)),
    % Cleanup
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables(),
    RetList = MessageList.

t_prop_apply_after_many(_In) ->
    ?PROPTEST(prop_apply_after_many).

prop_apply_after_many() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                List = lists:map(fun(Id) ->
                                Message = {make_ref(), Id},
                                {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
                MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
                lists:map(fun({AbsTime, Message}) -> Res = timer2:apply_after(AbsTime, timer2_manager, send_message_to_pid, [self(), Message]),
                    {ok, {_ETRef, _Timer2Ref}} = Res
                    end, List),
                RetList = lists:sort(do_loop([], 5000, error)),
                % Cleanup
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_apply_after(),
                PidMatched = lists:any(fun(M)->self()=:=M end, lists:flatten(Match)),
                if
                    PidMatched ->
                        false;
                    true ->
                        RetList =:= MessageList
                end
            end).

t_apply_after_many(_In) ->
    List = lists:map(fun(Id) ->
                    Time = Id*100,
                    Message = {make_ref(), Id},
                    {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
    MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
    lists:map(fun({Time, Message}) -> Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
		{ok, {_ETRef, _Timer2Ref}} = Res
        end, List),
    RetList = lists:sort(do_loop([], 5000, error)),
    % Cleanup
    timer2:sleep(1000),
    {ok, {[], [], []}} = timer2_acceptor:show_tables(),
    RetList = MessageList.

t_prop_send_interval(_In) ->
    ?PROPTEST(prop_send_interval).

prop_send_interval() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Count = 4,
                Message = make_ref(),
                IRes = {ok, TRef} = timer2:send_interval(Time, self(), Message),
                {ok, {_ETRef, _Timer2Ref}} = IRes,
                % Cancel the timer
                _ = spawn_link(fun() ->
                                timer2:sleep((Time * Count) + 250),
                                CRes = timer2:cancel(TRef),
                                {ok, cancel} = CRes
                        end),
                RetList = lists:filter(fun(X) -> X =:= Message end,
                                       do_loop([], (Time * Count) + 2000, normal)), 
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_send_interval(),
                PidMatched = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
                if
                    PidMatched ->
                        false;
                    true ->
                        true =:= (length(RetList) >= Count)
                end
            end).

% Must be at the end, otherwise confuses the other tests.
t_send_interval(_In) ->
    Time = 500,
    Count = 4,
    Message = make_ref(),
    IRes = {ok, TRef} = timer2:send_interval(Time, self(), Message),
    {ok, {_ETRef, _Timer2Ref}} = IRes,
    % Cancel the timer
    _ = spawn_link(fun() ->
                    timer2:sleep((Time * Count) + 250),
                    CRes = timer2:cancel(TRef),
		            {ok, cancel} = CRes
            end),
    RetList = lists:filter(fun(X) -> X =:= Message end,
                           do_loop([], (Time * Count) + 2000, normal)), 
    timer2:sleep(1000),
    {ok, {[], [], _}} = timer2_acceptor:show_tables(),
    true = (length(RetList) >= Count).

t_prop_apply_interval(_In) ->
    ?PROPTEST(prop_apply_interval).

prop_apply_interval() ->
    ?FORALL({Time}, {integer(?PROP_TIME_MIN, ?PROP_TIME_MAX)},
            begin
                Count = 4,
                Message = make_ref(),
                IRes = {ok, TRef} = timer2:apply_interval(Time, timer2_manager, send_message_to_pid, [self(), Message]),
                {ok, {_ETRef, _Timer2Ref}} = IRes,
                % Cancel the timer
                _ = spawn_link(fun() ->
                                timer2:sleep((Time * Count) + 250),
                                CRes = timer2:cancel(TRef),
                                {ok, cancel} = CRes
                        end),
                RetList = lists:filter(fun(X) -> X =:= Message end,
                                       do_loop([], (Time * Count) + 1000, normal)), 
                timer2:sleep(1000),
                {ok, {Match}} = timer2_acceptor:match_apply_interval(),
                Matched = lists:any(fun(M)->{self(),Message}=:=M end, lists:flatten(Match)),
                if
                    Matched ->
                        false;
                    true ->
                        true =:= (length(RetList) >= Count)
                end
            end).

t_apply_interval(_In) ->
    Time = 500,
    Count = 4,
    Message = make_ref(),
    IRes = {ok, TRef} = timer2:apply_interval(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    {ok, {_ETRef, _Timer2Ref}} = IRes,
    % Cancel the timer
    _ = spawn_link(fun() ->
                    timer2:sleep((Time * Count) + 250),
                    CRes = timer2:cancel(TRef),
		            {ok, cancel} = CRes
            end),
    RetList = lists:filter(fun(X) -> X =:= Message end,
                           do_loop([], (Time * Count) + 1000, normal)), 
    timer2:sleep(1000),
    {ok, {[], [], _}} = timer2_acceptor:show_tables(),
    true = (length(RetList) >= Count).

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

