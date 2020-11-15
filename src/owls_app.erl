-module(owls_app).
-behaviour(application).

-export([start/2,start/0,load_cli/0]).
-export([stop/1]).

start(_Type, _Args) ->
	ok = app_settings(),
	owls_sup:start_link().

stop(_State) ->
	ok.

start() ->
	ok = app_settings(),
	application:ensure_all_started(owls).

load_cli()->
	code:purge(user_default),
	_=code:load_file(user_default),
	ok.

app_settings()->
	ok = load_cli(),
	ok = inets:start(),
	lager:start(),
	ok = application:start(sasl),
	ok = application:start(os_mon),
	disksup:set_check_interval(5),
	disksup:set_almost_full_threshold(0.90),
	_ = application:ensure_all_started(ssl),
	ok.
