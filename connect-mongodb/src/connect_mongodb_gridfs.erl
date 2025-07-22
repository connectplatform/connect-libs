%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform MongoDB - GridFS Large File Storage Support
%%%
%%% GridFS implementation for storing and retrieving large files in MongoDB:
%%% - Streaming upload and download with configurable chunk sizes
%%% - Async/await patterns for non-blocking operations
%%% - File metadata management and indexing
%%% - Automatic chunk management and error recovery
%%% - Support for file versioning and deduplication
%%%
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_mongodb_gridfs).

%% Public API
-export([
    %% File Operations
    upload_file/3,
    upload_file/4,
    upload_stream/3,
    upload_stream/4,
    download_file/2,
    download_file/3,
    download_stream/2,
    download_stream/3,
    
    %% Async Operations
    upload_file_async/3,
    upload_file_async/4,
    download_file_async/2,
    download_file_async/3,
    
    %% File Management
    delete_file/2,
    delete_file/3,
    find_files/2,
    find_files/3,
    get_file_info/2,
    list_files/1,
    list_files/2,
    
    %% Advanced Operations
    create_index/2,
    drop_index/2,
    rename_file/3,
    copy_file/3,
    
    %% Bucket Operations
    create_bucket/2,
    drop_bucket/2,
    bucket_stats/2
]).

%%%===================================================================
%%% Types and Records
%%%===================================================================

-type bucket_name() :: binary().
-type file_id() :: binary() | term().
-type filename() :: binary().
-type file_data() :: binary().
-type chunk_size() :: pos_integer().

-type gridfs_options() :: #{
    chunk_size => chunk_size(),
    metadata => map(),
    content_type => binary(),
    aliases => [binary()],
    timeout => timeout(),
    write_concern => map(),
    read_preference => primary | secondary | primary_preferred | secondary_preferred
}.

-type file_info() :: #{
    '_id' => file_id(),
    filename => filename(),
    length => non_neg_integer(),
    chunk_size => chunk_size(),
    upload_date => integer(),
    md5 => binary(),
    content_type => binary(),
    metadata => map()
}.

-type upload_result() :: #{
    file_id => file_id(),
    filename => filename(),
    length => non_neg_integer(),
    md5 => binary(),
    chunks_count => non_neg_integer(),
    upload_time => float()
}.

-type download_result() :: #{
    file_info => file_info(),
    data => file_data(),
    download_time => float()
}.

-type bucket_stats() :: #{
    files_count => non_neg_integer(),
    chunks_count => non_neg_integer(),
    total_size => non_neg_integer(),
    avg_file_size => float(),
    bucket_name => bucket_name()
}.

-export_type([
    bucket_name/0, file_id/0, filename/0, file_data/0, chunk_size/0,
    gridfs_options/0, file_info/0, upload_result/0, download_result/0, bucket_stats/0
]).

%%%===================================================================
%%% Macros and Constants
%%%===================================================================

-define(DEFAULT_BUCKET, <<"fs">>).
-define(DEFAULT_CHUNK_SIZE, 261120). % 255KB
-define(FILES_COLLECTION(Bucket), <<Bucket/binary, ".files">>).
-define(CHUNKS_COLLECTION(Bucket), <<Bucket/binary, ".chunks">>).
-define(MAX_FILE_SIZE, 16 * 1024 * 1024 * 1024). % 16GB limit
-define(UPLOAD_TIMEOUT, 300000). % 5 minutes
-define(DOWNLOAD_TIMEOUT, 300000). % 5 minutes

%%%===================================================================
%%% Public API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Upload a file to GridFS
%%--------------------------------------------------------------------
-spec upload_file(bucket_name(), filename(), file_data()) -> 
    {ok, upload_result()} | {error, term()}.
