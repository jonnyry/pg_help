# pg_help

A PostgreSQL function that ports the spirit of SQL Server's `sp_help` stored procedure to Postgres. Returns a single result set describing a table's columns, constraints, and indexes.

## Why?

In SQL Server, `sp_help 'mytable'` is the quickest way to get a summary of a table's structure. Postgres has `\d tablename` in `psql`, but that's a client command — you can't call it from a GUI, a notebook, an application, or anywhere else that just speaks SQL. `pg_help` fills that gap by returning the same kind of information as a regular result set.

## Installation

Run the function definition against your database:

```bash
psql -d mydb -f pg_help.sql
```

## Usage

Pass the fully-qualified table name (`schema.table`) as a string:

```sql
select * from pg_help('public.users');
```

## Output

Four `varchar(500)` columns (`col1`, `col2`, `col3`, `col4`) containing section headers and rows, in this order:

- **Table** — the table name
- **Columns** — column name, data type, nullability
- **Constraints** — primary keys, foreign keys, checks, uniques
- **Indexes** — index name, columns, optional `WHERE` clause

## Requirements

PostgreSQL 9.x or later. Uses standard catalogs (`pg_constraint`, `pg_index`, `pg_class`, `information_schema.columns`) so no extensions are needed.

## Notes

- The table name must be fully qualified (e.g. `public.users`, not just `users`).
- Output columns are fixed-width `varchar(500)`, mimicking the `sp_help` result-grid style.
- For interactive use in `psql`, `\d+ tablename` is usually a better choice. `pg_help` is most useful when you need the metadata as a queryable result set.
