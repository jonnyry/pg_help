-- Tests for pg_describe() and its internal helper functions.
--
-- Requires:
--   pg_describe.sql loaded
--   tests/test-schema.sql loaded
--
-- Run:
--   pg_prove -U postgres tests/test.sql
--   make test

\set ON_ERROR_STOP 1

begin;

create extension if not exists pgtap;

select plan(117);


-- ============================================================
-- 1. LISTING MODE  –  pg_describe() with no argument
-- ============================================================

select ok(
    exists(select 1 from pg_describe() where a='public' and b='customers'      and c='table'),
    'listing: customers table'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='orders'         and c='table'),
    'listing: orders table'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='customer_orders' and c='view'),
    'listing: customer_orders view'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='product_sales'  and c='materialized view'),
    'listing: product_sales materialized view'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='customers_customer_id_seq' and c='sequence'),
    'listing: customers sequence'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='audit_log'      and c='partitioned table'),
    'listing: audit_log partitioned table'
);
select ok(
    exists(select 1 from pg_describe() where a='public' and b='external_prices' and c='foreign table'),
    'listing: external_prices foreign table'
);
select ok(
    not exists(select 1 from pg_describe() where b='customers_pkey'),
    'listing: indexes not shown'
);
select ok(
    not exists(select 1 from pg_describe() where a='pg_catalog'),
    'listing: pg_catalog excluded'
);
select ok(
    not exists(select 1 from pg_describe() where a='information_schema'),
    'listing: information_schema excluded'
);
-- 10 tests


-- ============================================================
-- 2. PATTERN MATCHING
-- ============================================================

-- Exact name via visibility (no schema prefix)
select is(
    (select a from pg_describe('customers') limit 1),
    'Table "public.customers"',
    'pattern exact: customers resolves to public.customers'
);

-- Unquoted input is case-folded to lower-case
select is(
    (select a from pg_describe('CUSTOMERS') limit 1),
    'Table "public.customers"',
    'pattern case-fold: CUSTOMERS finds customers'
);

-- Double-quoted segment is case-sensitive: "CUSTOMERS" ≠ customers
select is(
    (select a from pg_describe('"CUSTOMERS"')),
    'Did not find any relation named ""CUSTOMERS"".',
    'pattern quoted case-sensitive: "CUSTOMERS" not found'
);

-- Double-quoted * is a literal asterisk, not a wildcard
select is(
    (select a from pg_describe('"*"')),
    'Did not find any relation named ""*"".',
    'pattern quoted star: literal * not found'
);

-- Wildcard * on name matches multiple objects
select ok(
    (select count(*) from pg_describe('cust*')
     where a like 'Table%' or a like 'View%'
        or a like 'Sequence%' or a like 'Index%') >= 7,
    'pattern wildcard: cust* matches view, table, sequence, and indexes'
);

-- Schema-qualified exact match bypasses visibility filter
select is(
    (select a from pg_describe('hr.employees') limit 1),
    'Table "hr.employees"',
    'pattern schema-qualified: hr.employees title'
);

-- Schema wildcard finds object across schemas
select ok(
    exists(select 1 from pg_describe('*.employees') where a = 'Table "hr.employees"'),
    'pattern schema wildcard: *.employees finds hr.employees'
);

-- Schema wildcard does not bleed into wrong objects
select ok(
    not exists(select 1 from pg_describe('*.employees') where a = 'Table "public.customers"'),
    'pattern schema wildcard: *.employees excludes customers'
);

-- Schema pattern + name wildcard
select ok(
    exists(select 1 from pg_describe('hr.*') where a = 'Table "hr.departments"') and
    exists(select 1 from pg_describe('hr.*') where a = 'Table "hr.employees"'),
    'pattern hr.*: matches all hr objects'
);

-- Schema pattern excludes other schemas
select ok(
    not exists(select 1 from pg_describe('hr.*') where a = 'Table "public.customers"'),
    'pattern hr.*: excludes public schema'
);

-- No match gives informative message
select is(
    (select a from pg_describe('no_such_relation_xyz')),
    'Did not find any relation named "no_such_relation_xyz".',
    'pattern not found: correct message'
);

-- Cross-database pattern gives error
select ok(
    (select a from pg_describe('otherdb.public.customers')) like 'ERROR:%',
    'pattern cross-database: error message returned'
);

-- System objects visible via pattern (pg_catalog is always in search path)
select ok(
    exists(select 1 from pg_describe('pg_class') where a = 'Table "pg_catalog.pg_class"'),
    'pattern system object: pg_class accessible via name-only pattern'
);
-- 13 tests