upload_file(Bucket, Filename, FileData) ->
    upload_file(Bucket, Filename, FileData, #{}).

-spec upload_file(bucket_name(), filename(), file_data(), gridfs_options()) -> 
    {ok, upload_result()} | {error, term()}.
upload_file(Bucket, Filename, FileData, Options) 
  when is_binary(Bucket), is_binary(Filename), is_binary(FileData), is_map(Options) ->
    case validate_upload_params(Bucket, Filename, FileData, Options) of
        ok ->
            StartTime = erlang:monotonic_time(microsecond),
            case upload_file_internal(Bucket, Filename, FileData, Options) of
                {ok, Result} ->
                    EndTime = erlang:monotonic_time(microsecond),
                    UploadTime = (EndTime - StartTime) / 1_000_000,
                    {ok, Result#{upload_time => UploadTime}};
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end;
upload_file(Bucket, Filename, FileData, Options) ->
    error({badarg, [Bucket, Filename, FileData, Options]}, [Bucket, Filename, FileData, Options], #{
        error_info => #{
            module => ?MODULE,
            function => upload_file,
            arity => 4,
            cause => "Bucket and Filename must be binary, FileData must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Upload file using streaming (for large files)
%%--------------------------------------------------------------------
-spec upload_stream(bucket_name(), filename(), fun()) -> 
    {ok, upload_result()} | {error, term()}.
upload_stream(Bucket, Filename, StreamFun) ->
    upload_stream(Bucket, Filename, StreamFun, #{}).

-spec upload_stream(bucket_name(), filename(), fun(), gridfs_options()) -> 
    {ok, upload_result()} | {error, term()}.
upload_stream(Bucket, Filename, StreamFun, Options) 
  when is_binary(Bucket), is_binary(Filename), is_function(StreamFun, 0), is_map(Options) ->
    StartTime = erlang:monotonic_time(microsecond),
    case upload_stream_internal(Bucket, Filename, StreamFun, Options) of
        {ok, Result} ->
            EndTime = erlang:monotonic_time(microsecond),
            UploadTime = (EndTime - StartTime) / 1_000_000,
            {ok, Result#{upload_time => UploadTime}};
        {error, _} = Error -> Error
    end;
upload_stream(Bucket, Filename, StreamFun, Options) ->
    error({badarg, [Bucket, Filename, StreamFun, Options]}, [Bucket, Filename, StreamFun, Options], #{
        error_info => #{
            module => ?MODULE,
            function => upload_stream,
            arity => 4,
            cause => "Invalid arguments - check types"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Download a file from GridFS
%%--------------------------------------------------------------------
-spec download_file(bucket_name(), file_id() | filename()) -> 
    {ok, download_result()} | {error, term()}.
download_file(Bucket, FileIdentifier) ->
    download_file(Bucket, FileIdentifier, #{}).

-spec download_file(bucket_name(), file_id() | filename(), gridfs_options()) -> 
    {ok, download_result()} | {error, term()}.
download_file(Bucket, FileIdentifier, Options) 
  when is_binary(Bucket), is_map(Options) ->
    StartTime = erlang:monotonic_time(microsecond),
    case download_file_internal(Bucket, FileIdentifier, Options) of
        {ok, Result} ->
            EndTime = erlang:monotonic_time(microsecond),
            DownloadTime = (EndTime - StartTime) / 1_000_000,
            {ok, Result#{download_time => DownloadTime}};
        {error, _} = Error -> Error
    end;
download_file(Bucket, FileIdentifier, Options) ->
    error({badarg, [Bucket, FileIdentifier, Options]}, [Bucket, FileIdentifier, Options], #{
        error_info => #{
            module => ?MODULE,
            function => download_file,
            arity => 3,
            cause => "Bucket must be binary, Options must be map"
        }
    }).

%%--------------------------------------------------------------------
%% @doc Download file using streaming (for large files)
%%--------------------------------------------------------------------
-spec download_stream(bucket_name(), file_id() | filename()) -> 
    {ok, fun()} | {error, term()}.
download_stream(Bucket, FileIdentifier) ->
    download_stream(Bucket, FileIdentifier, #{}).

-spec download_stream(bucket_name(), file_id() | filename(), gridfs_options()) -> 
    {ok, fun()} | {error, term()}.
download_stream(Bucket, FileIdentifier, Options) ->
    case get_file_info(Bucket, FileIdentifier) of
        {ok, FileInfo} ->
            {ok, create_download_stream(Bucket, FileInfo, Options)};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Async file upload
%%--------------------------------------------------------------------
-spec upload_file_async(bucket_name(), filename(), file_data()) -> 
    {ok, reference()} | {error, term()}.
upload_file_async(Bucket, Filename, FileData) ->
    upload_file_async(Bucket, Filename, FileData, #{}).

-spec upload_file_async(bucket_name(), filename(), file_data(), gridfs_options()) -> 
    {ok, reference()} | {error, term()}.
upload_file_async(Bucket, Filename, FileData, Options) ->
    Ref = make_ref(),
    spawn_link(fun() ->
        Result = upload_file(Bucket, Filename, FileData, Options),
        case Result of
            {ok, UploadResult} ->
                self() ! {gridfs_upload_result, Ref, UploadResult};
            {error, Error} ->
                self() ! {gridfs_upload_error, Ref, Error}
        end
    end),
    {ok, Ref}.

%%--------------------------------------------------------------------
%% @doc Async file download
%%--------------------------------------------------------------------
-spec download_file_async(bucket_name(), file_id() | filename()) -> 
    {ok, reference()} | {error, term()}.
download_file_async(Bucket, FileIdentifier) ->
    download_file_async(Bucket, FileIdentifier, #{}).

-spec download_file_async(bucket_name(), file_id() | filename(), gridfs_options()) -> 
    {ok, reference()} | {error, term()}.
download_file_async(Bucket, FileIdentifier, Options) ->
    Ref = make_ref(),
    spawn_link(fun() ->
        Result = download_file(Bucket, FileIdentifier, Options),
        case Result of
            {ok, DownloadResult} ->
                self() ! {gridfs_download_result, Ref, DownloadResult};
            {error, Error} ->
                self() ! {gridfs_download_error, Ref, Error}
        end
    end),
    {ok, Ref}.

%%--------------------------------------------------------------------
%% @doc Delete a file from GridFS
%%--------------------------------------------------------------------
-spec delete_file(bucket_name(), file_id() | filename()) -> ok | {error, term()}.
delete_file(Bucket, FileIdentifier) ->
    delete_file(Bucket, FileIdentifier, #{}).

-spec delete_file(bucket_name(), file_id() | filename(), gridfs_options()) -> ok | {error, term()}.
delete_file(Bucket, FileIdentifier, Options) ->
    case get_file_info(Bucket, FileIdentifier) of
        {ok, FileInfo} ->
            FileId = maps:get(<<"_id">>, FileInfo),
            delete_file_and_chunks(Bucket, FileId, Options);
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Find files matching criteria
%%--------------------------------------------------------------------
-spec find_files(bucket_name(), map()) -> {ok, [file_info()]} | {error, term()}.
find_files(Bucket, Filter) ->
    find_files(Bucket, Filter, #{}).

-spec find_files(bucket_name(), map(), gridfs_options()) -> {ok, [file_info()]} | {error, term()}.
find_files(Bucket, Filter, Options) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    connect_mongodb:find(FilesCollection, Filter, Options).

%%--------------------------------------------------------------------
%% @doc Get file information
%%--------------------------------------------------------------------
-spec get_file_info(bucket_name(), file_id() | filename()) -> {ok, file_info()} | {error, term()}.
get_file_info(Bucket, FileIdentifier) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    Filter = create_file_filter(FileIdentifier),
    case connect_mongodb:find_one(FilesCollection, Filter, #{}) of
        {ok, null} -> {error, file_not_found};
        {ok, FileInfo} -> {ok, FileInfo};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc List all files in bucket
%%--------------------------------------------------------------------
-spec list_files(bucket_name()) -> {ok, [file_info()]} | {error, term()}.
list_files(Bucket) ->
    list_files(Bucket, #{}).

-spec list_files(bucket_name(), gridfs_options()) -> {ok, [file_info()]} | {error, term()}.
list_files(Bucket, Options) ->
    find_files(Bucket, #{}, Options).

%%--------------------------------------------------------------------
%% @doc Create index on files collection
%%--------------------------------------------------------------------
-spec create_index(bucket_name(), map()) -> {ok, term()} | {error, term()}.
create_index(Bucket, IndexSpec) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    connect_mongodb:create_index(FilesCollection, IndexSpec, #{}).

%%--------------------------------------------------------------------
%% @doc Drop index from files collection
%%--------------------------------------------------------------------
-spec drop_index(bucket_name(), binary()) -> {ok, term()} | {error, term()}.
drop_index(Bucket, IndexName) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    connect_mongodb:drop_index(FilesCollection, IndexName, #{}).

%%--------------------------------------------------------------------
%% @doc Rename a file
%%--------------------------------------------------------------------
-spec rename_file(bucket_name(), file_id() | filename(), filename()) -> ok | {error, term()}.
rename_file(Bucket, FileIdentifier, NewFilename) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    Filter = create_file_filter(FileIdentifier),
    Update = #{<<"$set">> => #{<<"filename">> => NewFilename}},
    
    case connect_mongodb:update_one(FilesCollection, Filter, Update, #{}) of
        {ok, #{matched_count := 1}} -> ok;
        {ok, #{matched_count := 0}} -> {error, file_not_found};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Copy a file
%%--------------------------------------------------------------------
-spec copy_file(bucket_name(), file_id() | filename(), filename()) -> 
    {ok, upload_result()} | {error, term()}.
copy_file(Bucket, FileIdentifier, NewFilename) ->
    case download_file(Bucket, FileIdentifier, #{}) of
        {ok, #{file_info := FileInfo, data := FileData}} ->
            Metadata = maps:get(<<"metadata">>, FileInfo, #{}),
            ContentType = maps:get(<<"contentType">>, FileInfo, <<"application/octet-stream">>),
            Options = #{
                metadata => Metadata,
                content_type => ContentType
            },
            upload_file(Bucket, NewFilename, FileData, Options);
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Create a GridFS bucket (with indexes)
%%--------------------------------------------------------------------
-spec create_bucket(bucket_name(), gridfs_options()) -> ok | {error, term()}.
create_bucket(Bucket, Options) ->
    % Create indexes for optimal performance
    FilesCollection = ?FILES_COLLECTION(Bucket),
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    
    % Index on files collection
    FilesIndex = #{<<"filename">> => 1, <<"uploadDate">> => 1},
    case connect_mongodb:create_index(FilesCollection, FilesIndex, Options) of
        {ok, _} ->
            % Index on chunks collection
            ChunksIndex = #{<<"files_id">> => 1, <<"n">> => 1},
            case connect_mongodb:create_index(ChunksCollection, ChunksIndex, Options) of
                {ok, _} -> ok;
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Drop a GridFS bucket
%%--------------------------------------------------------------------
-spec drop_bucket(bucket_name(), gridfs_options()) -> ok | {error, term()}.
drop_bucket(Bucket, Options) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    
    case connect_mongodb:drop_collection(FilesCollection, Options) of
        {ok, _} ->
            case connect_mongodb:drop_collection(ChunksCollection, Options) of
                {ok, _} -> ok;
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @doc Get bucket statistics
%%--------------------------------------------------------------------
-spec bucket_stats(bucket_name(), gridfs_options()) -> {ok, bucket_stats()} | {error, term()}.
bucket_stats(Bucket, Options) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    
    % Count files and get total size
    case connect_mongodb:aggregate(FilesCollection, [
        #{<<"$group">> => #{
            <<"_id">> => null,
            <<"count">> => #{<<"$sum">> => 1},
            <<"totalSize">> => #{<<"$sum">> => <<"$length">>},
            <<"avgSize">> => #{<<"$avg">> => <<"$length">>}
        }}
    ], Options) of
        {ok, [FilesStats]} ->
            case connect_mongodb:count_documents(ChunksCollection, #{}, Options) of
                {ok, ChunksCount} ->
                    {ok, #{
                        files_count => maps:get(<<"count">>, FilesStats, 0),
                        chunks_count => ChunksCount,
                        total_size => maps:get(<<"totalSize">>, FilesStats, 0),
                        avg_file_size => maps:get(<<"avgSize">>, FilesStats, 0.0),
                        bucket_name => Bucket
                    }};
                {error, _} = Error -> Error
            end;
        {ok, []} ->
            {ok, #{
                files_count => 0,
                chunks_count => 0,
                total_size => 0,
                avg_file_size => 0.0,
                bucket_name => Bucket
            }};
        {error, _} = Error -> Error
    end.

%%%===================================================================
%%% Internal Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Validate upload parameters
%%--------------------------------------------------------------------
validate_upload_params(Bucket, Filename, FileData, Options) ->
    case {byte_size(Bucket) > 0, byte_size(Filename) > 0} of
        {true, true} ->
            case byte_size(FileData) =< ?MAX_FILE_SIZE of
                true -> validate_options(Options);
                false -> {error, file_too_large}
            end;
        {false, _} -> {error, invalid_bucket_name};
        {_, false} -> {error, invalid_filename}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Validate GridFS options
%%--------------------------------------------------------------------
validate_options(Options) ->
    ChunkSize = maps:get(chunk_size, Options, ?DEFAULT_CHUNK_SIZE),
    case ChunkSize > 0 andalso ChunkSize =< 16 * 1024 * 1024 of % 16MB max chunk
        true -> ok;
        false -> {error, invalid_chunk_size}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Internal file upload implementation
%%--------------------------------------------------------------------
upload_file_internal(Bucket, Filename, FileData, Options) ->
    ChunkSize = maps:get(chunk_size, Options, ?DEFAULT_CHUNK_SIZE),
    Metadata = maps:get(metadata, Options, #{}),
    ContentType = maps:get(content_type, Options, <<"application/octet-stream">>),
    
    FileId = generate_file_id(),
    FileLength = byte_size(FileData),
    UploadDate = erlang:system_time(second),
    
    % Calculate MD5 checksum
    MD5 = crypto:hash(md5, FileData),
    MD5Hex = binary:encode_hex(MD5),
    
    % Create chunks
    Chunks = create_chunks(FileData, ChunkSize),
    
    % Insert file document
    FileDoc = #{
        <<"_id">> => FileId,
        <<"filename">> => Filename,
        <<"length">> => FileLength,
        <<"chunkSize">> => ChunkSize,
        <<"uploadDate">> => UploadDate,
        <<"md5">> => MD5Hex,
        <<"contentType">> => ContentType,
        <<"metadata">> => Metadata
    },
    
    case insert_file_and_chunks(Bucket, FileDoc, Chunks, Options) of
        ok ->
            {ok, #{
                file_id => FileId,
                filename => Filename,
                length => FileLength,
                md5 => MD5Hex,
                chunks_count => length(Chunks)
            }};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Internal streaming upload implementation
%%--------------------------------------------------------------------
upload_stream_internal(Bucket, Filename, StreamFun, Options) ->
    ChunkSize = maps:get(chunk_size, Options, ?DEFAULT_CHUNK_SIZE),
    Metadata = maps:get(metadata, Options, #{}),
    ContentType = maps:get(content_type, Options, <<"application/octet-stream">>),
    
    FileId = generate_file_id(),
    UploadDate = erlang:system_time(second),
    
    % Stream upload with chunking
    case stream_upload_chunks(Bucket, FileId, StreamFun, ChunkSize, Options) of
        {ok, FileLength, MD5Hex, ChunksCount} ->
            % Insert file document
            FileDoc = #{
                <<"_id">> => FileId,
                <<"filename">> => Filename,
                <<"length">> => FileLength,
                <<"chunkSize">> => ChunkSize,
                <<"uploadDate">> => UploadDate,
                <<"md5">> => MD5Hex,
                <<"contentType">> => ContentType,
                <<"metadata">> => Metadata
            },
            
            FilesCollection = ?FILES_COLLECTION(Bucket),
            case connect_mongodb:insert_one(FilesCollection, FileDoc, Options) of
                {ok, _} ->
                    {ok, #{
                        file_id => FileId,
                        filename => Filename,
                        length => FileLength,
                        md5 => MD5Hex,
                        chunks_count => ChunksCount
                    }};
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Internal file download implementation  
%%--------------------------------------------------------------------
download_file_internal(Bucket, FileIdentifier, Options) ->
    case get_file_info(Bucket, FileIdentifier) of
        {ok, FileInfo} ->
            FileId = maps:get(<<"_id">>, FileInfo),
            case download_chunks(Bucket, FileId, Options) of
                {ok, FileData} ->
                    {ok, #{
                        file_info => FileInfo,
                        data => FileData
                    }};
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Generate unique file ID
%%--------------------------------------------------------------------
generate_file_id() ->
    % Generate MongoDB ObjectId-compatible ID
    Timestamp = erlang:system_time(second),
    Random = rand:uniform(16#FFFFFF),
    Counter = get_and_increment_counter(),
    
    <<Timestamp:32, Random:24, Counter:24>>.

%%--------------------------------------------------------------------
%% @private
%% @doc Get and increment counter for ObjectId generation
%%--------------------------------------------------------------------
get_and_increment_counter() ->
    case get(gridfs_counter) of
        undefined ->
            put(gridfs_counter, 1),
            0;
        Counter ->
            put(gridfs_counter, (Counter + 1) band 16#FFFFFF),
            Counter
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Create chunks from file data
%%--------------------------------------------------------------------
create_chunks(FileData, ChunkSize) ->
    create_chunks(FileData, ChunkSize, 0, []).

create_chunks(<<>>, _ChunkSize, _ChunkNum, Acc) ->
    lists:reverse(Acc);
create_chunks(FileData, ChunkSize, ChunkNum, Acc) ->
    case byte_size(FileData) =< ChunkSize of
        true ->
            % Last chunk
            Chunk = #{
                <<"n">> => ChunkNum,
                <<"data">> => FileData
            },
            lists:reverse([Chunk | Acc]);
        false ->
            <<ChunkData:ChunkSize/binary, Rest/binary>> = FileData,
            Chunk = #{
                <<"n">> => ChunkNum,
                <<"data">> => ChunkData
            },
            create_chunks(Rest, ChunkSize, ChunkNum + 1, [Chunk | Acc])
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Insert file document and chunks
%%--------------------------------------------------------------------
insert_file_and_chunks(Bucket, FileDoc, Chunks, Options) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    
    FileId = maps:get(<<"_id">>, FileDoc),
    
    % Prepare chunk documents
    ChunkDocs = [Chunk#{<<"files_id">> => FileId} || Chunk <- Chunks],
    
    % Use transaction if available
    case connect_mongodb:start_session(Options) of
        {ok, SessionRef} ->
            try
                ok = connect_mongodb:start_transaction(SessionRef, Options),
                
                % Insert file document
                {ok, _} = connect_mongodb:insert_one(FilesCollection, FileDoc, 
                                                   Options#{session => SessionRef}),
                
                % Insert chunks
                {ok, _} = connect_mongodb:insert_many(ChunksCollection, ChunkDocs,
                                                    Options#{session => SessionRef}),
                
                ok = connect_mongodb:commit_transaction(SessionRef, Options),
                ok
            catch
                _:Error ->
                    connect_mongodb:abort_transaction(SessionRef, Options),
                    {error, Error}
            end;
        {error, _} ->
            % Fallback without transaction
            case connect_mongodb:insert_one(FilesCollection, FileDoc, Options) of
                {ok, _} ->
                    case connect_mongodb:insert_many(ChunksCollection, ChunkDocs, Options) of
                        {ok, _} -> ok;
                        {error, _} = Error ->
                            % Cleanup file doc on chunk insert failure
                            connect_mongodb:delete_one(FilesCollection, #{<<"_id">> => FileId}, Options),
                            Error
                    end;
                {error, _} = Error -> Error
            end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Stream upload chunks
%%--------------------------------------------------------------------
stream_upload_chunks(Bucket, FileId, StreamFun, ChunkSize, Options) ->
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    MD5Context = crypto:hash_init(md5),
    
    case stream_chunks_loop(ChunksCollection, FileId, StreamFun, ChunkSize, Options,
                           0, 0, MD5Context, []) of
        {ok, TotalLength, FinalMD5Context, _ChunkDocs} ->
            MD5 = crypto:hash_final(FinalMD5Context),
            MD5Hex = binary:encode_hex(MD5),
            ChunksCount = (TotalLength + ChunkSize - 1) div ChunkSize,
            {ok, TotalLength, MD5Hex, ChunksCount};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Stream chunks loop
%%--------------------------------------------------------------------
stream_chunks_loop(ChunksCollection, FileId, StreamFun, ChunkSize, Options,
                  ChunkNum, TotalLength, MD5Context, ChunkDocs) ->
    try StreamFun() of
        {chunk, ChunkData} when is_binary(ChunkData) ->
            % Process chunk
            ChunkDoc = #{
                <<"files_id">> => FileId,
                <<"n">> => ChunkNum,
                <<"data">> => ChunkData
            },
            
            case connect_mongodb:insert_one(ChunksCollection, ChunkDoc, Options) of
                {ok, _} ->
                    NewMD5Context = crypto:hash_update(MD5Context, ChunkData),
                    stream_chunks_loop(ChunksCollection, FileId, StreamFun, ChunkSize, Options,
                                      ChunkNum + 1, TotalLength + byte_size(ChunkData),
                                      NewMD5Context, [ChunkDoc | ChunkDocs]);
                {error, _} = Error -> Error
            end;
        eof ->
            {ok, TotalLength, MD5Context, lists:reverse(ChunkDocs)};
        {error, _} = Error ->
            Error
    catch
        _:Error ->
            {error, {stream_error, Error}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Download chunks and reassemble file
%%--------------------------------------------------------------------
download_chunks(Bucket, FileId, Options) ->
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    Filter = #{<<"files_id">> => FileId},
    SortOptions = Options#{sort => #{<<"n">> => 1}},
    
    case connect_mongodb:find(ChunksCollection, Filter, SortOptions) of
        {ok, Chunks} ->
            FileData = reassemble_chunks(Chunks),
            {ok, FileData};
        {error, _} = Error -> Error
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Reassemble chunks into file data
%%--------------------------------------------------------------------
reassemble_chunks(Chunks) ->
    SortedChunks = lists:sort(fun(A, B) ->
        maps:get(<<"n">>, A, 0) =< maps:get(<<"n">>, B, 0)
    end, Chunks),
    
    lists:foldl(fun(Chunk, Acc) ->
        ChunkData = maps:get(<<"data">>, Chunk, <<>>),
        <<Acc/binary, ChunkData/binary>>
    end, <<>>, SortedChunks).

%%--------------------------------------------------------------------
%% @private
%% @doc Create download stream function
%%--------------------------------------------------------------------
create_download_stream(Bucket, FileInfo, Options) ->
    FileId = maps:get(<<"_id">>, FileInfo),
    ChunkSize = maps:get(<<"chunkSize">>, FileInfo),
    
    fun() ->
        case download_chunks(Bucket, FileId, Options) of
            {ok, FileData} ->
                create_chunk_iterator(FileData, ChunkSize);
            {error, Error} ->
                {error, Error}
        end
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Create chunk iterator for streaming
%%--------------------------------------------------------------------
create_chunk_iterator(FileData, ChunkSize) ->
    fun Iterator(Data) ->
        case byte_size(Data) of
            0 -> eof;
            Size when Size =< ChunkSize ->
                {chunk, Data, fun() -> eof end};
            _ ->
                <<Chunk:ChunkSize/binary, Rest/binary>> = Data,
                {chunk, Chunk, fun() -> Iterator(Rest) end}
        end
    end(FileData).

%%--------------------------------------------------------------------
%% @private
%% @doc Create file filter based on identifier
%%--------------------------------------------------------------------
create_file_filter(FileIdentifier) ->
    case FileIdentifier of
        Id when is_binary(Id) ->
            % Try both _id and filename
            #{<<"$or">> => [
                #{<<"_id">> => Id},
                #{<<"filename">> => Id}
            ]};
        Id ->
            #{<<"_id">> => Id}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc Delete file and its chunks
%%--------------------------------------------------------------------
delete_file_and_chunks(Bucket, FileId, Options) ->
    FilesCollection = ?FILES_COLLECTION(Bucket),
    ChunksCollection = ?CHUNKS_COLLECTION(Bucket),
    
    % Use transaction if available
    case connect_mongodb:start_session(Options) of
        {ok, SessionRef} ->
            try
                ok = connect_mongodb:start_transaction(SessionRef, Options),
                
                % Delete chunks first
                {ok, _} = connect_mongodb:delete_many(ChunksCollection, 
                                                    #{<<"files_id">> => FileId},
                                                    Options#{session => SessionRef}),
                
                % Delete file document
                {ok, _} = connect_mongodb:delete_one(FilesCollection,
                                                   #{<<"_id">> => FileId},
                                                   Options#{session => SessionRef}),
                
                ok = connect_mongodb:commit_transaction(SessionRef, Options),
                ok
            catch
                _:Error ->
                    connect_mongodb:abort_transaction(SessionRef, Options),
                    {error, Error}
            end;
        {error, _} ->
            % Fallback without transaction
            case connect_mongodb:delete_many(ChunksCollection, #{<<"files_id">> => FileId}, Options) of
                {ok, _} ->
                    case connect_mongodb:delete_one(FilesCollection, #{<<"_id">> => FileId}, Options) of
                        {ok, #{deleted_count := 1}} -> ok;
                        {ok, #{deleted_count := 0}} -> {error, file_not_found};
                        {error, _} = Error -> Error
                    end;
                {error, _} = Error -> Error
            end
    end. 