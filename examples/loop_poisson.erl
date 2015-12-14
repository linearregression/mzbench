[ % simulate poisson process using loop
    {pool, [{size, 3}, % three execution "threads"
            {worker_type, dummy_worker}],
        [{loop, [{time, {5, min}}, % total loop time
                 {rate, {1, rps}},
                 {poisson, true}],
                [{print, "FOO"}]}]} % this operation prints "FOO" to console
].
