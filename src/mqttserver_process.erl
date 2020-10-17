%%%-------------------------------------------------------------------
%%% @author stephb
%%% @copyright (C) 2020, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 14. Oct 2020 10:14 p.m.
%%%-------------------------------------------------------------------
-module(mqttserver_process).
-author("stephb").

-include("../include/mqtt_definitions.hrl").
-include("../include/internal.hrl").

%% API
-export([process/2]).

process(Data,State)->
	io:format("Data (~p bytes)>>> ~p~n",[length(Data),Data]),
	{ <<"Hello from MQTT">>, State }.

