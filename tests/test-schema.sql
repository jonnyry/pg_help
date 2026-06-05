-- Example schema for testing pg_describe.
-- Run pg_describe.sql first, then this file.
--
-- Usage:
--   select * from pg_describe('public.customers');
--   select * from pg_describe('public.products');
--   select * from pg_describe('public.orders');
--   select * from pg_describe('public.order_items');
--
--   select * from pg_describe('hr.departments');
--   select * from pg_describe('hr.employees');
--   select * from pg_describe('hr.job_history');
--
--   select * from pg_describe('public.customer_orders');
--   select * from pg_describe('public.product_sales');
--   select * from pg_describe('hr.employee_directory');

-- -----------------------------------------------------------------------
-- customers
-- Exercises: table comment, several column types, CHECK, UNIQUE, index
-- -----------------------------------------------------------------------

drop table if exists public.order_items cascade;
drop table if exists public.orders      cascade;
drop table if exists public.products    cascade;
drop table if exists public.customers   cascade;

create table public.customers
(
    customer_id  serial        primary key,
    email        varchar(255)  not null,
    full_name    varchar(255)  not null,
    phone        varchar(50),
    is_active    boolean       not null default true,
    credit_limit numeric(10,2) not null default 0.00,
    created_at   timestamp     not null default now(),
    constraint customers_email_uq   unique (email),
    constraint customers_credit_ck  check (credit_limit >= 0)
);

comment on table  public.customers             is 'Registered customers who can place orders.';
comment on column public.customers.email       is 'Normalised to lowercase by trigger.';
comment on column public.customers.credit_limit is 'Maximum credit extended; 0 means no credit.';

create index customers_full_name_idx on public.customers (full_name);

-- -----------------------------------------------------------------------
-- products
-- Exercises: table comment, numeric precision, CHECK, partial index
-- -----------------------------------------------------------------------

create table public.products
(
    product_id   serial        primary key,
    sku          varchar(100)  not null,
    name         varchar(255)  not null,
    description  text,
    price        numeric(12,4) not null,
    stock_qty    integer       not null default 0,
    is_available boolean       not null default true,
    constraint products_sku_uq    unique (sku),
    constraint products_price_ck  check (price > 0),
    constraint products_stock_ck  check (stock_qty >= 0)
);

comment on table public.products is 'Catalogue of sellable products.';

-- Only index available products — exercises partial index
create index products_available_idx on public.products (sku) where is_available;

-- -----------------------------------------------------------------------
-- orders
-- Exercises: FK to customers, CHECK on status enum-style column, timestamptz
-- -----------------------------------------------------------------------

create table public.orders
(
    order_id    serial       primary key,
    customer_id integer      not null,
    status      varchar(20)  not null default 'pending',
    notes       text,
    ordered_at  timestamptz  not null default now(),
    shipped_at  timestamptz,
    constraint orders_customer_fk  foreign key (customer_id) references public.customers (customer_id),
    constraint orders_status_ck    check (status in ('pending', 'confirmed', 'shipped', 'cancelled'))
);

comment on table public.orders is 'Customer orders.';

create index orders_customer_id_idx on public.orders (customer_id);
create index orders_status_idx      on public.orders (status);

-- -----------------------------------------------------------------------
-- order_items
-- Exercises: composite PK, two FKs, CHECK, no extra indexes beyond PK
-- -----------------------------------------------------------------------

create table public.order_items
(
    order_id    integer       not null,
    line_no     smallint      not null,
    product_id  integer       not null,
    qty         integer       not null,
    unit_price  numeric(12,4) not null,
    constraint order_items_pk          primary key (order_id, line_no),
    constraint order_items_order_fk    foreign key (order_id)   references public.orders   (order_id),
    constraint order_items_product_fk  foreign key (product_id) references public.products (product_id),
    constraint order_items_qty_ck      check (qty > 0),
    constraint order_items_price_ck    check (unit_price > 0)
);

comment on table public.order_items is 'Individual line items within an order.';

create index order_items_product_id_idx on public.order_items (product_id);

-- =========================================================================
-- hr schema
-- =========================================================================

create schema if not exists hr;

