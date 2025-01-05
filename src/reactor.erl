%%
%% Copyright (c) 2024-2025, Byteplug LLC.
%%
%% This source file is part of a project made by the Erlangsters community and
%% is released under the MIT license. Please refer to the LICENSE.md file that
%% can be found at the root of the project directory.
%%
%% Written by Jonathan De Wachter <jonathan.dewachter@byteplug.io>, November 2024
%%
-module(reactor).

-export([spawn/3, spawn/4, spawn/5]).
-export([enter_loop/3]).
-export([request/2, request/3]).
-export([notify/2]).
-export([reply/2]).
-export([get_state/1]).
-export([get_data/1]).

-compile({no_auto_import, [spawn/4]}).

%%
%% The reactor behavior.
%%
%% To be written.
%%

-type name() :: atom().
-type id() :: name() | pid().

-type timer_action() :: {timer, timeout(), Message :: term()}.
-type task_action() :: {task, Message :: term()}.
-type action() :: timer_action() | task_action().

-type request_id() :: erlang:timestamp().
-type from() :: {pid(), request_id()}.

-type spawn_return() ::
    already_spawned |
    {ok, spawner:spawn_return()} |
    {aborted, Reason :: term()} |
    timeout |
    {error, Reason :: term()}
.

-callback initialize(Args :: [term()]) ->
    {continue, State :: atom(), Data :: term()} |
    {continue, State :: atom(), Data :: term(), Action :: action()} |
    {abort, Reason :: term()}
.

-callback handle_request(State :: atom(), Request :: term(), From :: from(), Data :: term()) ->
    {reply, Response :: term(), NewState :: atom(), NewData :: term()} |
    {reply, Response :: term(), NewState :: atom(), NewData :: term(), Action :: action()} |
    {no_reply, NewData :: term(), NewState :: atom()} |
    {no_reply, NewData :: term(), NewState :: atom(), Action :: action()} |
    {stop, Reason :: term(), Reply :: term(), NewData :: term()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_notification(State :: atom(), Notification :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_message(State :: atom(), Message :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_task(State :: atom(), Payload :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_timeout(State :: atom(), Payload :: term(), Data :: term()) ->
    {continue, NewState :: atom(), NewData :: term()} |
    {continue, NewState :: atom(), NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}
.

-callback handle_transition(State :: atom(), NewState :: atom(), Data :: term()) ->
    {continue, NewData :: term()} |
    {continue, NewData :: term(), Action :: action()} |
    {stop, Reason :: term(), NewData :: term()}.

-callback terminate(State :: atom(), Reason :: term(), Data :: term()) ->
    Return :: term().

-spec spawn(spawner:mode(), module(), [term()]) -> spawn_return().
spawn(Mode, Module, Args) ->
    spawn(Mode, no_name, Module, Args).

-spec spawn(spawner:mode(), no_name | {name, name()}, module(), [term()]) ->
    spawn_return().
spawn(Mode, Name, Module, Args) ->
    spawn(Mode, Name, Module, Args, infinity).

-spec spawn(
    spawner:mode(),
    no_name | {name, name()},
    module(),
    [term()],
    timeout()
) -> spawn_return().
spawn(Mode, Name, Module, Args, Timeout) ->
    Root = self(),
    Loop = fun() ->
        % We register the process (if requested).
        Return = case Name of
            no_name ->
                register_ok;
            {name, Name_} ->
                try register(Name_, self()) of
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
                {error, Reason};
            {Pid, '$reactor_already_registered'} ->
                reactor_already_registered;
            {Pid, '$reactor_initialized'} ->
                ok;
            {Pid, '$reactor_aborted', Reason} ->
                {abort, Reason}
        after Timeout ->
            % XXX: Fix race condition here.
            erlang:exit(Pid, kill),
            timeout
        end
    end,
    {setup, Value, Return} = spawner:setup_spawn(Mode, Loop, Setup),
    case Value of
        ok ->
            {ok, Return};
        reactor_already_registered ->
            already_spawned;
        {abort, Reason} ->
            {aborted, Reason};
        timeout ->
            timeout;
        {error, Reason} ->
            {error, Reason}
    end.

-spec enter_loop(Module :: module(), State :: atom(), Data :: term()) ->
    Return :: term().
enter_loop(Module, State, Data) ->
    loop(Module, State, State, Data, no_action, []).

-spec request(id(), term()) -> {reply, Response :: term()} | no_reply.
request(Server, Request) ->
    request(Server, Request, infinity).

-spec request(id(), term(), timeout()) -> {reply, Reply :: term()} | no_reply.
request(Server, Request, Timeout) ->
    RequestId = erlang:timestamp(),
    From = {self(), RequestId},

    Server ! {'$reactor_request', From, Request},
    receive
        {reply, RequestId, Response} ->
            {reply, Response}
    after Timeout ->
        no_reply
    end.

-spec notify(id(), term()) -> ok.
notify(Server, Message) ->
    Server ! {'$reactor_notify', Message},
    ok.

-spec reply(from(), term()) -> ok.
reply({Pid, RequestId}, Response) ->
    Pid ! {reply, RequestId, Response},
    ok.

-spec get_state(id()) -> atom().
get_state(Server) ->
    Server ! {'$reactor_state', self()},
    receive
        {'$reactor_state', Server, State} ->
            State
    end.

-spec get_data(id()) -> term().
get_data(Server) ->
    Server ! {'$reactor_data', self()},
    receive
        {'$reactor_data', Server, Data} ->
            Data
    end.

loop(Module, State, State, Data, {timer, Timeout, Message}, Timers) ->
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
        {'$reactor_request', From, Request} ->
            % We clear the list of timers in order to ignore timers that are
            % currently active.
            NewTimers = [],

            case Module:handle_request(State, Request, From, Data) of
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
        {'$reactor_notify', Message} ->
            % We clear the list of timers in order to ignore timers that are
            % currently active.
            NewTimers = [],

            case Module:handle_notification(State, Message, Data) of
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
            Module:terminate(State, Reason, Data);
        false ->
            ok
    end.
