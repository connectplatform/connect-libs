-module(elibphone_utils).

-export([
    get_priv_path/1
]).

get_priv_path(File) ->
    case code:priv_dir(elibphonenumber) of
        {error, bad_name} ->
            Ebin = filename:dirname(code:which(?MODULE)),
            filename:join([filename:dirname(Ebin), "priv", File]);
        Dir ->
            filename:join(Dir, File)
    end.
