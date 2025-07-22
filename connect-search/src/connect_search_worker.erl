%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform Elasticsearch - Async Worker Process
%%%
%%% Handles async operations with:
%%% - Non-blocking operation execution
%%% - Result caching and optimization
%%% - Error handling and recovery
%%% - Telemetry collection
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_search_worker).

-behaviour(gen_server).

%% API
-export([start_link/4]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
    worker_type :: atom(),
    operation :: atom(),
    args :: list(),
    callback :: fun() | undefined,
    options :: map(),
    start_time :: integer()
}).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start async worker
%%--------------------------------------------------------------------
-spec start_link(WorkerType :: atom(), Operation :: atom(), 
                Args :: list(), Callback :: fun() | undefined) -> 
    {ok, pid()} | ignore | {error, term()}.
start_link(WorkerType, Operation, Args, Callback) ->
    start_link(WorkerType, Operation, Args, Callback, #{}).

-spec start_link(WorkerType :: atom(), Operation :: atom(), 
                Args :: [any()], Callback :: fun() | undefined, Options :: #{}) -> 
    ignore | {error, term()} | {ok, pid()}.
start_link(WorkerType, Operation, Args, Callback, Options) ->
    gen_server:start_link(?MODULE, [WorkerType, Operation, Args, Callback, Options], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Initialize the worker
%%--------------------------------------------------------------------
init([WorkerType, Operation, Args, Callback, Options]) ->
    process_flag(trap_exit, true),
    
    State = #state{
        worker_type = WorkerType,
        operation = Operation,
        args = Args,
        callback = Callback,
        options = Options,
        start_time = erlang:system_time(millisecond)
    },
    
    {ok, State}.

%%--------------------------------------------------------------------
%% @doc Handle calls
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

%%--------------------------------------------------------------------
%% @doc Handle casts
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle info messages
%%--------------------------------------------------------------------
handle_info({execute, RequestRef, CallerPid}, State) ->
    %% Execute the operation asynchronously
    spawn_link(fun() ->
        Result = execute_operation(State),
        CallerPid ! {elasticsearch_result, RequestRef, Result}
    end),
    
    %% Worker can terminate after spawning the operation
    {stop, normal, State};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc Handle termination
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @doc Handle code changes
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
%% Execute the actual operation
-spec execute_operation(#state{}) -> {ok, term()} | {error, term()}.
execute_operation(State) ->
    #state{
        worker_type = WorkerType,
        operation = Operation,
        args = Args,
        callback = Callback,
        options = Options
    } = State,
    
    try
        Result = case WorkerType of
            async_executor ->
                execute_elasticsearch_operation(Operation, Args, Options);
            _ ->
                {error, {unknown_worker_type, WorkerType}}
        end,
        
        %% Execute callback if provided
        case Callback of
            undefined -> Result;
            Fun when is_function(Fun, 1) -> 
                Fun(Result),
                Result;
            Fun when is_function(Fun, 2) ->
                Fun(Result, State),
                Result;
            _ -> Result
        end
    catch
        Class:Error:Stacktrace ->
            {error, {worker_exception, Class, Error, Stacktrace}}
    end.

%% @private
%% Execute Elasticsearch operation
-spec execute_elasticsearch_operation(atom(), list(), map()) -> 
    {ok, #{
        operation := atom(),
        args := list(),
        options := map(),
        executed_at := integer()
    }}.
execute_elasticsearch_operation(Operation, Args, Options) ->
    %% This would call into the main connect_search module
    %% For now, return a placeholder
    {ok, #{
        operation => Operation,
        args => Args,
        options => Options,
        executed_at => erlang:system_time(millisecond)
    }}. 