-- ============================================================
-- 3. TABLE DESCRIPTION  –  public.customers
-- ============================================================

select is(
    (select a from pg_describe('public.customers') limit 1),
    'Table "public.customers"',
    'customers: title row'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where a = 'Registered customers who can place orders.'),
    'customers: table comment'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = '>> Columns >>'),
    'customers: columns section present'
);

select set_has(
    $$ select a, b, c from pg_describe('public.customers') where b <> '' $$,
    $$ values
        ('customer_id',  'integer',                       'not null'),
        ('email',        'character varying(255)',         'not null'),
        ('full_name',    'character varying(255)',         'not null'),
        ('phone',        'character varying(50)',          ''        ),
        ('is_active',    'boolean',                       'not null'),
        ('credit_limit', 'numeric(10,2)',                 'not null'),
        ('created_at',   'timestamp without time zone',   'not null')
    $$,
    'customers: all columns with correct types and nullability'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where a = 'customer_id'
             and d like '%nextval%customers_customer_id_seq%'),
    'customers: customer_id has nextval default'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = '>> Indexes >>'),
    'customers: indexes section present'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where b like '%"customers_pkey" PRIMARY KEY%'),
    'customers: primary key index shown'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where b like '%"customers_email_uq" UNIQUE CONSTRAINT%'),
    'customers: unique constraint distinguished from plain UNIQUE'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where b like '%"customers_lower_full_name_idx"%lower%'),
    'customers: expression index shown with function'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = '>> Check constraints >>'),
    'customers: check constraints section present'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where b = 'customers_credit_ck'),
    'customers: customers_credit_ck constraint shown'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = '>> Referenced by >>'),
    'customers: referenced by section present'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = 'public.orders'),
    'customers: orders FK reference shown'
);

select ok(
    exists(select 1 from pg_describe('public.customers') where a = '>> Triggers >>'),
    'customers: triggers section present'
);

select ok(
    exists(select 1 from pg_describe('public.customers')
           where a = 'customers_normalize_email_trg'
             and c = 'INSERT OR UPDATE OF email'),
    'customers: trigger shows UPDATE OF email'
);

select ok(
    not exists(select 1 from pg_describe('public.customers') where a = '>> Column details >>'),
    'customers basic: no column details section'
);

select ok(
    not exists(select 1 from pg_describe('public.customers') where a = '>> Not-null constraints >>'),
    'customers basic: no not-null constraints section'
);
-- 17 tests


-- ============================================================
-- 4. VERBOSE MODE  –  public.customers
-- ============================================================

select ok(
    exists(select 1 from pg_describe('public.customers', true) where a = '>> Column details >>'),
    'customers verbose: column details section present'
);

select ok(
    exists(select 1 from pg_describe('public.customers', true)
           where a = 'email' and d = 'Normalised to lowercase by trigger.'),
    'customers verbose: email column comment shown'
);

select ok(
    exists(select 1 from pg_describe('public.customers', true)
           where a = 'credit_limit'
             and d = 'Maximum credit extended; 0 means no credit.'),
    'customers verbose: credit_limit column comment shown'
);

select case
    when current_setting('server_version_num')::int >= 180000
    then ok(
        exists(select 1 from pg_describe('public.customers', true)
               where a = '>> Not-null constraints >>'),
        'customers verbose: not-null constraints section present'
    )
    else skip('Not-null constraints in pg_constraint require PG18+')
end;

select ok(
    exists(select 1 from pg_describe('public.customers', true)
           where a = 'Access method: heap'),
    'customers verbose: access method shown'
);
-- 5 tests


-- ============================================================
-- 5. VIEW  –  public.customer_orders
-- ============================================================

select is(
    (select a from pg_describe('public.customer_orders') limit 1),
    'View "public.customer_orders"',
    'view: title row'
);

select ok(
    exists(select 1 from pg_describe('public.customer_orders') where a = 'customer_id'),
    'view: customer_id column present'
);

select ok(
    not exists(select 1 from pg_describe('public.customer_orders') where a = '>> Definition >>'),
    'view basic: definition section absent'
);

select ok(
    exists(select 1 from pg_describe('public.customer_orders', true) where a = '>> Definition >>'),
    'view verbose: definition section present'
);
-- 4 tests


-- ============================================================
-- 6. MATERIALIZED VIEW  –  public.product_sales
-- ============================================================

