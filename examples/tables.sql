-- Example tables for testing pg_help.
-- Run pg_help.sql first, then this file.
--
-- Usage:
--   select * from pg_help('public.customers');
--   select * from pg_help('public.products');
--   select * from pg_help('public.orders');
--   select * from pg_help('public.order_items');
--
--   select * from pg_help('hr.departments');
--   select * from pg_help('hr.employees');
--   select * from pg_help('hr.job_history');

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

comment on table public.customers is 'Registered customers who can place orders.';

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

comment on table public.orders is 'Customer orders. Each order belongs to one customer.';

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
