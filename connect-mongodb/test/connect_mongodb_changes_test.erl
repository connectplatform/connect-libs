%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB Change Streams - Comprehensive Test Suite
%%%
%%% Dedicated test suite for Change Streams real-time processing:
%%% - Collection-level change watching
%%% - Database-level change monitoring  
%%% - Cluster-level change tracking
%%% - Resume tokens and stream recovery
%%% - Event filtering and processing
%%% - Stream lifecycle management
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_changes_test).

-include_lib("eunit/include/eunit.hrl").

%%%===================================================================
%%% Test Setup and Teardown
%%%===================================================================

setup() ->
    application:ensure_all_started(connect_mongodb),
    TestConfig = #{
        host => <<"localhost">>,
        port => 27017,
        database => <<"changes_test">>,
        pool_size => 3
    },
    case connect_mongodb:start_link(TestConfig) of
        {ok, Pid} -> Pid;
        {error, {already_started, Pid}} -> Pid
    end.

teardown(_Pid) ->
    % Stop any active change streams
    connect_mongodb:stop_change_stream(test_stream_1),
    connect_mongodb:stop_change_stream(test_stream_2),
    connect_mongodb:stop().

%%%===================================================================
%%% Test Generators
%%%===================================================================

changes_test_() ->
    {foreach,
     fun setup/0,
     fun teardown/1,
     [
         fun test_collection_watching/1,
         fun test_database_watching/1,
         fun test_cluster_watching/1,
         fun test_stream_options/1,
         fun test_stream_management/1,
         fun test_event_filtering/1,
         fun test_resume_functionality/1
     ]}.

%%%===================================================================
%%% Test Cases
%%%===================================================================

test_collection_watching(_Pid) ->
    [
        ?_test(test_watch_single_collection()),
        ?_test(test_watch_collection_with_database()),
        ?_test(test_collection_with_pipeline()),
        ?_test(test_collection_with_filters())
    ].