select is(
    (select a from pg_describe('product_sales') limit 1),
    'Materialized view "public.product_sales"',
    'mat view: title row'
);

select ok(
    not exists(select 1 from pg_describe('product_sales') where a = '>> Definition >>'),
    'mat view basic: definition absent'
);

select ok(
    exists(select 1 from pg_describe('product_sales', true) where a = '>> Definition >>'),
    'mat view verbose: definition present'
);

select ok(
    exists(select 1 from pg_describe('product_sales')
           where b like '%"product_sales_product_id_idx"%'),
    'mat view: index shown'
);
-- 4 tests


-- ============================================================
-- 7. SEQUENCE  –  public.customers_customer_id_seq
-- ============================================================

select is(
    (select a from pg_describe('customers_customer_id_seq') limit 1),
    'Sequence "public.customers_customer_id_seq"',
    'sequence: title row'
);

select set_has(
    $$ select a from pg_describe('customers_customer_id_seq') $$,
    $$ values ('Type'),('Start'),('Minimum'),('Maximum'),('Increment'),('Cycles?'),('Cache') $$,
    'sequence: all property rows present'
);

select ok(
    exists(select 1 from pg_describe('customers_customer_id_seq')
           where a = 'Owned by' and b = 'public.customers.customer_id'),
    'sequence: owned by public.customers.customer_id'
);
-- 3 tests


-- ============================================================
-- 8. INDEX  –  customers_pkey and orders_status_cover_idx
-- ============================================================

select is(
    (select a from pg_describe('customers_pkey') limit 1),
    'Index "public.customers_pkey"',
    'index: title row'
);

select ok(
    exists(select 1 from pg_describe('customers_pkey') where c = 'yes'),
    'index: key column marked yes'
);

select is(
    (select a from pg_describe('orders_status_cover_idx') limit 1),
    'Index "public.orders_status_cover_idx"',
    'include index: title row'
);

select ok(
    exists(select 1 from pg_describe('orders_status_cover_idx') where c = 'no'),
    'include index: INCLUDE columns marked Key? = no'
);
-- 4 tests


-- ============================================================
-- 9. PARTITIONED TABLE  –  public.audit_log
-- ============================================================

select is(
    (select a from pg_describe('audit_log') limit 1),
    'Partitioned table "public.audit_log"',
    'partitioned table: title row'
);

select ok(
    exists(select 1 from pg_describe('audit_log') where a like 'Partition key:%created_at%'),
    'partitioned table: partition key shown'
);

select ok(
    exists(select 1 from pg_describe('audit_log') where a = 'Number of partitions: 2'),
    'partitioned table: partition count is 2'
);

select ok(
    exists(select 1 from pg_describe('audit_log')
           where a = 'id' and d = 'generated always as identity'),
    'partitioned table: identity column shown'
);
-- 4 tests


-- ============================================================
-- 10. FOREIGN TABLE  –  public.external_prices
-- ============================================================

select is(
    (select a from pg_describe('external_prices') limit 1),
    'Foreign table "public.external_prices"',
    'foreign table: title row'
);

select ok(
    exists(select 1 from pg_describe('external_prices')
           where a = 'Server' and b = 'local_files'),
    'foreign table: server name shown'
);

select ok(
    exists(select 1 from pg_describe('external_prices')
           where a = 'FDW options' and b like '%filename%'),
    'foreign table: FDW options shown'
);
-- 3 tests


-- ============================================================
-- 11. COMPOSITE TYPE  –  public.address_type
-- ============================================================

select is(
    (select a from pg_describe('address_type') limit 1),
    'Composite type "public.address_type"',
    'composite type: title row'
);

select set_has(
    $$ select a, b from pg_describe('address_type') where b = 'text' $$,
    $$ values ('street','text'),('city','text'),('country','text') $$,
    'composite type: all text columns present'
);
-- 2 tests


-- ============================================================
-- 12. GENERATED & IDENTITY COLUMNS  –  hr.employees / audit_log
-- ============================================================

select ok(
    exists(select 1 from pg_describe('hr.employees')
           where a = 'full_name' and d like 'generated always as%stored'),
    'hr.employees: generated stored column shown'
);

select ok(
    exists(select 1 from pg_describe('audit_log_id_seq')
           where a = 'Sequence for identity column'),
    'identity sequence: shows "Sequence for identity column" not "Owned by"'
);
-- 2 tests


-- ============================================================
-- 13. TRIGGER DETAILS  –  hr.employees
-- ============================================================

