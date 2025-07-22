# 🤖 AI Instruction Prompt: Connect-Search Library

*Comprehensive knowledge base for AI coders working with the Connect-Search pure Erlang Elasticsearch client*

---

## 📋 **LIBRARY OVERVIEW**

**Connect-Search** is a **pure Erlang OTP 27+ library** for Elasticsearch operations with async/await patterns and connection pooling. **Zero external dependencies** with comprehensive supervision and health monitoring.

### **Core Purpose**
- Connect to Elasticsearch clusters with connection pooling
- Perform document indexing, retrieval, and search operations
- Provide async operations for high-performance applications
- Monitor cluster and connection health with circuit breaker patterns
- Collect detailed statistics and performance metrics

### **Key Characteristics**
- ✅ **Pure Erlang**: No external dependencies, uses OTP 27 native HTTP client
- ✅ **OTP 27+ Ready**: Enhanced gen_server patterns, persistent terms caching
- ✅ **Type Safe**: Comprehensive Dialyzer compatibility
- ✅ **Async/Await**: Modern async patterns with callback-based result handling
- ✅ **Connection Pooling**: Automatic scaling with health monitoring
- ✅ **Circuit Breaker**: Built-in resilience patterns for cluster protection

---

## 🔧 **COMPLETE API REFERENCE**

### **Application Lifecycle**

#### `start/0` & `stop/0`
```erlang
-spec start() -> {ok, [atom()]} | {error, {atom(), term()}}.
-spec stop() -> ok | {error, term()}.
% Start/stop the ConnectPlatform Elasticsearch application
% Example: {ok, [connect_search]} = connect_search:start()
```

### **Connection Management**

#### `connect/1`
```erlang
-spec connect(Options :: map()) -> {ok, connection()} | {error, term()}.
% Connect to Elasticsearch with configuration options
% Options: #{host, port, scheme, timeout, pool_size, max_overflow, ssl_opts}
% Example: {ok, primary} = connect_search:connect(#{host => <<"localhost">>, port => 9200})
```

#### `disconnect/1`
```erlang
-spec disconnect(Connection :: connection()) -> ok | {error, not_found | restarting | running | simple_one_for_one}.
% Disconnect from a connection pool
% Example: ok = connect_search:disconnect(primary)
```

#### `ping/0`
```erlang
-spec ping() -> {ok, #{status := <<_:32>>}}.
% Ping Elasticsearch cluster - returns basic connectivity status
% Returns: {ok, #{status => <<"pong">>}}
```

### **Document Operations**

#### `index_async/4` (Recommended)
```erlang
-spec index_async(Index :: index(), DocId :: doc_id(), Document :: document(), Callback :: fun()) -> {ok, reference()}.
% Asynchronously index a document with callback for result handling
% Callback receives: {ok, #{index, id, result, version}} | {error, Reason}
% Example: {ok, Ref} = connect_search:index_async(<<"users">>, <<"123">>, #{name => <<"John">>}, fun(Result) -> io:format("~p~n", [Result]) end)
```

#### `index/3`
```erlang
-spec index(Index :: index(), DocId :: doc_id(), Document :: document()) -> {ok, map()}.
% Synchronously index a document - blocks until complete
% Returns: {ok, #{index, id, result => <<"created">>, version}}
% Example: {ok, Result} = connect_search:index(<<"users">>, <<"123">>, #{name => <<"John">>})
```

#### `get_async/3` (Recommended)
```erlang
-spec get_async(Index :: index(), DocId :: doc_id(), Callback :: fun()) -> {ok, reference()}.
% Asynchronously retrieve a document with callback
% Callback receives: {ok, #{index, id, found, source}} | {error, Reason}
% Example: {ok, Ref} = connect_search:get_async(<<"users">>, <<"123">>, fun(Doc) -> process_document(Doc) end)
```

#### `get/3`
```erlang
-spec get(Index :: index(), DocId :: doc_id(), Options :: options()) -> {ok, map()}.
% Synchronously retrieve a document
% Returns: {ok, #{index, id, found => boolean(), source => map()}}
% Example: {ok, Doc} = connect_search:get(<<"users">>, <<"123">>, #{})
```

#### `search_async/3` (Recommended)
```erlang
-spec search_async(Index :: index(), Query :: query(), Callback :: fun()) -> {ok, reference()}.
% Asynchronously search documents with callback
% Callback receives: {ok, #{took, timed_out, hits => #{total, max_score, hits}}} | {error, Reason}
% Example: {ok, Ref} = connect_search:search_async(<<"users">>, #{query => #{match_all => #{}}}, fun(Results) -> display_results(Results) end)
```

