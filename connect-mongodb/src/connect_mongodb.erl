%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB Driver - Main API
%%% 
%%% Features:
%%% - MongoDB 7.0+ compatible
%%% - SCRAM-SHA-256 authentication
%%% - Connection pooling with poolboy
%%% - OTP 27 native JSON support
%%% - Async operations
%%% - Connection health monitoring
%%% 
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb).

%% API exports
-export([
    start_link/1,
    stop/1,
    connect/1,
    disconnect/1,
    
    %% Database operations
    insert_one/3,
    insert_many/3,
    find_one/2,
    find_one/3,
    find/2,
    find/3,
    update_one/3,
    update_one/4,
    update_many/3,
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
    
    %% Aggregation
    aggregate/3,
    
    %% Transactions (MongoDB 4.0+)
    with_transaction/2,
    
    %% Health check
    ping/1,
    server_status/1
]).

%% Types
-type connection() :: pid().
-type database() :: binary().
-type collection() :: binary().
-type document() :: map().
-type filter() :: map().
-type options() :: map().
-type result() :: {ok, term()} | {error, term()}.

-export_type([connection/0, database/0, collection/0, document/0, 
              filter/0, options/0, result/0]).

%%%===================================================================
%%% API Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start a connection to MongoDB
%%--------------------------------------------------------------------
-spec start_link(ConnectionOpts :: map()) -> {ok, connection()} | {error, term()}.
start_link(ConnectionOpts) ->
    connect_mongodb_connection:start_link(ConnectionOpts).

%%--------------------------------------------------------------------
%% @doc Stop a MongoDB connection
%%--------------------------------------------------------------------
-spec stop(Connection :: connection()) -> ok.
stop(Connection) ->
    connect_mongodb_connection:stop(Connection).

%%--------------------------------------------------------------------
%% @doc Connect to MongoDB with options
%%--------------------------------------------------------------------
-spec connect(Options :: map()) -> {ok, connection()} | {error, term()}.
connect(Options) ->
    DefaultOpts = #{
        host => <<"localhost">>,
        port => 27017,
        database => <<"test">>,
        auth_mechanism => scram_sha_256,
        pool_size => 10,
        timeout => 5000,
        ssl => false,
        ssl_opts => []
    },
    ConnectOpts = maps:merge(DefaultOpts, Options),
    start_link(ConnectOpts).

%%--------------------------------------------------------------------
%% @doc Disconnect from MongoDB  
%%--------------------------------------------------------------------
-spec disconnect(Connection :: connection()) -> ok.
disconnect(Connection) ->
    stop(Connection).

%%--------------------------------------------------------------------
%% @doc Insert a single document
%%--------------------------------------------------------------------
-spec insert_one(Connection :: connection(), 
                Collection :: collection(), 
                Document :: document()) -> result().
insert_one(Connection, Collection, Document) ->
    connect_mongodb_ops:insert_one(Connection, Collection, Document).

%%--------------------------------------------------------------------
%% @doc Insert multiple documents
%%--------------------------------------------------------------------
-spec insert_many(Connection :: connection(),
                 Collection :: collection(),
                 Documents :: [document()]) -> result().
insert_many(Connection, Collection, Documents) ->
    connect_mongodb_ops:insert_many(Connection, Collection, Documents).

