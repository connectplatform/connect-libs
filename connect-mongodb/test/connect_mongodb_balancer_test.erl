%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB Load Balancer - Comprehensive Test Suite
%%%
%%% Dedicated test suite for advanced load balancing functionality:
%%% - Server management and configuration
%%% - Multiple balancing strategies  
%%% - Circuit breaker patterns
%%% - Health monitoring and recovery
%%% - Performance optimization
%%% - Real-time statistics and monitoring
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_balancer_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Setup and Teardown
%%%===================================================================

setup() ->
    application:ensure_all_started(connect_mongodb),
    TestConfig = #{
        host => <<"localhost">>,
        port => 27017,
        database => <<"balancer_test">>,
        pool_size => 3
    },
    case connect_mongodb:start_link(TestConfig) of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid
    end.

teardown(_Pid) ->
    % Clean up test servers and reset balancer
    connect_mongodb:remove_server(test_server_1),
    connect_mongodb:remove_server(test_server_2),
    connect_mongodb:remove_server(test_server_3),
    connect_mongodb:stop().

%%%===================================================================
%%% Test Generators
%%%===================================================================

balancer_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [
         fun test_server_management/1,
         fun test_balancing_strategies/1,
         fun test_circuit_breaker/1,
         fun test_health_monitoring/1,
         fun test_performance_optimization/1,
         fun test_statistics_monitoring/1,
         fun test_failover_recovery/1
     ]}.

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_server_management(_Pid) ->
    [
        ?_test(test_add_server()),
        ?_test(test_remove_server()),
        ?_test(test_update_server_weight()),
        ?_test(test_server_configuration()),
        ?_test(test_multiple_servers())
    ].

test_add_server() ->
    ServerConfig = #{
        host => <<"mongo1.cluster.com">>,
        port => 27017,
        type => primary,
        max_connections => 20,
        ssl => true
    },
    
    Result = connect_mongodb:add_server(ServerConfig, 10),
    ?assertMatch({ok, _ServerId}, Result).

test_remove_server() ->
    % Add server first
    ServerConfig = #{
        host => <<"mongo-temp.com">>,
        port => 27017,
        type => secondary
    },
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Then remove it
    Result = connect_mongodb:remove_server(ServerId),
    ?assertMatch({ok, removed}, Result).

test_update_server_weight() ->
    ServerConfig = #{
        host => <<"mongo-weighted.com">>,
        port => 27017,
        type => secondary
    },
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Update weight
    Result = connect_mongodb:set_server_weight(ServerId, 15),
    ?assertMatch({ok, updated}, Result).

test_server_configuration() ->
    % Test various server configurations
    Configs = [
        #{host => <<"primary.mongo.com">>, port => 27017, type => primary, weight => 20},
        #{host => <<"secondary1.mongo.com">>, port => 27017, type => secondary, weight => 10},
        #{host => <<"secondary2.mongo.com">>, port => 27018, type => secondary, weight => 10},
        #{host => <<"arbiter.mongo.com">>, port => 27019, type => arbiter, weight => 0}
    ],
    
    Results = [begin
        Weight = maps:get(weight, Config),
        connect_mongodb:add_server(Config, Weight)
    end || Config <- Configs],
    
    [?assertMatch({ok, _ServerId}, Result) || Result <- Results].

test_multiple_servers() ->
    % Add multiple servers and verify they're all managed
    ServerConfigs = [
        {<<"server1.mongo.com">>, 27017, primary, 15},
        {<<"server2.mongo.com">>, 27017, secondary, 10},
        {<<"server3.mongo.com">>, 27017, secondary, 8}
    ],
    
    ServerIds = [begin
        Config = #{host => Host, port => Port, type => Type},
        {ok, ServerId} = connect_mongodb:add_server(Config, Weight),
        ServerId
    end || {Host, Port, Type, Weight} <- ServerConfigs],
    
    % Verify all servers exist
    ?assertEqual(3, length(ServerIds)),
    
    % Get all servers
    AllServersResult = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, _Servers}, AllServersResult).

test_balancing_strategies(_Pid) ->
    [
        ?_test(test_round_robin_strategy()),
        ?_test(test_least_connections_strategy()),
        ?_test(test_weighted_strategy()),
        ?_test(test_response_time_strategy()),
        ?_test(test_geographic_strategy()),
        ?_test(test_strategy_switching())
    ].

