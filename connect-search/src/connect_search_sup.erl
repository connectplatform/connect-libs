%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Enhanced Supervision Tree
%%%
%%% Modern OTP 27 supervision with:
%%% - Dynamic connection pool management
%%% - Health monitoring and auto-recovery
%%% - Circuit breaker supervision
%%% - Telemetry and statistics collection
%%% - Hot code reloading support
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_sup).

-behaviour(supervisor).

%% API
-export([start_link/0, start_link/1]).

%% Supervisor callbacks
-export([init/1]).

%% Dynamic management
-export([
    add_connection_pool/2,
    remove_connection_pool/1,
    get_pool_stats/0,
    restart_pool/1
]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the supervisor with default configuration
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    start_link(#{}).

%%--------------------------------------------------------------------
%% @doc Start the supervisor with custom configuration
%%--------------------------------------------------------------------
-spec start_link(Options :: map()) -> ignore | {error, term()} | {ok, pid()}.
start_link(Options) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, [Options]).

%%--------------------------------------------------------------------
%% @doc Add a new connection pool dynamically
%%--------------------------------------------------------------------
-spec add_connection_pool(PoolName :: atom(), Config :: map()) -> 
    {ok, pid()} | {error, term()}.
add_connection_pool(PoolName, Config) ->
    PoolSpec = pool_child_spec(PoolName, Config),
    case supervisor:start_child(?SERVER, PoolSpec) of
        {ok, _Pid} = Ok -> Ok;
        {error, {already_started, Pid}} -> {ok, Pid};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Remove a connection pool dynamically  
%%--------------------------------------------------------------------
-spec remove_connection_pool(PoolName :: atom()) -> 
    ok | {error, not_found | restarting | running | simple_one_for_one}.
remove_connection_pool(PoolName) ->
    case supervisor:terminate_child(?SERVER, {pool, PoolName}) of
        ok ->
            supervisor:delete_child(?SERVER, {pool, PoolName});
        {error, _} = Error ->
            Error
    end.

%%--------------------------------------------------------------------
%% @doc Get statistics for all pools
%%--------------------------------------------------------------------
-spec get_pool_stats() -> {ok, map()} | {error, term()}.
get_pool_stats() ->
    try
        Children = supervisor:which_children(?SERVER),
        PoolStats = [begin
            case Id of
                {pool, PoolName} ->
                    Stats = connect_search_connection:get_stats(Pid),
                    {PoolName, Stats};
                _ ->
                    {system, #{status => running}}
            end
        end || {Id, Pid, _Type, _Modules} <- Children, is_pid(Pid)],
        
        {ok, #{
            total_pools => length([Id || {Id, _, _, _} <- Children, 
                                         element(1, Id) =:= pool]),
            pools => maps:from_list(PoolStats),
            supervisor_status => running,
            uptime => uptime()
        }}
    catch
        Class:Error:Stacktrace ->
            {error, {stats_failed, Class, Error, Stacktrace}}
    end.

%%--------------------------------------------------------------------
%% @doc Restart a specific connection pool
%%--------------------------------------------------------------------
-spec restart_pool(PoolName :: atom()) -> ok | {error, term()}.
restart_pool(PoolName) ->
    case supervisor:restart_child(?SERVER, {pool, PoolName}) of
        {ok, _} -> ok;
        {error, _} = Error -> Error
    end.

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the supervisor
%%--------------------------------------------------------------------
init([Options]) ->
    process_flag(trap_exit, true),
    
    %% Load configuration
    Config = load_configuration(Options),
    
    %% Define supervision strategy
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60,
        auto_shutdown => any_significant
    },
    
    %% Child specifications
    ChildSpecs = [
        %% Statistics and monitoring server
        #{
            id => connect_search_stats,
            start => {connect_search_stats, start_link, [Config]},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [connect_search_stats]
        },
        
        %% Health monitor
        #{
            id => connect_search_health,
            start => {connect_search_health, start_link, [Config]},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [connect_search_health]
        },
        
        %% Worker supervisor for async operations
        #{
            id => connect_search_worker_sup,
            start => {connect_search_worker_sup, start_link, [Config]},
            restart => permanent,
            shutdown => infinity,
            type => supervisor,
            modules => [connect_search_worker_sup]
        }
    ],
    
    %% Add configured connection pools
    ConnectionPools = maps:get(connection_pools, Config, #{}),
    PoolSpecs = [pool_child_spec(PoolName, PoolConfig) || 
                 {PoolName, PoolConfig} <- maps:to_list(ConnectionPools)],
    
    AllSpecs = ChildSpecs ++ PoolSpecs,
    
    {ok, {SupFlags, AllSpecs}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
%% Load and merge configuration from multiple sources
-spec load_configuration(map()) -> map().
load_configuration(Options) ->
    %% Application environment
    AppEnv = application:get_all_env(connect_search),
    
    %% Default configuration
    Defaults = #{
        connection_pools => #{
            primary => #{
                host => <<"localhost">>,
                port => 9200,
                scheme => <<"http">>,
                pool_size => 10,
                max_overflow => 5,
                timeout => 5000
            }
        },
        max_workers => 25,
        worker_timeout => 30000,
        monitoring_enabled => true,
        health_check_interval => 30000,
        circuit_breaker => #{
            failure_threshold => 5,
            recovery_timeout => 30000,
            half_open_max_calls => 3
        }
    },
    
    %% Merge in order of precedence: Options > AppEnv > Defaults
    Config1 = maps:merge(Defaults, maps:from_list(AppEnv)),
    maps:merge(Config1, Options).

%% @private  
%% Create child spec for connection pool
-spec pool_child_spec(atom(), map()) -> supervisor:child_spec().
pool_child_spec(PoolName, Config) ->
    #{
        id => {pool, PoolName},
        start => {connect_search_connection, start_link, [PoolName, Config]},
        restart => permanent,
        shutdown => 5000,
        type => worker,
        modules => [connect_search_connection]
    }.

%% @private
%% Calculate supervisor uptime
-spec uptime() -> non_neg_integer() | float().
uptime() ->
    case persistent_term:get({?MODULE, start_time}, undefined) of
        undefined ->
            StartTime = erlang:system_time(millisecond),
            persistent_term:put({?MODULE, start_time}, StartTime),
            0;
        StartTime ->
            erlang:system_time(millisecond) - StartTime
    end. 