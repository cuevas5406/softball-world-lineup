-- Altas idempotentes aplicadas en LAB. Usan la secuencia oficial.
DO $seed$
DECLARE
  g public.swl_live_games%rowtype;
  team_id_seed uuid;
  manager_id_seed uuid;
  player_id_seed uuid;
  named_count integer;
  suffix text;
  series_name text;
  jersey text;
  position text;
BEGIN
  SELECT * INTO STRICT g FROM public.swl_live_games WHERE game_pin='SWL-567892';
  PERFORM pg_advisory_xact_lock(hashtextextended('swl_v57_reservas_lab',0));
  FOREACH series_name IN ARRAY ARRAY['Jodones','300'] LOOP
    IF series_name='Jodones' THEN
      SELECT id INTO STRICT team_id_seed FROM public.teams WHERE id=g.away_team_id AND name='Los Jodones';
      manager_id_seed:=g.away_manager_id;
    ELSE
      SELECT id INTO STRICT team_id_seed FROM public.teams WHERE id=g.home_team_id AND name='Los 300';
      manager_id_seed:=g.home_manager_id;
    END IF;
    PERFORM set_config('request.jwt.claim.sub',manager_id_seed::text,true);
    IF public.swl_can_manage_roster(team_id_seed) IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'El mánager no tiene permiso vigente para fichar';
    END IF;
    FOR i IN 1..5 LOOP
      suffix:='V57 Reserva '||series_name||' '||lpad(i::text,2,'0');
      jersey:=(92+i)::text;
      position:=(ARRAY['P','1B','2B','SS','LF'])[i];
      SELECT count(*) INTO named_count FROM public.players p WHERE p.first_name='Prueba' AND p.last_name=suffix;
      IF named_count>1 THEN RAISE EXCEPTION 'Identidad de reserva ambigua: %',suffix; END IF;
      IF named_count=1 THEN
        SELECT p.id INTO STRICT player_id_seed FROM public.players p WHERE p.first_name='Prueba' AND p.last_name=suffix;
        IF NOT EXISTS (SELECT FROM public.rosters r WHERE r.team_id=team_id_seed AND r.player_id=player_id_seed AND r.removed_at IS NULL)
        THEN RAISE EXCEPTION 'La reserva ya existe, pero su fichaje requiere revisión: %',suffix; END IF;
      ELSE
        IF EXISTS (SELECT FROM public.rosters r JOIN public.players p ON p.id=r.player_id
          WHERE r.team_id=team_id_seed AND r.removed_at IS NULL AND p.jersey_number=jersey)
        THEN RAISE EXCEPTION 'Dorsal asignado en %: %',series_name,jersey; END IF;
        SELECT x.player_id INTO STRICT player_id_seed
          FROM public.swl_register_player('Prueba',suffix,jersey,position,NULL) x;
        PERFORM public.swl_sign_player(team_id_seed,player_id_seed,false);
      END IF;
    END LOOP;
  END LOOP;
END
$seed$;
