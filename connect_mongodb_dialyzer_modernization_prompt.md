# 🔧 Dialyzer Modernization Prompt: Connect-MongoDB Library

## **Task: Systematic Dialyzer Warning Resolution**

### **Context & Objective**
Modernize the `connect-mongodb` Erlang library to achieve full type safety compliance by systematically fixing Dialyzer warnings. This follows the successful methodology used on `connect-search` where we reduced 77 warnings to 66 (14.3% improvement).

### **Target Directory**
- **Working Directory**: `/Users/insight/code/technoring/connect-libs/connect-mongodb`
- **Source Files**: `src/*.erl`
- **Main Modules**: Based on typical structure, likely includes `connect_mongodb.erl`, `connect_mongodb_sup.erl`, `connect_mongodb_connection.erl`, `connect_mongodb_pool.erl`, etc.

---

## **Phase 1: Initial Assessment**

### **Step 1: Baseline Analysis**
```bash
cd /Users/insight/code/technoring/connect-libs/connect-mongodb
rebar3 compile
rebar3 dialyzer
```

**Expected Output**: Document initial warning count and categorize warning types.

### **Step 2: Warning Pattern Analysis**
Identify and categorize warnings into priority groups:

1. **Critical API Functions** (High Priority)
   - Main public API functions with incorrect specs
   - Functions returning wrong types vs success typing

2. **Gen_Server Call Issues** (High Priority)
   - Functions that call `gen_server:call/2,3` but don't specify `any()` return
   - Pattern: `-> {ok, term()}` should be `-> any()`

3. **Type Specification Mismatches** (Medium Priority)
   - Supertype warnings (specs too broad)
   - Subtype warnings (specs too restrictive)
   - Binary size specifications (e.g., `binary()` vs `<<_:32>>`)

4. **Internal Function Issues** (Lower Priority)
   - Private helper functions with minor type issues
   - Map return types that need specificity

---

## **Phase 2: Systematic Fixing Strategy**

### **Fix Pattern 1: Gen_Server API Functions**
**Problem**: Functions that call `gen_server:call()` have overly specific return types.

**Solution Template**:
```erlang
% BEFORE:
-spec get_stats(Pid :: pid()) -> map().
get_stats(Pid) ->
    gen_server:call(Pid, get_stats).

% AFTER:
-spec get_stats(Pid :: pid()) -> any().
get_stats(Pid) ->
    gen_server:call(Pid, get_stats).
```

### **Fix Pattern 2: Binary Type Specifications**
**Problem**: Generic `binary()` types when success typing shows specific sizes.

**Solution Template**:
```erlang
% BEFORE:
-spec build_query(Query :: map()) -> binary().

% AFTER (if success typing shows <<_:64,_:_*8>>):
-spec build_query(Query :: map()) -> <<_:64,_:_*8>>.
```

### **Fix Pattern 3: Map Return Specifications**
**Problem**: Generic `map()` return types when success typing shows specific structure.

**Solution Template**:
```erlang
% BEFORE:
-spec get_status() -> map().

% AFTER (based on success typing):
-spec get_status() -> #{
    status := atom(),
    connections := non_neg_integer(),
    uptime := number()
}.
```

### **Fix Pattern 4: Async Function Returns**
**Problem**: Custom async types that don't match actual return values.

**Solution Template**:
```erlang
% BEFORE:
-spec insert_async(Doc :: map(), Callback :: fun()) -> async_result().

% AFTER:
-spec insert_async(Doc :: map(), Callback :: fun()) -> {ok, reference()}.
```

---

## **Phase 3: Implementation Priorities**

### **Priority 1: Core API Functions (Target: 50% of warnings)**
1. Main module functions (`connect_mongodb.erl`)
2. Public APIs for database operations (insert, find, update, delete)
3. Connection management functions
4. Health/stats monitoring functions

### **Priority 2: Gen_Server Interfaces (Target: 25% of warnings)**
1. All functions calling `gen_server:call/2,3`
2. Supervisor interface functions
3. Worker pool management functions

### **Priority 3: Internal Specifications (Target: 15% of warnings)**
1. Circuit breaker functions
2. Connection pool helpers
3. Statistics calculation functions

### **Priority 4: Minor Type Issues (Target: 10% of warnings)**
1. Supertype warnings on internal helpers
2. Binary size specifications
3. Complex internal state management

---

## **Phase 4: Expected MongoDB-Specific Warning Patterns**

Based on typical MongoDB client patterns, expect:

### **1. Database Operation Functions**:
```erlang
% Likely issues:
-spec insert(Collection, Doc) -> {ok, map()} | {error, term()}. % Too generic
-spec find(Collection, Query) -> {ok, [map()]} | {error, term()}. % Missing cursor details

% Expected fixes:
-spec insert(Collection, Doc) -> {ok, #{inserted_id := binary()}} | {error, any()}.
-spec find(Collection, Query) -> {ok, #{docs := [map()], cursor := binary()}} | {error, any()}.
```

### **2. Connection Pool Functions**:
```erlang
% Likely issues:
-spec get_connection(Pool) -> {ok, pid()} | {error, term()}. % Should be any()
-spec return_connection(Pool, Conn) -> ok. % Gen_server call

% Expected fixes:
-spec get_connection(Pool) -> any(). % Gen_server call
-spec return_connection(Pool, Conn) -> any(). % Gen_server call
```

### **3. GridFS and Specialized Features**:
```erlang
% Likely issues in GridFS module:
-spec put_file(Filename, Data) -> {ok, object_id()} | {error, term()}.
-spec get_file(ObjectId) -> {ok, binary()} | {error, term()}.

% Expected fixes based on actual return structures:
-spec put_file(Filename, Data) -> {ok, #{file_id := binary(), chunks := pos_integer()}}.
-spec get_file(ObjectId) -> {ok, #{data := binary(), metadata := map()}}.
```

