
-module(timer2_tests).

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
