%%%-----------------------------------------------------------------------------
%%% @author helge
%%% @copyright (C) 2020, Arilia Wireless Inc.
%%% @doc
%%% 
%%% @end
%%% Created : 18. November 2020 @ 15:29:05
%%%-----------------------------------------------------------------------------
-module(ovsdb_client_handler).
-author("helge").

-behaviour(gen_server).
-behaviour(gen_sim_client).

-include("../include/common.hrl").
-include("../include/ovsdb_definitions.hrl").
-include("../include/inventory.hrl").

-define(SERVER, ?MODULE).


%% API
-export([start_link/0,creation_info/0]).
-export([set_configuration/1, start/1, start/2, restart/2, stop/1, stop/2, pause/1, pause/2, cancel/1, cancel/2, resume/1, report/0]).
-export([ap_status/2,push_ap_stats/2,dump_clients/0,list_ids/0,all_ready/0]).

% Debug API
-export ([dbg_status/0]).

%% gen_server callbacks
-export([init/1, handle_cast/2, handle_call/3, handle_info/2, terminate/2, code_change/3]).


%% data structures

-record (command,{
	cmd :: clients_start | clients_stop | clients_pause | clients_resume | clients_cancel,
	refs :: [UUID::binary()]
}).

-type command() :: #command{}.


-record (ap_proc_map, {
	process :: pid(),
	id :: UUID::binary()
}).

-record (hdl_state, {
	clients = ets:tid(),
	cmd_queue = [] :: [command()],
	config = #{} :: #{atom()=>term()},
	ap_statistics = [] :: [#ap_statistics{}],
	timer :: owls_timers:tms(),
	simnode_callback = none :: none | {pid(), term()},
	callback_state = none :: none | client_status(),
	state_num = 0 :: non_neg_integer()
}).


%%%============================================================================
%%% HANDLER - API
%%%============================================================================

-spec start_link () -> {ok, Pid :: pid()} | generic_error().
start_link () ->
	gen_server:start_link({local, ?SERVER},?MODULE, [], []).

creation_info() ->
	[	#{	id => ?MODULE ,
	       start => { ?MODULE , start_link, [] },
	       restart => permanent,
	       shutdown => 100,
	       type => worker,
	       modules => [?MODULE]} ].

dump_clients () ->
	gen_server:call(?SERVER,dump_clients).

list_ids() ->
	gen_server:call(?SERVER,list_ids).

all_ready() ->
	gen_server:call(?SERVER,all_ready).

