%%%-------------------------------------------------------------------
%%% @author stephb
%%% @copyright (C) 2020, Arilia Wireless Inc.
%%% @doc
%%%
%%% @end
%%% Created : 29. Oct 2020 3:11 p.m.
%%%-------------------------------------------------------------------
-module(user_default).
-author("stephb").

-include("../include/common.hrl").
-include("../include/inventory.hrl").
-include("../include/simengine.hrl").

%% API
-compile(export_all).
-compile(nowarn_export_all).

-define(SIM_APIKEY,sim_api_key).

-type generic_result() :: ok | { error, Reason::term() }.

-spec help() -> ok.
help()->
	case utils:app_env(role,none) of
		none ->
			io:format("Invalid application role. Please verify your configuration.~n");
		node ->
			node_help();
		manager ->
			manager_help()
	end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Node commands
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec node_help() -> ok.
node_help()->
	io:format("login(ApiKey).    ApiKey ,ust be a string.~n"),
	io:format("logout().~n"),
	io:format("connect(Node).    Node must be a string.~n"),
	io:format("connected().~n").

-spec login( ApiKey :: string()) -> ok.
login(ApiKey)->
	persistent_term:put(?SIM_APIKEY,ApiKey).

-spec logout() -> ok.
logout()->
	persistent_term:erase(?SIM_APIKEY),
	ok.

-spec connected() -> { ok , none } | { ok , Manager::node() }.
connected()->
	simnode:connected().

-spec connect(NodeName::string()) -> { ok , none | node() }.
connect(NodeName) ->
	Node = list_to_atom(NodeName),
	simnode:connect(Node).

-spec configuration() -> { ok , Configuration::term() }.
configuration()->
	simnode:get_configuration().


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%
%%  Manager commands
%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec manager_help() -> ok.
manager_help()->
	io:format("refresh_ouis().~n"),
	io:format("show_nodes().~n"),
	io:format("get_node_configuration( Node ).~n"),
	io:format("set_node_configuration( Node, Configuration ).~n").


-spec create_simulation(SimName::string())-> generic_result().
create_simulation(SimName) when is_list(SimName) ->
	{ ok , Nodes } = manager:connected_nodes(),
	io:format("Creation simulation: ~s~n",[SimName]),
	io:format("  -nodes(~p): ~p~n",[length(Nodes),Nodes]),
	MaxDevices = length(Nodes) * 10000,
	NumberOfDevices = input("Number of devices (max:" ++ integer_to_list(MaxDevices) ++ ") ", integer_to_list(MaxDevices div 2)),
	Simulation = #simulation{ id = list_to_binary(SimName),
		num_devices = list_to_integer(NumberOfDevices),
		creation_date = calendar:local_time(),
    start_date = undefined,
    end_date = undefined,
		nodes = Nodes },
	simengine:create(Simulation).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  CA Management functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec create_ca(SimName::string(),CAName::string())-> generic_result().
create_ca(SimName,CAName) when is_list(SimName), is_list(CAName)->
	ok.

-spec import_ca(SimName::string(),CAName::string(),Attributes::attribute_list())->ok | { error , Reason::term() }.
import_ca(SimName,CAName,Attributes) when is_list(SimName), is_list(CAName), is_map(Attributes) ->
	ok.

-spec remove_ca(SimName::string(),CAName::string())->generic_result().
remove_ca(SimName,CAName) when is_list(SimName), is_list(CAName) ->
	ok.

-spec show_ca(SimName::string(),CAName::string())-> { ok, Attributes::attribute_list() } | { error , Reason::term() }.
show_ca(SimName,CAName) when is_list(SimName), is_list(CAName) ->
	{ ok, #{} }.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Node Management functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec show_nodes() -> {ok,[node()]}.
show_nodes()->
	manager:connected_nodes().

-spec set_node_configuration( Node::node() , Configuration::term() ) -> ok.
set_node_configuration( Node, Configuration ) ->
	simnode:set_configuration(Node,Configuration).

-spec get_node_configuration( Node::node() ) -> { ok, Configuration::term() }.
get_node_configuration(Node) ->
	simnode:get_configuration(Node).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Node Management functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec create_server(SimName::string(),Type::service_role()) -> generic_result().
create_server(SimName,"mqtt_server") when is_list(SimName)->
	ok;
create_server(SimName,"ovsdb_server") when is_list(SimName)->
	ok;
create_server(SimName,all) when is_list(SimName)->
	ok;
create_server(SimName,Name) when is_list(SimName)->
	io:format("create_server: invalid server type ~p. Must be mqtt_server, ovsdb_server, all.~n",[Name]),
	{ error , unknown_server_type }.



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Misc management functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec refresh_ouis()-> ok.
refresh_ouis()->
	oui_server:refresh().


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%  Local utility functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

input(Prompt,Default)->
	InputData=string:trim(io:get_line( Prompt ++ " [" ++ Default ++ "] :")),
	case InputData=="" of
		true -> Default;
		false -> InputData
	end.

to_string([],R)->
	lists:reverse(R);
to_string([H|T],R) when is_list(H)->
	to_string(T,[H|R]);
to_string([H|T],R) when is_atom(H)->
	to_string(T,[atom_to_list(H)|R]);
to_string([H|T],R) when is_binary(H)->
	to_string(T,[binary_to_list(H)|R]).




