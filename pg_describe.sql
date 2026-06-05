-- =============================================================================
-- pg_describe  –  SQL equivalent of psql's \d / \d+
--
-- Usage:
--   select * from pg_describe();                          -- list visible relations (\d)
--   select * from pg_describe('customers');               -- describe by name
--   select * from pg_describe('public.customers');        -- schema-qualified
--   select * from pg_describe('cust*');                   -- wildcard pattern
--   select * from pg_describe('hr.*');                    -- all objects in a schema
--   select * from pg_describe('*.*');                     -- all objects in database
--   select * from pg_describe('customers', true);         -- verbose (\d+)
--
-- Pattern rules mirror psql \d exactly:
--   * = any sequence of characters   ? = any single character
--   Double-quoted segments are case-sensitive and treat * ? . as literals
--   A dot (outside quotes) separates schema pattern from name pattern
--   With a schema separator, all schemas are searched (including system ones)
--   Without a schema separator, only visible relations are returned
-- =============================================================================

-- Drop old signatures so reinstalls are clean
drop function if exists _pg_describe_pattern_seg_to_re(text);
drop function if exists _pg_describe_parse_pattern(text);
drop function if exists _pg_describe_one(text, text, boolean);
drop function if exists pg_describe(text);
drop function if exists pg_describe(text, boolean);


-- =============================================================================
-- INTERNAL: convert one pattern segment (no dots) to a POSIX regex fragment
-- Unquoted: folds to lower-case; * → .*, ? → ., $ → \$; other regex chars pass through
-- Quoted:   literal (regex metacharacters are escaped); no case-fold; "" → "
-- =============================================================================

create function _pg_describe_pattern_seg_to_re(_seg text)
returns text
language plpgsql
as $$
declare
    _result text    := '';
    _i      int     := 1;
    _len    int     := length(_seg);
    _ch     text;
    _in_dq  boolean := false;
