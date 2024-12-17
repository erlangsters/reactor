%%
%% Copyright (c) 2024, Byteplug LLC.
%%
%% This source file is part of a project made by the Erlangsters community and
%% is released under the MIT license. Please refer to the LICENSE.md file that
%% can be found at the root of the project directory.
%%
%% Written by Jonathan De Wachter <jonathan.dewachter@byteplug.io>, November 2024
%%
-module(reactor).

-export_type([options/0]).

-export([start/3, start/4]).
% -export([stop/1, stop/2]).
-export([stop/2]).
-export([call/2, call/3]).
-export([cast/2]).
-export([reply/2]).

-export([get_state/1]).
-export([get_data/1]).

-export([enter_loop/3]).

%%
%% The reactor behavior.
%%
%% To be written.
%%
-type name() :: atom().
-type id() :: name() | pid().

-type timeout_action() :: {timeout, timeout(), Message :: term()}.
-type task_action() :: {task, Task :: term()}.
-type action() :: timeout_action() | task_action().

-type request_id() :: erlang:timestamp().
-type from() :: {pid(), request_id()}.

-type options() :: #{
    timeout => timeout()
}.

-type start_return() ::
    already_started |
    {ok, spawner:spawn_return()} |
    {aborted, Reason :: term()} |
    timeout |
    {error, Reason :: term()}
.
-type stop_return() ::
    already_stopped |
    timeout |
    ok.

-callback initialize(Args :: [term()]) ->
    {continue, State :: atom(), Data :: term()} |
    {continue, State :: atom(), Data :: term(), Action :: action()} |
    {abort, Reason :: term()}
.