#### `search/2`
```erlang
-spec search(Index :: index(), Query :: query()) -> {ok, map()}.
% Synchronously search documents - blocks until complete
% Returns: {ok, #{took, timed_out, hits => #{total, max_score, hits => [Hit]}}}
% Example: {ok, Results} = connect_search:search(<<"users">>, #{query => #{match => #{name => <<"John">>}}})
```

### **Statistics & Monitoring**

#### `get_stats/0`
```erlang
-spec get_stats() -> map().
% Get basic Elasticsearch client statistics
% Returns: #{requests_total, requests_success, requests_error, connections_active, connections_total, uptime, circuit_breaker_opens}
% Example: Stats = connect_search:get_stats()
```

#### `get_health_status/0`
```erlang
-spec get_health_status() -> health_info().
% Get comprehensive health status from health monitoring system
% Returns detailed health information including cluster, connections, circuit breaker status
```

### **Pool Management**

#### `add_connection_pool/2`
```erlang
-spec add_connection_pool(PoolName :: atom(), Config :: map()) -> {ok, pid()} | {error, term()}.
% Dynamically add a connection pool
% Config: #{host, port, scheme, pool_size, max_overflow, timeout}
% Example: {ok, Pid} = connect_search:add_connection_pool(analytics_pool, #{host => <<"es-analytics.local">>, pool_size => 5})
```

#### `remove_connection_pool/1`
```erlang
-spec remove_connection_pool(PoolName :: atom()) -> ok | {error, not_found | restarting | running | simple_one_for_one}.
% Remove a connection pool dynamically
% Example: ok = connect_search:remove_connection_pool(analytics_pool)
```

#### `get_pool_stats/0`
```erlang
-spec get_pool_stats() -> {ok, map()} | {error, term()}.
% Get statistics for all connection pools
% Returns: {ok, #{total_pools, pools => #{pool_name => stats}, supervisor_status, uptime}}
```

### **Health Monitoring API**

#### `connect_search_health:get_health_status/0`
```erlang
-spec get_health_status() -> health_info().
% Get current health status with detailed breakdown
% Returns: #{status => healthy|degraded|unhealthy, cluster, connections, last_check, details}
```

#### `connect_search_health:force_health_check/0`
```erlang
-spec force_health_check() -> health_status().
% Force immediate health check of all components
% Returns updated health status
```

#### `connect_search_health:register_health_callback/1`
```erlang
-spec register_health_callback(Callback :: fun()) -> ok.
% Register callback for health status changes
% Callback receives: #{old_status, new_status, timestamp, details}
% Example: connect_search_health:register_health_callback(fun(Change) -> alert_ops_team(Change) end)
```

#### `connect_search_health:unregister_health_callback/1`
```erlang
-spec unregister_health_callback(Callback :: fun()) -> ok.
% Unregister health status change callback
```

### **Statistics Collection API**

#### `connect_search_stats:increment_counter/1,2`
```erlang
-spec increment_counter(Metric :: atom()) -> ok.
-spec increment_counter(Metric :: atom(), Value :: number()) -> ok.
% Increment performance counters using persistent terms
% Example: connect_search_stats:increment_counter(custom_searches, 1)
```

#### `connect_search_stats:record_timing/2`
```erlang
-spec record_timing(Metric :: atom(), Duration :: number()) -> ok.
% Record timing information for performance analysis
% Example: connect_search_stats:record_timing(search_duration, 45)
```

#### `connect_search_stats:get_detailed_stats/0`
```erlang
-spec get_detailed_stats() -> map().
% Get comprehensive statistics including timing averages and detailed breakdowns
```

#### `connect_search_stats:reset_stats/0`
```erlang
-spec reset_stats() -> ok.
% Reset all statistics counters and timers
```

### **Connection Management API**

#### `connect_search_connection:request/5`
```erlang
-spec request(Pid :: pid(), Method :: http_method(), Path :: binary(), Headers :: headers(), Body :: body()) -> result().
% Perform synchronous HTTP request to Elasticsearch
% Methods: get | post | put | delete | head | patch
% Example: connect_search_connection:request(Pid, get, <<"/_cluster/health">>, [], <<>>)
```

#### `connect_search_connection:request_async/6`
```erlang
-spec request_async(Pid :: pid(), Method :: http_method(), Path :: binary(), Headers :: headers(), Body :: body(), From :: {pid(), reference()}) -> ok.
% Perform asynchronous HTTP request with result sent to From process
```

