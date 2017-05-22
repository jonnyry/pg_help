
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
begin

	create temp table results
	(
		col1 varchar(500),
		col2 varchar(500),
		col3 varchar(500),
		col4 varchar(500)
	);

	insert into results (col1, col2, col3, col4) values 
	('>> Table >>', '', '', ''),
	('', '', '', ''),
	(_table_name, '', '', ''),
	('', '', '', '');

	insert into results (col1, col2, col3, col4) values 
	('>> Columns >>', '', '', ''),
	('', '', '', '');

	insert into results (col1, col2, col3, col4)
	select 
		column_name,
		upper(replace(data_type, 'character varying', 'varchar')) || coalesce('(' || character_maximum_length || ')', ''),
		case 
			when is_nullable = 'YES' then 'NULL' 
			else 'NOT NULL' 
		end as column_expr,
		''
	from information_schema.columns c
	where c.table_schema || '.' || c.table_name = _table_name
	order by c.ordinal_position;
	
	
	insert into results (col1, col2, col3, col4)
	values 
	('', '', '', ''),
	('>> Constraints >>', '', '', ''),
	('', '', '', '');
	
	insert into results (col1, col2, col3, col4)
	select 
		constraint_type,
		constraint_name,
		constraint_definition,
		''
	from
	(
		select 
			case
				when contype = 'p' then 1
				when contype = 'f' then 2
				when contype = 'c' then 3
				when contype = 'u' then 4
			end as order_by,
			case
				when contype = 'p' then 'PRIMARY KEY'
				when contype = 'f' then 'FOREIGN KEY'
				when contype = 'c' then 'CHECK'
				when contype = 'u' then 'UNIQUE'
			end as constraint_type,
			conrelid::regclass AS table_from, 
			conname as constraint_name, 
			pg_get_constraintdef(c.oid) as constraint_definition
		from pg_constraint c
		inner join pg_namespace n on n.oid = c.connamespace
		where contype in ('f','p','c','u') 
		order by order_by, constraint_name
	) a
	where cast(a.table_from as varchar) = _table_name;


	insert into results (col1, col2, col3, col4)
	values 
	('', '', '', ''),
	('>> Indexes >>', '', '', ''),
	('', '', '', '');
	
	insert into results (col1, col2, col3, col4)
	select
		'',
		index_name,
		column_names,
		where_clause
	from
	(
		select
		    i.relname as index_name,
		    '(' || array_to_string(array_agg(a.attname), ', ') || ')' as column_names,
		    coalesce('WHERE ' || pg_get_expr(ix.indpred, ix.indrelid), '') as where_clause,
			ix.indisprimary,
			ix.indisunique,
			ix.indpred
		from pg_class i 
		inner join pg_index ix on i.oid = ix.indexrelid 
		inner join pg_class t on t.oid = ix.indrelid
		inner join pg_attribute a on a.attrelid = t.oid and a.attnum = any(ix.indkey)
		inner join pg_namespace n on t.relnamespace = n.oid
		where t.relkind = 'r'
		and n.nspname || '.' || t.relname = _table_name
		group by t.relname, i.relname, ix.indisprimary, ix.indisunique, pg_get_expr(ix.indpred, ix.indrelid)
	) indexes
	where 

	return query
	select * 
	from results;
	
	drop table results;

end;
$$ language plpgsql;

