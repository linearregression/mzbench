[{pool, [{size, 1000},
         {worker_type, dummy_worker}],
    [
        {loop, [{time, {1, min}}, {rate, {1, rps}}, {poisson, true}],
            [{print, "loop"}]}
    ]
}].