#### `connect_search_connection:health_check/1`
```erlang
-spec health_check(Pid :: pid()) -> {ok, healthy | unhealthy} | {error, term()}.
% Check health of specific connection pool
```

#### `connect_search_connection:circuit_breaker_status/1`
```erlang
-spec circuit_breaker_status(Pid :: pid()) -> {ok, open | closed | half_open} | {error, term()}.
% Get circuit breaker status for connection pool
```

### **Supervisor Management API**

#### `connect_search_sup:restart_pool/1`
```erlang
-spec restart_pool(PoolName :: atom()) -> {ok, pid()} | {error, term()}.
% Restart a specific connection pool
% Example: {ok, Pid} = connect_search_sup:restart_pool(primary)
```

---

## 📊 **TYPE DEFINITIONS**

```erlang
-type connection() :: atom().
-type index() :: binary().
-type doc_id() :: binary().
-type document() :: map().
-type query() :: map().
-type options() :: map().
-type request_ref() :: reference().
-type result() :: {ok, map()} | {error, term()}.
-type async_result() :: {ok, request_ref()}.

-type http_method() :: get | post | put | delete | head | patch.
-type headers() :: [{binary(), binary()}].
-type body() :: binary() | iodata().

-type health_status() :: healthy | degraded | unhealthy.
-type health_info() :: #{
    status := health_status(),
    cluster := map(),
    connections := map(), 
    last_check := integer(),
    details := map()
}.

% Connection configuration map
-type connection_config() :: #{
    host => binary(),
    port => integer(),
    scheme => binary(),
    timeout => timeout(),
    pool_size => pos_integer(),
    max_overflow => non_neg_integer(),
    ssl_opts => [term()]
}.
```

---

## ⚠️ **CRITICAL ERROR TYPES & HANDLING**

| **Error** | **Meaning** | **Resolution** |
|-----------|-------------|----------------|
| `{error, connection_timeout}` | Connection to Elasticsearch timed out | Check network connectivity, increase timeout |
| `{error, pool_full}` | All connections in pool are busy | Increase pool_size or max_overflow |
| `{error, circuit_breaker_open}` | Circuit breaker protecting cluster | Wait for recovery or use cached data |
| `{error, index_not_found}` | Elasticsearch index doesn't exist | Create index or verify index name |
| `{error, invalid_json}` | Request/response JSON parsing failed | Validate query structure |
| `{error, {pool_not_found, PoolName}}` | Connection pool doesn't exist | Create pool with add_connection_pool/2 |
| `{error, elasticsearch_down}` | Elasticsearch cluster unavailable | Check cluster health and connectivity |

### **Error Handling Pattern**
```erlang
% Robust error handling for async operations
SearchCallback = fun(Result) ->
    case Result of
        {ok, #{hits := Hits}} ->
            process_search_results(Hits);
        {error, connection_timeout} ->
            log_warning("Search timeout, retrying..."),
            retry_search_later();
        {error, circuit_breaker_open} ->
            log_info("Circuit breaker open, using cached results"),
            use_cached_search_results();
        {error, Reason} ->
            log_error("Search failed: ~p", [Reason]),
            handle_search_error(Reason)
    end
end.
```

---

## 🎯 **USAGE PATTERNS & BEST PRACTICES**

### **Basic Elasticsearch Operations**
```erlang
start_elasticsearch_client() ->
    % Start the application
    {ok, _} = connect_search:start(),
    
    % Connect to cluster
    {ok, primary} = connect_search:connect(#{
        host => <<"localhost">>,
        port => 9200,
        scheme => <<"http">>,
        pool_size => 10
    }).

% Index documents asynchronously for high performance
index_user_async(UserId, UserData) ->
    {ok, _Ref} = connect_search:index_async(<<"users">>, UserId, UserData,
        fun({ok, Result}) ->
            logger:info("User ~s indexed successfully: ~p", [UserId, Result]);
           ({error, Reason}) ->
            logger:error("Failed to index user ~s: ~p", [UserId, Reason])
        end).

% Search with error handling
search_users(Query) ->
    SearchQuery = #{
        query => #{
            bool => #{
                must => [
                    #{match => #{name => Query}}
                ]
            }
        },
        size => 20
    },
    
    {ok, _Ref} = connect_search:search_async(<<"users">>, SearchQuery,
        fun({ok, #{hits := #{hits := Hits}}}) ->
            Users = [maps:get(source, Hit) || Hit <- Hits],
            process_user_results(Users);
           ({error, Reason}) ->
            handle_search_error(Reason)
        end).
```

