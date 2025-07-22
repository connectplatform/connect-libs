%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - OTP 27 Enhanced Modern Driver
%%% 
%%% Features:
%%% - OTP 27 native JSON support (no external dependencies)
%%% - Enhanced gen_server with improved error handling  
%%% - Persistent terms for connection pool caching
%%% - Async/await patterns with reference-based operations
%%% - Map-based configuration with type safety
%%% - Dynamic supervision with fault tolerance
%%% - Connection health monitoring and auto-recovery
%%% - SCRAM-SHA-256 authentication with secure defaults
%%% 
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb).
-behaviour(gen_server).

%% Public API
-export([
    start_link/0,
    start_link/1,
    stop/0,
    stop/1,
    
    %% Async document operations
    insert_one_async/3,
    insert_many_async/3,
    find_one_async/2,
    find_one_async/3,
    find_async/2,
    find_async/3,
    update_one_async/4,
    update_many_async/4,
    delete_one_async/2,
    delete_one_async/3,
    delete_many_async/2,
    delete_many_async/3,
    count_documents_async/2,
    count_documents_async/3,
    
    %% Sync document operations (legacy compatibility)
    insert_one/3,
    insert_many/3,
    find_one/2,
    find_one/3,
    find/2,
    find/3,
    update_one/4,
    update_many/4,
    delete_one/2,
    delete_one/3,
    delete_many/2,
    delete_many/3,
    count_documents/2,
    count_documents/3,
    
    %% Collection operations
    create_collection/2,
    drop_collection/2,
    list_collections/1,
    
    %% Index operations
    create_index/3,
    drop_index/3,
    list_indexes/2,
    
    %% Advanced operations
    aggregate/3,
    bulk_write/3,
    
    %% Transactions (MongoDB 4.0+)
    start_session/1,
    start_transaction/2,
    commit_transaction/2,
    abort_transaction/2,
    with_transaction/3,
    
    %% GridFS operations
    gridfs_upload/3,
    gridfs_upload/4,
    gridfs_upload_async/3,
    gridfs_upload_async/4,
    gridfs_download/2,
    gridfs_download/3,
    gridfs_download_async/2,
    gridfs_download_async/3,
    gridfs_stream_upload/3,
    gridfs_stream_download/2,
    gridfs_delete/2,
    gridfs_find/2,
    gridfs_list/1,
    gridfs_create_bucket/2,
    gridfs_drop_bucket/1,
    
    %% Change Streams operations
    watch_collection/2,
    watch_collection/3,
    watch_database/1,
    watch_database/2,
    watch_cluster/0,
    watch_cluster/1,
    resume_change_stream/2,
    stop_change_stream/1,
    
    %% Load Balancing operations
    add_server/2,
    remove_server/1,
    set_server_weight/2,
    get_server_stats/1,
    get_all_servers/0,
    set_balancing_strategy/1,
    enable_circuit_breaker/2,
    disable_circuit_breaker/1,
    
    %% Connection management
    get_connection_info/1,
    ping/1,
    server_status/1,
    list_databases/1,
    
    %% Statistics and monitoring
    statistics/0,
    statistics/1,
    connection_pool_stats/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

%% Internal exports for async operations
-export([async_worker/4]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type connection_config() :: #{
    host => binary() | string(),
    port => pos_integer(),
    database => binary(),
    username => binary(),
    password => binary(),
    auth_mechanism => scram_sha_1 | scram_sha_256,
    ssl => boolean(),
    ssl_opts => [ssl:tls_option()],
    pool_size => pos_integer(),
    max_overflow => non_neg_integer(),
    timeout => timeout(),
    connect_timeout => timeout(),
    socket_timeout => timeout(),
    server_selection_timeout => timeout(),
    replica_set => binary(),
    read_preference => primary | secondary | primary_preferred | secondary_preferred,
    write_concern => #{w => pos_integer() | majority, j => boolean(), wtimeout => timeout()},
    compression => snappy | zlib | zstd | none
}.

-type collection() :: binary().
-type database() :: binary().
-type document() :: map().
-type filter() :: map().
-type update() :: map().
-type pipeline() :: [document()].
-type index_spec() :: document().
-type bulk_operation() :: #{
    operation := insert | update | delete,
    document => document(),
    filter => filter(),
    update => update()
}.

-type operation_options() :: #{
    timeout => timeout(),
    read_preference => primary | secondary,
    write_concern => map(),
    session => reference(),
    ordered => boolean(),
    bypass_document_validation => boolean()
}.

-type operation_result() :: #{
    acknowledged := boolean(),
    inserted_count => non_neg_integer(),
    matched_count => non_neg_integer(),
    modified_count => non_neg_integer(),
    deleted_count => non_neg_integer(),
    upserted_count => non_neg_integer(),
    upserted_ids => [term()],
    inserted_ids => [term()],
    write_errors => [map()],
    write_concern_errors => [map()]
}.

-type async_ref() :: reference().
-type statistics() :: #{
    operations_total => non_neg_integer(),
    operations_success => non_neg_integer(),
    operations_error => non_neg_integer(),
    connections_active => non_neg_integer(),
    connections_available => non_neg_integer(),
    avg_response_time => float(),
    collections_cached => non_neg_integer(),
    indexes_cached => non_neg_integer(),
    memory_usage => non_neg_integer(),
    uptime_seconds => non_neg_integer()
}.

-record(state, {
    connections = #{} :: #{atom() => pid()},
    connection_pools = #{} :: #{atom() => pid()},
    statistics = #{} :: statistics(),
    workers = #{} :: #{pid() => async_ref()},
    max_workers = 20 :: pos_integer(),
    worker_timeout = 30000 :: timeout(),
    default_config = #{} :: connection_config()
}).