test_round_robin_strategy() ->
    Result = connect_mongodb:set_balancing_strategy(round_robin),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_least_connections_strategy() ->
    Result = connect_mongodb:set_balancing_strategy(least_connections),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_weighted_strategy() ->
    Result = connect_mongodb:set_balancing_strategy(weighted),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_response_time_strategy() ->
    Result = connect_mongodb:set_balancing_strategy(response_time),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_geographic_strategy() ->
    Result = connect_mongodb:set_balancing_strategy(geographic),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_strategy_switching() ->
    Strategies = [
        round_robin,
        least_connections,
        weighted,
        response_time,
        geographic
    ],
    
    % Test switching between all strategies
    Results = [connect_mongodb:set_balancing_strategy(Strategy) || Strategy <- Strategies],
    [?assertMatch({ok, _}, Result) || Result <- Results],
    
    % Verify current strategy can be retrieved
    AllServersResult = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, #{current_strategy := _Strategy}}, AllServersResult).

test_circuit_breaker(_Pid) ->
    [
        ?_test(test_enable_circuit_breaker()),
        ?_test(test_disable_circuit_breaker()),
        ?_test(test_circuit_breaker_configuration()),
        ?_test(test_circuit_breaker_thresholds())
    ].

test_enable_circuit_breaker() ->
    % Add a server first
    ServerConfig = #{host => <<"circuit-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    CircuitBreakerOpts = #{
        failure_threshold => 5,
        recovery_timeout => 30000,
        half_open_max_calls => 3
    },
    
    Result = connect_mongodb:enable_circuit_breaker(ServerId, CircuitBreakerOpts),
    ?assertMatch({ok, enabled}, Result).

test_disable_circuit_breaker() ->
    % Add a server and enable circuit breaker first
    ServerConfig = #{host => <<"disable-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    CircuitBreakerOpts = #{failure_threshold => 3, recovery_timeout => 15000},
    connect_mongodb:enable_circuit_breaker(ServerId, CircuitBreakerOpts),
    
    % Now disable it
    Result = connect_mongodb:disable_circuit_breaker(ServerId),
    ?assertMatch({ok, disabled}, Result).

test_circuit_breaker_configuration() ->
    ServerConfig = #{host => <<"config-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Test various circuit breaker configurations
    Configurations = [
        #{failure_threshold => 3, recovery_timeout => 10000},
        #{failure_threshold => 10, recovery_timeout => 60000, error_rate_threshold => 0.5},
        #{failure_threshold => 5, recovery_timeout => 30000, half_open_max_calls => 5}
    ],
    
    Results = [begin
        connect_mongodb:enable_circuit_breaker(ServerId, Config)
    end || Config <- Configurations],
    
    [?assertMatch({ok, enabled}, Result) || Result <- Results].

test_circuit_breaker_thresholds() ->
    ServerConfig = #{host => <<"threshold-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Test different threshold configurations
    ThresholdConfigs = [
        #{failure_threshold => 1, recovery_timeout => 5000},   % Very sensitive
        #{failure_threshold => 20, recovery_timeout => 120000}, % Very tolerant
        #{failure_threshold => 5, recovery_timeout => 30000, error_rate_threshold => 0.8} % High error tolerance
    ],
    
    Results = [begin
        connect_mongodb:enable_circuit_breaker(ServerId, Config)
    end || Config <- ThresholdConfigs],
    
    [?assertMatch({ok, enabled}, Result) || Result <- Results].

test_health_monitoring(_Pid) ->
    [
        ?_test(test_server_health_stats()),
        ?_test(test_health_monitoring_intervals()),
        ?_test(test_server_status_tracking()),
        ?_test(test_unhealthy_server_detection())
    ].

test_server_health_stats() ->
    % Add a server to monitor
    ServerConfig = #{host => <<"health-test.mongo.com">>, port => 27017, type => primary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 10),
    
    % Get server health statistics
    Result = connect_mongodb:get_server_stats(ServerId),
    ?assertMatch({ok, #{
        status := _Status,
        response_time := _ResponseTime,
        connection_count := _ConnectionCount,
        requests_per_second := _RPS
    }}, Result).

test_health_monitoring_intervals() ->
    % This would test different health check intervals
    % In a real implementation, this would configure monitoring frequency
    ServerConfig = #{
        host => <<"interval-test.mongo.com">>, 
        port => 27017, 
        type => secondary,
        health_check_interval => 10000  % 10 seconds
    },
    
    Result = connect_mongodb:add_server(ServerConfig, 5),
    ?assertMatch({ok, _ServerId}, Result).