%%% gen_sim_clients behaviour
-spec restart( all | [UUID::binary()], Attributes::#{ atom() => term() }) -> ok | generic_error().
restart( _UIDS,_Attributes ) ->
	ok.

-spec set_configuration (Cfg:: #{any() => any()}) -> ok | generic_error().
set_configuration (Cfg) ->
	gen_server:call(?SERVER,{set_config, Cfg}).

-spec start(What :: all | [UUID::binary()]) -> ok | generic_error().
start (What) ->
	start(What,#{}).

-spec start(What :: all | [UUID::binary()],Options :: #{atom()=>term()}) -> ok | generic_error().
start (What,Options) ->
	gen_server:call(?SERVER,{api_cmd_start, What, Options}).

-spec stop(What :: all | [UUID::binary()]) -> ok | generic_error().
stop (What) ->
	stop (What,#{}).

-spec stop(What :: all | [UUID::binary()],Options :: #{atom()=>term()}) -> ok | generic_error().
stop (What,Options) ->
	gen_server:call(?SERVER,{api_cmd_stop, What, Options}).

-spec pause(What :: all | [UUID::binary()]) -> ok | generic_error().
pause (What) ->
	pause (What,#{}).

-spec pause(What :: all | [UUID::binary()],Options :: #{atom()=>term()}) -> ok | generic_error().
pause (What,Options) ->
	gen_server:call(?SERVER,{api_cmd_pause, What, Options}).

-spec cancel(What :: all | [UUID::binary()]) -> ok | generic_error().
cancel (What) ->
	cancel (What,#{}).

-spec cancel(What :: all | [UUID::binary()],Options :: #{atom()=>term()}) -> ok | generic_error().
cancel (What, Options) ->
	gen_server:call(?SERVER,{api_cmd_cancel, What, Options}).

-spec report () -> {ok, Report :: term()} | generic_error().
report () ->
	gen_server:call(?SERVER,get_report).

resume (_) ->
	ok.

%%%============================================================================
%%% CLIENT CALLBACK API
%%%============================================================================
-spec ap_status (Status :: ovsdb_ap:ap_status(), Id :: binary()) -> ok.
ap_status (Status, Id) ->
	gen_server:cast(?SERVER,{status,Status,Id}).

-spec push_ap_stats (APStatistics :: #ap_statistics{}, Id :: string() |  binary()) -> ok.
push_ap_stats (Stats, Id) ->
	gen_server:cast(?SERVER,{ap_stats,Stats,Id}).


%%%============================================================================
%%% DEBUG API
%%%============================================================================

-spec dbg_status () -> ok.
dbg_status () ->
	gen_server:call(?SERVER,dbg_status).

%%%============================================================================
%%% GEN_SERVER callbacks
%%%============================================================================
-spec init (Args :: term()) -> {ok, State :: #hdl_state{}} | {stop, Reason :: term()}.
init (_) ->
	process_flag(trap_exit, true),
	ovsdb_client_stats:prepare_statistics(),
	{ok, _} = timer:apply_after(?MGR_REPORT_INTERVAL,gen_server,call,[self(),update_stats]),
	Tid = ets:new(ovsdb_clients,[ordered_set,private,{keypos, 2}]),
	{ok, #hdl_state{timer=owls_timers:new(millisecond), clients=Tid}}.

-spec handle_cast (Request :: term(), State :: #hdl_state{}) -> {noreply, NewState :: #hdl_state{}} | {stop, Reason :: term(), NewState :: #hdl_state{}}.
handle_cast (execute, State) ->
	{noreply, execute_cmd(State)};
handle_cast ({status,Status,Id}, State) ->
	{noreply, update_client_status(Status,Id,State)};
handle_cast ({ap_stats,NewStats,_Id},#hdl_state{ap_statistics=ApStats}=State) ->
	{noreply, State#hdl_state{ap_statistics=[NewStats|ApStats]}};
handle_cast (_,State) ->
	{noreply, State}.

-spec handle_call (Request :: term(), From :: {pid(),Tag::term()}, State :: #hdl_state{}) -> {reply, Reply :: term(), NewState :: #hdl_state{}} | {stop, Reason :: term(), Reply :: term(), NewState :: #hdl_state{}}.
handle_call ({set_config, Cfg},_,State) ->
	{reply, ok, apply_config(Cfg, State)};

handle_call ({api_cmd_start, Which, Options},_,#hdl_state{clients=Clients,simnode_callback=none}=State) ->
	ToStart = get_client_ids_in_state (Clients, ready, Which),
	NewState = State#hdl_state{simnode_callback=maps:get(callback,Options,none),
							   callback_state = running,
							   state_num = length(ToStart)},
	{reply, ok, cmd_startup_sim(NewState,Which,Options)};

handle_call ({api_cmd_start, Which, Options},_,State) ->
	{reply, ok, cmd_startup_sim(State,Which,Options)};

handle_call ({api_cmd_stop, Which, Options},_,#hdl_state{clients=Clients,simnode_callback=none}=State) ->
	ToStart = get_client_ids_in_state (Clients, {running,paused}, Which),
	NewState = State#hdl_state{simnode_callback=maps:get(callback,Options,none),
							   callback_state = ready,
							   state_num = length(ToStart)},
	{reply, ok, trigger_execute (0, queue_command (clients_stop, Which, NewState))};

handle_call ({api_cmd_stop, Which, _},_,State) ->
	NewState = trigger_execute (0, queue_command (clients_stop, Which, State)),
	{reply, ok, NewState};

handle_call ({api_cmd_pause, Which, _},_,State) ->
	NewState = trigger_execute (0, queue_command (clients_pause, Which,State)),
	{reply, ok, NewState};

handle_call ({api_cmd_resume, Which, _},_,State) ->
	NewState = trigger_execute (0, queue_command (clients_resume, Which,State)),
	{reply, ok, NewState};

handle_call ({api_cmd_cancel, Which, _},_,State) ->
	NewState = trigger_execute (0, queue_command (clients_cancel, Which,State)),
	{reply, ok, NewState};

handle_call (update_stats, _From, #hdl_state{clients=C, ap_statistics=S}=State) ->
	ovsdb_client_stats:update_statistics(C,S),
	{reply, ok, State#hdl_state{ap_statistics=[]}};

handle_call (dump_clients,_From, #hdl_state{clients=Clients}=State) ->
	C = ets:match_object(Clients,#ap_client{_='_'}),
	{reply,C,State};

handle_call (list_ids,_From, #hdl_state{clients=Clients}=State) ->
	C = ets:match_object(Clients,#ap_client{_='_'}),
	[io:format("~s~n",[X])||#ap_client{id=X}<-C],
	{reply,ok,State};

handle_call (all_ready,_From, #hdl_state{clients=Clients}=State) ->
	C = length(ets:match_object(Clients,#ap_client{_='_'})),
	R = length(get_client_ids_in_state(Clients,{ready},all)),
	if 
		(C > 0) and (C == R) ->
			{reply,true,State};
		true ->
			{reply,false,State}
	end;

handle_call (dbg_status,_From, State) ->
	print_debug_status (State),
	{reply, ok, State};

handle_call (_, _, State) ->
	{reply, invalid, State}.

-spec handle_info (Msg :: term(), State :: #hdl_state{}) -> {noreply, NewState :: #hdl_state{}}.
handle_info({'EXIT',From,Reason}, #hdl_state{clients=CTid}=State) ->
	case get_client_with_pid(CTid,From) of
		{ok, C} ->
			T = C#ap_client.transitions,
			UpdC = case Reason of
				normal -> 
					C#ap_client{process=none, transitions=[{cancelled,erlang:system_time()}|T]};
				_ ->
					C#ap_client{process=none, transitions=[{crashed,erlang:system_time()}|T]}
			end,
			ets:insert(CTid,UpdC),
			ets:match_delete(CTid,{ap_proc_map,From,'_'}),
			{noreply, cmd_launch_clients([C#ap_client.id],State)};
		_ ->
			{noreply, State}
	end;
	
handle_info(_, State) ->
	{noreply, State}.

-spec terminate (Reason :: shutdown | {shutdown, term()} | norma, State :: #hdl_state{}) -> ok.
terminate (_Reason, _State) ->
	ovsdb_client_stats:close().

-spec code_change (OldVersion :: term(), OldState ::#hdl_state{}, Extra :: term()) -> {ok, Extra :: term()}.
code_change (_,OldState,_) ->
	{ok, OldState}.

%%%============================================================================
%%% internal functions
%%%============================================================================

%--------trigger_execute/2---------------trigger execute after a delay of D milliseconds (0 = immedeately)

-spec trigger_execute (Delay :: non_neg_integer(), State :: #hdl_state{}) -> NewState :: #hdl_state{}.
trigger_execute (0, State) ->
	gen_server:cast(self(),execute),
	State.

%--------queue_command/3-----------------que command into state 
-spec queue_command (Where :: front | back,Command :: clients_start | clients_stop | clients_pause | clients_resume | clients_cancel, Refs :: all | [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
queue_command (Where,Cmd, all, #hdl_state{clients=Clients}=State) ->
	queue_command (Where,Cmd,[ID || #ap_client{id=ID} <- ets:match_object(Clients,'$1')],State);
queue_command (Where,Cmd,Refs,#hdl_state{cmd_queue=Q}=State) ->
	NewQueue = case Where of
		back -> 
			[#command{cmd=Cmd, refs=Refs}|Q];
		front -> 
			Q ++ [#command{cmd=Cmd, refs=Refs}]
	end,
	State#hdl_state{cmd_queue=NewQueue}.

-spec queue_command (Command :: clients_start | clients_stop | clients_pause | clients_resume | clients_cancel, Refs :: all | [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
queue_command (Command, Refs, State) ->
	queue_command (back,Command, Refs, State).

%--------apply_config/2------------------translates configuration into state
-spec apply_config (Cfg :: #{any() => any()}, State :: #hdl_state{}) -> NewState :: #hdl_state{}.
apply_config (Cfg, #hdl_state{clients=Clients}=State) when is_map_key(file,Cfg) ->
	#{file := CfgFile} = Cfg,
	Path = case filelib:is_regular(CfgFile) of
		true -> CfgFile;
		_ -> filename:join([utils:priv_dir(),CfgFile])
	end,
	_ = case file:consult(Path) of
		{ok, [Refs]} ->
			C = [#ap_client{id=ID,ca_name=CA,status=available,process=none,transitions=[{available,erlang:system_time()}]} || {CA,ID}<-Refs],
			ets:insert(Clients,C);
			
		{error, Err} ->
			?L_E(?DBGSTR("invalid config file at '~s' with error: '~p'",[Path,Err]))	
	end,
	State;
apply_config (Cfg, #hdl_state{clients=Clients}=State) when is_map_key(internal,Cfg) ->
	#{internal:=SimName, clients:=Num} = Cfg,
	case inventory:list_clients(SimName) of
		{ok, AvailCL} when length(AvailCL) > 0 ->			
			M = min(Num,length(AvailCL)),
			?L_I(?DBGSTR("startig ~B clients for simulation '~s'",[M,SimName])),
			F = fun (X) -> #ap_client{
								id=X,
								ca_name=SimName,
								status=available,
								process=none,
								transitions=[{available,erlang:system_time()}]
							}
			end,
			C = [F(X)||{N,X}<-lists:zip(lists:seq(1,length(AvailCL)),AvailCL),N=<M],
			ets:insert(Clients,C),
			State;
		_ ->
			?L_E(?DBGSTR("there are no clients in the inventory for simulation '~s'",[SimName])),
			State
	end;
apply_config (#{sim_name:=SimName, clients:=IDs, ovsdb_server_name:=Rsrv, ovsdb_server_port:=Rport}=CfgIn,State) ->
	Cfg = #{
		sim_name => SimName,
		client_ids => IDs,
		ovsdb_srv => list_to_binary(lists:flatten(["ssl",":",Rsrv,":",integer_to_list(Rport)])),
		callback => maps:get(callback,CfgIn,none)
	},
	apply_config (Cfg,State);
apply_config (#{sim_name:=SimName, client_ids:=IDs, ovsdb_srv:=R, callback:=SNCB}=Cfg, 
			  #hdl_state{clients=Clients}=State) ->
	F = fun (X) -> #ap_client{
						id=X,
						ca_name=SimName,
						redirector=R,
						status=available,
						process=none,
						transitions=[{available,erlang:system_time()}]
					}
	end,
	C = [F(X)||X<-IDs],
	ets:insert(Clients,C),
	cmd_launch_clients(IDs,State#hdl_state{config=Cfg, simnode_callback=SNCB, callback_state=ready, state_num=length(IDs)});
apply_config (_,State) ->
	io:format("GOT CONFIG I DON'T UNDERSTAND~n"),
	State.

%--------update_client_status/3-----------update the state of a client in the clients map
-spec update_client_status (ClientState :: available | dead | ovsdb_ap:ap_status(), ClientId :: string(), HandlerState :: #hdl_state{}) -> NewHandlerSate :: #hdl_state{}.
update_client_status (ClS, Id, #hdl_state{clients=Clients}=State) ->
	{ok, C} = get_client_with_id(Clients,Id),
	T = C#ap_client.transitions,
	ets:insert(Clients,C#ap_client{status=ClS,transitions=[{ClS,erlang:system_time()}|T]}),
	maybe_notify_simnode (State).

-spec maybe_notify_simnode (State::#hdl_state{}) -> State::#hdl_state{}.
maybe_notify_simnode (#hdl_state{simnode_callback=none}=State) ->
	State;
maybe_notify_simnode (#hdl_state{clients=Clients, simnode_callback={SN,Msg}, callback_state=Status, state_num=Num}=State) ->
	IDs = [X||#ap_client{id=X}<-ets:match_object(Clients,#ap_client{_='_'})],
	case length(get_client_ids_in_state(Clients,{Status},IDs)) == Num of
		true ->
			?L_IA("NOTIFY SIMNODE of ~s",[Status]),
			SN ! Msg,
			State#hdl_state{simnode_callback=none, callback_state=none, state_num=0};
		false ->
			State
	end.
	
%--------get_clients_in_state/3----------filter all clients with state
-spec get_client_ids_in_state (Clients :: ets:tid(), State :: client_status() | tuple(), Refs :: all | [UUID::binary()]) ->  [UUID::binary()].
get_client_ids_in_state (Tid, State, Refs) when is_atom(State) ->
	get_client_ids_in_state (Tid,{State},Refs);
get_client_ids_in_state (Tid, States, Refs) ->
	MSpec = [{#ap_client{status=X,_='_'},[],['$_']}||X<-tuple_to_list(States)],
	Clients = ets:select(Tid,MSpec),
	Cids = [ID||#ap_client{id=ID}<-Clients],
	case Refs of
		all ->
			Cids;
		Cand when is_list(Cand) ->
			[ID || ID <- Cids, lists:member(ID,Cand)]
	end.

-spec get_clients_with_ids (Clients::ets:tid(),Ids::[UUID::binary()]) -> [#ap_client{}].
get_clients_with_ids (CTid, Ids) ->
	get_clients_with_ids (CTid, Ids, []).
get_clients_with_ids (_,[],Acc) ->
	Acc;
get_clients_with_ids (CTid,[ID|Rest],Acc) ->
	case ets:match_object(CTid,#ap_client{id=ID,_='_'}) of
		[R] ->
			get_clients_with_ids (CTid,Rest,[R|Acc]);
		_ ->
			io:format("ID> ~s~n",[ID]),
			[]
	end.

 -spec get_client_with_pid (Clients :: ets:tid(), Pid :: pid()) -> {ok, #ap_client{}} | {error, not_found}.
get_client_with_pid (Tid, Pid) ->
	case ets:match_object(Tid,{ap_proc_map,Pid,'_'}) of
		[] ->
			{error, not_found};
		[{_,_,Id}] ->
			get_client_with_id(Tid,Id)
	end.

-spec get_client_with_id (Clients :: ets:tid(), Id :: string()) -> {ok, #ap_client{}} | {error, not_found}.
get_client_with_id (Tid, Id) ->
	case ets:match_object(Tid,#ap_client{id=Id,_='_'}) of
		[] ->
			{error, not_found};
		[R|_] ->
			{ok, R}
	end.

%--------cmd_startup_sim/2--------------lauches the start-up sequence of simulation clients
-spec cmd_startup_sim (State :: #hdl_state{},
                       Which :: all | [UUID::binary()],
                       Options :: #{atom() => term()}) -> NewState :: #hdl_state{}.
cmd_startup_sim (#hdl_state{timer=T, clients=Clients}=State, Which, #{stagger:={N,Per}}=Options) ->	
	case get_client_ids_in_state (Clients, ready, Which) of
		[] ->
			io:format("DONE STARTING CLIENTS~n"),
			?L_I("DONE STARTING CLIENTS"),
			T2 = owls_timers:mark("startup sequence end",T),
			State#hdl_state{timer=T2};
		Ready ->	
			T2 = owls_timers:mark("startup sequence ...",T),
			Sp = min(N,length(Ready)),
			{ToStart,_} = lists:split(Sp,Ready),
			_=timer:apply_after(Per,gen_server,call,[self(),{api_cmd_start, Which, Options}]),
			%io:format("STARTED CLIENTS ~p, more to come in ~Bms~n",[ToStart,Per]),
			trigger_execute (0, queue_command(front,clients_start,ToStart,State#hdl_state{timer=T2}))
	end;	
cmd_startup_sim (#hdl_state{timer=T, clients=Clients}=State, Which, _) ->
	T2 = owls_timers:mark("startup",T),
	ToStart = get_client_ids_in_state (Clients, ready, Which),
	trigger_execute (0, queue_command(front,clients_start,ToStart,State#hdl_state{timer=T2})).

%--------cmd_launch_clients/2--------------------lauch processes for clients (synchrounsly)
-spec cmd_launch_clients (ToLauch :: [UUID::binary()],State :: #hdl_state{}) -> State :: #hdl_state{}.
cmd_launch_clients (ToLauch, #hdl_state{clients=Clients}=State) ->
	Opt = [{report_int,?AP_REPORT_INTERVAL},{stats_int,?AP_STATS_INTERVAL}],
	F = fun (#ap_client{id=ID,ca_name=CAName,redirector=R}=C) -> 
			{ok, Pid} = ovsdb_ap:launch(CAName,ID,[{redirector,R}|Opt]), 
			[#ap_proc_map{id=ID, process=Pid},C#ap_client{process=Pid}]
		end,
	L = [F(C) || C <- get_clients_with_ids(Clients,ToLauch)],
	ets:insert(Clients,lists:flatten(L)),
	T = owls_timers:mark("launched",State#hdl_state.timer),
	State#hdl_state{timer=T}.

%%-----------------------------------------------------------------------------
%% command queue handling

%--------execute_cmd/1-------------------executes the first command in queue
-spec execute_cmd (State :: #hdl_state{}) -> NewState :: #hdl_state{}.
execute_cmd (#hdl_state{cmd_queue=[]}=State) ->
	State;
execute_cmd (#hdl_state{cmd_queue=Q}=State) ->
	[Cmd|RemCmds] = lists:reverse(Q),
	AltState = State#hdl_state{cmd_queue=lists:reverse(RemCmds)},
	case Cmd of	
		#command{cmd=clients_start, refs=R} ->
			clients_start(R, AltState);
		#command{cmd=clients_pause, refs=R} ->
			clients_pause(R, AltState);
		#command{cmd=clients_resume, refs=R} ->
			clients_resume(R, AltState);
		#command{cmd=clients_stop, refs=R} ->
			clients_stop(R, AltState);
		#command{cmd=clients_cancel, refs=R} ->
			clients_cancel(R, AltState)
	end.

%--------clients_start/2-------------starts the simulation of the cliens (in ready state)
-spec clients_start (Refs :: [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
clients_start (Refs, #hdl_state{clients=Clients, timer=T}=State) ->	 
	Ready = get_client_ids_in_state (Clients,ready,Refs),
	[ovsdb_ap:start_ap(P) || #ap_client{process=P} <- get_clients_with_ids(Clients,Ready)],
	State#hdl_state{timer=owls_timers:mark("clients_started",T)}.

%--------clients_stop/2-------------stops the simulation in specified clients
-spec clients_stop (Refs :: [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
clients_stop (Refs, #hdl_state{clients=Clients, timer=T}=State) ->
	T2 = owls_timers:mark("stop_called",T),
	ToStop = get_clients_with_ids(Clients,get_client_ids_in_state(Clients,{running,paused},Refs)),
	[ovsdb_ap:stop_ap(P) || #ap_client{process=P} <- ToStop],
	State#hdl_state{timer=owls_timers:mark("stop_executed",T2)}.

%--------clients_pause/2-------------pauses clients that are in running state
-spec clients_pause (Refs :: [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
clients_pause (Refs, #hdl_state{clients=Clients, timer=T}=State) ->
	T2 = owls_timers:mark("pause_called",T),
	ToPause = get_clients_with_ids(Clients,get_client_ids_in_state(Clients,running,Refs)),
	[ovsdb_ap:pause_ap(P) || #ap_client{process=P} <- ToPause],
	State#hdl_state{timer=owls_timers:mark("pause_executed",T2)}.

%--------clients_resume/2-------------resume paused clients
-spec clients_resume (Refs :: [UUID::binary()], State :: #hdl_state{}) -> NewState :: #hdl_state{}.
clients_resume (Refs, #hdl_state{clients=Clients, timer=T}=State) ->
	T2 = owls_timers:mark("resume_called",T),
	ToResume = get_clients_with_ids(Clients,get_client_ids_in_state(Clients,paused,Refs)),
	[ovsdb_ap:start_ap(P) || #ap_client{process=P} <- ToResume],
	State#hdl_state{timer=owls_timers:mark("resume_executed",T2)}.

%--------clients_cancel/2-------------cancel clients regardless of state
-spec clients_cancel (Refs :: [UUID::binary()], State :: #hdl_state{}) -> NNewState :: #hdl_state{}.
clients_cancel (Refs, #hdl_state{clients=Clients, timer=T}=State) ->
	T2 = owls_timers:mark("cancel_called",T),
	ToCancel = get_clients_with_ids(Clients,get_client_ids_in_state(Clients,{running,paused,stopped},Refs)),		
	[ovsdb_ap:cancel_ap(P) || #ap_client{process=P} <- ToCancel],
	State#hdl_state{timer=owls_timers:mark("cancel_executed",T2)}.


%%-----------------------------------------------------------------------------
%% cdebug output 

-spec print_debug_status (State :: #hdl_state{}) -> ok.
print_debug_status (#hdl_state{clients=Clients}) ->
	Cl = ets:match_object(Clients,#ap_client{_='_'}),
	dbg_status_header(),
	F = fun (Id,none) ->
				io:format("| ~17s |  *** error this AP was never created ***~n",[Id]);
		  	(_,Pid) ->
			    R = ovsdb_ap:dbg_status(Pid),
				dbg_status_row(R)
	end,
	[ F(ID,Pid) || #ap_client{id=ID, process=Pid} <- Cl ],
	io:format("+=================================================================================================+~n"),
	ok.

dbg_status_header () ->
	io:format("~n~n"),
	io:format("+=================================================================================================+~n"),
	io:format("|       AP ID       |   status   |   state   |   mqtt   | recons | clients | monitors | published |~n"),
	io:format("+-------------------------------------------------------------------------------------------------+~n").

dbg_status_row (R) ->
	io:format("| ~17s | ~10s | ~9s | ~8s | ~6B | ~7B | ~8B | ~9B |~n",
		[R#status_info.id,
		 R#status_info.status,
		 R#status_info.substate,
		 R#status_info.mqtt,
		 R#status_info.recons,
		 R#status_info.clients,
		 R#status_info.monitors,
		 R#status_info.published]
	).