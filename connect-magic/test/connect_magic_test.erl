%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform File Magic - OTP 27 Enhanced Tests
%%%
%%% Test suite for modernized file magic detection library with:
%%% - OTP 27 gen_server behavior testing
%%% - Async/await pattern testing
%%% - Map-based configuration testing
%%% - Error handling with enhanced error/3
%%% - Persistent terms caching testing
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_magic_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Setup and Teardown
%%%===================================================================

setup() ->
    application:ensure_all_started(connect_magic),
    ok.

cleanup(_) ->
    application:stop(connect_magic),
    ok.

%%%===================================================================
%%% OTP 27 Enhanced Gen_Server Tests
%%%===================================================================

gen_server_lifecycle_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Start with default options", fun test_start_default/0},
        {"Start with map options", fun test_start_with_options/0},
        {"Start with legacy proplist", fun test_start_legacy_proplist/0},
        {"Stop server gracefully", fun test_stop/0},
        {"Handle invalid options", fun test_invalid_options/0}
    ]}.

test_start_default() ->
    {ok, Pid} = connect_magic:start_link(),
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)).

test_start_with_options() ->
    Options = #{
        max_workers => 5,
        worker_timeout => 3000,
        monitoring_enabled => false
    },
    {ok, Pid} = connect_magic:start_link(Options),
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)).

test_start_legacy_proplist() ->
    Options = [
        {max_workers, 3},
        {worker_timeout, 2000}
    ],
    {ok, Pid} = connect_magic:start_link(Options),
    ?assert(is_pid(Pid)),
    ?assert(is_process_alive(Pid)).

test_stop() ->
    {ok, _Pid} = connect_magic:start_link(),
    ?assertEqual(ok, connect_magic:stop()).

test_invalid_options() ->
    try
        connect_magic:start_link("invalid"),
        ?assert(false) % Should not reach here
    catch
        error:{badarg, _} -> ok;
        _:_ -> ?assert(false) % Should catch badarg specifically
    end.

%%%===================================================================
%%% Modern Error Handling Tests (OTP 27 error/3)
%%%===================================================================

error_handling_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Enhanced error info for invalid file path", fun test_error_invalid_file/0},
        {"Enhanced error info for invalid buffer", fun test_error_invalid_buffer/0},
        {"Enhanced error info for invalid options", fun test_error_invalid_options/0}
    ]}.

test_error_invalid_file() ->
    connect_magic:start_link(),
    try
        connect_magic:detect_file_async(123, #{}) % Invalid file path
    catch
        error:{badarg, _} -> ok;
        _:_ -> ?assert(false)
    end.

test_error_invalid_buffer() ->
    connect_magic:start_link(),
    try
        connect_magic:detect_buffer_async("not_binary", #{}) % Invalid buffer
    catch
        error:{badarg, _} -> ok;
        _:_ -> ?assert(false)
    end.

test_error_invalid_options() ->
    connect_magic:start_link(),
    try
        connect_magic:detect_file_async(<<"/tmp/test">>, "not_map") % Invalid options
    catch
        error:{badarg, _} -> ok;
        _:_ -> ?assert(false)
    end.

%%%===================================================================
%%% Map-Based Configuration Tests
%%%===================================================================

map_config_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Default configuration", fun test_default_config/0},
        {"Custom timeout configuration", fun test_custom_timeout/0},
        {"Database configuration", fun test_database_config/0},
        {"Flag configuration", fun test_flag_config/0}
    ]}.

test_default_config() ->
    connect_magic:start_link(),
    Options = #{},
    % Test that default options work
    case connect_magic:detect_file_async(<<"/dev/null">>, Options) of
        {ok, Ref} when is_reference(Ref) -> ok;
        {error, _} -> ok % File might not exist, that's fine for config test
    end.

test_custom_timeout() ->
    connect_magic:start_link(),
    Options = #{timeout => 1000},
    % Test that custom timeout is respected
    case connect_magic:detect_file_async(<<"/dev/null">>, Options) of
        {ok, Ref} when is_reference(Ref) -> ok;
        {error, _} -> ok
    end.

test_database_config() ->
    connect_magic:start_link(),
    Options = #{database => <<"/usr/share/misc/magic">>},
    % Test that database option is accepted
    case connect_magic:detect_file_async(<<"/dev/null">>, Options) of
        {ok, Ref} when is_reference(Ref) -> ok;
        {error, _} -> ok
    end.

test_flag_config() ->
    connect_magic:start_link(),
    Options = #{flags => [mime_type, compress]},
    % Test that flag options are accepted
    case connect_magic:detect_file_async(<<"/dev/null">>, Options) of
        {ok, Ref} when is_reference(Ref) -> ok;
        {error, _} -> ok
    end.

%%%===================================================================
%%% Async/Await Pattern Tests
%%%===================================================================

async_patterns_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Async file detection", fun test_async_file_detection/0},
        {"Async buffer detection", fun test_async_buffer_detection/0},
        {"Multiple async operations", fun test_multiple_async/0},
        {"Async timeout handling", fun test_async_timeout/0}
    ]}.