-callback handle_call(State :: atom(), Request :: term(), From :: from(), Data :: term()) ->
    {reply, Reply :: term(), NewState :: atom(), NewData :: term()} |
    {reply, Reply :: term(), NewState :: atom(), NewData :: term(), Action :: action()} |
    {no_reply, NewData :: term(), NewState :: atom()} |
    {no_reply, NewData :: term(), NewState :: atom(), Action :: action()} |
    {stop, Reason :: term(), Reply :: term(), NewData :: term()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_cast(State :: atom(), Notification :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_message(State :: atom(), Message :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_timeout(State :: atom(), Payload :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_task(State :: atom(), Payload :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_transition(State :: atom(), NewState :: atom(), Data :: term()) ->
    {continue, NewData :: term()} |
    {continue, NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}.

-callback terminate(State :: atom(), Reason :: term(), Data :: term()) ->
    no_return().

-spec start(spawner:mode(), module(), [term()]) -> start_return().
start(Mode, Module, Args) ->
    start(Mode, Module, Args, []).

-spec start(spawner:mode(), module(), [term()], timeout()) -> start_return().
start(Mode, Module, Args, Options) ->
    Name = proplists:get_value(name, Options, undefined),
    Timeout = proplists:get_value(timeout, Options, infinity),

    Root = self(),
    Fun = fun() ->
        % We register the process (if requested).
        Return = case Name of
            undefined ->
                register_ok;
            Name ->
                try register(Name, self()) of
                    true ->
                        register_ok
                catch
                    error:badarg ->
                        register_not_ok
                end
        end,
        case Return of
            register_ok ->
                case Module:initialize(Args) of
                    {continue, State, Data} ->
                        Root ! {self(), '$reactor_initialized'},
                        loop(Module, State, State, Data, no_action, []);
                    {continue, State, Data, Action} ->
                        Root ! {self(), '$reactor_initialized'},
                        loop(Module, State, State, Data, Action, []);
                    {abort, Reason} ->
                        Root ! {self(), '$reactor_aborted', Reason}
                end;
            register_not_ok ->
                Root ! {self(), '$reactor_already_registered'}
        end
    end,
    Setup = fun(Pid, Monitor) ->
        receive
            {'DOWN', Monitor, process, Pid, Reason} ->
                % io:format(user, "YOLO: ~p~n", [Reason]),
                {error, Reason};
            {Pid, '$reactor_already_registered'} ->
                reactor_already_registered;
            {Pid, '$reactor_initialized'} ->
                ok;
            {Pid, '$reactor_aborted', Reason} ->
                {abort, Reason}
        after Timeout ->
            % xxx: race condition here
            erlang:exit(Pid, kill),
            timeout
        end
    end,
    {setup, Value, Return} = spawner:setup_spawn(Mode, Fun, Setup),
    case Value of
        ok ->
            {ok, Return};
        reactor_already_registered ->
            already_started;
        {abort, Reason} ->
            {aborted, Reason};
        timeout ->
            timeout;
        {error, Reason} ->
            {error, Reason}
    end.


% -spec stop(id()) -> stop_return().
% stop(Name) when is_atom(Name) ->
%     case whereis(Name) of
%         undefined ->
%             already_stopped;
%         Pid ->
%             stop(Pid)
%     end;

-spec stop(id(), timeout()) -> stop_return().
stop(Name, Timeout) when is_atom(Name) ->
    case whereis(Name) of
        undefined ->
            already_stopped;
        Pid ->
            stop(Pid, Timeout)
    end;
stop(_Pid, _Timeout) ->
    % Monitor = monitor(process, Pid),
    % case is_process_alive(Pid) ->
    %     true ->
    %         Pid ! '$reactor_stop',
    %         receive
    %             {'DOWN', Monitor, process, Server, normal} ->
    %                 ok
    %         after Timeout ->
    %             timeout
    %         end;
    %     false ->
    %         true = demonitor(Monitor)
    % end.
    ok.

-spec call(id(), term()) -> {reply, Reply :: term()} | no_reply.
call(Reactor, Request) ->
    call(Reactor, Request, infinity).

-spec call(id(), term(), timeout()) -> {reply, Reply :: term()} | no_reply.
call(Reactor, Request, Timeout) ->
    RequestId = erlang:timestamp(),
    From = {self(), RequestId},

    Reactor ! {'$reactor_call', From, Request},
    receive
        {reply, RequestId, Reply} ->
            {reply, Reply}
    after Timeout ->
        no_reply
    end.

-spec cast(id(), term()) -> ok.
cast(Reactor, Message) ->
    Reactor ! {'$reactor_cast', Message},
    ok.

-spec reply(from(), term()) -> ok.
reply({Pid, RequestId}, Response) ->
    Pid ! {reply, RequestId, Response},
    ok.

-spec get_state(id()) -> atom().
get_state(Pid) ->
    Pid ! {'$reactor_state', self()},
    receive
        {'$reactor_state', Pid, State} ->
            State
    end.

-spec get_data(id()) -> term().
get_data(Pid) ->
    Pid ! {'$reactor_data', self()},
    receive
        {'$reactor_data', Pid, Data} ->
            Data
    end.

-spec enter_loop(Module :: module(), State :: atom(), Data :: term()) ->
    no_return().
enter_loop(Module, State, Data) ->
    loop(Module, State, State, Data, no_action, []).

loop(Module, State, State, Data, {timeout, Timeout, Message}, Timers) ->
    % We must create a timer that must be ignored if we receive a message
    % before it expires. We generate a unique ID in order to identify it.
    Id = erlang:timestamp(),
    erlang:send_after(Timeout, self(), {'$reactor_timeout', Id, Message}),
    loop(Module, State, State, Data, no_action, [Id|Timers]);
loop(Module, State, State, Data, {task, Task}, Timers) ->
    % We must execute a task.
    case Module:handle_task(State, Task, Data) of
        {continue, NewState} ->
            loop(Module, State, NewState, Data, no_action, Timers);
        {continue, NewState, Action} ->
            loop(Module, State, NewState, Data, Action, Timers);
        {stop, Reason, NewData} ->
            try_terminate(Module, State, Reason, NewData)
    end;
loop(Module, State, State, Data, no_action, Timers) ->
    receive
        {'$reactor_state', Pid} ->
            Pid ! {'$reactor_state', self(), State},
            loop(Module, State, State, Data, no_action, Timers);
        {'$reactor_data', Pid} ->
            Pid ! {'$reactor_data', self(), Data},
            loop(Module, State, State, Data, no_action, Timers);
        {'$reactor_call', From, Request} ->
            % We clear the list of timers in order to ignore timers that are
            % currently active.
            NewTimers = [],

            case Module:handle_call(State, Request, From, Data) of
                {reply, Reply, NewState, NewData} ->
                    ok = reply(From, Reply),
                    loop(Module, State, NewState, NewData, no_action, NewTimers);
                {reply, Reply, NewState, NewData, Action} ->
                    ok = reply(From, Reply),
                    loop(Module, State, NewState, NewData, Action, NewTimers);
                {no_reply, NewState, NewData} ->
                    loop(Module, State, NewState, NewData, no_action, NewTimers);
                {no_reply, NewState, NewData, Action} ->
                    loop(Module, State, NewState, NewData, Action, NewTimers);
                {stop, Reason, Reply, NewData} ->
                    ok = reply(From, Reply),
                    try_terminate(Module, State, Reason, NewData);
                {stop, Reason, NewData} ->
                    try_terminate(Module, State, Reason, NewData)
            end;
        {'$reactor_cast', Message} ->
            % We clear the list of timers in order to ignore timers that are
            % currently active.
            NewTimers = [],

            case Module:handle_cast(State, Message, Data) of
                {continue, NewState, NewData} ->
                    loop(Module, State, NewState, NewData, no_action, NewTimers);
                {continue, NewState, NewData, Action} ->
                    loop(Module, State, NewState, NewData, Action, NewTimers);
                {stop, Reason, NewData} ->
                    try_terminate(Module, State, Reason, NewData)
            end;
        {'$reactor_timeout', Id, Message} ->
            % A timer has expired but we must ignore it if a message has been
            % received. If the timer ID is in the list of timers, we don't
            % ignore it.
            case lists:member(Id, Timers) of
                true ->
                    % Remove the timer ID from the list of timers.
                    NewTimers = lists:delete(Id, Timers),

                    case Module:handle_timeout(State, Message, Data) of
                        {continue, NewState, NewData} ->
                            loop(Module, State, NewState, NewData, no_action, NewTimers);
                        {continue, NewState, NewData, Action} ->
                            loop(Module, State, NewState, NewData, Action, NewTimers);
                        {stop, Reason, NewData} ->
                            try_terminate(Module, State, Reason, NewData)
                    end;
                false ->
                    % Simply ignore the timer.
                    loop(Module, State, State, Data, no_action, Timers)
            end;
        '$reactor_stop' ->
            try_terminate(Module, State, normal, Data);
        Message ->
            % We clear the list of timers in order to ignore timers that are
            % currently active.
            NewTimers = [],

            case Module:handle_message(State, Message, Data) of
                {continue, NewState, NewData} ->
                    loop(Module, State, NewState, NewData, no_action, NewTimers);
                {continue, NewState, NewData, Action} ->
                    loop(Module, State, NewState, NewData, Action, NewTimers);
                {stop, Reason, NewData} ->
                    try_terminate(Module, State, Reason, NewData)
            end
    end;
loop(Module, State, NewState, Data, _Action, _Timers) ->
    % A state change has occurred. (We clear the list of timers in order to
    % ignore them. The action is also ignored.)
    case Module:handle_transition(State, NewState, Data) of
        {continue, NewData} ->
            loop(Module, NewState, NewState, NewData, no_action, []);
        {continue, NewData, NewAction} ->
            loop(Module, NewState, NewState, NewData, NewAction, []);
        {stop, Reason, NewData} ->
            try_terminate(Module, State, Reason, NewData)
    end.

try_terminate(Module, State, Reason, Data) ->
    case erlang:function_exported(Module, terminate, 3) of
        true ->
            Module:terminate(State, Reason, Data),
            ok;
        false ->
            ok
    end.
