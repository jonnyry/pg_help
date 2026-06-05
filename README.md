# pg_describe

A PostgreSQL function that brings `psql`'s `\d` and `\d+` commands into SQL - returning the same relation descriptions as a regular result set you can query from any client.

## Why?

Postgres has `\d name` in `psql`, but that's a client command - you can't call it from a GUI, a notebook, an application, or anywhere else that just speaks SQL. `pg_describe` fills that gap with the same output, the same pattern syntax, and the same verbose mode.

## Installation

```bash
psql -d mydb -f pg_describe.sql
```

## Usage

```sql
-- List all visible user relations  (\d)
select * from pg_describe();

-- Describe a single relation
select * from pg_describe('public.orders');
select * from pg_describe('orders');           -- visibility search, like \d

-- Wildcard patterns  (\d cust*)
select * from pg_describe('cust*');

-- Schema patterns
select * from pg_describe('hr.*');             -- all objects in hr schema
select * from pg_describe('*.employees');      -- employees in any schema
select * from pg_describe('*.*');              -- everything in the database

-- Verbose mode  (\d+)
select * from pg_describe('orders', true);
```

## Pattern rules

Pattern syntax mirrors `psql`:

| Pattern | Meaning |
|---|---|
| `*` | any sequence of characters |
| `?` | any single character |
| `"quoted"` | case-sensitive literal (`*` `?` `.` treated as plain chars) |
| `schema.name` | match by schema; no visibility filter |
| `name` (no dot) | match visible relations only |
| `*.*` | all objects in all schemas (including system) |

Unquoted characters are folded to lower-case before matching, so `ORDERS`, `Orders`, and `orders` all find `public.orders`.

## Output

Four `text` columns (`a`, `b`, `c`, `d`). With no argument, returns a listing:

| a | b | c | d |
|---|---|---|---|
| schema | relation name | type | owner |

With a pattern, returns full descriptions. Sections vary by relation type:

| Section | a | b | c | d |
|---|---|---|---|---|
| Title | `Table "schema.name"` etc. | | | |
| **Columns** | name | type | `not null` / `` | default |
| **Indexes** | | definition | | |
| **Check constraints** | | name | definition | |
| **Foreign-key constraints** | | name | definition | |
| **Referenced by** | table | constraint | definition | |
| **Triggers** | name | timing + level | events | function |
| **Partition key** *(partitioned)* | definition | | | |
| **Server** *(foreign table)* | server name | | | |
| **Sequence properties** | property | value | | |

Verbose mode (`true`) adds:

| Section | a | b | c | d |
|---|---|---|---|---|
| **Column details** | name | storage | stats target | comment |
| **Not-null constraints** | | name | definition | |
| **Definition** *(views)* | SQL line | | | |
| Access method | `Access method: heap` | | | |

## Relation types

`pg_describe` handles all eight relation types that `\d` covers:

| Type | `relkind` |
|---|---|
| Table | `r` |
| Partitioned table | `p` |
| View | `v` |
| Materialized view | `m` |
| Sequence | `S` |
| Index | `i` |
| Foreign table | `f` |
| Composite type | `c` |

## Requirements

PostgreSQL 18 or later. No extensions required.

## Testing

Requires [pgTAP](https://pgtap.org/). Load the schema and run:

```bash
make setup
make test
```

## Linting

Requires [plpgsql_check](https://github.com/okbob/plpgsql_check). Analyses the PL/pgSQL function bodies for type mismatches, unused variables, and invalid embedded SQL:

```bash
make lint
```

## Examples

The `tests/test-schema.sql` file contains a sample schema (two schemas, seven tables, three views, three triggers, a partitioned table, a foreign table, and a composite type):

```bash
psql -d mydb -f pg_describe.sql
psql -d mydb -f tests/test-schema.sql
```