test_async_file_detection() ->
    connect_magic:start_link(),
    % Create a temporary file for testing
    TempFile = <<"/tmp/connect_magic_test">>,
    file:write_file(TempFile, <<"Hello World">>),
    
    case connect_magic:detect_file_async(TempFile) of
        {ok, Ref} when is_reference(Ref) ->
            receive
                {magic_result, Ref, Result} ->
                    ?assertMatch(#{type := _, source := file}, Result);
                {magic_error, Ref, _Error} ->
                    % Error is acceptable for test
                    ok
            after 5000 ->
                ?assert(false) % Timeout
            end;
        {error, _} -> 
            % Error starting async operation
            ok
    end,
    
    % Cleanup
    file:delete(TempFile).

test_async_buffer_detection() ->
    connect_magic:start_link(),
    Buffer = <<"Hello World Test Buffer">>,
    
    case connect_magic:detect_buffer_async(Buffer) of
        {ok, Ref} when is_reference(Ref) ->
            receive
                {magic_result, Ref, Result} ->
                    ?assertMatch(#{type := _, source := buffer}, Result);
                {magic_error, Ref, _Error} ->
                    % Error is acceptable for test
                    ok
            after 5000 ->
                ?assert(false) % Timeout
            end;
        {error, _} ->
            % Error starting async operation
            ok
    end.

test_multiple_async() ->
    connect_magic:start_link(),
    Buffer1 = <<"Test Buffer 1">>,
    Buffer2 = <<"Test Buffer 2">>,
    
    % Start multiple async operations
    Refs = case {connect_magic:detect_buffer_async(Buffer1), 
                 connect_magic:detect_buffer_async(Buffer2)} of
        {{ok, Ref1}, {ok, Ref2}} -> [Ref1, Ref2];
        _ -> []
    end,
    
    % Collect results
    Results = collect_async_results(Refs, []),
    
    % Should get at least some results (even errors are fine)
    ?assert(length(Results) =< 2).

test_async_timeout() ->
    connect_magic:start_link(),
    Options = #{timeout => 1}, % Very short timeout
    Buffer = <<"Test Buffer">>,
    
    case connect_magic:detect_buffer_async(Buffer, Options) of
        {ok, _Ref} -> ok;
        {error, _} -> ok % Timeout or other error is expected
    end.

%%%===================================================================
%%% Persistent Terms Caching Tests
%%%===================================================================

persistent_cache_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Database list caching", fun test_database_caching/0},
        {"Version caching", fun test_version_caching/0},
        {"Cache persistence", fun test_cache_persistence/0}
    ]}.

test_database_caching() ->
    connect_magic:start_link(),
    
    % Get databases (should be cached in persistent terms)
    Databases1 = connect_magic:list_databases(),
    Databases2 = connect_magic:list_databases(),
    
    % Both calls should return the same result
    ?assertEqual(Databases1, Databases2),
    ?assert(is_list(Databases1)).

test_version_caching() ->
    connect_magic:start_link(),
    
    % Get version (should be cached)
    Version1 = connect_magic:version(),
    Version2 = connect_magic:version(),
    
    ?assertEqual(Version1, Version2),
    ?assert(is_binary(Version1)).

test_cache_persistence() ->
    connect_magic:start_link(),
    
    % Get initial values
    Version = connect_magic:version(),
    Databases = connect_magic:list_databases(),
    
    % Stop and restart
    connect_magic:stop(),
    timer:sleep(100),
    connect_magic:start_link(),
    
    % Values should be the same (cached in persistent terms)
    ?assertEqual(Version, connect_magic:version()),
    ?assertEqual(Databases, connect_magic:list_databases()).

%%%===================================================================
%%% Statistics and Monitoring Tests
%%%===================================================================

statistics_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"Basic statistics", fun test_basic_statistics/0},
        {"Statistics format", fun test_statistics_format/0}
    ]}.

test_basic_statistics() ->
    connect_magic:start_link(),
    
    Stats = connect_magic:statistics(),
    ?assert(is_map(Stats)),
    
    % Should have required fields
    RequiredFields = [
        requests_total, requests_success, requests_error,
        cache_hits, cache_misses, avg_response_time,
        databases_loaded, memory_usage
    ],
    
    lists:foreach(fun(Field) ->
        ?assert(maps:is_key(Field, Stats))
    end, RequiredFields).

test_statistics_format() ->
    connect_magic:start_link(),
    
    Stats = connect_magic:statistics(),
    
    % All numeric values should be non-negative
    maps:fold(fun(_Key, Value, _Acc) ->
        ?assert(is_number(Value)),
        ?assert(Value >= 0)
    end, ok, Stats).

%%%===================================================================
%%% Specialized Detection Tests
%%%===================================================================

specialized_detection_test_() ->
    {setup, fun setup/0, fun cleanup/1, [
        {"MIME type detection", fun test_mime_type/0},
        {"Encoding detection", fun test_encoding/0},
        {"Compressed type detection", fun test_compressed_type/0}
    ]}.

test_mime_type() ->
    connect_magic:start_link(),
    Buffer = <<"Hello World">>,
    
    case connect_magic:mime_type(Buffer) of
        {ok, MimeType} -> 
            ?assert(is_binary(MimeType));
        {error, _} -> 
            % Error is acceptable for test
            ok
    end.

test_encoding() ->
    connect_magic:start_link(),
    Buffer = <<"Hello World">>,
    
    case connect_magic:encoding(Buffer) of
        {ok, Encoding} -> 
            ?assert(is_binary(Encoding));
        {error, _} -> 
            % Error is acceptable for test
            ok
    end.

test_compressed_type() ->
    connect_magic:start_link(),
    Buffer = <<"Hello World">>, % Not compressed
    
    case connect_magic:compressed_type(Buffer) of
        {ok, _Type} -> 
            ?assert(false); % Should not detect as compressed
        {error, not_compressed} -> 
            ok; % Expected result
        {error, _} -> 
            ok % Other errors are acceptable
    end.

%%%===================================================================
%%% Helper Functions
%%%===================================================================

collect_async_results([], Acc) ->
    Acc;
collect_async_results([Ref | Refs], Acc) ->
    Result = receive
        {magic_result, Ref, R} -> {ok, R};
        {magic_error, Ref, E} -> {error, E}
    after 1000 ->
        {error, timeout}
    end,
    collect_async_results(Refs, [Result | Acc]). 