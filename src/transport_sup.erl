-module(broker_sup).

-define(Broker, rabbitmq).

-behaviour(supervisor).

%% API
-export([start_link/0, get_broker/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    case ?Broker of
        rabbitmq ->
    {ok, { {one_for_one, 5, 10}, [
             {broker,
              {rabbitmq_broker, start_link, []},
              permanent,
              infinity,
              worker,
              [rabbitmq_broker] 
             } ]} };
        redis ->
    {ok, { {one_for_one, 5, 10}, [
             {broker,
              {redis_broker, start_link, []},
              permanent,
              infinity,
              worker,
              [redis_broker] 
             } ]} }
    end.

get_broker() ->
    Children = supervisor:which_children(?MODULE),
    io:format("~p, ~n", Children),
    {broker, Broker, _, _} = lists:keyfind(broker, 1, Children),
    Broker.

