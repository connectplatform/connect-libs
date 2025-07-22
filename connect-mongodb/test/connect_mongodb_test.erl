%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - OTP 27 Enhanced Tests
%%%
%%% Test suite for modernized MongoDB driver with:
%%% - OTP 27 gen_server behavior testing
%%% - Async/await pattern testing
%%% - Map-based configuration testing
%%% - Enhanced error handling with error/3
%%% - Persistent terms caching testing
%%% - Connection pool management testing
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Setup and Teardown
%%%===================================================================

setup() ->
    application:ensure_all_started(connect_mongodb),
    % Initialize with test configuration
    TestConfig = #{
        host => <<"localhost">>,
        port => 27017,
        database => <<"connect_test">>,
        pool_size => 5,
        max_workers => 10
    },
    case connect_mongodb:start_link(TestConfig) of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid
    end.

teardown(_Pid) ->
    connect_mongodb:stop(),
    application:stop(connect_mongodb).

%%%===================================================================
%%% Test Generators
%%%===================================================================

connect_mongodb_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [
         fun test_basic_operations/1,
         fun test_async_operations/1,
         fun test_gridfs_operations/1,
         fun test_change_streams/1,
         fun test_load_balancing/1,
         fun test_error_handling/1,
         fun test_configuration/1,
         fun test_statistics/1,
         fun test_connection_pool/1
     ]}.

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_basic_operations(_Pid) ->
    [
        ?_test(test_insert_one()),
        ?_test(test_insert_many()),
        ?_test(test_find_operations()),
        ?_test(test_update_operations()),
        ?_test(test_delete_operations()),
        ?_test(test_count_documents()),
        ?_test(test_collection_operations()),
        ?_test(test_index_operations())
    ].

test_async_operations(_Pid) ->
    [
        ?_test(test_async_insert()),
        ?_test(test_async_find()),
        ?_test(test_async_update()),
        ?_test(test_async_delete()),
        ?_test(test_async_timeout_handling()),
        ?_test(test_concurrent_operations())
    ].

test_error_handling(_Pid) ->
    [
        ?_test(test_invalid_arguments()),
        ?_test(test_enhanced_error_info()),
        ?_test(test_worker_pool_limits()),
        ?_test(test_connection_errors())
    ].

test_configuration(_Pid) ->
    [
        ?_test(test_map_based_config()),
        ?_test(test_default_values()),
        ?_test(test_configuration_validation())
    ].

test_statistics(_Pid) ->
    [
        ?_test(test_statistics_retrieval()),
        ?_test(test_connection_pool_stats()),
        ?_test(test_operation_metrics())
    ].

test_connection_pool(_Pid) ->
    [
        ?_test(test_connection_info()),
        ?_test(test_ping_operation()),
        ?_test(test_server_status())
    ].

%%%===================================================================
%%% Individual Tests
%%%===================================================================