select ok(
    exists(select 1 from pg_describe('hr.employees')
           where a = 'employees_normalize_name_trg'
             and c like '%UPDATE OF%first_name%last_name%'),
    'hr.employees: trigger shows UPDATE OF first_name, last_name'
);
-- 1 test


-- ============================================================
-- 14. MULTI-MATCH: separator between descriptions
-- ============================================================

select ok(
    exists(
        select 1
        from (
            select
                a,
                lag(a, 1) over (order by rn) as prev_a,
                lag(a, 2) over (order by rn) as prev2_a
            from (
                select a, row_number() over () as rn
                from pg_describe('cust*')
            ) numbered
        ) lagged
        where (a like 'Table%' or a like 'View%' or a like 'Sequence%' or a like 'Index%')
          and prev_a  = '---'
          and prev2_a = ''
    ),
    'multi-match: blank + --- separator precedes each description'
);

select ok(
    (select count(*) from pg_describe('cust*')
     where a like 'Table "%' or a like 'View "%'
        or a like 'Sequence "%' or a like 'Index "%') >= 7,
    'multi-match: at least 7 distinct title rows for cust*'
);
-- 2 tests


-- ============================================================
-- 15. SELF-REFERENCING FK  –  hr.departments
-- ============================================================

select ok(
    exists(select 1 from pg_describe('hr.departments') where a = '>> Foreign-key constraints >>'),
    'hr.departments: foreign-key constraints section present'
);

select ok(
    exists(select 1 from pg_describe('hr.departments') where a = '>> Referenced by >>'),
    'hr.departments: referenced by section present'
);

select ok(
    exists(select 1 from pg_describe('hr.departments')
           where a = 'hr.departments' and b = 'departments_parent_fk'),
    'hr.departments: self-reference appears in referenced by'
);
-- 3 tests


-- ============================================================
-- 16. _pg_describe_pattern_seg_to_re  –  basic conversions
-- ============================================================

select is(
    _pg_describe_pattern_seg_to_re('foo'),
    'foo',
    'seg_to_re: plain lowercase unchanged'
);

select is(
    _pg_describe_pattern_seg_to_re('FOO'),
    'foo',
    'seg_to_re: unquoted uppercase folded'
);

select is(
    _pg_describe_pattern_seg_to_re('*'),
    '.*',
    'seg_to_re: * becomes .*'
);

select is(
    _pg_describe_pattern_seg_to_re('?'),
    '.',
    'seg_to_re: ? becomes .'
);

select is(
    _pg_describe_pattern_seg_to_re('$'),
    '\$',
    'seg_to_re: $ escaped to \$'
);

select is(
    _pg_describe_pattern_seg_to_re('cust*'),
    'cust.*',
    'seg_to_re: prefix wildcard'
);

select is(
    _pg_describe_pattern_seg_to_re('f?o'),
    'f.o',
    'seg_to_re: ? mid-string'
);

select is(
    _pg_describe_pattern_seg_to_re('[A-Z]'),
    '[a-z]',
    'seg_to_re: character class lowercased and preserved'
);
-- 8 tests


-- ============================================================
-- 17. _pg_describe_pattern_seg_to_re  –  double-quote quoting
-- ============================================================

select is(
    _pg_describe_pattern_seg_to_re('"FOO"'),
    'FOO',
    'seg_to_re: quoted segment preserves case'
);

select is(
    _pg_describe_pattern_seg_to_re('"*"'),
    '\*',
    'seg_to_re: quoted * escaped'
);

select is(
    _pg_describe_pattern_seg_to_re('"?"'),
    '\?',
    'seg_to_re: quoted ? escaped'
);

select is(
    _pg_describe_pattern_seg_to_re('"."'),
    '\.',
    'seg_to_re: quoted . escaped'
);

select is(
    _pg_describe_pattern_seg_to_re('"foo.bar"'),
    'foo\.bar',
    'seg_to_re: dot inside quotes escaped'
);

select is(
    _pg_describe_pattern_seg_to_re('"foo""bar"'),
    'foo"bar',
    'seg_to_re: "" inside quotes produces literal "'
);

select is(
    _pg_describe_pattern_seg_to_re('pre"MID"suf'),
    'preMIDsuf',
    'seg_to_re: mixed quoted and unquoted segments'
);

select is(
    _pg_describe_pattern_seg_to_re('*"TABLE"*'),
    '.*TABLE.*',
    'seg_to_re: wildcards outside quotes, literal inside'
);
-- 8 tests


