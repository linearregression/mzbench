#!/usr/bin/env python
"""mzbench data migrator

Usage:
  migrate [--check] [--jobs <jobs>] <data_dir>

Options:
    <data_dir>
                    Path to MZBench data directory
    --check
                    Check for actual migrations
    --jobs <jobs>
                    Number of parallel jobs, by default set to number of cores
"""

from __future__ import print_function
import os
import subprocess
import sys
import docopt
from contextlib import contextmanager
from os import path
from distutils.dir_util import mkpath
import shutil
import multiprocessing

dirname = path.dirname(path.realpath(__file__))
migrations_dir = path.join(dirname, '../migrations/')

def read_migrations(migration_dir):
    print('Reading migrations from {0}'.format(migration_dir))
    files = os.listdir(migration_dir)
    return dict((int(f.split('_')[0]), path.join(migration_dir, f)) for f in files)

def read_state(data_dir):
    print('Reading migration state from {0}'.format(data_dir))
    state_file = state_file_path(data_dir)
    if path.isfile(state_file):
        with open(state_file, 'r') as f:
            content = f.read()
        print('Current migration state is "{0}"'.format(content))
        return int(content)
    else:
        print('No migration state was found')
        return -1

def save_state(state, data_dir):
    state_file = state_file_path(data_dir)
    new_state = "{0}".format(state)
    print('Saving migration state "{0}" to {1}'.format(new_state, state_file))
    mkpath(os.path.dirname(state_file))
    with open(state_file, 'w') as f:
        f.write(new_state)

def state_file_path(data_dir):
    return path.join(data_dir, ".migrations", "status")

def migrations_to_apply(data_dir):
    last_applied = read_state(data_dir)
    migrations = read_migrations(migrations_dir)
    to_apply = dict((i, migrations[i]) for i in migrations if i > last_applied)
    if to_apply:
        print("Migrations to apply:")
        for i in to_apply:
            print(" {0} -> {1}".format(i, to_apply[i]))
    else:
        print("Nothing to migrate")
    return to_apply

def migrate(data_dir, jobs):
    to_apply = migrations_to_apply(data_dir)
    keys = to_apply.keys()
    keys.sort()
    for i in keys:
        print('')
        print('================================================================================')
        print('Migration: {0}'.format(to_apply[i]))
        print('================================================================================')
        with backup(i, data_dir):
            apply_migration(to_apply[i], data_dir, jobs)
            save_state(i, data_dir)

def benchmarks(data_dir):
    for d in os.listdir(data_dir):
        if d != ".migrations":
            yield d

def apply_migration(script_path, data_dir, jobs):
    pool = multiprocessing.Pool(processes=jobs)
    pool.map(migration_worker, [ (i, script_path, data_dir) for i in benchmarks(data_dir) ], 1)

def migration_worker((bench_id, script_path, data_dir)):
    bench_path = path.join(data_dir, bench_id)
    cmd = [script_path, bench_path]
    cmd_str = " ".join(cmd)
    print('Executing {0} in {1}'.format(cmd_str, os.getpid()))
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        res_out, res_err = p.communicate()
        return res_err
    except:
        print("Unexpected error: {0}".format(sys.exc_info()))
        raise

    if p.returncode != 0:
        print('ERROR: Migration "{0}" returned {1}\nOutput: {2}\nStderr: {3}\n'.format(cmd_str, p.returncode, res_out, res_err))
        raise Exception('Migration "{0}" failed'.format(cmd_str))

@contextmanager
def backup(name, data_dir):
    do_backup(name, data_dir)
    try:
        yield
    except:
        do_rollback(name, data_dir)
        raise

def do_backup(name, data_dir):
    backupdir = os.path.join(data_dir, '.migrations', 'backup', '{0}'.format(name))
    mkpath(backupdir)
    print('Making a backup {0}'.format(backupdir))
    for bench_id in benchmarks(data_dir):
        from_dir = path.join(data_dir, bench_id)
        to_dir = path.join(backupdir, bench_id)
        print('.', end='')
        sys.stdout.flush()
        shutil.copytree(from_dir, to_dir)
    print()

def do_rollback(name, data_dir):
    backupdir = os.path.join(data_dir, '.migrations', 'backup', '{0}'.format(name))
    print('Rolling back from {0}'.format(backupdir))
    for bench_id in benchmarks(backupdir):
        from_dir = path.join(backupdir, bench_id)
        to_dir = path.join(data_dir, bench_id)
        print('.', end='')
        shutil.rmtree(to_dir)
        shutil.move(from_dir, data_dir)
    print('')
    shutil.rmtree(backupdir)

def main():
    args = docopt.docopt(__doc__, version='0.1.0')
    data_dir = args['<data_dir>']

    if args['--jobs']:
        jobs = int(args['--jobs'])
    else:
        jobs = multiprocessing.cpu_count()

    print("Jobs: {0}".format(jobs))

    if args['--check']:
        if migrations_to_apply(data_dir):
            sys.exit(1)
    else:
        migrate(data_dir, jobs)

if __name__ == '__main__':
    main()