begin
    while _i <= _len loop
        _ch := substring(_seg from _i for 1);

        if _in_dq then
            if _ch = '"' then
                if _i < _len and substring(_seg from _i + 1 for 1) = '"' then
                    _result := _result || '"';  -- "" → literal "
                    _i      := _i + 1;
                else
                    _in_dq := false;
                end if;
            else
                -- quoted: escape regex metacharacters, preserve case
                if position(_ch in '.*+?()[]{}^$|\') > 0 then
                    _result := _result || '\' || _ch;
                else
                    _result := _result || _ch;
                end if;
            end if;
        else
            case _ch
                when '"' then _in_dq := true;
                when '*'  then _result := _result || '.*';
                when '?'  then _result := _result || '.';
                when '$'  then _result := _result || '\$';      -- literal $
                else           _result := _result || lower(_ch); -- fold + pass through
            end case;
        end if;

        _i := _i + 1;
    end loop;

    return _result;
end;
$$;


-- =============================================================================
-- INTERNAL: parse a full psql relation pattern into its parts
--
-- OUT schema_re  – POSIX regex for the schema name (NULL if no dot separator)
-- OUT name_re    – POSIX regex for the relation name
-- OUT check_vis  – true → apply pg_table_is_visible (no schema separator in pattern)
-- OUT db_name    – non-NULL for database.schema.name patterns (caller validates)
-- =============================================================================

create function _pg_describe_parse_pattern(
    _pattern   text,
    out schema_re  text,
    out name_re    text,
    out check_vis  boolean,
    out db_name    text
)
language plpgsql
as $$
declare
    _i     int     := 1;
    _len   int     := length(_pattern);
    _ch    text;
    _in_dq boolean := false;
    _dots  int[]   := array[]::int[];
begin
    -- Collect positions of all unquoted dots
    while _i <= _len loop
        _ch := substring(_pattern from _i for 1);
        if _in_dq then
            if _ch = '"' then
                if _i < _len and substring(_pattern from _i + 1 for 1) = '"' then
                    _i := _i + 1;   -- skip escaped double-quote
                else
                    _in_dq := false;
                end if;
            end if;
        else
            if    _ch = '"' then _in_dq := true;
            elsif _ch = '.' then _dots   := _dots || _i;
            end if;
        end if;
        _i := _i + 1;
    end loop;

    if coalesce(array_length(_dots, 1), 0) = 0 then
        -- No dot: name-only pattern, visibility filter applies
        schema_re := null;
        name_re   := _pg_describe_pattern_seg_to_re(_pattern);
        check_vis := true;
        db_name   := null;

    elsif array_length(_dots, 1) = 1 then
        -- schema.name
        schema_re := _pg_describe_pattern_seg_to_re(
                         substring(_pattern from 1 for _dots[1] - 1));
        name_re   := _pg_describe_pattern_seg_to_re(
                         substring(_pattern from _dots[1] + 1));
        check_vis := false;
        db_name   := null;

    else
        -- database.schema.name  (first two dots used)
        db_name   := substring(_pattern from 1 for _dots[1] - 1);
        schema_re := _pg_describe_pattern_seg_to_re(
                         substring(_pattern from _dots[1] + 1
                                   for _dots[2] - _dots[1] - 1));
        name_re   := _pg_describe_pattern_seg_to_re(
                         substring(_pattern from _dots[2] + 1));
        check_vis := false;
    end if;
end;
$$;


-- =============================================================================
-- INTERNAL: describe exactly one relation, already resolved to schema + name
-- Contains all the \d / \d+ description logic.
-- =============================================================================

create function _pg_describe_one(
    _schema_name text,
    _table_only  text,
    _verbose     boolean default false
)
returns table (a text, b text, c text, d text)
language plpgsql
as $$
declare
    _obj_comment  text;
    _relkind      text;
    _reloid       oid;
    _owned_by     text;
    _index_footer text;
    _server_name  text;
    _tbl_fdw_opts text;
begin

    select c.oid, c.relkind::text, obj_description(c.oid, 'pg_class')
    into   _reloid, _relkind, _obj_comment
    from   pg_class     c
    join   pg_namespace n on n.oid = c.relnamespace
    where  n.nspname = _schema_name
      and  c.relname = _table_only
      and  c.relkind in ('r','p','v','m','S','i','f','c');

    if not found then
        return;  -- caller reports not-found
    end if;

    -- -------------------------------------------------------------------------
    -- Title
    -- -------------------------------------------------------------------------

    return query values
    (
        case _relkind
            when 'r' then 'Table'
            when 'p' then 'Partitioned table'
            when 'v' then 'View'
            when 'm' then 'Materialized view'
            when 'S' then 'Sequence'
            when 'i' then 'Index'
            when 'f' then 'Foreign table'
            when 'c' then 'Composite type'
        end || ' "' || _schema_name || '.' || _table_only || '"',
        ''::text, ''::text, ''::text
    );

    if _obj_comment is not null then
        return query values
            (''::text,     ''::text, ''::text, ''::text),
            (_obj_comment, ''::text, ''::text, ''::text);
    end if;

    -- =========================================================================
    -- SEQUENCE
    -- =========================================================================

    if _relkind = 'S' then

        return query
        select props.key, props.val, ''::text, ''::text
        from   pg_sequence s
        cross  join lateral (values
            ('Type',      format_type(s.seqtypid, null)),
            ('Start',     s.seqstart::text),
            ('Minimum',   s.seqmin::text),
            ('Maximum',   s.seqmax::text),
            ('Increment', s.seqincrement::text),
            ('Cycles?',   case s.seqcycle when true then 'yes' else 'no' end),
            ('Cache',     s.seqcache::text)
        ) as props(key, val)
        where  s.seqrelid = _reloid;

        -- deptype 'a' = owned by (serial); 'i' = identity column sequence
        select d.deptype, n.nspname || '.' || c.relname || '.' || a.attname
        into   _relkind, _owned_by       -- reuse _relkind temporarily for deptype
        from   pg_depend    d
        join   pg_class     c on c.oid = d.refobjid
        join   pg_namespace n on n.oid = c.relnamespace
        join   pg_attribute a on a.attrelid = c.oid and a.attnum = d.refobjsubid
        where  d.objid   = _reloid
          and  d.deptype in ('a','i')
          and  d.classid = 'pg_class'::regclass;

        if _owned_by is not null then
            return query values (
                case _relkind
                    when 'i' then 'Sequence for identity column'
                    else 'Owned by'
                end,
                _owned_by, ''::text, ''::text);
        end if;

        return;

    end if;

    -- =========================================================================
    -- INDEX (describing the index object itself)
    -- =========================================================================

    if _relkind = 'i' then

        return query values
            (''::text,       ''::text,     ''::text,     ''::text),
            ('Column'::text, 'Type'::text, 'Key?'::text, 'Definition'::text),
            (''::text,       ''::text,     ''::text,     ''::text);

        return query
        select
            coalesce(ta.attname::text, ia.attname::text),
            format_type(ia.atttypid, ia.atttypmod)::text,
            case when k.pos <= ix.indnkeyatts then 'yes' else 'no' end,
            pg_get_indexdef(_reloid, k.pos::int, true)
        from   pg_index ix
        cross  join lateral unnest(ix.indkey) with ordinality as k(attnum, pos)
        join   pg_attribute ia
               on ia.attrelid = _reloid and ia.attnum = k.pos
        left   join pg_attribute ta
               on ta.attrelid = ix.indrelid and ta.attnum = k.attnum and k.attnum != 0
        where  ix.indexrelid = _reloid
        order  by k.pos;

        select
            case when ix.indisprimary then 'primary key, '
                 when ix.indisunique  then 'unique, '
                 else '' end
            || am.amname
            || ', for table "' || n.nspname || '.' || t.relname || '"'
            || coalesce(', predicate (' || pg_get_expr(ix.indpred, ix.indrelid) || ')', '')
        into   _index_footer
        from   pg_index     ix
        join   pg_class     t  on t.oid  = ix.indrelid
        join   pg_namespace n  on n.oid  = t.relnamespace
        join   pg_class     ic on ic.oid = ix.indexrelid
        join   pg_am        am on am.oid = ic.relam
        where  ix.indexrelid = _reloid;

        return query values
            (''::text,      ''::text, ''::text, ''::text),
            (_index_footer, ''::text, ''::text, ''::text);

        return;

    end if;

    -- =========================================================================
    -- COLUMNS (tables, views, mat views, foreign tables, composite types)
    -- a = column name   b = type   c = nullable   d = default / fdw options
    -- =========================================================================

    return query values
        (''::text,              ''::text, ''::text, ''::text),
        ('>> Columns >>'::text, ''::text, ''::text, ''::text),
        (''::text,              ''::text, ''::text, ''::text);

    if _relkind = 'f' then
        return query
        select
            a.attname::text,
            format_type(a.atttypid, a.atttypmod)::text,
            case when a.attnotnull then 'not null' else '' end,
            coalesce(
                (select string_agg(
                            opt.option_name || '=' || quote_literal(opt.option_value),
                            ', ' order by opt.option_name)
                 from   pg_options_to_table(a.attfdwoptions) opt),
                '')
        from   pg_attribute a
        where  a.attrelid = _reloid
          and  a.attnum   > 0
          and  not a.attisdropped
        order  by a.attnum;
    else
        return query
        select
            a.attname::text,
            format_type(a.atttypid, a.atttypmod)::text,
            case when a.attnotnull then 'not null' else '' end,
            coalesce(
                case
                    when a.attidentity  = 'a' then 'generated always as identity'
                    when a.attidentity  = 'd' then 'generated by default as identity'
                    when a.attgenerated = 's' then
                        'generated always as (' || pg_get_expr(d.adbin, d.adrelid) || ') stored'
                    else pg_get_expr(d.adbin, d.adrelid)
                end, '')
        from   pg_attribute  a
        left   join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where  a.attrelid = _reloid
          and  a.attnum   > 0
          and  not a.attisdropped
        order  by a.attnum;
    end if;

    -- =========================================================================
    -- VERBOSE: column details (storage, stats target, description)
    -- Only emitted for columns that have a non-default value in at least one field.
    -- a = column name   b = storage   c = stats target   d = description
    -- =========================================================================

    if _verbose and _relkind <> 'v' then

        if exists (
            select 1
            from   pg_attribute a
            where  a.attrelid = _reloid
              and  a.attnum   > 0
              and  not a.attisdropped
              and  (a.attstattarget is not null
                    or a.attcompression <> ''
                    or col_description(a.attrelid, a.attnum) is not null)
        ) then
            return query values
                (''::text,                    ''::text,         ''::text,      ''::text),
                ('>> Column details >>'::text, 'Storage'::text,  'Stats'::text, 'Description'::text),
                (''::text,                    ''::text,         ''::text,      ''::text);

            return query
            select
                a.attname::text,
                case a.attstorage
                    when 'p' then 'plain'
                    when 'e' then 'external'
                    when 'x' then 'extended'
                    when 'm' then 'main'
                end,
                coalesce(a.attstattarget::text, ''),
                coalesce(col_description(a.attrelid, a.attnum), '')
            from   pg_attribute a
            where  a.attrelid = _reloid
              and  a.attnum   > 0
              and  not a.attisdropped
              and  (a.attstattarget is not null
                    or a.attcompression <> ''
                    or col_description(a.attrelid, a.attnum) is not null)
            order  by a.attnum;

        end if;

    end if;

    -- =========================================================================
    -- VIEW definition (verbose only)
    -- =========================================================================

    if _relkind = 'v' then

        if _verbose then
            return query values
                (''::text,                ''::text, ''::text, ''::text),
                ('>> Definition >>'::text, ''::text, ''::text, ''::text),
                (''::text,                ''::text, ''::text, ''::text);

            return query
            select line::text, ''::text, ''::text, ''::text
            from   unnest(string_to_array(pg_get_viewdef(_reloid, true), E'\n')) as line
            where  trim(line) <> '';
        end if;

        return;

    end if;

    -- Composite types: columns only (+ verbose column details if applicable), done
    if _relkind = 'c' then
        return;
    end if;

    -- =========================================================================
    -- PARTITION KEY (partitioned tables)
    -- =========================================================================

    if _relkind = 'p' then

        return query
        select 'Partition key: ' || pg_get_partkeydef(_reloid),
               ''::text, ''::text, ''::text;

        return query
        select 'Number of partitions: ' || count(*)::text,
               ''::text, ''::text, ''::text
        from   pg_inherits
        where  inhparent = _reloid;

    end if;

    -- =========================================================================
    -- INDEXES (tables, partitioned tables, materialized views)
    -- =========================================================================

    if _relkind in ('r','p','m') then

        if exists (select 1 from pg_index where indrelid = _reloid) then

            return query values
                (''::text,              ''::text, ''::text, ''::text),
                ('>> Indexes >>'::text, ''::text, ''::text, ''::text),
                (''::text,              ''::text, ''::text, ''::text);

            return query
            select
                ''::text,
                '"' || i.relname || '" '
                || case
                    when ix.indisprimary then 'PRIMARY KEY, '
                    when ix.indisunique
                     and exists (select 1 from pg_constraint
                                 where conindid = ix.indexrelid and contype in ('p','u'))
                        then 'UNIQUE CONSTRAINT, '
                    when ix.indisunique then 'UNIQUE, '
                    else ''
                   end
                || am.amname
                || ' ('
                || (select string_agg(
                               pg_get_indexdef(ix.indexrelid, ks.pos::int, true),
                               ', ' order by ks.pos)
                    from   unnest(ix.indkey) with ordinality as ks(attnum, pos)
                    where  ks.pos <= ix.indnkeyatts)
                || ')'
                || case
                    when ix.indnkeyatts < ix.indnatts then
                        ' INCLUDE ('
                        || (select string_agg(
                                       pg_get_indexdef(ix.indexrelid, ks.pos::int, true),
                                       ', ' order by ks.pos)
                            from   unnest(ix.indkey) with ordinality as ks(attnum, pos)
                            where  ks.pos > ix.indnkeyatts)
                        || ')'
                    else ''
                   end
                || coalesce(' WHERE ' || pg_get_expr(ix.indpred, ix.indrelid), ''),
                ''::text,
                ''::text
            from   pg_index ix
            join   pg_class     i  on i.oid  = ix.indexrelid
            join   pg_am        am on am.oid = i.relam
            where  ix.indrelid = _reloid
            order  by ix.indisprimary desc, ix.indisunique desc, i.relname;

        end if;

    end if;

    -- =========================================================================
    -- MATERIALIZED VIEW definition (verbose only)
    -- =========================================================================

    if _relkind = 'm' and _verbose then

        return query values
            (''::text,                ''::text, ''::text, ''::text),
            ('>> Definition >>'::text, ''::text, ''::text, ''::text),
            (''::text,                ''::text, ''::text, ''::text);

        return query
        select line::text, ''::text, ''::text, ''::text
        from   unnest(string_to_array(pg_get_viewdef(_reloid, true), E'\n')) as line
        where  trim(line) <> '';

    end if;

    -- =========================================================================
    -- CHECK CONSTRAINTS (tables, partitioned tables)
    -- =========================================================================

    if _relkind in ('r','p') then

        if exists (select 1 from pg_constraint
                   where conrelid = _reloid and contype = 'c' and conparentid = 0) then

            return query values
                (''::text,                       ''::text, ''::text, ''::text),
                ('>> Check constraints >>'::text, ''::text, ''::text, ''::text),
                (''::text,                       ''::text, ''::text, ''::text);

            return query
            select ''::text, c.conname::text, pg_get_constraintdef(c.oid)::text, ''::text
            from   pg_constraint c
            where  c.conrelid    = _reloid
              and  c.contype     = 'c'
              and  c.conparentid = 0
            order  by c.conname;

        end if;

    end if;

    -- =========================================================================
    -- FOREIGN-KEY CONSTRAINTS (tables, partitioned tables)
    -- =========================================================================

    if _relkind in ('r','p') then

        if exists (select 1 from pg_constraint where conrelid = _reloid and contype = 'f') then

            return query values
                (''::text,                            ''::text, ''::text, ''::text),
                ('>> Foreign-key constraints >>'::text, ''::text, ''::text, ''::text),
                (''::text,                            ''::text, ''::text, ''::text);

            return query
            select ''::text, c.conname::text, pg_get_constraintdef(c.oid)::text, ''::text
            from   pg_constraint c
            where  c.conrelid = _reloid and c.contype = 'f'
            order  by c.conname;

        end if;

    end if;

    -- =========================================================================
    -- NOT-NULL CONSTRAINTS (verbose; tables, foreign tables — PG18+)
    -- =========================================================================

    if _verbose and _relkind in ('r','p','f') then

        if exists (select 1 from pg_constraint where conrelid = _reloid and contype = 'n') then

            return query values
                (''::text,                           ''::text, ''::text, ''::text),
                ('>> Not-null constraints >>'::text,  ''::text, ''::text, ''::text),
                (''::text,                           ''::text, ''::text, ''::text);

            return query
            select ''::text, c.conname::text, pg_get_constraintdef(c.oid)::text, ''::text
            from   pg_constraint c
            where  c.conrelid = _reloid and c.contype = 'n'
            order  by c.conname;

        end if;

    end if;

    -- =========================================================================
    -- REFERENCED BY (tables, partitioned tables)
    -- =========================================================================

    if _relkind in ('r','p') then

        if exists (select 1 from pg_constraint where confrelid = _reloid and contype = 'f') then

            return query values
                (''::text,                   ''::text, ''::text, ''::text),
                ('>> Referenced by >>'::text, ''::text, ''::text, ''::text),
                (''::text,                   ''::text, ''::text, ''::text);

            return query
            select
                (n2.nspname || '.' || t2.relname)::text,
                c.conname::text,
                pg_get_constraintdef(c.oid)::text,
                ''::text
            from   pg_constraint c
            join   pg_class     t2 on t2.oid = c.conrelid
            join   pg_namespace n2 on n2.oid = t2.relnamespace
            where  c.confrelid = _reloid and c.contype = 'f'
            order  by n2.nspname || '.' || t2.relname, c.conname;

        end if;

    end if;

    -- =========================================================================
    -- TRIGGERS (tables, partitioned tables, views)
    -- a = name   b = timing + level   c = events (with UPDATE OF cols)   d = function
    -- =========================================================================

    if _relkind in ('r','p','v') then

        if exists (select 1 from pg_trigger where tgrelid = _reloid and not tgisinternal) then

            return query values
                (''::text,               ''::text, ''::text, ''::text),
                ('>> Triggers >>'::text,  ''::text, ''::text, ''::text),
                (''::text,               ''::text, ''::text, ''::text);

            return query
            select
                t.tgname::text,
                case
                    when t.tgtype::int & 64 > 0 then 'INSTEAD OF'
                    when t.tgtype::int & 2  > 0 then 'BEFORE'
                    else 'AFTER'
                end
                || ' '
                || case when t.tgtype::int & 1 > 0 then 'ROW' else 'STATEMENT' end,
                array_to_string(array_remove(array[
                    case when t.tgtype::int & 4  > 0 then 'INSERT' end,
                    case when t.tgtype::int & 16 > 0 then
                        'UPDATE'
                        || coalesce(
                               nullif(
                                   ' OF ' || (
                                       select string_agg(a.attname, ', ' order by u.ord)
                                       from   unnest(t.tgattr::smallint[])
                                              with ordinality as u(num, ord)
                                       join   pg_attribute a
                                              on a.attrelid = t.tgrelid and a.attnum = u.num
                                   ),
                                   ' OF ')
                               , '')
                    end,
                    case when t.tgtype::int & 8  > 0 then 'DELETE'   end,
                    case when t.tgtype::int & 32 > 0 then 'TRUNCATE' end
                ], null), ' OR '),
                (pn.nspname || '.' || p.proname)::text
            from   pg_trigger   t
            join   pg_proc      p  on p.oid  = t.tgfoid
            join   pg_namespace pn on pn.oid = p.pronamespace
            where  t.tgrelid = _reloid and not t.tgisinternal
            order  by t.tgname;

        end if;

    end if;

    -- =========================================================================
    -- FOREIGN TABLE: server and table-level FDW options
    -- =========================================================================

    if _relkind = 'f' then

        select
            fs.srvname,
            (select string_agg(
                        opt.option_name || '=' || quote_literal(opt.option_value),
                        ', ' order by opt.option_name)
             from   pg_options_to_table(ft.ftoptions) opt)
        into   _server_name, _tbl_fdw_opts
        from   pg_foreign_table  ft
        join   pg_foreign_server fs on fs.oid = ft.ftserver
        where  ft.ftrelid = _reloid;

        return query values
            (''::text,       ''::text,     ''::text, ''::text),
            ('Server'::text, _server_name, ''::text, ''::text);

        if _tbl_fdw_opts is not null then
            return query values
                ('FDW options'::text, '(' || _tbl_fdw_opts || ')', ''::text, ''::text);
        end if;

    end if;

    -- =========================================================================
    -- VERBOSE: replica identity and access method (tables, mat views)
    -- =========================================================================

    if _verbose and _relkind in ('r','p','m') then

        -- Replica identity: only when non-default
        return query
        select
            'Replica identity: ' ||
            case c.relreplident
                when 'n' then 'nothing'
                when 'f' then 'full'
                when 'i' then 'index'
                else null
            end,
            ''::text, ''::text, ''::text
        from   pg_class c
        where  c.oid = _reloid and c.relreplident <> 'd';

        -- Access method
        return query
        select
            'Access method: ' || am.amname,
            ''::text, ''::text, ''::text
        from   pg_class c
        join   pg_am    am on am.oid = c.relam
        where  c.oid = _reloid and c.relam != 0;

    end if;

end;
$$;


-- =============================================================================
-- PUBLIC ENTRY POINT
--
-- No argument  → list visible user relations (equivalent to \dtvmsE)
-- With pattern → describe each matching relation; pattern rules mirror psql \d
-- _verbose     → include \d+ extras (storage, comments, definition, access method)
-- =============================================================================

create function pg_describe(
    _pattern text    default null,
    _verbose boolean default false
)
returns table (a text, b text, c text, d text)
language plpgsql
as $$
declare
    _schema_re  text;
    _name_re    text;
    _check_vis  boolean;
    _db_name    text;
    _first      boolean := true;
    _nschema    text;
    _nname      text;
begin

    -- =========================================================================
    -- LISTING MODE: no argument
    -- Equivalent to \dtvmsE; shows only user-created relations.
    -- =========================================================================

    if _pattern is null or trim(_pattern) = '' then

        return query
        select
            n.nspname::text,
            c.relname::text,
            case c.relkind
                when 'r' then 'table'
                when 'p' then 'partitioned table'
                when 'v' then 'view'
                when 'm' then 'materialized view'
                when 'S' then 'sequence'
                when 'f' then 'foreign table'
            end::text,
            pg_get_userbyid(c.relowner)::text
        from   pg_class     c
        join   pg_namespace n on n.oid = c.relnamespace
        where  c.relkind in ('r','p','v','m','S','f')
          and  pg_table_is_visible(c.oid)
          and  n.nspname not in ('pg_catalog','information_schema')
        order  by n.nspname, c.relname;

        return;

    end if;

    -- =========================================================================
    -- PATTERN MODE: parse, find matches, describe each one
    -- =========================================================================

    select p.schema_re, p.name_re, p.check_vis, p.db_name
    into   _schema_re,  _name_re,  _check_vis,  _db_name
    from   _pg_describe_parse_pattern(_pattern) p;

    -- Validate database for three-part patterns (database.schema.name)
    if _db_name is not null and lower(_db_name) <> lower(current_database()) then
        return query values
            ('ERROR: cross-database references are not implemented: "' || _pattern || '"'::text,
             ''::text, ''::text, ''::text);
        return;
    end if;

    -- Iterate over all matching relations, ordered by schema then name
    for _nschema, _nname in
        select n.nspname, c.relname
        from   pg_class     c
        join   pg_namespace n on n.oid = c.relnamespace
        where  c.relkind in ('r','p','v','m','S','i','f','c')
          and  c.relname  ~ ('^' || _name_re   || '$')
          and  (_schema_re is null or n.nspname ~ ('^' || _schema_re || '$'))
          and  (not _check_vis or pg_table_is_visible(c.oid))
        order  by n.nspname, c.relname
    loop
        -- Separator between descriptions when multiple matches
        if not _first then
            return query values (''::text,    ''::text, ''::text, ''::text);
            return query values ('---'::text, ''::text, ''::text, ''::text);
        end if;
        _first := false;

        return query select * from _pg_describe_one(_nschema, _nname, _verbose);

    end loop;

    -- No matches found
    if _first then
        return query values
            ('Did not find any relation named "' || _pattern || '".'::text,
             ''::text, ''::text, ''::text);
    end if;

end;
$$;
