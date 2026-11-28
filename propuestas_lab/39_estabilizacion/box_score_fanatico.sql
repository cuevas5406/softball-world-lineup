-- Superficie de lectura para el Box Score del fanático.
CREATE FUNCTION public.swl_v57_spectator_box_source(p_game_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $source$
  WITH lineups AS (
    SELECT jsonb_build_object('team_id', l.team_id, 'pitcher_id', l.pitcher_id,
      'defensive_positions', l.defensive_positions,
      'designated_hitter_id', l.designated_hitter_id,
      'lineup', (SELECT coalesce(jsonb_agg(jsonb_build_object(
        'player_id',s.slot->'player_id','order',s.slot->'order',
        'batting_order',s.slot->'batting_order','batting_role',s.slot->'batting_role')
        ORDER BY s.ord),'[]'::jsonb)
        FROM jsonb_array_elements(l.lineup) WITH ORDINALITY AS s(slot,ord))) AS data, l.team_id
    FROM public.swl_game_lineups l WHERE l.game_id=p_game_id
  ), events AS (
    SELECT e.id, e.version, jsonb_build_object('version', e.version,
             'inning', e.inning,
             'is_top', e.is_top,
             'batting_team_id', e.batting_team_id,
             'event_type', e.event_type,
       'event_data', (SELECT coalesce(jsonb_object_agg(f.key,f.value),'{}'::jsonb)
         FROM jsonb_each(CASE WHEN jsonb_typeof(e.event_data)='object'
              THEN e.event_data ELSE '{}'::jsonb END) f
         WHERE f.key IN ('advance_cause', 'batter_base', 'batter_id', 'incoming_player_id', 'outgoing_player_id', 'out_runner_id', 'out_runner_ids', 'outs', 'outs_added', 'pitcher_id', 'plate_appearance_completed', 'player_id', 'rbi', 'reverts_version', 'runner_id', 'runs', 'scope', 'scoring_player_ids'))) AS data
    FROM public.swl_game_events e WHERE e.game_id=p_game_id
  ), changes AS (
    SELECT c.version, c.team_id, jsonb_build_object('version', c.version,
             'team_id', c.team_id,
             'old_pitcher_id', c.old_pitcher_id,
             'new_pitcher_id', c.new_pitcher_id) AS data
    FROM public.swl_v56_pitcher_changes c WHERE c.game_id=p_game_id
  ), pitches AS (
    SELECT p.version, p.pitcher_id, jsonb_build_object('version', p.version,
             'pitcher_id', p.pitcher_id,
             'outs', p.outs,
             'hits', p.hits,
             'walks', p.walks,
             'strikes_out', p.strikes_out,
             'pitch_count', to_jsonb(p)->'pitch_count',
             'pitch_balls', to_jsonb(p)->'pitch_balls',
             'pitch_strikes', to_jsonb(p)->'pitch_strikes',
             'pitch_in_play', to_jsonb(p)->'pitch_in_play') AS data
    FROM public.swl_v56_pitching_events p WHERE p.game_id=p_game_id
  ), player_ids AS (
    SELECT slot->>'player_id' AS id
      FROM lineups l CROSS JOIN LATERAL jsonb_array_elements(l.data->'lineup') AS slot
    UNION SELECT jsonb_object_keys(CASE
      WHEN jsonb_typeof(data->'defensive_positions')='object'
        THEN data->'defensive_positions' ELSE '{}'::jsonb END) FROM lineups
    UNION SELECT data->>'designated_hitter_id' FROM lineups
    UNION SELECT data->>'pitcher_id' FROM lineups
    UNION SELECT data->>'old_pitcher_id' FROM changes
    UNION SELECT data->>'new_pitcher_id' FROM changes
    UNION SELECT pitcher_id::text FROM pitches
    UNION SELECT data->'event_data'->>'batter_id' FROM events
    UNION SELECT data->'event_data'->>'incoming_player_id' FROM events
    UNION SELECT data->'event_data'->>'outgoing_player_id' FROM events
    UNION SELECT scorer FROM events e CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(e.data->'event_data'->'scoring_player_ids')='array'
        THEN e.data->'event_data'->'scoring_player_ids' ELSE '[]'::jsonb END) AS scorer
  )
  SELECT jsonb_build_object(
    'game', jsonb_build_object('id', g.id,
             'game_pin', g.game_pin,
             'status', g.status,
             'created_at', g.created_at,
             'version', g.version,
             'inning', g.inning,
             'is_top', g.is_top,
             'swl_finish_reason', g.swl_finish_reason,
             'swl_regulation_innings', g.swl_regulation_innings,
             'home_team_id', g.home_team_id,
             'away_team_id', g.away_team_id,
             'home_runs', g.home_runs,
             'away_runs', g.away_runs,
             'home_hits', g.home_hits,
             'away_hits', g.away_hits,
             'home_errors', g.home_errors,
             'away_errors', g.away_errors,
             'home_innings', g.home_innings,
             'away_innings', g.away_innings),
    'lineups', (SELECT coalesce(jsonb_agg(l.data ORDER BY l.team_id),'[]'::jsonb) FROM lineups l),
    'events', (SELECT coalesce(jsonb_agg(e.data ORDER BY e.version,e.id),'[]'::jsonb)
               FROM events e WHERE e.version<=g.version),
    'changes', (SELECT coalesce(jsonb_agg(c.data ORDER BY c.version,c.team_id),'[]'::jsonb)
                FROM changes c WHERE c.version<=g.version),
    'pitches', (SELECT coalesce(jsonb_agg(p.data ORDER BY p.version,p.pitcher_id),'[]'::jsonb)
                FROM pitches p WHERE p.version<=g.version),
    'players', (SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,
      'first_name',p.first_name,'last_name',p.last_name,'jersey_number',p.jersey_number) ORDER BY p.id),'[]'::jsonb)
      FROM player_ids i JOIN public.players p ON p.id=CASE
        WHEN i.id ~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' THEN i.id::uuid END)
  )
  FROM public.swl_live_games g
  WHERE g.id=p_game_id AND (SELECT auth.uid()) IS NOT NULL
    AND g.status IN ('IN_PROGRESS','FINAL','OFFICIAL');
$source$;
REVOKE ALL ON FUNCTION public.swl_v57_spectator_box_source(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.swl_v57_spectator_box_source(uuid) TO authenticated;
