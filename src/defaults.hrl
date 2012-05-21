%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012  Mahesh Paolini-Subramanya
%%% @doc Common header files and definitions.
%%% @end
%%%-------------------------------------------------------------------
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

%%
%% Errors
%%

%% Timer
-define(UNKNOWN_TIMER, not_found).
-define(INVALID_TIMER, invalid_timer).
-define(EXISTS_TIMER, timer_exists).
-define(NOT_STARTED_TIMER, timer_not_started).
%% Gproc
-define(GPROC_REGISTRATION_ERROR, gproc_registration_error).
-define(GPROC_UNKNOWN_PROCESS, gproc_unknown_process).


%%
%% Types
%%
-define(TIMER2_TAB, timer2_tab).
-define(TIMER2_REF_TAB, timer2_ref_tab).
-define(TIMER2_PID_TAB, timer2_pid_tab).

-define(DEFAULT_TIMER_TIMEOUT, 5000).
-define(MAX_TIMEOUT, 16#0800000).


%%
%% Types
%%
-type error()                                 :: {error, Reason :: term()}.
-type timer_name()                            :: binary() | atom().
-type timer_type()                            :: atom().
-type time()                                  :: non_neg_integer().
-type timer2_ref()                            :: {reference(), reference()}.
-type timer2_server_ref()                     :: {pid(), reference()}.
-type child_type()                            :: timer2_acceptor | timer2_supervisor.