-- ============================================================
-- 18. _pg_describe_pattern_seg_to_re  –  verify generated regex matches
-- ============================================================

select ok(
    'foo' ~ ('^' || _pg_describe_pattern_seg_to_re('foo') || '$'),
    'regex match: foo matches foo'
);
select ok(
    not ('bar' ~ ('^' || _pg_describe_pattern_seg_to_re('foo') || '$')),
    'regex match: foo does not match bar'
);

select ok(
    'foo' ~ ('^' || _pg_describe_pattern_seg_to_re('FOO') || '$'),
    'regex match: FOO (folded) matches foo'
);

select ok(
    'customers' ~ ('^' || _pg_describe_pattern_seg_to_re('cust*') || '$'),
    'regex match: cust* matches customers'
);
select ok(
    'customer_orders' ~ ('^' || _pg_describe_pattern_seg_to_re('cust*') || '$'),
    'regex match: cust* matches customer_orders'
);
select ok(
    not ('products' ~ ('^' || _pg_describe_pattern_seg_to_re('cust*') || '$')),
    'regex match: cust* does not match products'
);

select ok(
    not ('customers' ~ ('^' || _pg_describe_pattern_seg_to_re('"CUSTOMERS"') || '$')),
    'regex match: "CUSTOMERS" does not match customers'
);

select ok(
    'customers' ~ ('^' || _pg_describe_pattern_seg_to_re('"customers"') || '$'),
    'regex match: "customers" matches customers'
);

select ok(
    'price$usd' ~ ('^' || _pg_describe_pattern_seg_to_re('price$usd') || '$'),
    'regex match: $ in pattern matches literal $'
);
-- 9 tests


-- ============================================================
-- 19. _pg_describe_parse_pattern  –  no dot (name-only)
-- ============================================================

select is(
    (select schema_re from _pg_describe_parse_pattern('customers')),
    null,
    'parse: no dot → schema_re null'
);
select is(
    (select name_re from _pg_describe_parse_pattern('customers')),
    'customers',
    'parse: no dot → name_re = customers'
);
select is(
    (select check_vis from _pg_describe_parse_pattern('customers')),
    true,
    'parse: no dot → check_vis true'
);
select is(
    (select db_name from _pg_describe_parse_pattern('customers')),
    null,
    'parse: no dot → db_name null'
);
-- 4 tests


-- ============================================================
-- 20. _pg_describe_parse_pattern  –  one dot (schema.name)
-- ============================================================

select is(
    (select schema_re from _pg_describe_parse_pattern('public.customers')),
    'public',
    'parse: one dot → schema_re = public'
);
select is(
    (select name_re from _pg_describe_parse_pattern('public.customers')),
    'customers',
    'parse: one dot → name_re = customers'
);
select is(
    (select check_vis from _pg_describe_parse_pattern('public.customers')),
    false,
    'parse: one dot → check_vis false'
);

select is(
    (select schema_re from _pg_describe_parse_pattern('*.*')),
    '.*',
    'parse: *.* → schema_re = .*'
);
select is(
    (select name_re from _pg_describe_parse_pattern('*.*')),
    '.*',
    'parse: *.* → name_re = .*'
);
-- 5 tests


-- ============================================================
-- 21. _pg_describe_parse_pattern  –  two dots (database.schema.name)
-- ============================================================

select is(
    (select db_name from _pg_describe_parse_pattern('mydb.public.customers')),
    'mydb',
    'parse: two dots → db_name = mydb'
);
select is(
    (select schema_re from _pg_describe_parse_pattern('mydb.public.customers')),
    'public',
    'parse: two dots → schema_re = public'
);
select is(
    (select name_re from _pg_describe_parse_pattern('mydb.public.customers')),
    'customers',
    'parse: two dots → name_re = customers'
);
-- 3 tests


-- ============================================================
-- 22. _pg_describe_parse_pattern  –  quoted dots are not separators
-- ============================================================

select is(
    (select schema_re from _pg_describe_parse_pattern('"foo.bar"')),
    null,
    'parse: quoted dot is not a separator → schema_re null'
);
select is(
    (select name_re from _pg_describe_parse_pattern('"foo.bar"')),
    'foo\.bar',
    'parse: quoted dot escaped in name_re'
);
select is(
    (select check_vis from _pg_describe_parse_pattern('"foo.bar"')),
    true,
    'parse: quoted dot → still name-only, check_vis true'
);
-- 3 tests


select * from finish();

rollback;
