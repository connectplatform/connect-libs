%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch Client - Main API
%%% 
%%% Features:
%%% - Elasticsearch 8.x compatible
%%% - Modern HTTP/2 support via hackney
%%% - Connection pooling
%%% - OTP 27 native JSON support
%%% - Circuit breaker pattern
%%% - Bulk operations
%%% - Search templates
%%% - Async operations
%%% 
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search).

%% API exports
-export([
    start_link/1,
    stop/1,
    connect/1,
    disconnect/1,
    
    %% Document operations
    index/4,
    get/3,
    exists/3,
    delete/3,
    update/4,
    
    %% Search operations
    search/2,
    search/3,
    search/4,
    msearch/2,
    
    %% Bulk operations
    bulk/2,
    
    %% Index operations
    create_index/2,
    create_index/3,
    delete_index/2,
    exists_index/2,
    get_index/2,
    put_mapping/3,
    get_mapping/2,
    get_mapping/3,
    
    %% Template operations
    put_template/3,
    get_template/2,
    delete_template/2,
    
    %% Cluster operations
    cluster_health/1,
    cluster_stats/1,
    nodes_info/1,
    nodes_stats/1,
    
    %% Alias operations
    put_alias/3,
    get_alias/2,
    delete_alias/3,
    
    %% Snapshot operations
    create_snapshot/4,
    get_snapshot/3,
    delete_snapshot/3,
    restore_snapshot/3,
    
    %% Health check
    ping/1,
    info/1
]).

%% Types
-type connection() :: pid().
-type index() :: binary().
-type doc_type() :: binary().
-type doc_id() :: binary().
-type document() :: map().
-type query() :: map().
-type options() :: map().
-type result() :: {ok, term()} | {error, term()}.

-export_type([connection/0, index/0, doc_type/0, doc_id/0, document/0, 
              query/0, options/0, result/0]).

%%%===================================================================
%%% API Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start a connection to Elasticsearch
%%--------------------------------------------------------------------
-spec start_link(ConnectionOpts :: map()) -> {ok, connection()} | {error, term()}.
start_link(ConnectionOpts) ->
    connect_search_connection:start_link(ConnectionOpts).

%%--------------------------------------------------------------------
%% @doc Stop an Elasticsearch connection
%%--------------------------------------------------------------------
-spec stop(Connection :: connection()) -> ok.
stop(Connection) ->
    connect_search_connection:stop(Connection).

%%--------------------------------------------------------------------
%% @doc Connect to Elasticsearch with options
%%--------------------------------------------------------------------
-spec connect(Options :: map()) -> {ok, connection()} | {error, term()}.
connect(Options) ->
    DefaultOpts = #{
        host => <<"localhost">>,
        port => 9200,
        scheme => <<"http">>,
        pool_size => 10,
        timeout => 5000,
        ssl => false,
        ssl_opts => [],
        headers => #{
            <<"Content-Type">> => <<"application/json">>,
            <<"Accept">> => <<"application/json">>
        }
    },
    ConnectOpts = maps:merge(DefaultOpts, Options),
    start_link(ConnectOpts).

%%--------------------------------------------------------------------
%% @doc Disconnect from Elasticsearch
%%--------------------------------------------------------------------
-spec disconnect(Connection :: connection()) -> ok.
disconnect(Connection) ->
    stop(Connection).

%%--------------------------------------------------------------------
%% @doc Index a document
%%--------------------------------------------------------------------
-spec index(Connection :: connection(),
           Index :: index(),
           DocId :: doc_id(),
           Document :: document()) -> result().
index(Connection, Index, DocId, Document) ->
    connect_search_ops:index(Connection, Index, DocId, Document).

%%--------------------------------------------------------------------
%% @doc Get a document by ID
%%--------------------------------------------------------------------
-spec get(Connection :: connection(),
         Index :: index(),
         DocId :: doc_id()) -> result().
get(Connection, Index, DocId) ->
    connect_search_ops:get(Connection, Index, DocId).

%%--------------------------------------------------------------------
%% @doc Check if document exists
%%--------------------------------------------------------------------
-spec exists(Connection :: connection(),
            Index :: index(),
            DocId :: doc_id()) -> result().
exists(Connection, Index, DocId) ->
    connect_search_ops:exists(Connection, Index, DocId).