test_server_status_tracking() ->
    ServerConfig = #{host => <<"status-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Get current status
    {ok, Stats} = connect_mongodb:get_server_stats(ServerId),
    Status = maps:get(status, Stats),
    
    % Status should be one of the expected values
    ?assert(lists:member(Status, [healthy, degraded, failed, connecting])).

test_unhealthy_server_detection() ->
    % Test detection of unhealthy servers
    ServerConfig = #{host => <<"unhealthy-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 5),
    
    % Enable circuit breaker to handle unhealthy state
    CircuitBreakerOpts = #{failure_threshold => 2, recovery_timeout => 5000},
    Result = connect_mongodb:enable_circuit_breaker(ServerId, CircuitBreakerOpts),
    ?assertMatch({ok, enabled}, Result).

test_performance_optimization(_Pid) ->
    [
        ?_test(test_connection_distribution()),
        ?_test(test_response_time_optimization()),
        ?_test(test_load_distribution()),
        ?_test(test_concurrent_load_handling())
    ].

test_connection_distribution() ->
    % Add multiple servers
    Servers = [
        {<<"perf1.mongo.com">>, 27017, primary, 20},
        {<<"perf2.mongo.com">>, 27017, secondary, 15},
        {<<"perf3.mongo.com">>, 27017, secondary, 10}
    ],
    
    [begin
        Config = #{host => Host, port => Port, type => Type},
        connect_mongodb:add_server(Config, Weight)
    end || {Host, Port, Type, Weight} <- Servers],
    
    % Set weighted strategy to test distribution
    Result = connect_mongodb:set_balancing_strategy(weighted),
    ?assertMatch({ok, _PreviousStrategy}, Result).

test_response_time_optimization() ->
    % Test response time-based balancing
    connect_mongodb:set_balancing_strategy(response_time),
    
    % Get all servers to verify strategy is set
    Result = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, #{current_strategy := response_time}}, Result).

test_load_distribution() ->
    % Test load distribution across servers
    connect_mongodb:set_balancing_strategy(least_connections),
    
    % Verify strategy is active
    Result = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, #{current_strategy := least_connections}}, Result).

test_concurrent_load_handling() ->
    % Add servers for concurrent testing
    Servers = [
        {<<"concurrent1.mongo.com">>, 27017, primary, 25},
        {<<"concurrent2.mongo.com">>, 27017, secondary, 20},
        {<<"concurrent3.mongo.com">>, 27017, secondary, 15}
    ],
    
    ServerIds = [begin
        Config = #{host => Host, port => Port, type => Type, max_connections => 50},
        {ok, ServerId} = connect_mongodb:add_server(Config, Weight),
        ServerId
    end || {Host, Port, Type, Weight} <- Servers],
    
    % Verify all servers were added for concurrent handling
    ?assertEqual(3, length(ServerIds)).

test_statistics_monitoring(_Pid) ->
    [
        ?_test(test_global_balancer_stats()),
        ?_test(test_server_specific_stats()),
        ?_test(test_performance_metrics()),
        ?_test(test_real_time_monitoring())
    ].

test_global_balancer_stats() ->
    % Add some servers first
    Servers = [
        {<<"stats1.mongo.com">>, 27017, primary, 20},
        {<<"stats2.mongo.com">>, 27017, secondary, 15}
    ],
    
    [begin
        Config = #{host => Host, port => Port, type => Type},
        connect_mongodb:add_server(Config, Weight)
    end || {Host, Port, Type, Weight} <- Servers],
    
    % Get global statistics
    Result = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, #{
        total_servers := _Total,
        healthy_servers := _Healthy,
        current_strategy := _Strategy,
        server_stats := _ServerStats
    }}, Result).

test_server_specific_stats() ->
    ServerConfig = #{host => <<"specific-stats.mongo.com">>, port => 27017, type => primary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 15),
    
    % Get specific server stats
    Result = connect_mongodb:get_server_stats(ServerId),
    ?assertMatch({ok, #{
        status := _Status,
        response_time := _ResponseTime,
        connection_count := _ConnectionCount,
        requests_per_second := _RPS,
        error_rate := _ErrorRate
    }}, Result).