test_watch_single_collection() ->
    Options = #{
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_collection(<<"users">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_watch_collection_with_database() ->
    Options = #{
        full_document => default,
        max_await_time_ms => 5000
    },
    
    Result = connect_mongodb:watch_collection(<<"testdb">>, <<"orders">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_collection_with_pipeline() ->
    Options = #{
        pipeline => [
            #{<<"$match">> => #{<<"operationType">> => <<"insert">>}}
        ],
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_collection(<<"products">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_collection_with_filters() ->
    Options = #{
        filter => #{
            <<"operationType">> => #{<<"$in">> => [<<"insert">>, <<"update">>, <<"replace">>]},
            <<"fullDocument.status">> => <<"active">>
        }
    },
    
    Result = connect_mongodb:watch_collection(<<"inventory">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_database_watching(_Pid) ->
    [
        ?_test(test_watch_database_simple()),
        ?_test(test_watch_database_with_options()),
        ?_test(test_database_collection_filter())
    ].

test_watch_database_simple() ->
    Result = connect_mongodb:watch_database(<<"myapp">>),
    ?assertMatch({ok, _StreamRef}, Result).

test_watch_database_with_options() ->
    Options = #{
        full_document => update_lookup,
        start_at_operation_time => erlang:system_time(millisecond),
        batch_size => 100
    },
    
    Result = connect_mongodb:watch_database(<<"myapp">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_database_collection_filter() ->
    Options = #{
        filter => #{
            <<"ns.coll">> => #{<<"$in">> => [<<"users">>, <<"orders">>, <<"products">>]}
        },
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_database(<<"ecommerce">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_cluster_watching(_Pid) ->
    [
        ?_test(test_watch_cluster_simple()),
        ?_test(test_watch_cluster_with_options()),
        ?_test(test_cluster_namespace_filter())
    ].

test_watch_cluster_simple() ->
    Result = connect_mongodb:watch_cluster(),
    ?assertMatch({ok, _StreamRef}, Result).

test_watch_cluster_with_options() ->
    Options = #{
        full_document => update_lookup,
        full_document_before_change => when_available,
        start_at_operation_time => erlang:system_time(millisecond),
        max_await_time_ms => 10000
    },
    
    Result = connect_mongodb:watch_cluster(Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_cluster_namespace_filter() ->
    Options = #{
        filter => #{
            <<"ns.db">> => #{<<"$in">> => [<<"app1">>, <<"app2">>, <<"shared">>]}
        }
    },
    
    Result = connect_mongodb:watch_cluster(Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_stream_options(_Pid) ->
    [
        ?_test(test_full_document_options()),
        ?_test(test_timing_options()),
        ?_test(test_batch_options()),
        ?_test(test_resume_options())
    ].

test_full_document_options() ->
    % Test different full document options
    FullDocOptions = [
        default,
        update_lookup,
        when_available,
        required
    ],
    
    Results = [begin
        Options = #{full_document => Option},
        connect_mongodb:watch_collection(<<"test_collection">>, Options)
    end || Option <- FullDocOptions],
    
    [?assertMatch({ok, _}, Result) || Result <- Results].

test_timing_options() ->
    Options = #{
        max_await_time_ms => 30000,
        start_at_operation_time => erlang:system_time(millisecond) - 60000  % 1 minute ago
    },
    
    Result = connect_mongodb:watch_collection(<<"timed_events">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_batch_options() ->
    Options = #{
        batch_size => 50,
        max_await_time_ms => 5000
    },
    
    Result = connect_mongodb:watch_database(<<"batch_test">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_resume_options() ->
    ResumeToken = <<"test_resume_token_123">>,
    Options = #{
        resume_after => ResumeToken,
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_collection(<<"resumable">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_stream_management(_Pid) ->
    [
        ?_test(test_stream_creation()),
        ?_test(test_stream_stopping()),
        ?_test(test_multiple_streams()),
        ?_test(test_stream_lifecycle())
    ].

test_stream_creation() ->
    % Create multiple different types of streams
    CollectionResult = connect_mongodb:watch_collection(<<"users">>, #{}),
    ?assertMatch({ok, _StreamRef1}, CollectionResult),
    
    DatabaseResult = connect_mongodb:watch_database(<<"myapp">>, #{}),
    ?assertMatch({ok, _StreamRef2}, DatabaseResult),
    
    ClusterResult = connect_mongodb:watch_cluster(#{}),
    ?assertMatch({ok, _StreamRef3}, ClusterResult).

test_stream_stopping() ->
    % Create a stream and then stop it
    {ok, StreamRef} = connect_mongodb:watch_collection(<<"temp_collection">>, #{}),
    
    StopResult = connect_mongodb:stop_change_stream(StreamRef),
    ?assertMatch(ok, StopResult).

test_multiple_streams() ->
    % Create multiple concurrent streams
    Collections = [<<"users">>, <<"orders">>, <<"products">>, <<"inventory">>],
    
    StreamRefs = [begin
        {ok, StreamRef} = connect_mongodb:watch_collection(Collection, #{}),
        StreamRef
    end || Collection <- Collections],
    
    % Verify all streams were created
    ?assertEqual(4, length(StreamRefs)),
    [?assert(is_reference(Ref)) || Ref <- StreamRefs],
    
    % Stop all streams
    [connect_mongodb:stop_change_stream(Ref) || Ref <- StreamRefs].

test_stream_lifecycle() ->
    Options = #{full_document => update_lookup},
    
    % Create stream
    {ok, StreamRef} = connect_mongodb:watch_collection(<<"lifecycle_test">>, Options),
    
    % In a real implementation, we would:
    % 1. Verify stream is active
    % 2. Receive some events
    % 3. Pause/resume if supported
    % 4. Finally stop
    
    StopResult = connect_mongodb:stop_change_stream(StreamRef),
    ?assertMatch(ok, StopResult).

test_event_filtering(_Pid) ->
    [
        ?_test(test_operation_type_filter()),
        ?_test(test_document_filter()),
        ?_test(test_namespace_filter()),
        ?_test(test_complex_filters())
    ].

test_operation_type_filter() ->
    % Filter for specific operation types
    Options = #{
        filter => #{
            <<"operationType">> => #{<<"$in">> => [<<"insert">>, <<"update">>]}
        }
    },
    
    Result = connect_mongodb:watch_collection(<<"filtered_ops">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_document_filter() ->
    % Filter based on document content
    Options = #{
        filter => #{
            <<"fullDocument.status">> => <<"published">>,
            <<"fullDocument.category">> => #{<<"$in">> => [<<"tech">>, <<"science">>]}
        }
    },
    
    Result = connect_mongodb:watch_collection(<<"articles">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_namespace_filter() ->
    % Filter by namespace (database/collection)
    Options = #{
        filter => #{
            <<"ns.db">> => <<"production">>,
            <<"ns.coll">> => #{<<"$regex">> => <<"^user_">>}
        }
    },
    
    Result = connect_mongodb:watch_cluster(Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_complex_filters() ->
    % Complex MongoDB query filters
    Options = #{
        filter => #{
            <<"$and">> => [
                #{<<"operationType">> => #{<<"$ne">> => <<"delete">>}},
                #{<<"$or">> => [
                    #{<<"fullDocument.priority">> => <<"high">>},
                    #{<<"fullDocument.urgent">> => true}
                ]}
            ]
        }
    },
    
    Result = connect_mongodb:watch_database(<<"priority_db">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_resume_functionality(_Pid) ->
    [
        ?_test(test_resume_after_token()),
        ?_test(test_start_after_token()),
        ?_test(test_resume_stream_management())
    ].

test_resume_after_token() ->
    ResumeToken = <<"mock_resume_token_456">>,
    Options = #{
        resume_after => ResumeToken,
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_collection(<<"resumable_collection">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_start_after_token() ->
    StartToken = <<"mock_start_token_789">>,
    Options = #{
        start_after => StartToken,
        full_document => update_lookup
    },
    
    Result = connect_mongodb:watch_database(<<"start_after_test">>, Options),
    ?assertMatch({ok, _StreamRef}, Result).

test_resume_stream_management() ->
    % Test the resume stream management functionality
    StreamRef = make_ref(),
    ResumeToken = <<"management_resume_token">>,
    
    Result = connect_mongodb:resume_change_stream(StreamRef, ResumeToken),
    ?assertMatch({ok, _NewStreamRef}, Result).

%%%===================================================================
%%% Helper Functions  
%%%===================================================================

% Helper function to simulate receiving change events
% In a real implementation, this would be used to test event processing
% simulate_change_event(OperationType, Collection) ->
%     #{
%         '_id' => #{
%             <<"_data">> => <<"mock_change_id">>
%         },
%         operation_type => OperationType,
%         cluster_time => erlang:system_time(millisecond),
%         full_document => #{
%             <<"_id">> => <<"test_doc_id">>,
%             <<"field">> => <<"test_value">>
%         },
%         ns => #{
%             db => <<"test_db">>,
%             coll => Collection
%         },
%         document_key => #{
%             <<"_id">> => <<"test_doc_id">>
%         }
%     }. 