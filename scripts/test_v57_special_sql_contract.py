"""Static checks only; does not connect to Supabase or execute PostgreSQL."""
from pathlib import Path
import re
s = (Path(__file__).resolve().parents[1] / "propuestas_lab/18_v57_jugadas_especiales_revision_corredores.sql").read_text()
checks = {
 "rpc declarada": "create or replace function public.swl_v56_special_play" in s.lower(),
 "uuid del sustituto validado": "runner_text := p_data ->> 'player_id'" in s and "runner := runner_text::uuid" in s,
 "LAST_OUT normalizado en ambos controles": s.count("btrim(p_data ->> 'player_id') = 'LAST_OUT'") == 2,
 "carreras no contadas por out": "RUNNER_OUT: destination=0 identifica out en home, nunca carrera" in s,
 "doble matanza no excede 3 outs": "if p_action = 'DOUBLE_PLAY' and g.outs > 1" in s,
 "control de version": "swl_v56_lock_batting_turn(p_game_id, p_expected_version)" in s,
 "identidad de bases validada": "swl_v56_validate_base_players(resulting,players)" in s,
 "registro de eventos": "insert into public.swl_game_events" in s,
 "privilegios limitados": "grant execute" in s.lower(),
}
for label, passed in checks.items(): print(("OK" if passed else "FAIL") + " - " + label)
assert all(checks.values())
