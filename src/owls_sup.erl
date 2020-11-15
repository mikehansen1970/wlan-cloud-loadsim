-module(owls_sup).
-behaviour(supervisor).

-include("../include/common.hrl").
-include_lib("../deps/lager/include/lager.hrl").

-export([start_link/0]).
-export([init/1]).

start_link() ->
	supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	Processes = case application:get_env(?OWLS_APP,role,undefined) of
		manager ->
			?L_I1("Simulation Manager starting."),
			node_finder:creation_info() ++
			manager:creation_info() ++
			manager_rest_api:creation_info() ++
			oui_server:creation_info() ++
			inventory:creation_info();
		node ->
			?L_I1("Simulation Node starting."),
			simnode:creation_info() ++
      node_rest_api:creation_info();
		undefined ->
			lager:error("No role has been defined in configuration (must be manager or node)")
	end,
	{ok, {{one_for_one, 1, 5}, Processes}}.