-- -----------------------------------------------------------------------
-- hr.departments
-- Exercises: self-referencing FK (shows in both Constraints and Referenced By)
-- -----------------------------------------------------------------------

drop table if exists hr.job_history  cascade;
drop table if exists hr.employees    cascade;
drop table if exists hr.departments  cascade;

create table hr.departments
(
    dept_id        serial       primary key,
    name           varchar(100) not null,
    parent_dept_id integer,
    constraint departments_name_uq      unique (name),
    constraint departments_parent_fk    foreign key (parent_dept_id) references hr.departments (dept_id)
);

comment on table hr.departments is 'Company departments, optionally nested under a parent department.';

-- -----------------------------------------------------------------------
-- hr.employees
-- Exercises: generated column, composite UNIQUE, date type, FK to departments
-- -----------------------------------------------------------------------

create table hr.employees
(
    employee_id   serial       primary key,
    dept_id       integer      not null,
    first_name    varchar(100) not null,
    last_name     varchar(100) not null,
    full_name     text         generated always as (first_name || ' ' || last_name) stored,
    email         varchar(255) not null,
    hire_date     date         not null default current_date,
    salary        numeric(12,2),
    manager_id    integer,
    constraint employees_dept_fk        foreign key (dept_id)     references hr.departments (dept_id),
    constraint employees_manager_fk     foreign key (manager_id)  references hr.employees   (employee_id),
    constraint employees_email_uq       unique (email),
    constraint employees_name_dept_uq   unique (first_name, last_name, dept_id),
    constraint employees_salary_ck      check (salary is null or salary > 0)
);

comment on table hr.employees is 'All current employees, with optional manager and department assignment.';

create index employees_dept_id_idx    on hr.employees (dept_id);
create index employees_manager_id_idx on hr.employees (manager_id);
create index employees_last_name_idx  on hr.employees (last_name);

-- -----------------------------------------------------------------------
-- hr.job_history
-- Exercises: composite PK, date-range CHECK, FKs to employees and departments
-- -----------------------------------------------------------------------

create table hr.job_history
(
    employee_id  integer      not null,
    start_date   date         not null,
    end_date     date         not null,
    dept_id      integer      not null,
    job_title    varchar(100) not null,
    constraint job_history_pk          primary key (employee_id, start_date),
    constraint job_history_employee_fk foreign key (employee_id) references hr.employees   (employee_id),
    constraint job_history_dept_fk     foreign key (dept_id)     references hr.departments (dept_id),
    constraint job_history_dates_ck    check (end_date > start_date)
);

comment on table hr.job_history is 'Historical record of employee roles and department transfers.';

-- =========================================================================
-- Trigger functions and triggers
-- =========================================================================

-- -----------------------------------------------------------------------
-- public.customers — normalise email to lowercase on insert or update
-- -----------------------------------------------------------------------

create or replace function public.customers_normalize_email()
returns trigger as $$
begin
    new.email := lower(trim(new.email));
    return new;
end;
$$ language plpgsql;

drop trigger if exists customers_normalize_email_trg on public.customers;

create trigger customers_normalize_email_trg
before insert or update of email on public.customers
for each row execute function public.customers_normalize_email();

-- -----------------------------------------------------------------------
-- public.orders — prevent modification of shipped or cancelled orders
-- -----------------------------------------------------------------------

create or replace function public.orders_lock_closed()
returns trigger as $$
begin
    if old.status in ('shipped', 'cancelled') then
        raise exception 'Cannot modify a % order.', old.status;
    end if;
    return new;
end;
$$ language plpgsql;

drop trigger if exists orders_lock_closed_trg on public.orders;

create trigger orders_lock_closed_trg
before update on public.orders
for each row execute function public.orders_lock_closed();

-- -----------------------------------------------------------------------
-- hr.employees — trim whitespace from names on insert or update
-- -----------------------------------------------------------------------

create or replace function hr.employees_normalize_name()
returns trigger as $$
begin
    new.first_name := trim(new.first_name);
    new.last_name  := trim(new.last_name);
    return new;
end;
$$ language plpgsql;

drop trigger if exists employees_normalize_name_trg on hr.employees;

create trigger employees_normalize_name_trg
before insert or update of first_name, last_name on hr.employees
for each row execute function hr.employees_normalize_name();