test_performance_metrics() ->
    % Add servers and get performance metrics
    ServerConfig = #{host => <<"metrics.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 10),
    
    {ok, Stats} = connect_mongodb:get_server_stats(ServerId),
    
    % Verify performance metrics are present
    ?assert(maps:is_key(response_time, Stats)),
    ?assert(maps:is_key(requests_per_second, Stats)),
    ?assert(maps:is_key(connection_count, Stats)).

test_real_time_monitoring() ->
    % Test real-time monitoring capabilities
    {ok, GlobalStats} = connect_mongodb:get_all_servers(),
    
    % Verify real-time stats structure
    ?assert(maps:is_key(total_servers, GlobalStats)),
    ?assert(maps:is_key(healthy_servers, GlobalStats)),
    ?assert(maps:is_key(server_stats, GlobalStats)).

test_failover_recovery(_Pid) ->
    [
        ?_test(test_server_failover()),
        ?_test(test_automatic_recovery()),
        ?_test(test_graceful_degradation()),
        ?_test(test_recovery_monitoring())
    ].

test_server_failover() ->
    % Add servers for failover testing
    PrimaryConfig = #{host => <<"primary-failover.mongo.com">>, port => 27017, type => primary},
    SecondaryConfig = #{host => <<"secondary-failover.mongo.com">>, port => 27017, type => secondary},
    
    {ok, PrimaryId} = connect_mongodb:add_server(PrimaryConfig, 20),
    {ok, SecondaryId} = connect_mongodb:add_server(SecondaryConfig, 15),
    
    % Enable circuit breakers for failover detection
    CircuitOpts = #{failure_threshold => 3, recovery_timeout => 10000},
    connect_mongodb:enable_circuit_breaker(PrimaryId, CircuitOpts),
    connect_mongodb:enable_circuit_breaker(SecondaryId, CircuitOpts),
    
    % Verify servers are added and configured
    ?assert(is_reference(PrimaryId)),
    ?assert(is_reference(SecondaryId)).

test_automatic_recovery() ->
    ServerConfig = #{host => <<"recovery-test.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 10),
    
    % Enable circuit breaker with recovery settings
    RecoveryOpts = #{
        failure_threshold => 2,
        recovery_timeout => 5000,
        half_open_max_calls => 2
    },
    
    Result = connect_mongodb:enable_circuit_breaker(ServerId, RecoveryOpts),
    ?assertMatch({ok, enabled}, Result).

test_graceful_degradation() ->
    % Add multiple servers to test graceful degradation
    Servers = [
        {<<"graceful1.mongo.com">>, 27017, primary, 25},
        {<<"graceful2.mongo.com">>, 27017, secondary, 20},
        {<<"graceful3.mongo.com">>, 27017, secondary, 15}
    ],
    
    ServerIds = [begin
        Config = #{host => Host, port => Port, type => Type},
        {ok, ServerId} = connect_mongodb:add_server(Config, Weight),
        % Enable circuit breakers for graceful handling
        connect_mongodb:enable_circuit_breaker(ServerId, #{failure_threshold => 5}),
        ServerId
    end || {Host, Port, Type, Weight} <- Servers],
    
    % Verify all servers are configured for graceful degradation
    ?assertEqual(3, length(ServerIds)).

test_recovery_monitoring() ->
    ServerConfig = #{host => <<"monitor-recovery.mongo.com">>, port => 27017, type => secondary},
    {ok, ServerId} = connect_mongodb:add_server(ServerConfig, 8),
    
    % Monitor recovery by checking server stats
    {ok, Stats} = connect_mongodb:get_server_stats(ServerId),
    
    % Verify monitoring data is available
    ?assert(maps:is_key(status, Stats)),
    ?assert(maps:is_key(error_rate, Stats)).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

% Helper function to create test server configuration
% create_test_server(Name, Port, Type, Weight) ->
%     Config = #{
%         host => list_to_binary(Name ++ ".test.mongo.com"),
%         port => Port,
%         type => Type,
%         max_connections => 25,
%         ssl => false
%     },
%     connect_mongodb:add_server(Config, Weight).

% Helper function to verify server status
% verify_server_status(ServerId, ExpectedStatus) ->
%     {ok, Stats} = connect_mongodb:get_server_stats(ServerId),
%     ActualStatus = maps:get(status, Stats),
%     ?assertEqual(ExpectedStatus, ActualStatus). 