%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Mahesh Paolini-Subramanya
%%% @doc Main module for the timer2 application.
%%% @end
%%%-------------------------------------------------------------------
-module(timer2_tests).
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

%% ------------------------------------------------------------------
%% Includes
%% ------------------------------------------------------------------

-include("../src/defaults.hrl").
-include_lib("eunit/include/eunit.hrl").

%% ------------------------------------------------------------------
%% Defines
%% ------------------------------------------------------------------

-define(setup(F), {setup, fun start/0, fun stop/1, F}).
-define(foreach(F), {foreach, fun start/0, fun stop/1, F}).

%% ------------------------------------------------------------------
%% Test Function Definitions
%% ------------------------------------------------------------------

%%
%% Test Descriptions
%%
start_stop_test_() ->
    [{"The acceptor can be started pinged, and stopped successfully",
      ?foreach([fun t_acceptor_start/1,
                fun t_processor_start/1,
                fun t_start_child/1,
                fun t_acceptor_ping/1,
                fun t_processor_ping/1])}].

send_after_test_() ->
    [{"A message is sent and received",
     ?setup(fun t_send_after/1)}].

pid_cleanup_test_() ->
    [{"The source Pid exits",
     ?setup(fun t_pid/1)}].

table_cleanup_test_() ->
    [{"The ETS tables are cleaned out after processing",
      ?setup(fun t_table_check/1)}].

exit_after_test_() ->
    [{"The process exits after an interval",
     ?setup(fun t_exit_after/1)}].

kill_after_test_() ->
    [{"The process is killed after an interval",
     ?setup(fun t_kill_after/1)}].

apply_after_test_() ->
    [{"An MFA is applied and received",
     ?setup(fun t_apply_after/1)}].

cancel_send_after_test_() ->
    [{"Cancel a message that is send_after",
     ?setup(fun t_cancel_send_after/1)}].

cancel_apply_after_test_() ->
    [{"Cancel a message that is apply_after",
     ?setup(fun t_cancel_apply_after/1)}].

send_after_many_test_() ->
    [{"Many message are sent and received",
     ?setup(fun t_send_after_many/1)}].

apply_after_many_test_() ->
    [{"Many MFA are are applied after and received",
     ?setup(fun t_apply_after_many/1)}].
send_interval_test_() ->
    [{"A message is sent at intervals and received",
     ?setup(fun t_send_interval/1)}].

apply_interval_test_() ->
    [{"An MFA is applied at intervals and received",
     ?setup(fun t_apply_interval/1)}].

%%
%% Setup Functions
%%
start() ->
    timer2:start().


stop(_) ->
    timer2:stop().



%%
%% Helper Functions
%%
t_acceptor_start(_In) ->
    Pid = timer2_manager:get_process(timer2_acceptor),
    ?_assertEqual(true, is_process_alive(Pid)).

t_processor_start(_In) ->
    Pid = timer2_manager:get_process(timer2_processor),
    ?_assertEqual(true, is_process_alive(Pid)).

t_acceptor_ping(_In) ->
    Res = timer2_manager:safe_call({timer2_acceptor, undefined}, ping),
    ?_assertEqual({ok, ping}, Res).

t_processor_ping(_In) ->
    Res = timer2_manager:safe_call({timer2_processor, undefined}, ping),
    ?_assertEqual({ok, ping}, Res).

t_start_child(_In) ->
    {ok, APid} = timer2_sup:add_child(timer2_acceptor),
    {ok, PPid} = timer2_sup:add_child(timer2_processor),
    Res = timer2_sup:add_child(dummy_type),
    _ = ?_assertEqual({error, badarg}, Res),
    _ = ?_assertEqual(true, is_process_alive(APid)),
    ?_assertEqual(true, is_process_alive(PPid)).

t_send_after(_In) ->
    Time = 500,
    Message = make_ref(),
    Res = timer2:send_after(Time, self(), Message),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res),
    RetMessage = wait_for_message(self(), Message, 2500),
    timer2:sleep(1000),
    ?_assertEqual(RetMessage, Message).

t_table_check(_In) ->
    t_send_after(dummy_message),
    % Cleanup
    timer2:sleep(1000),
    ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()).

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
    ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()).

t_apply_after(_In) ->
    Time = 500,
    Message = make_ref(),
    Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res),
    Message = wait_for_message(self(), Message, 2500),
    timer2:sleep(1000),
    ?_assertEqual(Message, Message).

t_exit_after(_In) ->
    Time = 500,
    process_flag(trap_exit, true),
    Message = make_ref(),
    Res = timer2:exit_after(Time, self(), Message),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res),
    Response = wait_for_exit(self(), 2500),
    timer2:sleep(1000),
    ?_assertMatch(Response, Message).

