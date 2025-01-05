%%
%% Copyright (c) 2024-2025, Byteplug LLC.
%%
%% This source file is part of a project made by the Erlangsters community and
%% is released under the MIT license. Please refer to the LICENSE.md file that
%% can be found at the root of the project directory.
%%
%% Written by Jonathan De Wachter <jonathan.dewachter@byteplug.io>, November 2024
%%
-module(reactor_test).
-include_lib("eunit/include/eunit.hrl").

compute_result(Operation, A, B) ->
    case Operation of
        add -> A + B;
        subtract -> A - B;
        multiply -> A * B
    end.

reactor_test() ->
    % A canonical test meant to verify the key features of the behavior.
    meck:new(my_reactor, [non_strict]),
    meck:expect(my_reactor, initialize, fun([A, B]) ->
        {continue, add, #{a => A, b => B}}
    end),
    meck:expect(my_reactor, handle_request, fun
        (Operation, result, _From, #{a := A, b := B} = Data) ->
            {reply, compute_result(Operation, A, B), Operation, Data};
        (_Operation, switch, _From, _Data) ->
            % Move to 'subtract' state and switch the operands.
            {reply, ok, subtract, #{a => 69, b => 42}}
    end),
    meck:expect(my_reactor, handle_notification, fun
        (Operation, {Pid, result}, #{a := A, b := B} = Data) ->
            Pid ! {self(), compute_result(Operation, A, B)},
            {continue, Operation, Data};
        (_Operation, switch, _Data) ->
            % Move to 'multiply' state and switch the operands.
            {continue, multiply, #{a => 10, b => 100}}
    end),
    meck:expect(my_reactor, handle_message, fun
        (Operation, {Pid, result}, #{a := A, b := B} = Data) ->
            Pid ! {self(), compute_result(Operation, A, B)},
            {continue, Operation, Data};
        (_Operation, switch, _Data) ->
            % Move back to initial state and data.
            {continue, add, #{a => 42, b => 69}}
    end),
    Root = self(),
    meck:expect(my_reactor, handle_transition, fun(From, To, Data) ->
        Root ! {transition, From, To, Data},
        {continue, Data}
    end),

    {ok, Pid} = reactor:spawn(link, my_reactor, [42, 69]),

    {reply, 111} = reactor:request(Pid, result),
    reactor:notify(Pid, {self(), result}),
    ok = receive
        {Pid, 111} -> ok
    end,
    Pid ! {self(), result},
    ok = receive
        {Pid, 111} -> ok
    end,

    {reply, ok} = reactor:request(Pid, switch),

    ok = receive
        {transition, add, subtract, #{a := 69, b := 42}} ->
            ok
    end,

    {reply, 27} = reactor:request(Pid, result),
    reactor:notify(Pid, {self(), result}),
    ok = receive
        {Pid, 27} -> ok
    end,
    Pid ! {self(), result},
    ok = receive
        {Pid, 27} -> ok
    end,

    ok = reactor:notify(Pid, switch),
    ok = receive
        {transition, subtract, multiply, #{a := 10, b := 100}} ->
            ok
    end,

    {reply, 1000} = reactor:request(Pid, result),
    reactor:notify(Pid, {self(), result}),
    ok = receive
        {Pid, 1000} -> ok
    end,
    Pid ! {self(), result},
    ok = receive
        {Pid, 1000} -> ok
    end,

    Pid ! switch,
    ok = receive
        {transition, multiply, add, #{a := 42, b := 69}} ->
            ok
    end,

    meck:unload(my_reactor),

    ok.

reactor_spawn_test() ->
    % XXX: To be implemented.
    ok.

reactor_enter_loop_test() ->
    % XXX: To be implemented.
    ok.

reactor_initialize_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_request_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_notification_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_message_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_timeout_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_task_test() ->
    % XXX: To be implemented.
    ok.

reactor_handle_transition_test() ->
    % XXX: To be implemented.
    ok.
