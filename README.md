# pg_help

A PostgreSQL function that ports the spirit of SQL Server's `sp_help` stored procedure to Postgres. Returns a single result set describing a table's structure — columns, constraints, indexes, triggers, and references.

## Why?

In SQL Server, `sp_help 'mytable'` is the quickest way to get a summary of a table's structure. Postgres has `\d tablename` in `psql`, but that's a client command — you can't call it from a GUI, a notebook, an application, or anywhere else that just speaks SQL. `pg_help` fills that gap by returning the same kind of information as a regular result set.

## Installation

Run the function definition against your database:

```bash
psql -d mydb -f pg_help.sql
```

## Usage

Pass a schema-qualified table name, or just the table name to use the current schema:

```sql
select * from pg_help('public.orders');

select * from pg_help('orders');   -- uses current_schema()
```

## Example output

```sql
select * from pg_help('orders');
```

```
 col1                    | col2                                                  | col3                                                        | col4
-------------------------+-------------------------------------------------------+-------------------------------------------------------------+-----------------------------------------
 >> Table >>             |                                                       |                                                             |
                         |                                                       |                                                             |
 orders                  | Customer orders. Each order belongs to one customer.  |                                                             |
                         |                                                       |                                                             |
 >> Columns >>           |                                                       |                                                             |
                         |                                                       |                                                             |
 -- Column --            | -- Type --                                            | -- Nullable --                                              | -- Default --
 order_id                | INTEGER                                               | NOT NULL                                                    | nextval('orders_order_id_seq'::regclass)
 customer_id             | INTEGER                                               | NOT NULL                                                    |
 status                  | VARCHAR(20)                                           | NOT NULL                                                    | 'pending'::character varying
 notes                   | TEXT                                                  | NULL                                                        |
 ordered_at              | TIMESTAMPTZ                                           | NOT NULL                                                    | now()
 shipped_at              | TIMESTAMPTZ                                           | NULL                                                        |
                         |                                                       |                                                             |
 >> Constraints >>       |                                                       |                                                             |
                         |                                                       |                                                             |
 PRIMARY KEY             | orders_pkey                                           | PRIMARY KEY (order_id)                                      |
 FOREIGN KEY             | orders_customer_fk                                    | FOREIGN KEY (customer_id) REFERENCES customers(customer_id) |
 CHECK                   | orders_status_ck                                      | CHECK (status IN ('pending','confirmed','shipped','cancelled'))|
                         |                                                       |                                                             |
 >> Indexes >>           |                                                       |                                                             |
                         |                                                       |                                                             |
 UNIQUE BTREE            | orders_pkey                                           | (order_id)                                                  |
 BTREE                   | orders_customer_id_idx                                | (customer_id)                                               |
 BTREE                   | orders_status_idx                                     | (status)                                                    |
                         |                                                       |                                                             |
 >> Triggers >>          |                                                       |                                                             |
                         |                                                       |                                                             |
 orders_lock_closed_trg  | BEFORE ROW                                            | UPDATE                                                      | public.orders_lock_closed
                         |                                                       |                                                             |
 >> Referenced By >>     |                                                       |                                                             |
                         |                                                       |                                                             |
 public.order_items      | order_items_order_fk                                  | FOREIGN KEY (order_id) REFERENCES orders(order_id)          |
```

## Output

Four `text` columns (`col1`–`col4`) containing section headers and data rows, in this order:

| Section | col1 | col2 | col3 | col4 |
|---|---|---|---|---|
| **Table** | table name | comment | | |
| **Columns** | column name | data type | `NOT NULL` / `NULL` | default expression |
| **Constraints** | type (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`, `UNIQUE`) | constraint name | definition | |
| **Indexes** | type (`BTREE`, `UNIQUE BTREE`, etc.) | index name | columns | `WHERE` clause (partial indexes) |
| **Triggers** | trigger name | timing + level (`BEFORE ROW`, `AFTER STATEMENT`, etc.) | events (`INSERT OR UPDATE`) | function name |
| **Referenced By** | referencing table | constraint name | definition | |

If the table does not exist, a single row is returned with a `Table not found` message.

## Requirements

PostgreSQL 12 or later. No extensions required.

## Examples

The `examples/` folder contains a sample schema (two schemas, seven tables, three triggers) that exercises every section of the output:

```bash
psql -d mydb -f pg_help.sql
psql -d mydb -f examples/example-schema.sql
```
