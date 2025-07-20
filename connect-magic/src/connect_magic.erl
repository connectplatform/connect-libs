%%%-------------------------------------------------------------------
%%% @doc ConnectPlatform File Magic - File Type Detection
%%% 
%%% Features:
%%% - Modern libmagic 5.45+ bindings
%%% - Thread-safe operations
%%% - Multiple detection modes (MIME, description, encoding)
%%% - Binary and file path support
%%% - Compressed file detection
%%% - Custom magic databases
%%% - High performance with minimal memory footprint
%%% 
%%% @copyright 2025 ConnectPlatform
%%% @end
%%%-------------------------------------------------------------------
-module(connect_magic).

%% API exports
-export([
    start_link/0,
    start_link/1,
    stop/1,
    
    %% File type detection
    file/1,
    file/2,
    buffer/1,
    buffer/2,
    
    %% MIME type detection
    mime_file/1,
    mime_file/2,
    mime_buffer/1,
    mime_buffer/2,
    
    %% Encoding detection
    encoding_file/1,
    encoding_file/2,
    encoding_buffer/1,
    encoding_buffer/2,
    
    %% Compressed file detection
    compressed_file/1,
    compressed_file/2,
    compressed_buffer/1,
    compressed_buffer/2,
    
    %% Custom magic database
    load_database/2,
    compile_database/2,
    
    %% Utility functions
    version/0,
    list_databases/0,
    error_to_string/1
]).

%% Types
-type magic_handle() :: reference().
-type magic_flags() :: [atom()].
-type file_path() :: binary() | string().
-type buffer() :: binary().
-type mime_type() :: binary().
-type description() :: binary().
-type encoding() :: binary().
-type result() :: {ok, binary()} | {error, term()}.

%% Magic flags
-define(MAGIC_NONE, none).
-define(MAGIC_DEBUG, debug).
-define(MAGIC_SYMLINK, symlink).
-define(MAGIC_COMPRESS, compress).
-define(MAGIC_DEVICES, devices).
-define(MAGIC_MIME_TYPE, mime_type).
-define(MAGIC_CONTINUE, continue).
-define(MAGIC_CHECK, check).
-define(MAGIC_PRESERVE_ATIME, preserve_atime).
-define(MAGIC_RAW, raw).
-define(MAGIC_ERROR, error).
-define(MAGIC_MIME_ENCODING, mime_encoding).
-define(MAGIC_MIME, mime).
-define(MAGIC_APPLE, apple).
-define(MAGIC_EXTENSION, extension).
-define(MAGIC_COMPRESS_TRANSP, compress_transp).
-define(MAGIC_NO_CHECK_COMPRESS, no_check_compress).
-define(MAGIC_NO_CHECK_TAR, no_check_tar).
-define(MAGIC_NO_CHECK_SOFT, no_check_soft).
-define(MAGIC_NO_CHECK_APPTYPE, no_check_apptype).
-define(MAGIC_NO_CHECK_ELF, no_check_elf).
-define(MAGIC_NO_CHECK_TEXT, no_check_text).
-define(MAGIC_NO_CHECK_CDF, no_check_cdf).
-define(MAGIC_NO_CHECK_TOKENS, no_check_tokens).
-define(MAGIC_NO_CHECK_ENCODING, no_check_encoding).

-export_type([magic_handle/0, magic_flags/0, file_path/0, buffer/0, 
              mime_type/0, description/0, encoding/0, result/0]).

%%%===================================================================
%%% API Functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Start magic detection with default flags
%%--------------------------------------------------------------------
-spec start_link() -> {ok, magic_handle()} | {error, term()}.
start_link() ->
    start_link([]).

%%--------------------------------------------------------------------
%% @doc Start magic detection with custom flags
%%--------------------------------------------------------------------
-spec start_link(Flags :: magic_flags()) -> {ok, magic_handle()} | {error, term()}.
start_link(Flags) ->
    connect_magic_nif:start_link(Flags).

%%--------------------------------------------------------------------
%% @doc Stop magic detection handle
%%--------------------------------------------------------------------
-spec stop(Handle :: magic_handle()) -> ok.
stop(Handle) ->
    connect_magic_nif:stop(Handle).

%%--------------------------------------------------------------------
%% @doc Detect file type by file path (description)
%%--------------------------------------------------------------------
-spec file(FilePath :: file_path()) -> result().
file(FilePath) ->
    {ok, Handle} = start_link([]),
    Result = connect_magic_nif:file(Handle, FilePath),
    stop(Handle),
    Result.

-spec file(Handle :: magic_handle(), FilePath :: file_path()) -> result().
file(Handle, FilePath) ->
    connect_magic_nif:file(Handle, FilePath).

%%--------------------------------------------------------------------
%% @doc Detect file type from buffer (description)
%%--------------------------------------------------------------------
-spec buffer(Buffer :: buffer()) -> result().
buffer(Buffer) ->
    {ok, Handle} = start_link([]),
    Result = connect_magic_nif:buffer(Handle, Buffer),
    stop(Handle),
    Result.

