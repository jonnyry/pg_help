-- Runs plpgsql_check against all pg_describe functions.
-- Raises an exception (non-zero exit) if any issues are found.

create extension if not exists plpgsql_check;

do $$
declare
    v_issues text;
begin
    select string_agg(m, e'\n' order by m)
    into   v_issues
    from (
        select * from plpgsql_check_function('pg_describe(text,boolean)')
        union all
        select * from plpgsql_check_function('_pg_describe_one(text,text,boolean)')
        union all
        select * from plpgsql_check_function('_pg_describe_pattern_seg_to_re(text)')
        union all
        select * from plpgsql_check_function('_pg_describe_parse_pattern(text)')
    ) t(m);

    if v_issues is not null then
        raise exception e'plpgsql_check issues found:\n%', v_issues;
    end if;

    raise notice 'All functions clean.';
end;
$$;