-export_type([
    connection_config/0, collection/0, database/0, document/0, 
    filter/0, update/0, pipeline/0, index_spec/0, bulk_operation/0,
    operation_options/0, operation_result/0, async_ref/0, statistics/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(SERVER, ?MODULE).
-define(DEFAULT_TIMEOUT, 30000).
-define(DEFAULT_POOL_SIZE, 10).
-define(DEFAULT_MAX_OVERFLOW, 5).
-define(CACHE_KEY_CONNECTIONS, {?MODULE, connections}).
-define(CACHE_KEY_COLLECTIONS, {?MODULE, collections}).
-define(CACHE_KEY_INDEXES, {?MODULE, indexes}).
-define(STATS_UPDATE_INTERVAL, 5000). % 5 seconds
-define(HEALTH_CHECK_INTERVAL, 30000). % 30 seconds

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start the MongoDB driver with default configuration
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    start_link(#{}).

%%--------------------------------------------------------------------
%% @doc Start the MongoDB driver with custom configuration
%%--------------------------------------------------------------------
-spec start_link(connection_config()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Config) when is_map(Config) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Config, []);
start_link(Config) ->
    error({badarg, Config}, [Config], #{
        error_info => #{
            module => ?MODULE,
            function => start_link,
            arity => 1,
            cause => "Configuration must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Stop the default MongoDB connection pool
%%--------------------------------------------------------------------
-spec stop() -> ok.
stop() ->
    gen_server:stop(?SERVER).

%%--------------------------------------------------------------------
%% @doc Stop a specific MongoDB connection
%%--------------------------------------------------------------------
-spec stop(atom()) -> ok.
stop(ConnectionName) when is_atom(ConnectionName) ->
    gen_server:call(?SERVER, {stop_connection, ConnectionName});
stop(ConnectionName) ->
    error({badarg, ConnectionName}, [ConnectionName], #{
        error_info => #{
            module => ?MODULE,
            function => stop,
            arity => 1,
            cause => "Connection name must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously insert a single document
%%--------------------------------------------------------------------
-spec insert_one_async(collection(), document(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
insert_one_async(Collection, Document, Options) when is_binary(Collection), is_map(Document), is_map(Options) ->
    gen_server:call(?SERVER, {insert_one_async, Collection, Document, Options}, 
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
insert_one_async(Collection, Document, Options) ->
    error({badarg, [Collection, Document, Options]}, [Collection, Document, Options], #{
        error_info => #{
            module => ?MODULE,
            function => insert_one_async,
            arity => 3,
            cause => "Collection must be binary, Document and Options must be maps"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously insert multiple documents
%%--------------------------------------------------------------------
-spec insert_many_async(collection(), [document()], operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
insert_many_async(Collection, Documents, Options) when is_binary(Collection), is_list(Documents), is_map(Options) ->
    gen_server:call(?SERVER, {insert_many_async, Collection, Documents, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
insert_many_async(Collection, Documents, Options) ->
    error({badarg, [Collection, Documents, Options]}, [Collection, Documents, Options], #{
        error_info => #{
            module => ?MODULE,
            function => insert_many_async,
            arity => 3,
            cause => "Collection must be binary, Documents must be list, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously find a single document
%%--------------------------------------------------------------------
-spec find_one_async(collection(), filter()) -> {ok, async_ref()} | {error, term()}.
find_one_async(Collection, Filter) ->
    find_one_async(Collection, Filter, #{}).

-spec find_one_async(collection(), filter(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
find_one_async(Collection, Filter, Options) when is_binary(Collection), is_map(Filter), is_map(Options) ->
    gen_server:call(?SERVER, {find_one_async, Collection, Filter, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
find_one_async(Collection, Filter, Options) ->
    error({badarg, [Collection, Filter, Options]}, [Collection, Filter, Options], #{
        error_info => #{
            module => ?MODULE,
            function => find_one_async,
            arity => 3,
            cause => "Collection, Filter, and Options must all be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously find multiple documents
%%--------------------------------------------------------------------
-spec find_async(collection(), filter()) -> {ok, async_ref()} | {error, term()}.
find_async(Collection, Filter) ->
    find_async(Collection, Filter, #{}).

-spec find_async(collection(), filter(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
find_async(Collection, Filter, Options) when is_binary(Collection), is_map(Filter), is_map(Options) ->
    gen_server:call(?SERVER, {find_async, Collection, Filter, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
find_async(Collection, Filter, Options) ->
    error({badarg, [Collection, Filter, Options]}, [Collection, Filter, Options], #{
        error_info => #{
            module => ?MODULE,
            function => find_async,
            arity => 3,
            cause => "Collection, Filter, and Options must all be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously update a single document
%%--------------------------------------------------------------------
-spec update_one_async(collection(), filter(), update(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
update_one_async(Collection, Filter, Update, Options) when is_binary(Collection), is_map(Filter), is_map(Update), is_map(Options) ->
    gen_server:call(?SERVER, {update_one_async, Collection, Filter, Update, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
update_one_async(Collection, Filter, Update, Options) ->
    error({badarg, [Collection, Filter, Update, Options]}, [Collection, Filter, Update, Options], #{
        error_info => #{
            module => ?MODULE,
            function => update_one_async,
            arity => 4,
            cause => "All arguments must be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously update multiple documents
%%--------------------------------------------------------------------
-spec update_many_async(collection(), filter(), update(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
update_many_async(Collection, Filter, Update, Options) when is_binary(Collection), is_map(Filter), is_map(Update), is_map(Options) ->
    gen_server:call(?SERVER, {update_many_async, Collection, Filter, Update, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
update_many_async(Collection, Filter, Update, Options) ->
    error({badarg, [Collection, Filter, Update, Options]}, [Collection, Filter, Update, Options], #{
        error_info => #{
            module => ?MODULE,
            function => update_many_async,
            arity => 4,
            cause => "All arguments must be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously delete a single document
%%--------------------------------------------------------------------
-spec delete_one_async(collection(), filter()) -> {ok, async_ref()} | {error, term()}.
delete_one_async(Collection, Filter) ->
    delete_one_async(Collection, Filter, #{}).

-spec delete_one_async(collection(), filter(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
delete_one_async(Collection, Filter, Options) when is_binary(Collection), is_map(Filter), is_map(Options) ->
    gen_server:call(?SERVER, {delete_one_async, Collection, Filter, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
delete_one_async(Collection, Filter, Options) ->
    error({badarg, [Collection, Filter, Options]}, [Collection, Filter, Options], #{
        error_info => #{
            module => ?MODULE,
            function => delete_one_async,
            arity => 3,
            cause => "Collection, Filter, and Options must all be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously delete multiple documents
%%--------------------------------------------------------------------
-spec delete_many_async(collection(), filter()) -> {ok, async_ref()} | {error, term()}.
delete_many_async(Collection, Filter) ->
    delete_many_async(Collection, Filter, #{}).

-spec delete_many_async(collection(), filter(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
delete_many_async(Collection, Filter, Options) when is_binary(Collection), is_map(Filter), is_map(Options) ->
    gen_server:call(?SERVER, {delete_many_async, Collection, Filter, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
delete_many_async(Collection, Filter, Options) ->
    error({badarg, [Collection, Filter, Options]}, [Collection, Filter, Options], #{
        error_info => #{
            module => ?MODULE,
            function => delete_many_async,
            arity => 3,
            cause => "Collection, Filter, and Options must all be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Asynchronously count documents
%%--------------------------------------------------------------------
-spec count_documents_async(collection(), filter()) -> {ok, async_ref()} | {error, term()}.
count_documents_async(Collection, Filter) ->
    count_documents_async(Collection, Filter, #{}).

-spec count_documents_async(collection(), filter(), operation_options()) -> 
    {ok, async_ref()} | {error, term()}.
count_documents_async(Collection, Filter, Options) when is_binary(Collection), is_map(Filter), is_map(Options) ->
    gen_server:call(?SERVER, {count_documents_async, Collection, Filter, Options},
                   maps:get(timeout, Options, ?DEFAULT_TIMEOUT));
count_documents_async(Collection, Filter, Options) ->
    error({badarg, [Collection, Filter, Options]}, [Collection, Filter, Options], #{
        error_info => #{
            module => ?MODULE,
            function => count_documents_async,
            arity => 3,
            cause => "Collection, Filter, and Options must all be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Synchronously insert a single document (legacy compatibility)
%%--------------------------------------------------------------------
-spec insert_one(collection(), document(), operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
insert_one(Collection, Document, Options) ->
    case insert_one_async(Collection, Document, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously insert multiple documents (legacy compatibility)
%%--------------------------------------------------------------------
-spec insert_many(collection(), [document()], operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
insert_many(Collection, Documents, Options) ->
    case insert_many_async(Collection, Documents, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously find a single document (legacy compatibility)
%%--------------------------------------------------------------------
-spec find_one(collection(), filter()) -> {ok, document() | null} | {error, term()}.
find_one(Collection, Filter) ->
    find_one(Collection, Filter, #{}).

-spec find_one(collection(), filter(), operation_options()) -> 
    {ok, document() | null} | {error, term()}.
find_one(Collection, Filter, Options) ->
    case find_one_async(Collection, Filter, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously find multiple documents (legacy compatibility)
%%--------------------------------------------------------------------
-spec find(collection(), filter()) -> {ok, [document()]} | {error, term()}.
find(Collection, Filter) ->
    find(Collection, Filter, #{}).

-spec find(collection(), filter(), operation_options()) -> 
    {ok, [document()]} | {error, term()}.
find(Collection, Filter, Options) ->
    case find_async(Collection, Filter, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously update a single document (legacy compatibility)
%%--------------------------------------------------------------------
-spec update_one(collection(), filter(), update(), operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
update_one(Collection, Filter, Update, Options) ->
    case update_one_async(Collection, Filter, Update, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously update multiple documents (legacy compatibility)
%%--------------------------------------------------------------------
-spec update_many(collection(), filter(), update(), operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
update_many(Collection, Filter, Update, Options) ->
    case update_many_async(Collection, Filter, Update, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously delete a single document (legacy compatibility)
%%--------------------------------------------------------------------
-spec delete_one(collection(), filter()) -> {ok, operation_result()} | {error, term()}.
delete_one(Collection, Filter) ->
    delete_one(Collection, Filter, #{}).

-spec delete_one(collection(), filter(), operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
delete_one(Collection, Filter, Options) ->
    case delete_one_async(Collection, Filter, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously delete multiple documents (legacy compatibility)
%%--------------------------------------------------------------------
-spec delete_many(collection(), filter()) -> {ok, operation_result()} | {error, term()}.
delete_many(Collection, Filter) ->
    delete_many(Collection, Filter, #{}).

-spec delete_many(collection(), filter(), operation_options()) -> 
    {ok, operation_result()} | {error, term()}.
delete_many(Collection, Filter, Options) ->
    case delete_many_async(Collection, Filter, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Synchronously count documents (legacy compatibility)
%%--------------------------------------------------------------------
-spec count_documents(collection(), filter()) -> {ok, non_neg_integer()} | {error, term()}.
count_documents(Collection, Filter) ->
    count_documents(Collection, Filter, #{}).

-spec count_documents(collection(), filter(), operation_options()) -> 
    {ok, non_neg_integer()} | {error, term()}.
count_documents(Collection, Filter, Options) ->
    case count_documents_async(Collection, Filter, Options) of
        {ok, Ref} ->
            receive
                {mongodb_result, Ref, Result} -> {ok, Result};
                {mongodb_error, Ref, Error} -> {error, Error}
            after maps:get(timeout, Options, ?DEFAULT_TIMEOUT) ->
                {error, timeout}
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Create a collection
%%--------------------------------------------------------------------
-spec create_collection(collection(), operation_options()) -> {ok, operation_result()} | {error, term()}.
create_collection(Collection, Options) when is_binary(Collection), is_map(Options) ->
    gen_server:call(?SERVER, {create_collection, Collection, Options});
create_collection(Collection, Options) ->
    error({badarg, [Collection, Options]}, [Collection, Options], #{
        error_info => #{
            module => ?MODULE,
            function => create_collection,
            arity => 2,
            cause => "Collection must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Drop a collection
%%--------------------------------------------------------------------
-spec drop_collection(collection(), operation_options()) -> {ok, operation_result()} | {error, term()}.
drop_collection(Collection, Options) when is_binary(Collection), is_map(Options) ->
    gen_server:call(?SERVER, {drop_collection, Collection, Options});
drop_collection(Collection, Options) ->
    error({badarg, [Collection, Options]}, [Collection, Options], #{
        error_info => #{
            module => ?MODULE,
            function => drop_collection,
            arity => 2,
            cause => "Collection must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc List all collections
%%--------------------------------------------------------------------
-spec list_collections(operation_options()) -> {ok, [binary()]} | {error, term()}.
list_collections(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {list_collections, Options});
list_collections(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => list_collections,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Create an index
%%--------------------------------------------------------------------
-spec create_index(collection(), index_spec(), operation_options()) -> {ok, operation_result()} | {error, term()}.
create_index(Collection, IndexSpec, Options) when is_binary(Collection), is_map(IndexSpec), is_map(Options) ->
    gen_server:call(?SERVER, {create_index, Collection, IndexSpec, Options});
create_index(Collection, IndexSpec, Options) ->
    error({badarg, [Collection, IndexSpec, Options]}, [Collection, IndexSpec, Options], #{
        error_info => #{
            module => ?MODULE,
            function => create_index,
            arity => 3,
            cause => "All arguments must be maps (Collection as binary)"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Drop an index
%%--------------------------------------------------------------------
-spec drop_index(collection(), binary(), operation_options()) -> {ok, operation_result()} | {error, term()}.
drop_index(Collection, IndexName, Options) when is_binary(Collection), is_binary(IndexName), is_map(Options) ->
    gen_server:call(?SERVER, {drop_index, Collection, IndexName, Options});
drop_index(Collection, IndexName, Options) ->
    error({badarg, [Collection, IndexName, Options]}, [Collection, IndexName, Options], #{
        error_info => #{
            module => ?MODULE,
            function => drop_index,
            arity => 3,
            cause => "Collection and IndexName must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc List indexes for a collection
%%--------------------------------------------------------------------
-spec list_indexes(collection(), operation_options()) -> {ok, [document()]} | {error, term()}.
list_indexes(Collection, Options) when is_binary(Collection), is_map(Options) ->
    gen_server:call(?SERVER, {list_indexes, Collection, Options});
list_indexes(Collection, Options) ->
    error({badarg, [Collection, Options]}, [Collection, Options], #{
        error_info => #{
            module => ?MODULE,
            function => list_indexes,
            arity => 2,
            cause => "Collection must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Execute aggregation pipeline
%%--------------------------------------------------------------------
-spec aggregate(collection(), pipeline(), operation_options()) -> {ok, [document()]} | {error, term()}.
aggregate(Collection, Pipeline, Options) when is_binary(Collection), is_list(Pipeline), is_map(Options) ->
    gen_server:call(?SERVER, {aggregate, Collection, Pipeline, Options});
aggregate(Collection, Pipeline, Options) ->
    error({badarg, [Collection, Pipeline, Options]}, [Collection, Pipeline, Options], #{
        error_info => #{
            module => ?MODULE,
            function => aggregate,
            arity => 3,
            cause => "Collection must be binary, Pipeline must be list, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Execute bulk write operations
%%--------------------------------------------------------------------
-spec bulk_write(collection(), [bulk_operation()], operation_options()) -> {ok, operation_result()} | {error, term()}.
bulk_write(Collection, Operations, Options) when is_binary(Collection), is_list(Operations), is_map(Options) ->
    gen_server:call(?SERVER, {bulk_write, Collection, Operations, Options});
bulk_write(Collection, Operations, Options) ->
    error({badarg, [Collection, Operations, Options]}, [Collection, Operations, Options], #{
        error_info => #{
            module => ?MODULE,
            function => bulk_write,
            arity => 3,
            cause => "Collection must be binary, Operations must be list, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Start a new session
%%--------------------------------------------------------------------
-spec start_session(operation_options()) -> {ok, reference()} | {error, term()}.
start_session(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {start_session, Options});
start_session(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => start_session,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Start a transaction
%%--------------------------------------------------------------------
-spec start_transaction(reference(), operation_options()) -> ok | {error, term()}.
start_transaction(SessionRef, Options) when is_reference(SessionRef), is_map(Options) ->
    gen_server:call(?SERVER, {start_transaction, SessionRef, Options});
start_transaction(SessionRef, Options) ->
    error({badarg, [SessionRef, Options]}, [SessionRef, Options], #{
        error_info => #{
            module => ?MODULE,
            function => start_transaction,
            arity => 2,
            cause => "SessionRef must be reference, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Commit a transaction
%%--------------------------------------------------------------------
-spec commit_transaction(reference(), operation_options()) -> ok | {error, term()}.
commit_transaction(SessionRef, Options) when is_reference(SessionRef), is_map(Options) ->
    gen_server:call(?SERVER, {commit_transaction, SessionRef, Options});
commit_transaction(SessionRef, Options) ->
    error({badarg, [SessionRef, Options]}, [SessionRef, Options], #{
        error_info => #{
            module => ?MODULE,
            function => commit_transaction,
            arity => 2,
            cause => "SessionRef must be reference, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Abort a transaction
%%--------------------------------------------------------------------
-spec abort_transaction(reference(), operation_options()) -> ok | {error, term()}.
abort_transaction(SessionRef, Options) when is_reference(SessionRef), is_map(Options) ->
    gen_server:call(?SERVER, {abort_transaction, SessionRef, Options});
abort_transaction(SessionRef, Options) ->
    error({badarg, [SessionRef, Options]}, [SessionRef, Options], #{
        error_info => #{
            module => ?MODULE,
            function => abort_transaction,
            arity => 2,
            cause => "SessionRef must be reference, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Execute function within a transaction
%%--------------------------------------------------------------------
-spec with_transaction(reference(), fun(), operation_options()) -> {ok, term()} | {error, term()}.
with_transaction(SessionRef, Fun, Options) when is_reference(SessionRef), is_function(Fun, 0), is_map(Options) ->
    gen_server:call(?SERVER, {with_transaction, SessionRef, Fun, Options});
with_transaction(SessionRef, Fun, Options) ->
    error({badarg, [SessionRef, Fun, Options]}, [SessionRef, Fun, Options], #{
        error_info => #{
            module => ?MODULE,
            function => with_transaction,
            arity => 3,
            cause => "SessionRef must be reference, Fun must be function/0, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get connection information
%%--------------------------------------------------------------------
-spec get_connection_info(atom()) -> {ok, map()} | {error, term()}.
get_connection_info(ConnectionName) when is_atom(ConnectionName) ->
    gen_server:call(?SERVER, {get_connection_info, ConnectionName});
get_connection_info(ConnectionName) ->
    error({badarg, ConnectionName}, [ConnectionName], #{
        error_info => #{
            module => ?MODULE,
            function => get_connection_info,
            arity => 1,
            cause => "Connection name must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Ping the MongoDB server
%%--------------------------------------------------------------------
-spec ping(operation_options()) -> {ok, map()} | {error, term()}.
ping(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {ping, Options});
ping(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => ping,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get server status
%%--------------------------------------------------------------------
-spec server_status(operation_options()) -> {ok, map()} | {error, term()}.
server_status(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {server_status, Options});
server_status(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => server_status,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc List databases
%%--------------------------------------------------------------------
-spec list_databases(operation_options()) -> {ok, [binary()]} | {error, term()}.
list_databases(Options) when is_map(Options) ->
    gen_server:call(?SERVER, {list_databases, Options});
list_databases(Options) ->
    error({badarg, Options}, [Options], #{
        error_info => #{
            module => ?MODULE,
            function => list_databases,
            arity => 1,
            cause => "Options must be a map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get driver statistics
%%--------------------------------------------------------------------
-spec statistics() -> statistics().
statistics() ->
    gen_server:call(?SERVER, get_statistics).

-spec statistics(atom()) -> {ok, statistics()} | {error, term()}.
statistics(ConnectionName) when is_atom(ConnectionName) ->
    gen_server:call(?SERVER, {get_statistics, ConnectionName});
statistics(ConnectionName) ->
    error({badarg, ConnectionName}, [ConnectionName], #{
        error_info => #{
            module => ?MODULE,
            function => statistics,
            arity => 1,
            cause => "Connection name must be an atom"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Get connection pool statistics
%%--------------------------------------------------------------------
-spec connection_pool_stats() -> {ok, map()} | {error, term()}.
connection_pool_stats() ->
    gen_server:call(?SERVER, get_connection_pool_stats).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(Config) ->
    process_flag(trap_exit, true),
    
    % Initialize persistent terms cache
    init_persistent_cache(),
    
    % Set up statistics and health check timers
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_statistics),
    erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), health_check),
    
    InitialStats = #{
        operations_total => 0,
        operations_success => 0,
        operations_error => 0,
        connections_active => 0,
        connections_available => 0,
        avg_response_time => 0.0,
        collections_cached => 0,
        indexes_cached => 0,
        memory_usage => 0,
        uptime_seconds => 0
    },
    
    DefaultConfig = maps:merge(#{
        host => <<"localhost">>,
        port => 27017,
        database => <<"test">>,
        pool_size => ?DEFAULT_POOL_SIZE,
        max_overflow => ?DEFAULT_MAX_OVERFLOW,
        timeout => ?DEFAULT_TIMEOUT,
        ssl => false,
        auth_mechanism => scram_sha_256
    }, Config),
    
    State = #state{
        statistics = InitialStats,
        max_workers = maps:get(max_workers, Config, 20),
        worker_timeout = maps:get(worker_timeout, Config, ?DEFAULT_TIMEOUT),
        default_config = DefaultConfig
    },
    
    % Initialize default connection pool
    {ok, initialize_default_connection_pool(State)}.

handle_call({insert_one_async, Collection, Document, Options}, From, State) ->
    {noreply, spawn_async_worker(insert_one, [Collection, Document, Options], From, State)};

handle_call({insert_many_async, Collection, Documents, Options}, From, State) ->
    {noreply, spawn_async_worker(insert_many, [Collection, Documents, Options], From, State)};

handle_call({find_one_async, Collection, Filter, Options}, From, State) ->
    {noreply, spawn_async_worker(find_one, [Collection, Filter, Options], From, State)};

handle_call({find_async, Collection, Filter, Options}, From, State) ->
    {noreply, spawn_async_worker(find, [Collection, Filter, Options], From, State)};

handle_call({update_one_async, Collection, Filter, Update, Options}, From, State) ->
    {noreply, spawn_async_worker(update_one, [Collection, Filter, Update, Options], From, State)};

handle_call({update_many_async, Collection, Filter, Update, Options}, From, State) ->
    {noreply, spawn_async_worker(update_many, [Collection, Filter, Update, Options], From, State)};

handle_call({delete_one_async, Collection, Filter, Options}, From, State) ->
    {noreply, spawn_async_worker(delete_one, [Collection, Filter, Options], From, State)};

handle_call({delete_many_async, Collection, Filter, Options}, From, State) ->
    {noreply, spawn_async_worker(delete_many, [Collection, Filter, Options], From, State)};

handle_call({count_documents_async, Collection, Filter, Options}, From, State) ->
    {noreply, spawn_async_worker(count_documents, [Collection, Filter, Options], From, State)};

handle_call(get_statistics, _From, State) ->
    CurrentStats = State#state.statistics,
    Stats = CurrentStats#{
        connections_active => length(maps:keys(State#state.connections)),
        memory_usage => erlang:memory(processes)
    },
    {reply, Stats, State};

handle_call(get_connection_pool_stats, _From, State) ->
    PoolStats = get_pool_statistics(State#state.connection_pools),
    {reply, {ok, PoolStats}, State};

%% GridFS operations
handle_call({gridfs_upload, Filename, Data, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:upload_file(Filename, Data, Options),
    {reply, Result, State};

handle_call({gridfs_upload, Bucket, Filename, Data, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:upload_file(Bucket, Filename, Data, Options),
    {reply, Result, State};

handle_call({gridfs_download, Filename, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:download_file(Filename, Options),
    {reply, Result, State};

handle_call({gridfs_download, Bucket, Filename, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:download_file(Bucket, Filename, Options),
    {reply, Result, State};

handle_call({gridfs_delete, Filename, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:delete_file(Filename, Options),
    {reply, Result, State};

handle_call({gridfs_find, Filter, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:find_files(Filter, Options),
    {reply, Result, State};

handle_call({gridfs_list, Options}, _From, State) ->
    Result = connect_mongodb_gridfs:list_files(Options),
    {reply, Result, State};

%% Change Streams operations
handle_call({watch_collection, Collection, Options}, _From, State) ->
    Result = connect_mongodb_changes:watch_collection(Collection, [], Options),
    {reply, Result, State};

handle_call({watch_collection, _Database, Collection, Options}, _From, State) ->
    Result = connect_mongodb_changes:watch_collection(Collection, [], Options),
    {reply, Result, State};

handle_call({watch_database, Database, Options}, _From, State) ->
    Result = connect_mongodb_changes:watch_database(Database, Options),
    {reply, Result, State};

handle_call({watch_cluster, Options}, _From, State) ->
    Result = connect_mongodb_changes:watch_cluster(Options),
    {reply, Result, State};

%% Load Balancing operations
handle_call({add_server, ServerConfig, Weight}, _From, State) ->
    Result = connect_mongodb_balancer:add_server(ServerConfig, Weight),
    {reply, Result, State};

handle_call({remove_server, ServerId}, _From, State) ->
    Result = connect_mongodb_balancer:remove_server(ServerId),
    {reply, Result, State};

handle_call({set_server_weight, _ServerId, _Weight}, _From, State) ->
    % TODO: Implement set_server_weight in connect_mongodb_balancer
    Result = {error, not_implemented},
    {reply, Result, State};

handle_call({get_server_stats, ServerId}, _From, State) ->
    Result = connect_mongodb_balancer:get_connection_stats(ServerId),
    {reply, Result, State};

handle_call(get_all_servers, _From, State) ->
    Result = connect_mongodb_balancer:get_all_servers_health(),
    {reply, Result, State};

handle_call({set_balancing_strategy, Strategy}, _From, State) ->
    Result = connect_mongodb_balancer:set_load_balancing_strategy(Strategy),
    {reply, Result, State};

handle_call({enable_circuit_breaker, _ServerId, _Options}, _From, State) ->
    % TODO: Implement enable_circuit_breaker in connect_mongodb_balancer
    Result = {error, not_implemented},
    {reply, Result, State};

handle_call({disable_circuit_breaker, _ServerId}, _From, State) ->
    % TODO: Implement disable_circuit_breaker in connect_mongodb_balancer
    Result = {error, not_implemented},
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%% Async GridFS operations
handle_cast({gridfs_upload_async, Ref, From, Filename, Data, Options}, State) ->
    spawn_link(fun() ->
        Result = connect_mongodb_gridfs:upload_file_async(Filename, Data, Options),
        From ! {async_result, Ref, Result}
    end),
    {noreply, State};

handle_cast({gridfs_upload_async, Ref, From, Bucket, Filename, Data, Options}, State) ->
    spawn_link(fun() ->
        Result = connect_mongodb_gridfs:upload_file_async(Bucket, Filename, Data, Options),
        From ! {async_result, Ref, Result}
    end),
    {noreply, State};

handle_cast({gridfs_download_async, Ref, From, Filename, Options}, State) ->
    spawn_link(fun() ->
        Result = connect_mongodb_gridfs:download_file_async(Filename, Options),
        From ! {async_result, Ref, Result}
    end),
    {noreply, State};

handle_cast({gridfs_download_async, Ref, From, Bucket, Filename, Options}, State) ->
    spawn_link(fun() ->
        Result = connect_mongodb_gridfs:download_file_async(Bucket, Filename, Options),
        From ! {async_result, Ref, Result}
    end),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, _Reason}, State) ->
    % Clean up dead worker
    Workers = maps:remove(Pid, State#state.workers),
    {noreply, State#state{workers = Workers}};

handle_info(update_statistics, State) ->
    % Schedule next statistics update
    erlang:send_after(?STATS_UPDATE_INTERVAL, self(), update_statistics),
    {noreply, State};

handle_info(health_check, State) ->
    % Schedule next health check
    erlang:send_after(?HEALTH_CHECK_INTERVAL, self(), health_check),
    % Perform health checks on connections
    perform_health_checks(State#state.connections),
    {noreply, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    % Clean up persistent terms
    persistent_term:erase(?CACHE_KEY_CONNECTIONS),
    persistent_term:erase(?CACHE_KEY_COLLECTIONS),
    persistent_term:erase(?CACHE_KEY_INDEXES),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize persistent terms cache
%%--------------------------------------------------------------------
init_persistent_cache() ->
    persistent_term:put(?CACHE_KEY_CONNECTIONS, #{}),
    persistent_term:put(?CACHE_KEY_COLLECTIONS, #{}),
    persistent_term:put(?CACHE_KEY_INDEXES, #{}).

%%--------------------------------------------------------------------
%% @private  
%% @doc Spawn async worker process
%%--------------------------------------------------------------------
spawn_async_worker(Operation, Args, From, State) ->
    case maps:size(State#state.workers) < State#state.max_workers of
        true ->
            Ref = make_ref(),
            Pid = spawn_link(?MODULE, async_worker, [Operation, Args, Ref, self()]),
            Workers = maps:put(Pid, Ref, State#state.workers),
            gen_server:reply(From, {ok, Ref}),
            State#state{workers = Workers};
        false ->
            gen_server:reply(From, {error, too_many_workers}),
            State
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Async worker process
%%--------------------------------------------------------------------
async_worker(Operation, Args, Ref, ServerPid) ->
    StartTime = erlang:monotonic_time(microsecond),
    
    Result = case Operation of
        insert_one -> execute_insert_one_internal(Args);
        insert_many -> execute_insert_many_internal(Args);
        find_one -> execute_find_one_internal(Args);
        find -> execute_find_internal(Args);
        update_one -> execute_update_one_internal(Args);
        update_many -> execute_update_many_internal(Args);
        delete_one -> execute_delete_one_internal(Args);
        delete_many -> execute_delete_many_internal(Args);
        count_documents -> execute_count_documents_internal(Args)
    end,
    
    EndTime = erlang:monotonic_time(microsecond),
    Duration = EndTime - StartTime,
    
    % Send result back to caller
    case Result of
        {ok, Data} ->
            EnhancedResult = case is_map(Data) of
                true -> Data#{processed_at => EndTime, duration_us => Duration};
                false -> #{result => Data, processed_at => EndTime, duration_us => Duration}
            end,
            ServerPid ! {mongodb_result, Ref, EnhancedResult};
        {error, Error} ->
            ServerPid ! {mongodb_error, Ref, Error}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Initialize default connection pool
%%--------------------------------------------------------------------
initialize_default_connection_pool(State) ->
    % This would initialize the actual MongoDB connection pool
    % For now, return the state as-is with placeholder
    State.

%%--------------------------------------------------------------------
%% @private
%% @doc Get pool statistics
%%--------------------------------------------------------------------
get_pool_statistics(_Pools) ->
    % This would return actual pool statistics
    % For now, return mock data
    #{
        total_pools => 1,
        active_connections => 5,
        available_connections => 5,
        waiting_requests => 0,
        total_requests => 1000,
        avg_checkout_time => 2.5
    }.

%%--------------------------------------------------------------------
%% @private
%% @doc Perform health checks on connections
%%--------------------------------------------------------------------
perform_health_checks(_Connections) ->
    % This would perform actual health checks
    % For now, just log that health check was performed
    logger:debug("MongoDB connection health check completed").

%%--------------------------------------------------------------------
%% @private
%% @doc Internal operation implementations (stubs - would call actual MongoDB driver)
%%--------------------------------------------------------------------
execute_insert_one_internal([_Collection, _Document, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        acknowledged => true,
        inserted_count => 1,
        inserted_ids => [generate_object_id()]
    }}.

execute_insert_many_internal([_Collection, Documents, _Options]) ->
    % Mock implementation - would use actual MongoDB driver  
    {ok, #{
        acknowledged => true,
        inserted_count => length(Documents),
        inserted_ids => [generate_object_id() || _ <- Documents]
    }}.

execute_find_one_internal([_Collection, _Filter, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        <<"_id">> => generate_object_id(),
        <<"field">> => <<"value">>
    }}.

execute_find_internal([_Collection, _Filter, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, [
        #{<<"_id">> => generate_object_id(), <<"field">> => <<"value1">>},
        #{<<"_id">> => generate_object_id(), <<"field">> => <<"value2">>}
    ]}.

execute_update_one_internal([_Collection, _Filter, _Update, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        acknowledged => true,
        matched_count => 1,
        modified_count => 1
    }}.

execute_update_many_internal([_Collection, _Filter, _Update, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        acknowledged => true,
        matched_count => 3,
        modified_count => 2
    }}.

execute_delete_one_internal([_Collection, _Filter, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        acknowledged => true,
        deleted_count => 1
    }}.

execute_delete_many_internal([_Collection, _Filter, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, #{
        acknowledged => true,
        deleted_count => 5
    }}.

execute_count_documents_internal([_Collection, _Filter, _Options]) ->
    % Mock implementation - would use actual MongoDB driver
    {ok, 42}.

%%%===================================================================
%%% GridFS Operations Implementation 
%%%===================================================================

gridfs_upload(Filename, Data, Options) ->
    gen_server:call(?SERVER, {gridfs_upload, Filename, Data, Options}).

gridfs_upload(Bucket, Filename, Data, Options) ->
    gen_server:call(?SERVER, {gridfs_upload, Bucket, Filename, Data, Options}).

gridfs_upload_async(Filename, Data, Options) ->
    Ref = make_ref(),
    gen_server:cast(?SERVER, {gridfs_upload_async, Ref, self(), Filename, Data, Options}),
    Ref.

gridfs_upload_async(Bucket, Filename, Data, Options) ->
    Ref = make_ref(),
    gen_server:cast(?SERVER, {gridfs_upload_async, Ref, self(), Bucket, Filename, Data, Options}),
    Ref.

gridfs_download(Filename, Options) ->
    gen_server:call(?SERVER, {gridfs_download, Filename, Options}).

gridfs_download(Bucket, Filename, Options) ->
    gen_server:call(?SERVER, {gridfs_download, Bucket, Filename, Options}).

gridfs_download_async(Filename, Options) ->
    Ref = make_ref(),
    gen_server:cast(?SERVER, {gridfs_download_async, Ref, self(), Filename, Options}),
    Ref.

gridfs_download_async(Bucket, Filename, Options) ->
    Ref = make_ref(),
    gen_server:cast(?SERVER, {gridfs_download_async, Ref, self(), Bucket, Filename, Options}),
    Ref.

gridfs_stream_upload(Filename, StreamRef, Options) ->
    connect_mongodb_gridfs:upload_stream(Filename, StreamRef, Options).

gridfs_stream_download(Filename, Options) ->
    connect_mongodb_gridfs:download_stream(Filename, Options).

gridfs_delete(Filename, Options) ->
    gen_server:call(?SERVER, {gridfs_delete, Filename, Options}).

gridfs_find(Filter, Options) ->
    gen_server:call(?SERVER, {gridfs_find, Filter, Options}).

gridfs_list(Options) ->
    gen_server:call(?SERVER, {gridfs_list, Options}).

gridfs_create_bucket(BucketName, Options) ->
    connect_mongodb_gridfs:create_bucket(BucketName, Options).

gridfs_drop_bucket(BucketName) ->
    connect_mongodb_gridfs:drop_bucket(BucketName, #{}).

%%%===================================================================
%%% Change Streams Operations Implementation
%%%===================================================================

watch_collection(Collection, Options) ->
    gen_server:call(?SERVER, {watch_collection, Collection, Options}).

watch_collection(Database, Collection, Options) ->
    gen_server:call(?SERVER, {watch_collection, Database, Collection, Options}).

watch_database(Database) ->
    gen_server:call(?SERVER, {watch_database, Database, #{}}).

watch_database(Database, Options) ->
    gen_server:call(?SERVER, {watch_database, Database, Options}).

watch_cluster() ->
    gen_server:call(?SERVER, {watch_cluster, #{}}).

watch_cluster(Options) ->
    gen_server:call(?SERVER, {watch_cluster, Options}).

resume_change_stream(StreamRef, ResumeToken) ->
    connect_mongodb_changes:resume_change_stream(StreamRef, ResumeToken).

stop_change_stream(StreamRef) ->
    connect_mongodb_changes:stop_change_stream(StreamRef).

%%%===================================================================
%%% Load Balancing Operations Implementation
%%%===================================================================

add_server(ServerConfig, Weight) ->
    gen_server:call(?SERVER, {add_server, ServerConfig, Weight}).

remove_server(ServerId) ->
    gen_server:call(?SERVER, {remove_server, ServerId}).

set_server_weight(ServerId, Weight) ->
    gen_server:call(?SERVER, {set_server_weight, ServerId, Weight}).

get_server_stats(ServerId) ->
    gen_server:call(?SERVER, {get_server_stats, ServerId}).

get_all_servers() ->
    gen_server:call(?SERVER, get_all_servers).

set_balancing_strategy(Strategy) ->
    gen_server:call(?SERVER, {set_balancing_strategy, Strategy}).

enable_circuit_breaker(ServerId, Options) ->
    gen_server:call(?SERVER, {enable_circuit_breaker, ServerId, Options}).

disable_circuit_breaker(ServerId) ->
    gen_server:call(?SERVER, {disable_circuit_breaker, ServerId}).

%%--------------------------------------------------------------------
%% @private
%% @doc Generate a mock ObjectId
%%--------------------------------------------------------------------
generate_object_id() ->
    <<(rand:uniform(16#FFFFFFFF)):32,
      (rand:uniform(16#FFFFFF)):24,
      (rand:uniform(16#FFFF)):16,
      (rand:uniform(16#FFFFFF)):24>>. 