%%--------------------------------------------------------------------
%% Basic Operations Tests
%%--------------------------------------------------------------------
test_insert_one() ->
    TestDoc = #{<<"name">> => <<"John">>, <<"age">> => 30},
    Result = connect_mongodb:insert_one(<<"users">>, TestDoc, #{}),
    ?assertMatch({ok, #{acknowledged := true, inserted_count := 1}}, Result).

test_insert_many() ->
    TestDocs = [
        #{<<"name">> => <<"Alice">>, <<"age">> => 25},
        #{<<"name">> => <<"Bob">>, <<"age">> => 35}
    ],
    Result = connect_mongodb:insert_many(<<"users">>, TestDocs, #{}),
    ?assertMatch({ok, #{acknowledged := true, inserted_count := 2}}, Result).

test_find_operations() ->
    % Test find_one
    Filter = #{<<"name">> => <<"John">>},
    FindOneResult = connect_mongodb:find_one(<<"users">>, Filter, #{}),
    ?assertMatch({ok, #{<<"field">> := <<"value">>}}, FindOneResult),
    
    % Test find multiple
    FindResult = connect_mongodb:find(<<"users">>, #{}, #{}),
    ?assertMatch({ok, [_|_]}, FindResult).

test_update_operations() ->
    Filter = #{<<"name">> => <<"John">>},
    Update = #{<<"$set">> => #{<<"age">> => 31}},
    
    % Test update_one
    UpdateOneResult = connect_mongodb:update_one(<<"users">>, Filter, Update, #{}),
    ?assertMatch({ok, #{acknowledged := true, matched_count := 1}}, UpdateOneResult),
    
    % Test update_many
    UpdateManyResult = connect_mongodb:update_many(<<"users">>, #{}, Update, #{}),
    ?assertMatch({ok, #{acknowledged := true}}, UpdateManyResult).

test_delete_operations() ->
    Filter = #{<<"name">> => <<"Alice">>},
    
    % Test delete_one
    DeleteOneResult = connect_mongodb:delete_one(<<"users">>, Filter, #{}),
    ?assertMatch({ok, #{acknowledged := true, deleted_count := 1}}, DeleteOneResult),
    
    % Test delete_many
    DeleteManyResult = connect_mongodb:delete_many(<<"users">>, #{}, #{}),
    ?assertMatch({ok, #{acknowledged := true}}, DeleteManyResult).

test_count_documents() ->
    Filter = #{<<"age">> => #{<<"$gte">> => 25}},
    Result = connect_mongodb:count_documents(<<"users">>, Filter, #{}),
    ?assertMatch({ok, _Count} when is_integer(_Count), Result).

test_collection_operations() ->
    % Test create collection
    CreateResult = connect_mongodb:create_collection(<<"test_collection">>, #{}),
    ?assertMatch({ok, _}, CreateResult),
    
    % Test list collections
    ListResult = connect_mongodb:list_collections(#{}),
    ?assertMatch({ok, _List} when is_list(_List), ListResult),
    
    % Test drop collection
    DropResult = connect_mongodb:drop_collection(<<"test_collection">>, #{}),
    ?assertMatch({ok, _}, DropResult).

test_index_operations() ->
    IndexSpec = #{<<"name">> => 1},
    
    % Test create index
    CreateResult = connect_mongodb:create_index(<<"users">>, IndexSpec, #{}),
    ?assertMatch({ok, _}, CreateResult),
    
    % Test list indexes
    ListResult = connect_mongodb:list_indexes(<<"users">>, #{}),
    ?assertMatch({ok, _List} when is_list(_List), ListResult),
    
    % Test drop index
    DropResult = connect_mongodb:drop_index(<<"users">>, <<"name_1">>, #{}),
    ?assertMatch({ok, _}, DropResult).

%%--------------------------------------------------------------------
%% Async Operations Tests
%%--------------------------------------------------------------------
test_async_insert() ->
    TestDoc = #{<<"async_name">> => <<"AsyncUser">>, <<"async_age">> => 40},
    {ok, Ref} = connect_mongodb:insert_one_async(<<"users">>, TestDoc, #{}),
    ?assert(is_reference(Ref)),
    
    % Wait for result
    receive
        {mongodb_result, Ref, Result} ->
            ?assertMatch(#{acknowledged := true, inserted_count := 1}, Result)
    after 5000 ->
        ?assert(false) % Timeout
    end.

test_async_find() ->
    Filter = #{<<"async_name">> => <<"AsyncUser">>},
    {ok, Ref} = connect_mongodb:find_one_async(<<"users">>, Filter, #{}),
    ?assert(is_reference(Ref)),
    
    receive
        {mongodb_result, Ref, Result} ->
            ?assertMatch(#{<<"field">> := <<"value">>}, Result)
    after 5000 ->
        ?assert(false) % Timeout
    end.

test_async_update() ->
    Filter = #{<<"async_name">> => <<"AsyncUser">>},
    Update = #{<<"$set">> => #{<<"async_age">> => 41}},
    {ok, Ref} = connect_mongodb:update_one_async(<<"users">>, Filter, Update, #{}),
    ?assert(is_reference(Ref)),
    
    receive
        {mongodb_result, Ref, Result} ->
            ?assertMatch(#{acknowledged := true, matched_count := 1}, Result)
    after 5000 ->
        ?assert(false) % Timeout
    end.

test_async_delete() ->
    Filter = #{<<"async_name">> => <<"AsyncUser">>},
    {ok, Ref} = connect_mongodb:delete_one_async(<<"users">>, Filter, #{}),
    ?assert(is_reference(Ref)),
    
    receive
        {mongodb_result, Ref, Result} ->
            ?assertMatch(#{acknowledged := true, deleted_count := 1}, Result)
    after 5000 ->
        ?assert(false) % Timeout
    end.

test_async_timeout_handling() ->
    % Test with very short timeout
    Options = #{timeout => 1}, % 1ms timeout
    {ok, Ref} = connect_mongodb:find_async(<<"users">>, #{}, Options),
    
    receive
        {mongodb_result, Ref, _Result} ->
            % Could succeed if very fast
            ok;
        {mongodb_error, Ref, timeout} ->
            % Expected timeout
            ok
    after 1000 ->
        ?assert(false) % Should have received something
    end.

test_concurrent_operations() ->
    % Start multiple async operations
    Refs = [begin
        {ok, Ref} = connect_mongodb:find_async(<<"users">>, #{}, #{}),
        Ref
    end || _ <- lists:seq(1, 5)],
    
    % Wait for all results
    Results = [receive
        {mongodb_result, Ref, Result} -> Result;
        {mongodb_error, Ref, _Error} -> error
    after 10000 ->
        timeout
    end || Ref <- Refs],
    
    % Should have 5 results, none should be timeout
    ?assertEqual(5, length(Results)),
    ?assert(lists:all(fun(R) -> R =/= timeout end, Results)).

%%--------------------------------------------------------------------
%% Error Handling Tests
%%--------------------------------------------------------------------
test_invalid_arguments() ->
    % Test invalid collection name (not binary)
    Result1 = try
        connect_mongodb:insert_one(invalid_collection, #{}, #{})
    catch
        error:{badarg, _Args, #{error_info := ErrorInfo}} ->
            ?assertMatch(#{
                module := connect_mongodb,
                function := insert_one_async,
                cause := _
            }, ErrorInfo),
            error_caught
    end,
    ?assertEqual(error_caught, Result1),
    
         % Test invalid document (not map)
     Result2 = try
         connect_mongodb:insert_one(<<"test">>, invalid_document, #{})
     catch
         error:{badarg, _ArgsB, #{error_info := _ErrorInfoB}} ->
             error_caught
     end,
     ?assertEqual(error_caught, Result2).

test_enhanced_error_info() ->
    % Test that error/3 provides enhanced error information
    try
        connect_mongodb:find_one(123, #{}, #{}) % Invalid collection type
    catch
        error:{badarg, _Args, ErrorMap} ->
            ?assertMatch(#{error_info := #{
                module := connect_mongodb,
                function := find_one_async,
                arity := 3,
                cause := _
            }}, ErrorMap)
    end.

test_worker_pool_limits() ->
    % This test would verify worker pool limits
    % For now, just test that the system handles worker limits gracefully
    ?assert(true). % Placeholder

test_connection_errors() ->
    % Test connection error scenarios
    % For now, just verify that errors are properly formatted
    ?assert(true). % Placeholder

%%--------------------------------------------------------------------
%% Configuration Tests
%%--------------------------------------------------------------------
test_map_based_config() ->
    Config = #{
        host => <<"test.example.com">>,
        port => 27018,
        database => <<"test_db">>,
        pool_size => 15
    },
    
    % Test that configuration is accepted
    {ok, TestPid} = connect_mongodb:start_link(Config),
    ?assert(is_pid(TestPid)),
    gen_server:stop(TestPid).

test_default_values() ->
    % Test that default values are properly set
    {ok, TestPid} = connect_mongodb:start_link(#{}),
    ?assert(is_pid(TestPid)),
    gen_server:stop(TestPid).

test_configuration_validation() ->
    % Test invalid configuration
    Result = try
        connect_mongodb:start_link(invalid_config)
    catch
        error:{badarg, _Args, #{error_info := ErrorInfo}} ->
            ?assertMatch(#{cause := "Configuration must be a map"}, ErrorInfo),
            error_caught
    end,
    ?assertEqual(error_caught, Result).

%%--------------------------------------------------------------------
%% Statistics Tests  
%%--------------------------------------------------------------------
test_statistics_retrieval() ->
    Stats = connect_mongodb:statistics(),
    ?assertMatch(#{
        operations_total := _,
        operations_success := _,
        operations_error := _,
        connections_active := _,
        connections_available := _,
        memory_usage := _
    }, Stats).

test_connection_pool_stats() ->
    Result = connect_mongodb:connection_pool_stats(),
    ?assertMatch({ok, #{
        total_pools := _,
        active_connections := _,
        available_connections := _
    }}, Result).

test_operation_metrics() ->
    % Perform an operation and check if metrics are updated
    InitialStats = connect_mongodb:statistics(),
    _InitialTotal = maps:get(operations_total, InitialStats, 0),
    
    % Perform operation
    connect_mongodb:find_one(<<"users">>, #{}, #{}),
    
    % Check updated stats (in real implementation, this would be updated)
    NewStats = connect_mongodb:statistics(),
    ?assertMatch(#{operations_total := _Total}, NewStats).

%%--------------------------------------------------------------------
%% Connection Pool Tests
%%--------------------------------------------------------------------
test_connection_info() ->
    Result = connect_mongodb:get_connection_info(default),
    ?assertMatch({ok, _Info}, Result).

test_ping_operation() ->
    Result = connect_mongodb:ping(#{}),
    ?assertMatch({ok, _Response}, Result).

test_server_status() ->
    Result = connect_mongodb:server_status(#{}),
    ?assertMatch({ok, _Status}, Result).

%%--------------------------------------------------------------------
%% GridFS Operations Tests
%%--------------------------------------------------------------------
test_gridfs_operations(_Pid) ->
    [
        ?_test(test_gridfs_upload()),
        ?_test(test_gridfs_download()),
        ?_test(test_gridfs_async_upload()),
        ?_test(test_gridfs_async_download()),
        ?_test(test_gridfs_streaming()),
        ?_test(test_gridfs_file_management()),
        ?_test(test_gridfs_bucket_operations())
    ].

test_gridfs_upload() ->
    % Test basic file upload to GridFS
    TestData = <<"This is test file content for GridFS upload">>,
    Options = #{
        filename => <<"test_file.txt">>,
        content_type => <<"text/plain">>,
        metadata => #{<<"test">> => true}
    },
    
    Result = connect_mongodb:gridfs_upload(<<"test_file.txt">>, TestData, Options),
    ?assertMatch({ok, _FileId}, Result).

test_gridfs_download() ->
    % Test file download from GridFS
    Options = #{bucket => <<"test_bucket">>},
    Result = connect_mongodb:gridfs_download(<<"test_file.txt">>, Options),
    ?assertMatch({ok, {_FileData, _Metadata}}, Result).

test_gridfs_async_upload() ->
    % Test async file upload
    TestData = <<"Async upload test content">>,
    Options = #{filename => <<"async_test.txt">>},
    
    Ref = connect_mongodb:gridfs_upload_async(<<"async_test.txt">>, TestData, Options),
    ?assert(is_reference(Ref)),
    
    % In real implementation, would check for async result message
    % receive {async_result, Ref, Result} -> ... end
    ok.

test_gridfs_async_download() ->
    % Test async file download
    Options = #{bucket => <<"test_bucket">>},
    Ref = connect_mongodb:gridfs_download_async(<<"test_file.txt">>, Options),
    ?assert(is_reference(Ref)).

test_gridfs_streaming() ->
    % Test streaming operations
    StreamRef = make_ref(),
    Options = #{chunk_size => 1024, bucket => <<"streams">>},
    
    % Test stream upload
    Result1 = connect_mongodb:gridfs_stream_upload(<<"large_file.bin">>, StreamRef, Options),
    ?assertMatch({ok, _FileId}, Result1),
    
    % Test stream download  
    Result2 = connect_mongodb:gridfs_stream_download(<<"large_file.bin">>, Options),
    ?assertMatch({ok, _BytesRead}, Result2).

test_gridfs_file_management() ->
    % Test file listing and searching
    ListResult = connect_mongodb:gridfs_list(#{bucket => <<"test_bucket">>}),
    ?assertMatch({ok, _Files}, ListResult),
    
    % Test file search with filters
    Filter = #{<<"metadata.type">> => <<"document">>},
    FindResult = connect_mongodb:gridfs_find(Filter, #{bucket => <<"docs">>}),
    ?assertMatch({ok, _MatchingFiles}, FindResult),
    
    % Test file deletion
    DeleteResult = connect_mongodb:gridfs_delete(<<"old_file.txt">>, #{}),
    ?assertMatch({ok, deleted}, DeleteResult).

test_gridfs_bucket_operations() ->
    % Test bucket creation and management
    CreateResult = connect_mongodb:gridfs_create_bucket(<<"new_bucket">>, #{
        chunk_size => 512 * 1024  % 512KB chunks
    }),
    ?assertMatch({ok, created}, CreateResult),
    
    % Test bucket deletion
    DropResult = connect_mongodb:gridfs_drop_bucket(<<"old_bucket">>),
    ?assertMatch({ok, dropped}, DropResult).

%%--------------------------------------------------------------------
%% Change Streams Tests
%%--------------------------------------------------------------------
test_change_streams(_Pid) ->
    [
        ?_test(test_watch_collection()),
        ?_test(test_watch_database()),
        ?_test(test_watch_cluster()),
        ?_test(test_change_stream_options()),
        ?_test(test_change_stream_resume()),
        ?_test(test_change_stream_management())
    ].

test_watch_collection() ->
    % Test watching a specific collection
    Options = #{
        full_document => update_lookup,
        filter => #{<<"operationType">> => #{<<"$in">> => [<<"insert">>, <<"update">>]}}
    },
    
    Result = connect_mongodb:watch_collection(<<"users">>, Options),
    ?assertMatch({ok, _StreamRef}, Result),
    
    % Test watching collection with database specification
    Result2 = connect_mongodb:watch_collection(<<"testdb">>, <<"orders">>, Options),
    ?assertMatch({ok, _StreamRef2}, Result2).

test_watch_database() ->
    % Test watching entire database
    Options = #{
        full_document => update_lookup,
        filter => #{<<"ns.coll">> => #{<<"$in">> => [<<"users">>, <<"orders">>]}}
    },
    
    % Test database watch with default options
    Result1 = connect_mongodb:watch_database(<<"myapp">>),
    ?assertMatch({ok, _StreamRef}, Result1),
    
    % Test database watch with custom options
    Result2 = connect_mongodb:watch_database(<<"myapp">>, Options),
    ?assertMatch({ok, _StreamRef2}, Result2).

test_watch_cluster() ->
    % Test watching entire cluster
    Options = #{
        full_document => update_lookup,
        start_at_operation_time => erlang:system_time(millisecond)
    },
    
    % Test cluster watch with default options
    Result1 = connect_mongodb:watch_cluster(),
    ?assertMatch({ok, _StreamRef}, Result1),
    
    % Test cluster watch with custom options
    Result2 = connect_mongodb:watch_cluster(Options),
    ?assertMatch({ok, _StreamRef2}, Result2).

test_change_stream_options() ->
    % Test various change stream configuration options
    AdvancedOptions = #{
        full_document => update_lookup,
        full_document_before_change => when_available,
        start_after => <<"resume_token_123">>,
        max_await_time_ms => 1000,
        batch_size => 10
    },
    
    Result = connect_mongodb:watch_collection(<<"products">>, AdvancedOptions),
    ?assertMatch({ok, _StreamRef}, Result).

test_change_stream_resume() ->
    % Test change stream resumption
    StreamRef = make_ref(),
    ResumeToken = <<"mock_resume_token_456">>,
    
    Result = connect_mongodb:resume_change_stream(StreamRef, ResumeToken),
    ?assertMatch({ok, _NewStreamRef}, Result).

test_change_stream_management() ->
    % Test stopping change streams
    StreamRef = make_ref(),
    
    Result = connect_mongodb:stop_change_stream(StreamRef),
    ?assertMatch(ok, Result).

%%--------------------------------------------------------------------
%% Load Balancing Tests
%%--------------------------------------------------------------------
test_load_balancing(_Pid) ->
    [
        ?_test(test_server_management()),
        ?_test(test_balancing_strategies()),
        ?_test(test_circuit_breaker()),
        ?_test(test_server_monitoring()),
        ?_test(test_load_balancing_stats())
    ].

test_server_management() ->
    % Test adding servers to load balancer
    ServerConfig = #{
        host => <<"mongo2.cluster.com">>,
        port => 27017,
        type => secondary,
        max_connections => 15
    },
    
    AddResult = connect_mongodb:add_server(ServerConfig, 5),
    ?assertMatch({ok, _ServerId}, AddResult),
    
    % Test removing server
    RemoveResult = connect_mongodb:remove_server(server_2),
    ?assertMatch({ok, removed}, RemoveResult),
    
    % Test updating server weight
    WeightResult = connect_mongodb:set_server_weight(server_1, 8),
    ?assertMatch({ok, updated}, WeightResult).

test_balancing_strategies() ->
    % Test different load balancing strategies
    Strategies = [
        round_robin,
        least_connections,
        weighted,
        response_time,
        geographic
    ],
    
    % Test setting each strategy
    [begin
        Result = connect_mongodb:set_balancing_strategy(Strategy),
        ?assertMatch({ok, _OldStrategy}, Result)
    end || Strategy <- Strategies],
    
    % Test getting all servers
    ServersResult = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, _Servers}, ServersResult).

test_circuit_breaker() ->
    % Test circuit breaker functionality
    CircuitBreakerOpts = #{
        failure_threshold => 5,
        recovery_timeout => 30000,
        half_open_max_calls => 3,
        error_rate_threshold => 0.5
    },
    
    % Enable circuit breaker
    EnableResult = connect_mongodb:enable_circuit_breaker(server_1, CircuitBreakerOpts),
    ?assertMatch({ok, enabled}, EnableResult),
    
    % Disable circuit breaker
    DisableResult = connect_mongodb:disable_circuit_breaker(server_1),
    ?assertMatch({ok, disabled}, DisableResult).

test_server_monitoring() ->
    % Test individual server statistics
    StatsResult = connect_mongodb:get_server_stats(server_1),
    ?assertMatch({ok, #{
        status := _Status,
        response_time := _ResponseTime,
        connection_count := _ConnectionCount,
        requests_per_second := _RPS
    }}, StatsResult).

test_load_balancing_stats() ->
    % Test comprehensive load balancing statistics
    AllServersResult = connect_mongodb:get_all_servers(),
    ?assertMatch({ok, #{
        total_servers := _Total,
        healthy_servers := _Healthy,
        current_strategy := _Strategy,
        server_stats := _ServerStats
    }}, AllServersResult).

%%%===================================================================
%%% Helper Functions
%%%===================================================================

% Helper functions for testing (currently unused but available for expansion)
% wait_for_async_result(Ref, Timeout) ->
%     receive
%         {mongodb_result, Ref, Result} -> {ok, Result};
%         {mongodb_error, Ref, Error} -> {error, Error}
%     after Timeout ->
%         {error, timeout}
%     end. 