
create or replace function pg_help
(
	_table_name varchar(500)
)
returns table
(
	col1 varchar(500),
	col2 varchar(500),
	col3 varchar(500),
	col4 varchar(500)
)
as $$
declare
	_schema_name varchar(500);
	_table_only  varchar(500);
	_obj_comment text;
begin

	_schema_name := split_part(_table_name, '.', 1);
	_table_only  := split_part(_table_name, '.', 2);

	-- suppress the "does not exist, skipping" notice from DROP TABLE IF EXISTS
	set local client_min_messages = warning;

	-- guard against a temp table left over from a previous errored call
	drop table if exists _pg_help_results;

	create temp table _pg_help_results
	(
		col1 varchar(500),
		col2 varchar(500),
		col3 varchar(500),
		col4 varchar(500)
	);

	-- -----------------------------------------------------------------------
	-- >> Table >>
	-- -----------------------------------------------------------------------

	select obj_description(c.oid, 'pg_class')
	into _obj_comment
	from pg_class c
	inner join pg_namespace n on n.oid = c.relnamespace
	where n.nspname = _schema_name
	  and c.relname = _table_only;

	insert into _pg_help_results (col1, col2, col3, col4) values
	('>> Table >>', '', '', ''),
	('', '', '', ''),
	(_table_name, coalesce(_obj_comment, ''), '', ''),
	('', '', '', '');

	-- -----------------------------------------------------------------------
	-- >> Columns >>
	-- col1=name  col2=type  col3=nullable  col4=default
	-- -----------------------------------------------------------------------

	insert into _pg_help_results (col1, col2, col3, col4) values
	('>> Columns >>', '', '', ''),
	('', '', '', '');

	insert into _pg_help_results (col1, col2, col3, col4)
	select
		a.attname,
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

	insert into _pg_help_results (col1, col2, col3, col4) values
	('', '', '', ''),
	('>> Constraints >>', '', '', ''),
	('', '', '', '');

	insert into _pg_help_results (col1, col2, col3, col4)
	select
		case
			when contype = 'p' then 'PRIMARY KEY'
			when contype = 'f' then 'FOREIGN KEY'
			when contype = 'c' then 'CHECK'
			when contype = 'u' then 'UNIQUE'
		end,
		conname,
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

	insert into _pg_help_results (col1, col2, col3, col4) values
	('', '', '', ''),
	('>> Indexes >>', '', '', ''),
	('', '', '', '');

	insert into _pg_help_results (col1, col2, col3, col4)
	select
		case when ix.indisunique then 'UNIQUE ' else '' end || upper(am.amname),
		i.relname,
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
	-- >> Referenced By >>
	-- col1=from_table  col2=constraint_name  col3=definition
	-- -----------------------------------------------------------------------

	insert into _pg_help_results (col1, col2, col3, col4) values
	('', '', '', ''),
	('>> Referenced By >>', '', '', ''),
	('', '', '', '');

	insert into _pg_help_results (col1, col2, col3, col4)
	select
		n2.nspname || '.' || t2.relname,
		c.conname,
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

	return query
	select *
	from _pg_help_results;

	drop table _pg_help_results;

end;
$$ language plpgsql;
