#!/usr/bin/env escript

main([BenchDir]) ->
    StatusFile = filename:join(BenchDir, "status"),
    case file:consult(StatusFile) of
        {ok, [Status]} ->
            NewStatusContent = io_lib:format("~p.", [migrate(Status)]),
            ok = file:write_file(StatusFile, NewStatusContent);
        {error, enoent} -> ok;
        {error, Reason} ->
            io:format("Can't read status file: ~s with reason: ~p", [StatusFile, Reason]),
            erlang:error({file_read_error, StatusFile, Reason})
    end.

migrate(Status = #{config:= Config}) ->
    case maps:find(cloud, Config) of
        {ok, _} -> Status;
        error ->
            Status#{config => Config#{cloud => undefined}}
    end;
migrate(Status = #{}) ->
    Status.