### **Health Monitoring Integration**
```erlang
setup_health_monitoring() ->
    % Register for health change notifications
    connect_search_health:register_health_callback(fun(Change) ->
        #{old_status := Old, new_status := New} = Change,
        case New of
            unhealthy -> 
                alert_ops_team("Elasticsearch unhealthy", Change),
                switch_to_readonly_mode();
            degraded -> 
                log_warning("Elasticsearch performance degraded", Change);
            healthy when Old =/= healthy -> 
                log_info("Elasticsearch recovered", Change),
                resume_normal_operations();
            _ -> ok
        end
    end).

% Periodic health monitoring
monitor_cluster_health() ->
    spawn(fun() ->
        monitor_loop()
    end).

monitor_loop() ->
    HealthStatus = connect_search:get_health_status(),
    update_metrics_dashboard(HealthStatus),
    timer:sleep(30000), % Check every 30 seconds
    monitor_loop().
```

### **Connection Pool Management**
```erlang
setup_multiple_pools() ->
    % Primary pool for reads/writes
    {ok, primary} = connect_search:add_connection_pool(primary, #{
        host => <<"es-primary.cluster">>,
        port => 9200,
        pool_size => 20,
        max_overflow => 10
    }),
    
    % Analytics pool for heavy queries
    {ok, analytics} = connect_search:add_connection_pool(analytics, #{
        host => <<"es-analytics.cluster">>,
        port => 9200,
        pool_size => 8,
        max_overflow => 4
    }),
    
    % Log pool for logging data
    {ok, logs} = connect_search:add_connection_pool(logs, #{
        host => <<"es-logs.cluster">>,
        port => 9200,
        pool_size => 5,
        max_overflow => 2
    }).

% Route operations to appropriate pools
route_operation(Operation, Index, Data) ->
    Pool = case Index of
        <<"logs-", _/binary>> -> logs;
        <<"analytics-", _/binary>> -> analytics;
        _ -> primary
    end,
    execute_on_pool(Pool, Operation, Index, Data).
```

### **Performance Optimization Patterns**
```erlang
% Batch operations for high throughput
batch_index_documents(Documents) ->
    Refs = [begin
        {ok, Ref} = connect_search:index_async(
            maps:get(index, Doc), 
            maps:get(id, Doc), 
            maps:get(source, Doc),
            fun(Result) -> handle_batch_result(maps:get(id, Doc), Result) end
        ),
        Ref
    end || Doc <- Documents],
    
    {ok, length(Refs)}.

% Concurrent searches
concurrent_search(Queries) ->
    Refs = [begin
        {ok, Ref} = connect_search:search_async(Index, Query, 
            fun(Result) -> collect_search_result(QueryId, Result) end),
        {QueryId, Ref}
    end || {QueryId, Index, Query} <- Queries],
    
    wait_for_search_results(Refs).

% Statistics collection for performance monitoring
collect_performance_metrics() ->
    spawn(fun() ->
        performance_loop()
    end).

performance_loop() ->
    Stats = connect_search:get_stats(),
    PoolStats = connect_search:get_pool_stats(),
    
    % Record key metrics
    connect_search_stats:record_timing(stats_collection, 
        timer:tc(fun() -> 
            update_monitoring_dashboard(Stats, PoolStats)
        end)),
    
    timer:sleep(60000), % Collect every minute
    performance_loop().
```

---

## 🏗️ **ARCHITECTURE UNDERSTANDING**

### **Supervision Tree**
```
connect_search_sup (supervisor)
├── connect_search_stats (gen_server) - Statistics collection
├── connect_search_health (gen_server) - Health monitoring
├── {pool, primary} (connect_search_connection) - Connection pool
├── {pool, analytics} (connect_search_connection) - Optional additional pools
└── connect_search_worker_sup (supervisor) - Worker process management
    ├── connect_search_worker (gen_server) - Async operation workers
    └── ... (dynamic workers)
```

### **Async Operation Flow**
```erlang
% 1. Request async operation
{ok, Ref} = connect_search:search_async(Index, Query, Callback),

% 2. Worker spawned to handle operation
% 3. HTTP request made to Elasticsearch via connection pool
% 4. Response processed and callback executed
% 5. Statistics updated automatically

% No need to manually collect results - callback handles everything
```

### **Connection Pool Behavior**
```erlang
% Pools automatically manage connections
% Circuit breaker protects against failures
% Health checks run automatically
% Statistics collected via persistent terms for zero overhead
```

---

## 🛡️ **SECURITY & RELIABILITY GUIDELINES**

