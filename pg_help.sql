create or replace function pg_help
(
	_table_name text
)
returns table
(
	col1 text,
	col2 text,
	col3 text,
	col4 text
)
as $$
declare
	_schema_name text;
	_table_only  text;
	_obj_comment text;
begin

	if position('.' in _table_name) > 0 then
		_schema_name := split_part(_table_name, '.', 1);
		_table_only  := split_part(_table_name, '.', 2);
	else
		_schema_name := current_schema();
		_table_only  := _table_name;
	end if;

	-- early-exit if the table doesn't exist
	if not exists (
		select 1
		from pg_class c
		inner join pg_namespace n on n.oid = c.relnamespace
		where n.nspname = _schema_name
		  and c.relname = _table_only
		  and c.relkind in ('r', 'p', 'v', 'm', 'f')
	) then
		return query select
			'Table not found: ' || _schema_name || '.' || _table_only,
			'', '', '';
		return;
	end if;

	-- -----------------------------------------------------------------------
	-- >> Table >>
	-- -----------------------------------------------------------------------

	select obj_description(c.oid, 'pg_class')
	into _obj_comment
	from pg_class c
	inner join pg_namespace n on n.oid = c.relnamespace
	where n.nspname = _schema_name
	  and c.relname = _table_only;

	return query values
		('>> Table >>', '', '', ''),
		('', '', '', ''),
		(_table_name, coalesce(_obj_comment, ''), '', ''),
		('', '', '', '');

	-- -----------------------------------------------------------------------
	-- >> Columns >>
	-- col1=name  col2=type  col3=nullable  col4=default
	-- -----------------------------------------------------------------------

	return query values
		('>> Columns >>', '', '', ''),
		('', '', '', ''),
		('-- Column --', '-- Type --', '-- Nullable --', '-- Default --');

	return query
	select
		a.attname::text,
		upper(
			replace(replace(replace(replace(replace(
				pg_catalog.format_type(a.atttypid, a.atttypmod),
				'character varying', 'varchar'),
				'timestamp without time zone', 'timestamp'),
				'timestamp with time zone', 'timestamptz'),
				'time without time zone', 'time'),
				'time with time zone', 'timetz')
		),
		case when a.attnotnull then 'NOT NULL' else 'NULL' end,
		coalesce(pg_get_expr(d.adbin, d.adrelid), '')
	from pg_catalog.pg_attribute a
	inner join pg_catalog.pg_class t on t.oid = a.attrelid
	inner join pg_catalog.pg_namespace n on n.oid = t.relnamespace
	left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
	where n.nspname = _schema_name
	  and t.relname = _table_only
	  and a.attnum > 0
	  and not a.attisdropped
	order by a.attnum;

	-- -----------------------------------------------------------------------
	-- >> Constraints >>
	-- col1=type  col2=name  col3=definition
	-- -----------------------------------------------------------------------

	return query values
		('', '', '', ''),
		('>> Constraints >>', '', '', ''),
		('', '', '', '');

	return query
	select
		case
			when contype = 'p' then 'PRIMARY KEY'
			when contype = 'f' then 'FOREIGN KEY'
			when contype = 'c' then 'CHECK'
			when contype = 'u' then 'UNIQUE'
		end,
		conname::text,
		pg_get_constraintdef(c.oid),
		''
	from pg_constraint c
	inner join pg_class t on t.oid = c.conrelid
	inner join pg_namespace n on n.oid = c.connamespace
	where n.nspname = _schema_name
	  and t.relname = _table_only
	  and contype in ('p', 'f', 'c', 'u')
	order by
		case contype when 'p' then 1 when 'f' then 2 when 'c' then 3 when 'u' then 4 end,
		conname;

	-- -----------------------------------------------------------------------
	-- >> Indexes >>
	-- col1=type  col2=name  col3=columns  col4=where clause
	-- -----------------------------------------------------------------------

	return query values
		('', '', '', ''),
		('>> Indexes >>', '', '', ''),
		('', '', '', '');

	return query
	select
		case when ix.indisunique then 'UNIQUE ' else '' end || upper(am.amname),
		i.relname::text,
		'(' || array_to_string(array_agg(a.attname order by k.pos), ', ') || ')',
		coalesce('WHERE ' || pg_get_expr(ix.indpred, ix.indrelid), '')
	from pg_index ix
	inner join pg_class i on i.oid = ix.indexrelid
	inner join pg_class t on t.oid = ix.indrelid
	inner join pg_namespace n on t.relnamespace = n.oid
	inner join pg_am am on am.oid = i.relam
	inner join pg_attribute a on a.attrelid = t.oid
	inner join lateral unnest(ix.indkey) with ordinality as k(attnum, pos) on k.attnum = a.attnum
	where n.nspname = _schema_name
	  and t.relname = _table_only
	group by i.relname, ix.indisunique, ix.indisprimary, am.amname, ix.indpred, ix.indrelid
	order by ix.indisprimary desc, i.relname;

	-- -----------------------------------------------------------------------
	-- >> Triggers >>
	-- col1=name  col2=timing+level  col3=events  col4=function
	-- -----------------------------------------------------------------------

	return query values
		('', '', '', ''),
		('>> Triggers >>', '', '', ''),
		('', '', '', '');

	return query
	select
		t.tgname::text,
		case
			when t.tgtype::integer & 64 > 0 then 'INSTEAD OF'
			when t.tgtype::integer & 2  > 0 then 'BEFORE'
			else 'AFTER'
		end || ' ' ||
		case when t.tgtype::integer & 1 > 0 then 'ROW' else 'STATEMENT' end,
		array_to_string(array_remove(array[
			case when t.tgtype::integer & 4  > 0 then 'INSERT'   end,
			case when t.tgtype::integer & 16 > 0 then 'UPDATE'   end,
			case when t.tgtype::integer & 8  > 0 then 'DELETE'   end,
			case when t.tgtype::integer & 32 > 0 then 'TRUNCATE' end
		], null), ' OR '),
		pn.nspname || '.' || p.proname
	from pg_trigger t
	inner join pg_class c on c.oid = t.tgrelid
	inner join pg_namespace n on n.oid = c.relnamespace
	inner join pg_proc p on p.oid = t.tgfoid
	inner join pg_namespace pn on pn.oid = p.pronamespace
	where n.nspname = _schema_name
	  and c.relname = _table_only
	  and not t.tgisinternal
	order by t.tgname;

	-- -----------------------------------------------------------------------
	-- >> Referenced By >>
	-- col1=from_table  col2=constraint_name  col3=definition
	-- -----------------------------------------------------------------------

	return query values
		('', '', '', ''),
		('>> Referenced By >>', '', '', ''),
		('', '', '', '');

	return query
	select
		n2.nspname || '.' || t2.relname,
		c.conname::text,
		pg_get_constraintdef(c.oid),
		''
	from pg_constraint c
	inner join pg_class t on t.oid = c.confrelid
	inner join pg_namespace n on n.oid = t.relnamespace
	inner join pg_class t2 on t2.oid = c.conrelid
	inner join pg_namespace n2 on n2.oid = t2.relnamespace
	where c.contype = 'f'
	  and n.nspname = _schema_name
	  and t.relname = _table_only
	order by n2.nspname || '.' || t2.relname, c.conname;

end;
$$ language plpgsql;