-spec buffer(Handle :: magic_handle(), Buffer :: buffer()) -> result().
buffer(Handle, Buffer) ->
    connect_magic_nif:buffer(Handle, Buffer).

%%--------------------------------------------------------------------
%% @doc Detect MIME type by file path
%%--------------------------------------------------------------------
-spec mime_file(FilePath :: file_path()) -> result().
mime_file(FilePath) ->
    {ok, Handle} = start_link([?MAGIC_MIME]),
    Result = connect_magic_nif:file(Handle, FilePath),
    stop(Handle),
    Result.

-spec mime_file(Handle :: magic_handle(), FilePath :: file_path()) -> result().
mime_file(Handle, FilePath) ->
    connect_magic_nif:file(Handle, FilePath).

%%--------------------------------------------------------------------
%% @doc Detect MIME type from buffer
%%--------------------------------------------------------------------
-spec mime_buffer(Buffer :: buffer()) -> result().
mime_buffer(Buffer) ->
    {ok, Handle} = start_link([?MAGIC_MIME]),
    Result = connect_magic_nif:buffer(Handle, Buffer),
    stop(Handle),
    Result.

-spec mime_buffer(Handle :: magic_handle(), Buffer :: buffer()) -> result().
mime_buffer(Handle, Buffer) ->
    connect_magic_nif:buffer(Handle, Buffer).

%%--------------------------------------------------------------------
%% @doc Detect encoding by file path
%%--------------------------------------------------------------------
-spec encoding_file(FilePath :: file_path()) -> result().
encoding_file(FilePath) ->
    {ok, Handle} = start_link([?MAGIC_MIME_ENCODING]),
    Result = connect_magic_nif:file(Handle, FilePath),
    stop(Handle),
    Result.

-spec encoding_file(Handle :: magic_handle(), FilePath :: file_path()) -> result().
encoding_file(Handle, FilePath) ->
    connect_magic_nif:file(Handle, FilePath).

%%--------------------------------------------------------------------
%% @doc Detect encoding from buffer
%%--------------------------------------------------------------------
-spec encoding_buffer(Buffer :: buffer()) -> result().
encoding_buffer(Buffer) ->
    {ok, Handle} = start_link([?MAGIC_MIME_ENCODING]),
    Result = connect_magic_nif:buffer(Handle, Buffer),
    stop(Handle),
    Result.

-spec encoding_buffer(Handle :: magic_handle(), Buffer :: buffer()) -> result().
encoding_buffer(Handle, Buffer) ->
    connect_magic_nif:buffer(Handle, Buffer).

%%--------------------------------------------------------------------
%% @doc Detect compressed file type by file path
%%--------------------------------------------------------------------
-spec compressed_file(FilePath :: file_path()) -> result().
compressed_file(FilePath) ->
    {ok, Handle} = start_link([?MAGIC_COMPRESS]),
    Result = connect_magic_nif:file(Handle, FilePath),
    stop(Handle),
    Result.

-spec compressed_file(Handle :: magic_handle(), FilePath :: file_path()) -> result().
compressed_file(Handle, FilePath) ->
    connect_magic_nif:file(Handle, FilePath).

%%--------------------------------------------------------------------
%% @doc Detect compressed file type from buffer
%%--------------------------------------------------------------------
-spec compressed_buffer(Buffer :: buffer()) -> result().
compressed_buffer(Buffer) ->
    {ok, Handle} = start_link([?MAGIC_COMPRESS]),
    Result = connect_magic_nif:buffer(Handle, Buffer),
    stop(Handle),
    Result.

-spec compressed_buffer(Handle :: magic_handle(), Buffer :: buffer()) -> result().
compressed_buffer(Handle, Buffer) ->
    connect_magic_nif:buffer(Handle, Buffer).

%%--------------------------------------------------------------------
%% @doc Load custom magic database
%%--------------------------------------------------------------------
-spec load_database(Handle :: magic_handle(), DatabasePath :: file_path()) -> ok | {error, term()}.
load_database(Handle, DatabasePath) ->
    connect_magic_nif:load_database(Handle, DatabasePath).

%%--------------------------------------------------------------------
%% @doc Compile magic database from source
%%--------------------------------------------------------------------
-spec compile_database(SourcePath :: file_path(), OutputPath :: file_path()) -> ok | {error, term()}.
compile_database(SourcePath, OutputPath) ->
    connect_magic_nif:compile_database(SourcePath, OutputPath).

%%--------------------------------------------------------------------
%% @doc Get libmagic version
%%--------------------------------------------------------------------
-spec version() -> binary().
version() ->
    connect_magic_nif:version().

%%--------------------------------------------------------------------
%% @doc List available magic databases
%%--------------------------------------------------------------------
-spec list_databases() -> [binary()].
list_databases() ->
    connect_magic_nif:list_databases().

%%--------------------------------------------------------------------
%% @doc Convert error code to string
%%--------------------------------------------------------------------
-spec error_to_string(ErrorCode :: integer()) -> binary().
error_to_string(ErrorCode) ->
    connect_magic_nif:error_to_string(ErrorCode). 