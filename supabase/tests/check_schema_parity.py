#!/usr/bin/env python
"""Verify the Drift and Postgres schemas still agree.

Sync maps rows field-for-field (brain.md §4), so a column present on one side
and not the other silently drops data rather than raising an error. This script
compares the generated Drift schema against a live Postgres database and exits
non-zero on any mismatch.

    psql -d <db> -f supabase/migrations/*.sql     # apply first
    python supabase/tests/check_schema_parity.py --dsn "host=... dbname=..."

Without --dsn it reads a column dump on stdin, in the form produced by:

    select table_name || '::' || string_agg(column_name, ',' order by column_name)
      from information_schema.columns
     where table_schema = 'public'
     group by table_name;
"""

from __future__ import annotations

import argparse
import io
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GENERATED = REPO / 'lib' / 'data' / 'local' / 'database.g.dart'

# Columns that exist locally but must never reach the server.
LOCAL_ONLY_COLUMNS = {'is_dirty'}

# Tables that are device-only by design (brain.md §5, §6.2).
LOCAL_ONLY_TABLES = {'emergency_contacts', 'sync_queue', 'sync_state'}

# Per-table local extras, with the reason they stay local.
LOCAL_ONLY_PER_TABLE = {
    'announcements': {'is_read'},          # per-device read state
    'payments': {'receipt_local_path'},    # on-device file path
}

QUERY = (
    "select table_name || '::' || "
    "string_agg(column_name, ',' order by column_name) "
    "from information_schema.columns "
    "where table_schema = 'public' group by table_name order by table_name;"
)


def drift_schema() -> dict[str, set[str]]:
    source = io.open(GENERATED, encoding='utf-8').read()
    tables: dict[str, set[str]] = {}
    for block in re.split(r'(?=class \$\w+Table extends)', source):
        name = re.search(r"static const String \$name = '(\w+)'", block)
        if not name:
            continue
        columns = set(re.findall(r"GeneratedColumn<\w+>\(\s*'([a-z_]+)'", block))
        if columns:
            tables[name.group(1)] = columns
    return tables


def parse_dump(text: str) -> dict[str, set[str]]:
    tables: dict[str, set[str]] = {}
    for line in text.splitlines():
        line = line.strip()
        if '::' not in line:
            continue
        table, columns = line.split('::', 1)
        tables[table.strip()] = set(columns.split(','))
    return tables


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--dsn', help='psql connection string')
    parser.add_argument('--psql', default='psql')
    args = parser.parse_args()

    if args.dsn:
        result = subprocess.run(
            [args.psql, args.dsn, '-t', '-A', '-c', QUERY],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            print(result.stderr, file=sys.stderr)
            return 2
        server = parse_dump(result.stdout)
    else:
        server = parse_dump(sys.stdin.read())

    if not server:
        print('No server columns read.', file=sys.stderr)
        return 2

    local = drift_schema()
    problems: list[str] = []

    for table, columns in sorted(local.items()):
        if table in LOCAL_ONLY_TABLES:
            if table in server:
                problems.append(
                    f'{table}: device-only table must not exist on the server'
                )
            continue

        if table not in server:
            problems.append(f'{table}: missing on the server')
            continue

        allowed = LOCAL_ONLY_COLUMNS | LOCAL_ONLY_PER_TABLE.get(table, set())
        only_local = columns - server[table] - allowed
        only_server = server[table] - columns

        if only_local:
            problems.append(
                f'{table}: in Drift but not on the server -> {sorted(only_local)}'
            )
        if only_server:
            problems.append(
                f'{table}: on the server but not in Drift -> {sorted(only_server)}'
            )

    for table in sorted(server):
        if table not in local:
            problems.append(f'{table}: server table has no Drift counterpart')

    if problems:
        print('SCHEMA MISMATCH\n')
        for problem in problems:
            print(f'  {problem}')
        return 1

    print(
        f'Schemas agree: {len(server)} synced tables, '
        'local-only columns correctly absent server-side.'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