%%--------------------------------------------------------------------
%% @doc Delete a document
%%--------------------------------------------------------------------
-spec delete(Connection :: connection(),
            Index :: index(),
            DocId :: doc_id()) -> result().
delete(Connection, Index, DocId) ->
    connect_search_ops:delete(Connection, Index, DocId).

%%--------------------------------------------------------------------
%% @doc Update a document
%%--------------------------------------------------------------------
-spec update(Connection :: connection(),
            Index :: index(),
            DocId :: doc_id(),
            Document :: document()) -> result().
update(Connection, Index, DocId, Document) ->
    connect_search_ops:update(Connection, Index, DocId, Document).

%%--------------------------------------------------------------------
%% @doc Search documents
%%--------------------------------------------------------------------
-spec search(Connection :: connection(), Index :: index()) -> result().
search(Connection, Index) ->
    search(Connection, Index, #{}).

-spec search(Connection :: connection(), 
            Index :: index(), 
            Query :: query()) -> result().
search(Connection, Index, Query) ->
    search(Connection, Index, Query, #{}).

-spec search(Connection :: connection(),
            Index :: index(),
            Query :: query(),
            Options :: options()) -> result().
search(Connection, Index, Query, Options) ->
    connect_search_ops:search(Connection, Index, Query, Options).

%%--------------------------------------------------------------------
%% @doc Multi-search operation
%%--------------------------------------------------------------------
-spec msearch(Connection :: connection(), Queries :: [query()]) -> result().
msearch(Connection, Queries) ->
    connect_search_ops:msearch(Connection, Queries).

%%--------------------------------------------------------------------
%% @doc Bulk operations
%%--------------------------------------------------------------------
-spec bulk(Connection :: connection(), Operations :: [map()]) -> result().
bulk(Connection, Operations) ->
    connect_search_ops:bulk(Connection, Operations).

%%--------------------------------------------------------------------
%% @doc Create an index
%%--------------------------------------------------------------------
-spec create_index(Connection :: connection(), Index :: index()) -> result().
create_index(Connection, Index) ->
    create_index(Connection, Index, #{}).

-spec create_index(Connection :: connection(),
                  Index :: index(), 
                  Settings :: map()) -> result().
create_index(Connection, Index, Settings) ->
    connect_search_ops:create_index(Connection, Index, Settings).

%%--------------------------------------------------------------------
%% @doc Delete an index
%%--------------------------------------------------------------------
-spec delete_index(Connection :: connection(), Index :: index()) -> result().
delete_index(Connection, Index) ->
    connect_search_ops:delete_index(Connection, Index).

%%--------------------------------------------------------------------
%% @doc Check if index exists
%%--------------------------------------------------------------------
-spec exists_index(Connection :: connection(), Index :: index()) -> result().
exists_index(Connection, Index) ->
    connect_search_ops:exists_index(Connection, Index).

%%--------------------------------------------------------------------
%% @doc Get index information
%%--------------------------------------------------------------------
-spec get_index(Connection :: connection(), Index :: index()) -> result().
get_index(Connection, Index) ->
    connect_search_ops:get_index(Connection, Index).

%%--------------------------------------------------------------------
%% @doc Put mapping for index
%%--------------------------------------------------------------------
-spec put_mapping(Connection :: connection(),
                 Index :: index(),
                 Mapping :: map()) -> result().
put_mapping(Connection, Index, Mapping) ->
    connect_search_ops:put_mapping(Connection, Index, Mapping).

%%--------------------------------------------------------------------
%% @doc Get mapping for all indices
%%--------------------------------------------------------------------
-spec get_mapping(Connection :: connection()) -> result().
get_mapping(Connection) ->
    connect_search_ops:get_mapping(Connection).

%%--------------------------------------------------------------------
%% @doc Get mapping for specific index
%%--------------------------------------------------------------------
-spec get_mapping(Connection :: connection(), Index :: index()) -> result().
get_mapping(Connection, Index) ->
    connect_search_ops:get_mapping(Connection, Index).

%%--------------------------------------------------------------------
%% @doc Put index template
%%--------------------------------------------------------------------
-spec put_template(Connection :: connection(),
                  Name :: binary(),
                  Template :: map()) -> result().
put_template(Connection, Name, Template) ->
    connect_search_ops:put_template(Connection, Name, Template).

%%--------------------------------------------------------------------
%% @doc Get index template
%%--------------------------------------------------------------------
-spec get_template(Connection :: connection(), Name :: binary()) -> result().
get_template(Connection, Name) ->
    connect_search_ops:get_template(Connection, Name).

%%--------------------------------------------------------------------
%% @doc Delete index template
%%--------------------------------------------------------------------
-spec delete_template(Connection :: connection(), Name :: binary()) -> result().
delete_template(Connection, Name) ->
    connect_search_ops:delete_template(Connection, Name).

%%--------------------------------------------------------------------
%% @doc Get cluster health
%%--------------------------------------------------------------------
-spec cluster_health(Connection :: connection()) -> result().
cluster_health(Connection) ->
    connect_search_ops:cluster_health(Connection).

%%--------------------------------------------------------------------
%% @doc Get cluster stats
%%--------------------------------------------------------------------
-spec cluster_stats(Connection :: connection()) -> result().
cluster_stats(Connection) ->
    connect_search_ops:cluster_stats(Connection).

%%--------------------------------------------------------------------
%% @doc Get nodes info
%%--------------------------------------------------------------------
-spec nodes_info(Connection :: connection()) -> result().
nodes_info(Connection) ->
    connect_search_ops:nodes_info(Connection).

%%--------------------------------------------------------------------
%% @doc Get nodes stats
%%--------------------------------------------------------------------
-spec nodes_stats(Connection :: connection()) -> result().
nodes_stats(Connection) ->
    connect_search_ops:nodes_stats(Connection).

%%--------------------------------------------------------------------
%% @doc Create alias
%%--------------------------------------------------------------------
-spec put_alias(Connection :: connection(),
               Index :: index(),
               Alias :: binary()) -> result().
put_alias(Connection, Index, Alias) ->
    connect_search_ops:put_alias(Connection, Index, Alias).

%%--------------------------------------------------------------------
%% @doc Get alias
%%--------------------------------------------------------------------
-spec get_alias(Connection :: connection(), Alias :: binary()) -> result().
get_alias(Connection, Alias) ->
    connect_search_ops:get_alias(Connection, Alias).

%%--------------------------------------------------------------------
%% @doc Delete alias
%%--------------------------------------------------------------------
-spec delete_alias(Connection :: connection(),
                  Index :: index(),
                  Alias :: binary()) -> result().
delete_alias(Connection, Index, Alias) ->
    connect_search_ops:delete_alias(Connection, Index, Alias).

%%--------------------------------------------------------------------
%% @doc Create snapshot
%%--------------------------------------------------------------------
-spec create_snapshot(Connection :: connection(),
                     Repository :: binary(),
                     Snapshot :: binary(),
                     Settings :: map()) -> result().
create_snapshot(Connection, Repository, Snapshot, Settings) ->
    connect_search_ops:create_snapshot(Connection, Repository, Snapshot, Settings).

%%--------------------------------------------------------------------
%% @doc Get snapshot
%%--------------------------------------------------------------------
-spec get_snapshot(Connection :: connection(),
                  Repository :: binary(),
                  Snapshot :: binary()) -> result().
get_snapshot(Connection, Repository, Snapshot) ->
    connect_search_ops:get_snapshot(Connection, Repository, Snapshot).

%%--------------------------------------------------------------------
%% @doc Delete snapshot
%%--------------------------------------------------------------------
-spec delete_snapshot(Connection :: connection(),
                     Repository :: binary(),
                     Snapshot :: binary()) -> result().
delete_snapshot(Connection, Repository, Snapshot) ->
    connect_search_ops:delete_snapshot(Connection, Repository, Snapshot).

%%--------------------------------------------------------------------
%% @doc Restore snapshot
%%--------------------------------------------------------------------
-spec restore_snapshot(Connection :: connection(),
                      Repository :: binary(),
                      Snapshot :: binary()) -> result().
restore_snapshot(Connection, Repository, Snapshot) ->
    connect_search_ops:restore_snapshot(Connection, Repository, Snapshot).

%%--------------------------------------------------------------------
%% @doc Ping Elasticsearch cluster
%%--------------------------------------------------------------------
-spec ping(Connection :: connection()) -> result().
ping(Connection) ->
    connect_search_ops:ping(Connection).

%%--------------------------------------------------------------------
%% @doc Get cluster info
%%--------------------------------------------------------------------
-spec info(Connection :: connection()) -> result().
info(Connection) ->
    connect_search_ops:info(Connection). 