-- =========================================================================
-- Views and materialized views
-- =========================================================================

-- -----------------------------------------------------------------------
-- public.customer_orders
-- A view joining customers and orders
-- -----------------------------------------------------------------------

drop view if exists public.customer_orders cascade;

create view public.customer_orders as
select
    c.customer_id,
    c.full_name,
    c.email,
    o.order_id,
    o.status,
    o.ordered_at
from public.customers c
inner join public.orders o on o.customer_id = c.customer_id;

comment on view public.customer_orders is 'Orders with customer details, one row per order.';

-- -----------------------------------------------------------------------
-- public.product_sales
-- A materialized view aggregating revenue per product, with an index
-- -----------------------------------------------------------------------

drop materialized view if exists public.product_sales cascade;

create materialized view public.product_sales as
select
    p.product_id,
    p.sku,
    p.name,
    sum(oi.qty)                    as total_qty_sold,
    sum(oi.qty * oi.unit_price)    as total_revenue
from public.products p
inner join public.order_items oi on oi.product_id = p.product_id
group by p.product_id, p.sku, p.name;

comment on materialized view public.product_sales is 'Aggregated sales totals per product. Refresh with REFRESH MATERIALIZED VIEW.';

create index product_sales_product_id_idx on public.product_sales (product_id);

-- -----------------------------------------------------------------------
-- hr.employee_directory
-- A view joining employees with their department and manager name
-- -----------------------------------------------------------------------

drop view if exists hr.employee_directory cascade;

create view hr.employee_directory as
select
    e.employee_id,
    e.full_name,
    e.email,
    d.name                              as department,
    m.full_name                         as manager,
    e.hire_date
from hr.employees e
inner join hr.departments d on d.dept_id = e.dept_id
left  join hr.employees m on m.employee_id = e.manager_id;

comment on view hr.employee_directory is 'Employee listing with department and manager name.';

-- =========================================================================
-- Additional objects for pg_describe testing
-- =========================================================================

-- -----------------------------------------------------------------------
-- Expression index and covering (INCLUDE) index
-- Exercises: expression index columns, INCLUDE columns
-- -----------------------------------------------------------------------

drop index if exists public.customers_lower_full_name_idx;
create index customers_lower_full_name_idx on public.customers (lower(full_name));

drop index if exists public.orders_status_cover_idx;
create index orders_status_cover_idx on public.orders (status) include (ordered_at, customer_id);

-- -----------------------------------------------------------------------
-- public.audit_log — partitioned table (RANGE on created_at)
-- Exercises: partitioned table description
-- -----------------------------------------------------------------------

drop table if exists public.audit_log_2025 cascade;
drop table if exists public.audit_log_2024 cascade;
drop table if exists public.audit_log      cascade;

create table public.audit_log
(
    id          bigint       generated always as identity,
    event_type  text         not null,
    payload     jsonb,
    created_at  timestamptz  not null default now()
)
partition by range (created_at);

comment on table public.audit_log is 'Audit log of system events, partitioned by creation date.';

create table public.audit_log_2024
    partition of public.audit_log
    for values from ('2024-01-01') to ('2025-01-01');

create table public.audit_log_2025
    partition of public.audit_log
    for values from ('2025-01-01') to ('2026-01-01');

-- -----------------------------------------------------------------------
-- public.external_prices — foreign table (file_fdw)
-- Exercises: foreign table description, server, FDW options
-- -----------------------------------------------------------------------

create extension if not exists file_fdw;

drop server      if exists local_files cascade;
create server local_files foreign data wrapper file_fdw;

drop foreign table if exists public.external_prices;
create foreign table public.external_prices
(
    sku    text     not null,
    price  numeric
)
server local_files
options (filename '/tmp/prices.csv', format 'csv');

comment on foreign table public.external_prices is 'Price feed imported from an external CSV file.';

-- -----------------------------------------------------------------------
-- public.address_type — composite type
-- Exercises: composite type description
-- -----------------------------------------------------------------------

drop type if exists public.address_type cascade;
create type public.address_type as
(
    street   text,
    city     text,
    country  text
);

comment on type public.address_type is 'Postal address composite type.';
