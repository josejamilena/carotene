-module(msg_queue_serv).

-behaviour(gen_server).

-export([init/1, terminate/2, code_change/3, handle_call/3,
         handle_cast/2, handle_info/2]).
-export([start/3, start_link/3]).
-export([stop/1]).

-include_lib("carotene.hrl").

-record(state, {exchange_name, reply_pid, auth_config, already_auth, user_id, queue}).

start_link(ExchangeName, UserId, ReplyPid) ->
    Opts = [],
    gen_server:start_link(?MODULE, [ExchangeName, UserId, ReplyPid], Opts).

start(ExchangeName, UserId, ReplyPid) ->
    Opts = [],
    gen_server:start(?MODULE, [ExchangeName, UserId, ReplyPid], Opts).

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).

init([ExchangeName, UserId, ReplyPid]) ->
    {ok, AuthConfig} = application:get_env(carotene, subscribe_auth),
    % TODO: things can go wrong here with authorization, but lets advance first
    erlang:monitor(process, ReplyPid),
    ok = maybe_consume(UserId, AuthConfig, ExchangeName),
    gen_server:cast(presence_serv, {subscribe_exchange, UserId, ExchangeName, self()}),
    {ok, #state{reply_pid = ReplyPid, exchange_name = ExchangeName, user_id = UserId}}.

handle_info({'DOWN', _Ref, process, _Pid, _}, State) ->
    {stop, normal, State};

handle_info({received_message, Msg, exchange, _Exchange}, State = #state{reply_pid = ReplyPid}) ->
    ReplyPid ! {received_message, Msg},
    {noreply, State};

handle_info(shutdown, State) ->
    {stop, normal, State}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

terminate(_Reason, #state{exchange_name=ExchangeName, user_id=UserId}) ->
    gen_server:cast(presence_serv, {unsubscribe_exchange, UserId, ExchangeName, self()}),
    ok.

code_change(_OldVsn, State, _Extra) ->
    State.

%% Internal
maybe_consume(UserId, AuthConfig, ExchangeName) ->
    case can_subscribe(UserId, AuthConfig, ExchangeName) of
        ok -> subscribe(ExchangeName);
        _ -> error
    end.

can_subscribe(UserId, AuthConfig, ExchangeName) ->
    case lists:keyfind(enabled, 1, AuthConfig) of
        false -> ok;
        {enabled, false} -> ok;
        {enabled, true} -> case lists:keyfind(level, 1, AuthConfig) of
                               false -> bad_configuration;
                               {level, anonymous} -> ok;
                               {level, auth} -> case UserId of
                                                    undefined -> needs_authentication;
                                                    _ -> ok
                                                end;
                               {level, ask} -> case ask_authentication(UserId, AuthConfig, ExchangeName) of
                                                   true -> ok;
                                                   Error -> Error
                                               end
                           end;
        _ -> ok
    end.

ask_authentication(UserId, AuthConfig, ExchangeName) ->
    case lists:keyfind(authorization_url, 1, AuthConfig) of
        false -> bad_configuration;
        {authorization_url, AuthorizeUrl} ->
            {ok, {{_Version, 200, _ReasonPhrase}, _Headers, Body}} = httpc:request(post, {AuthorizeUrl, [], "application/x-www-form-urlencoded", "user_id="++binary_to_list(UserId)++"&exchange="++binary_to_list(ExchangeName)}, [], []),
            % TODO: This can crash
            case jsx:decode(binary:list_to_bin(Body)) of
                [{<<"authorized">>, <<"true">>}] -> true;
                [{<<"authorized">>, <<"false">>}] -> no_authorization;
                _ -> bad_server_response_on_authorization
            end
    end.

subscribe(ExchangeName) ->
    {_BrokerModule, Broker} = broker_sup:get_broker(),
    % TODO: This is particular to rabbitmq
    {ok, QueueServer} = gen_server:call(Broker, start_queue),
    ok = gen_server:call(QueueServer, {subscribe, ExchangeName}).