%%--------------------------------------------------------------------
%% @doc Find a single document
%%--------------------------------------------------------------------
-spec find_one(Connection :: connection(), Collection :: collection()) -> result().
find_one(Connection, Collection) ->
    find_one(Connection, Collection, #{}).

-spec find_one(Connection :: connection(), 
              Collection :: collection(),
              Filter :: filter()) -> result().
find_one(Connection, Collection, Filter) ->
    connect_mongodb_ops:find_one(Connection, Collection, Filter).

%%--------------------------------------------------------------------
%% @doc Find multiple documents
%%--------------------------------------------------------------------
-spec find(Connection :: connection(), Collection :: collection()) -> result().
find(Connection, Collection) ->
    find(Connection, Collection, #{}).

-spec find(Connection :: connection(),
          Collection :: collection(), 
          Filter :: filter()) -> result().
find(Connection, Collection, Filter) ->
    connect_mongodb_ops:find(Connection, Collection, Filter).

%%--------------------------------------------------------------------
%% @doc Update a single document
%%--------------------------------------------------------------------
-spec update_one(Connection :: connection(),
                Collection :: collection(),
                Filter :: filter()) -> result().
update_one(Connection, Collection, Filter) ->
    update_one(Connection, Collection, Filter, #{}).

-spec update_one(Connection :: connection(),
                Collection :: collection(), 
                Filter :: filter(),
                Update :: document()) -> result().
update_one(Connection, Collection, Filter, Update) ->
    connect_mongodb_ops:update_one(Connection, Collection, Filter, Update).

%%--------------------------------------------------------------------
%% @doc Update multiple documents
%%--------------------------------------------------------------------
-spec update_many(Connection :: connection(),
                 Collection :: collection(),
                 Filter :: filter()) -> result().
update_many(Connection, Collection, Filter) ->
    update_many(Connection, Collection, Filter, #{}).

-spec update_many(Connection :: connection(),
                 Collection :: collection(),
                 Filter :: filter(), 
                 Update :: document()) -> result().
update_many(Connection, Collection, Filter, Update) ->
    connect_mongodb_ops:update_many(Connection, Collection, Filter, Update).

%%--------------------------------------------------------------------
%% @doc Delete a single document
%%--------------------------------------------------------------------
-spec delete_one(Connection :: connection(), Collection :: collection()) -> result().
delete_one(Connection, Collection) ->
    delete_one(Connection, Collection, #{}).

-spec delete_one(Connection :: connection(),
                Collection :: collection(),
                Filter :: filter()) -> result().
delete_one(Connection, Collection, Filter) ->
    connect_mongodb_ops:delete_one(Connection, Collection, Filter).

%%--------------------------------------------------------------------
%% @doc Delete multiple documents  
%%--------------------------------------------------------------------
-spec delete_many(Connection :: connection(), Collection :: collection()) -> result().
delete_many(Connection, Collection) ->
    delete_many(Connection, Collection, #{}).

-spec delete_many(Connection :: connection(),
                 Collection :: collection(),
                 Filter :: filter()) -> result().
delete_many(Connection, Collection, Filter) ->
    connect_mongodb_ops:delete_many(Connection, Collection, Filter).

%%--------------------------------------------------------------------
%% @doc Count documents in collection
%%--------------------------------------------------------------------
-spec count_documents(Connection :: connection(), Collection :: collection()) -> result().
count_documents(Connection, Collection) ->
    count_documents(Connection, Collection, #{}).

-spec count_documents(Connection :: connection(),
                     Collection :: collection(),
                     Filter :: filter()) -> result().
count_documents(Connection, Collection, Filter) ->
    connect_mongodb_ops:count_documents(Connection, Collection, Filter).

%%--------------------------------------------------------------------
%% @doc Create a collection
%%--------------------------------------------------------------------
-spec create_collection(Connection :: connection(), Collection :: collection()) -> result().
create_collection(Connection, Collection) ->
    connect_mongodb_ops:create_collection(Connection, Collection).

%%--------------------------------------------------------------------
%% @doc Drop a collection
%%--------------------------------------------------------------------
-spec drop_collection(Connection :: connection(), Collection :: collection()) -> result().
drop_collection(Connection, Collection) ->
    connect_mongodb_ops:drop_collection(Connection, Collection).

%%--------------------------------------------------------------------
%% @doc List all collections
%%--------------------------------------------------------------------
-spec list_collections(Connection :: connection()) -> result().
list_collections(Connection) ->
    connect_mongodb_ops:list_collections(Connection).

%%--------------------------------------------------------------------
%% @doc Create an index
%%--------------------------------------------------------------------
-spec create_index(Connection :: connection(),
                  Collection :: collection(),
                  IndexSpec :: document()) -> result().
create_index(Connection, Collection, IndexSpec) ->
    connect_mongodb_ops:create_index(Connection, Collection, IndexSpec).

%%--------------------------------------------------------------------
%% @doc Drop an index
%%--------------------------------------------------------------------
-spec drop_index(Connection :: connection(),
                Collection :: collection(), 
                IndexName :: binary()) -> result().
drop_index(Connection, Collection, IndexName) ->
    connect_mongodb_ops:drop_index(Connection, Collection, IndexName).

%%--------------------------------------------------------------------
%% @doc List indexes for a collection
%%--------------------------------------------------------------------
-spec list_indexes(Connection :: connection(), Collection :: collection()) -> result().
list_indexes(Connection, Collection) ->
    connect_mongodb_ops:list_indexes(Connection, Collection).

%%--------------------------------------------------------------------
%% @doc Execute aggregation pipeline
%%--------------------------------------------------------------------
-spec aggregate(Connection :: connection(),
               Collection :: collection(),
               Pipeline :: [document()]) -> result().
aggregate(Connection, Collection, Pipeline) ->
    connect_mongodb_ops:aggregate(Connection, Collection, Pipeline).

%%--------------------------------------------------------------------
%% @doc Execute function within a transaction
%%--------------------------------------------------------------------
-spec with_transaction(Connection :: connection(), Fun :: fun()) -> result().
with_transaction(Connection, Fun) ->
    connect_mongodb_transaction:with_transaction(Connection, Fun).

%%--------------------------------------------------------------------
%% @doc Ping the MongoDB server
%%--------------------------------------------------------------------
-spec ping(Connection :: connection()) -> result().
ping(Connection) ->
    connect_mongodb_ops:ping(Connection).

%%--------------------------------------------------------------------
%% @doc Get server status
%%--------------------------------------------------------------------
-spec server_status(Connection :: connection()) -> result().
server_status(Connection) ->
    connect_mongodb_ops:server_status(Connection). 