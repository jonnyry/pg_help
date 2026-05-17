# pg_help

A PostgreSQL function that ports the spirit of SQL Server's `sp_help` stored procedure to Postgres. Returns a single result set describing the structure of a table, view, or materialized view.

## Why?

In SQL Server, `sp_help 'mytable'` is the quickest way to get a summary of a relation's structure. Postgres has `\d name` in `psql`, but that's a client command — you can't call it from a GUI, a notebook, an application, or anywhere else that just speaks SQL. `pg_help` fills that gap by returning the same kind of information as a regular result set.

## Installation

Run the function definition against your database:

```bash
psql -d mydb -f pg_help.sql
```

## Usage

Pass a schema-qualified name, or just the name to use the current schema:

```sql
select * from pg_help('public.orders');

select * from pg_help('orders');             -- uses current_schema()

select * from pg_help('public.customer_orders');    -- view

select * from pg_help('public.product_sales');      -- materialized view
```

## Example output

```sql
select * from pg_help('orders');
```

```
 a                       | b                      | c                                                           | d
-------------------------+------------------------+-------------------------------------------------------------+-----------------------------------------
 >> Table >>             |                        |                                                             |
                         |                        |                                                             |
 orders                  | Customer orders.       |                                                             |
                         |                        |                                                             |
 >> Columns >>           |                        |                                                             |
                         |                        |                                                             |
 order_id                | INTEGER                | NOT NULL                                                    | nextval('orders_order_id_seq'::regclass)
 customer_id             | INTEGER                | NOT NULL                                                    |
 status                  | VARCHAR(20)            | NOT NULL                                                    | 'pending'::character varying
 notes                   | TEXT                   | NULL                                                        |
 ordered_at              | TIMESTAMPTZ            | NOT NULL                                                    | now()
 shipped_at              | TIMESTAMPTZ            | NULL                                                        |
                         |                        |                                                             |
 >> Constraints >>       |                        |                                                             |
                         |                        |                                                             |
 PRIMARY KEY             | orders_pkey            | PRIMARY KEY (order_id)                                      |
 FOREIGN KEY             | orders_customer_fk     | FOREIGN KEY (customer_id) REFERENCES customers(customer_id) |
 CHECK                   | orders_status_ck       | CHECK ((status = ANY (ARRAY['pending','confirmed',...])))   |
                         |                        |                                                             |
 >> Indexes >>           |                        |                                                             |
                         |                        |                                                             |
 UNIQUE BTREE            | orders_pkey            | (order_id)                                                  |
 BTREE                   | orders_customer_id_idx | (customer_id)                                               |
 BTREE                   | orders_status_idx      | (status)                                                    |
                         |                        |                                                             |
 >> Triggers >>          |                        |                                                             |
                         |                        |                                                             |
 orders_lock_closed_trg  | BEFORE ROW             | UPDATE                                                      | public.orders_lock_closed
                         |                        |                                                             |
 >> Referenced By >>     |                        |                                                             |
                         |                        |                                                             |
 public.order_items      | order_items_order_fk   | FOREIGN KEY (order_id) REFERENCES orders(order_id)         |
```

## Output

Four `text` columns (`a`–`d`) containing section headers and data rows. Sections vary by relation type:

| Section | a | b | c | d | Tables | Views | Mat. views |
|---|---|---|---|---|:---:|:---:|:---:|
| **Table** / **View** / **Materialized View** | name | comment | | | ✓ | ✓ | ✓ |
| **Columns** | column name | data type | `NOT NULL` / `NULL` | default expression | ✓ | ✓ | ✓ |
| **Definition** | SQL (one row per line) | | | | | ✓ | ✓ |
| **Constraints** | type (`PRIMARY KEY`, `FOREIGN KEY`, `CHECK`, `UNIQUE`) | name | definition | | ✓ | | |
| **Indexes** | type (`BTREE`, `UNIQUE BTREE`, etc.) | name | columns | `WHERE` clause | ✓ | | ✓ |
| **Triggers** | trigger name | timing + level (`BEFORE ROW`, etc.) | events (`INSERT OR UPDATE`) | function | ✓ | ✓ | |
| **Referenced By** | referencing table | constraint name | definition | | ✓ | | |

If the relation does not exist, a single `Not found` row is returned.

## Requirements

PostgreSQL 12 or later. No extensions required.

## Examples

The `examples/` folder contains a sample schema (two schemas, seven tables, three views, three triggers) that exercises every section of the output:

```bash
psql -d mydb -f pg_help.sql
psql -d mydb -f examples/example-schema.sql
```