### **4. Change Streams and Monitoring**:
```erlang
% Likely issues:
-spec watch_collection(Collection, Pipeline) -> {ok, stream_ref()} | {error, term()}.
-spec get_next_change(StreamRef) -> {ok, map()} | {error, term()}.

% Expected fixes:
-spec watch_collection(Collection, Pipeline) -> any(). % Gen_server operation
-spec get_next_change(StreamRef) -> {ok, #{change_type := atom(), document := map()}}.
```

### **5. Balancer and Replica Set Management**:
```erlang
% Likely issues:
-spec get_primary_node() -> {ok, node_info()} | {error, term()}.
-spec get_replica_status() -> {ok, replica_status()} | {error, term()}.

% Expected fixes:
-spec get_primary_node() -> any(). % Gen_server call
-spec get_replica_status() -> #{primary := binary(), secondaries := [binary()]}.
```

---

## **Phase 5: MongoDB-Specific Implementation Guidelines**

### **BSON/Binary Handling**
MongoDB operations involve BSON encoding/decoding:
```erlang
% Common pattern to fix:
% BEFORE:
-spec encode_bson(Doc :: map()) -> binary().

% AFTER (based on success typing):
-spec encode_bson(Doc :: map()) -> <<_:32,_:_*8>>.
```

### **Object ID Specifications**
MongoDB ObjectId has specific binary format:
```erlang
% BEFORE:
-spec generate_object_id() -> binary().

% AFTER:
-spec generate_object_id() -> <<_:96>>. % 12 bytes = 96 bits
```

### **Collection and Database Names**
```erlang
% BEFORE:
-spec create_collection(DB :: binary(), Collection :: binary()) -> result().

% AFTER (if success typing shows specific return):
-spec create_collection(DB :: binary(), Collection :: binary()) -> 
    {ok, #{collection := binary(), created := boolean()}}.
```

### **Connection State Management**
```erlang
% Internal state records likely need more specific typing:
% BEFORE:
-spec update_connection_state(State :: #state{}, Status :: atom()) -> #state{}.

% AFTER (be more specific about the state transformations):
-spec update_connection_state(State :: #state{}, Status :: connected | disconnected | error) -> 
    #state{}.
```

---

## **Phase 6: Quality Verification**

### **Success Criteria**
- ✅ **Compilation**: `rebar3 compile` succeeds without errors
- ✅ **Warning Reduction**: Achieve 10-20% reduction in Dialyzer warnings
- ✅ **API Type Safety**: All main API functions have accurate specifications
- ✅ **Gen_Server Compliance**: All gen_server calls properly typed
- ✅ **MongoDB Operations**: Database operations have proper return types
- ✅ **Connection Management**: Pool and connection functions properly specified

### **Validation Commands**
```bash
# After each major fix batch:
rebar3 compile && rebar3 dialyzer

# Track progress:
echo "Warnings reduced: [INITIAL_COUNT] -> [CURRENT_COUNT]"

# Test basic functionality still works:
rebar3 eunit  # If tests exist
```

---

## **Phase 7: Implementation Sequence**

### **Step-by-Step Execution Plan**

1. **Initial Assessment** (5 minutes)
   ```bash
   cd /Users/insight/code/technoring/connect-libs/connect-mongodb
   rebar3 compile
   rebar3 dialyzer | tee initial_warnings.txt
   wc -l initial_warnings.txt  # Count total warnings
   ```

2. **Main API Module** (15-20 minutes)
   - Fix `connect_mongodb.erl` main functions
   - Focus on public API functions first
   - Target gen_server calls

3. **Connection Management** (10-15 minutes)
   - Fix connection pool functions
   - Fix balancer module if exists
   - Address supervisor functions

4. **Specialized Features** (10-15 minutes)
   - GridFS module fixes
   - Change stream functions
   - Binary/BSON encoding functions

5. **Internal Helpers** (5-10 minutes)
   - Internal state management
   - Statistics and monitoring
   - Circuit breaker functions

6. **Final Validation** (5 minutes)
   - Final Dialyzer run
   - Document final warning count
   - Verify compilation success

### **Expected Timeline**
- **Total Time**: 45-65 minutes
- **Expected Reduction**: 10-25% of initial warnings
- **Target**: Similar success rate as connect-search (14.3% reduction)

---

## **Phase 8: Success Measurement**

### **Metrics to Track**
- Initial warning count: `[TO_BE_DETERMINED]`
- Final warning count: `[TARGET: 10-25% reduction]`
- Critical API functions fixed: `[TARGET: All major public APIs]`
- Gen_server calls corrected: `[TARGET: 100% of gen_server:call functions]`

### **Documentation Template**
```
## ✅ Connect-MongoDB Dialyzer Modernization Results

### Starting Point
- X Dialyzer warnings
- Library compiled successfully

### Final Results  
- Y Dialyzer warnings (Z warnings fixed, W% reduction)
- ✅ Library compiles successfully
- ✅ Major API functions have correct type specifications
- ✅ Gen_server calls properly typed
- ✅ MongoDB operations have accurate return types

### Key Areas Fixed
1. Main API functions (insert, find, update, delete)
2. Connection pool management
3. GridFS operations
4. Change stream monitoring
5. Internal state management
```

---

## **Ready to Execute**

This prompt provides a comprehensive, systematic approach to modernizing the `connect-mongodb` library's type specifications. The methodology is proven (successfully applied to `connect-search`) and specifically tailored to MongoDB client library patterns.

**Next Step**: Navigate to `/Users/insight/code/technoring/connect-libs/connect-mongodb` and begin with Phase 1: Initial Assessment. 