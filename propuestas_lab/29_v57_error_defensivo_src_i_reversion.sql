DO $patch$
DECLARE
  ddl text := pg_get_functiondef(
    'public.swl_v57_defensive_error(uuid,bigint,text,uuid,jsonb)'::regprocedure
  );
  from_sql text := 'SELECT players[src.i] FROM generate_subscripts(moves,1) AS src(i) WHERE moves[src.i]=0';
  to_sql text := 'SELECT players[i] FROM generate_subscripts(moves,1) AS src(i) WHERE moves[i]=0';
BEGIN
  IF md5(replace(ddl, from_sql, to_sql)) <> '85d1c79919d41af53e71a3e26c45e8e4'
     OR length(ddl) - length(replace(ddl, from_sql, '')) <> length(from_sql)
  THEN
    RAISE EXCEPTION 'La definición instalada cambió. Volver a inspeccionar.';
  END IF;
  EXECUTE replace(ddl, from_sql, to_sql);
END
$patch$;