t_kill_after(_In) ->
    Time = 500,
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() -> timer2:sleep(10000) end),
    Res = timer2:kill_after(Time, Pid),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res),
    Message = wait_for_exit(Pid, 2500),
    timer2:sleep(1000),
    ?_assertMatch(killed, Message).

t_cancel_send_after(_In) ->
    Time = 2000,
    Message = make_ref(),
    SRes = timer2:send_after(Time, self(), Message),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, SRes),
    {ok, TRef} = SRes,
    timer2:sleep(500),
    CRes = timer2:cancel(TRef),
    _ = ?_assertEqual({ok, cancel}, CRes),
    _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
    timer2:sleep(1000),
    ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()).

t_cancel_apply_after(_In) ->
    Time = 500,
    Message = make_ref(),
    SRes = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, SRes),
    {ok, TRef} = SRes,
    timer2:sleep(100),
    CRes = timer2:cancel(TRef),
    _ = ?_assertEqual({ok, cancel}, CRes),
    _ = ?_assertError(timeout, wait_for_message(self(), Message, 4000)),
    timer2:sleep(1000),
    _ = ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()).


t_send_after_many(_In) ->
    List = lists:map(fun(Id) ->
                    Time = Id*100,
                    Message = {make_ref(), Id},
                    {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
    MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
    lists:map(fun({Time, Message}) -> Res = timer2:send_after(Time, self(), Message),
                _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res)
        end, List),
    RetList = lists:sort(do_loop([], 5000, error)),
    % Cleanup
    timer2:sleep(1000),
    _ = ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()),
    ?_assertEqual(RetList, MessageList).

t_apply_after_many(_In) ->
    List = lists:map(fun(Id) ->
                    Time = Id*100,
                    Message = {make_ref(), Id},
                    {Time, Message} end, lists:seq(1,4)) ++ [{2000, last_message}],
    MessageList = lists:sort(lists:map(fun({_Time, Message}) -> Message end, List)),
    lists:map(fun({Time, Message}) -> Res = timer2:apply_after(Time, timer2_manager, send_message_to_pid, [self(), Message]),
                _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, Res)
        end, List),
    RetList = lists:sort(do_loop([], 5000, error)),
    % Cleanup
    timer2:sleep(1000),
    _ = ?_assertEqual({ok, {[], [], []}}, timer2_acceptor:show_tables()),
    ?_assertEqual(RetList, MessageList).

% Must be at the end, otherwise confuses the other tests.
t_send_interval(_In) ->
    Time = 500,
    Count = 4,
    Message = make_ref(),
    IRes = {ok, TRef} = timer2:send_interval(Time, self(), Message),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, IRes),
    % Cancel the timer
    _ = spawn_link(fun() ->
                    timer2:sleep((Time * Count) + 250),
                    CRes = timer2:cancel(TRef),
                    ?_assertEqual({ok, cancel}, CRes)
            end),
    RetList = lists:filter(fun(X) -> X =:= Message end,
                           do_loop([], (Time * Count) + 2000, normal)), 
    timer2:sleep(1000),
    _ = ?_assertMatch({ok, {[], [], _}}, timer2_acceptor:show_tables()),
    ?_assertEqual(true, length(RetList) >= Count).

t_apply_interval(_In) ->
    Time = 500,
    Count = 4,
    Message = make_ref(),
    IRes = {ok, TRef} = timer2:apply_interval(Time, timer2_manager, send_message_to_pid, [self(), Message]),
    _ = ?_assertMatch({ok, {_ETRef, _Timer2Ref}}, IRes),
    % Cancel the timer
    _ = spawn_link(fun() ->
                    timer2:sleep((Time * Count) + 250),
                    CRes = timer2:cancel(TRef),
                    ?_assertEqual({ok, cancel}, CRes)
            end),
    RetList = lists:filter(fun(X) -> X =:= Message end,
                           do_loop([], (Time * Count) + 1000, normal)), 
    timer2:sleep(1000),
    _ = ?_assertMatch({ok, {[], [], _}}, timer2_acceptor:show_tables()),
    ?_assertEqual(true, length(RetList) >= Count).

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
            ?debugFmt("Recived strange message OtherMessage:~p~n", [OtherMessage]),
            wait_for_message(Pid, Message, Timeout)
    after Timeout ->
            erlang:error(timeout)
    end.

wait_for_exit(Pid, Timeout) ->
    receive
        {'EXIT', _Pid, Reason} ->
            Reason;
        OtherMessage ->
            ?debugFmt("Recived strange message OtherMessage:~p~n", [OtherMessage]),
            wait_for_exit(Pid, Timeout)
    after Timeout ->
            erlang:error(timeout)
    end.