### **Connection Security**
```erlang
% TLS configuration for production
Config = #{
    host => <<"es.production.com">>,
    port => 9200,
    scheme => <<"https">>,
    ssl_opts => [
        {verify, verify_peer},
        {cacertfile, "/etc/ssl/certs/ca-certificates.crt"},
        {versions, ['tlsv1.2', 'tlsv1.3']},
        {ciphers, strong}
    ]
}.
```

### **Input Validation**
```erlang
validate_and_search(Index, Query) when is_binary(Index), is_map(Query) ->
    % Validate query structure
    case validate_query_structure(Query) of
        ok -> connect_search:search(Index, Query);
        {error, _} = Error -> Error
    end;
validate_and_search(_, _) ->
    {error, invalid_parameters}.
```

### **Circuit Breaker Integration**
```erlang
safe_elasticsearch_operation(Fun) ->
    case connect_search:get_health_status() of
        #{status := healthy} ->
            Fun();
        #{status := degraded} ->
            logger:warning("Elasticsearch degraded, operation may be slow"),
            Fun();
        #{status := unhealthy} ->
            {error, elasticsearch_unavailable}
    end.
```

---

## ⚡ **PERFORMANCE CHARACTERISTICS**

- **Throughput**: High with async operations and connection pooling
- **Latency**: Low latency with persistent connection pools
- **Memory**: Efficient with persistent terms statistics storage
- **Startup**: Fast startup with zero external dependencies
- **Scalability**: Horizontal scaling through dynamic pool management
- **Reliability**: Circuit breaker pattern protects against cascading failures

---

## 🔧 **DEVELOPMENT & TESTING**

### **Build Requirements**
- Erlang/OTP 27+
- Rebar3
- Elasticsearch cluster (for integration testing)
- No external Erlang dependencies

### **Manual Testing**
```erlang
% Start in Erlang shell
1> connect_search:start().
{ok, [connect_search]}

2> connect_search:connect(#{host => <<"localhost">>, port => 9200}).
{ok, primary}

3> connect_search:index(<<"test">>, <<"doc1">>, #{message => <<"Hello World">>}).
{ok, #{id => <<"doc1">>, index => <<"test">>, result => <<"created">>, version => 1}}

4> connect_search:get(<<"test">>, <<"doc1">>, #{}).
{ok, #{found => true, id => <<"doc1">>, index => <<"test">>, source => #{message => <<"Hello World">>}}}
```

---

## 💡 **AI CODING GUIDELINES**

### **When to Use This Library**
- ✅ Applications requiring Elasticsearch integration
- ✅ High-performance search applications needing async operations
- ✅ Systems requiring robust connection management and health monitoring
- ✅ Applications needing circuit breaker patterns for resilience
- ✅ Projects wanting zero external dependencies

### **Performance Best Practices**
```erlang
% Use async operations for high throughput
{ok, Ref} = connect_search:index_async(Index, DocId, Doc, Callback),

% Monitor health proactively
connect_search_health:register_health_callback(HealthHandler),

% Use appropriate pool sizing
connect_search:connect(#{pool_size => CPUCount * 2, max_overflow => CPUCount}).
```

### **Integration Pattern**
```erlang
% Always use callbacks for async operations
Callback = fun
    ({ok, Result}) -> handle_success(Result);
    ({error, Reason}) -> handle_error(Reason)
end,

{ok, _Ref} = connect_search:search_async(Index, Query, Callback).
```

### **Error Recovery Strategy**
```erlang
% Implement exponential backoff for retries
retry_operation(Operation, 0) ->
    {error, max_retries_exceeded};
retry_operation(Operation, RetriesLeft) ->
    case Operation() of
        {ok, _} = Success -> Success;
        {error, connection_timeout} ->
            timer:sleep(1000 * (5 - RetriesLeft)), % Exponential backoff
            retry_operation(Operation, RetriesLeft - 1);
        {error, _} = PermanentError -> PermanentError
    end.
```

---

## 📦 **DEPENDENCY & BUILD INFO**

```erlang
% rebar.config
{minimum_otp_vsn, "27"}.
{deps, []}.  % Zero external dependencies!

% Application configuration
{application, connect_search, [
    {description, "ConnectPlatform Elasticsearch - Modern OTP 27 Client"},
    {vsn, "2.0.0"},
    {applications, [kernel, stdlib, inets]}, % Only standard OTP apps
    {env, []}
]}.
```

---

*This library is production-ready with comprehensive async/await patterns, connection pooling, health monitoring, and circuit breaker resilience patterns - all implemented in pure Erlang with zero external dependencies.* 