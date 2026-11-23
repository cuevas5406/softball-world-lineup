from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'propuestas_lab/23_v57_tercer_out_hit_propuesta_sin_ejecutar.sql').read_text()


class ThirdOutHitProposal(unittest.TestCase):
    def test_preserves_server_function_contract(self):
        self.assertIn('CREATE OR REPLACE FUNCTION public.swl_v57_batted_ball(', SQL)
        self.assertIn('RETURNS jsonb', SQL)
        self.assertIn('SECURITY DEFINER', SQL)
        self.assertIn("SET search_path TO ''", SQL)
        self.assertIn('REVOKE ALL ON FUNCTION public.swl_v57_batted_ball', SQL)
        self.assertIn('TO authenticated', SQL)

    def test_third_out_changes_half_inning_and_clears_bases(self):
        self.assertIn('terminal := g.outs=2;', SQL)
        self.assertIn('outs=CASE WHEN terminal THEN 0 ELSE g.outs+1 END', SQL)
        self.assertIn('is_top=CASE WHEN terminal THEN NOT g.is_top ELSE g.is_top END', SQL)
        self.assertIn('inning=g.inning+CASE WHEN terminal AND NOT g.is_top THEN 1 ELSE 0 END', SQL)
        self.assertIn('new_occ:=ARRAY[false,false,false]', SQL)
        self.assertIn('new_players:=ARRAY[null,null,null]::uuid[]', SQL)

    def test_runs_only_on_confirmed_non_force_time_play(self):
        self.assertIn('forced_out := moves[retired_source] = -(retired_source+1)', SQL)
        self.assertIn('scored:=0;', SQL)
        self.assertIn('IF confirmed_timing AND NOT forced_out THEN', SQL)
        self.assertIn('FOR i IN (retired_source+1)..3 LOOP', SQL)
        self.assertIn('IF moves[i]=0 THEN scored:=scored+1;', SQL)
        self.assertIn("jsonb_typeof(p_data->'count_runs_on_third_out') <> 'boolean'", SQL)

    def test_records_out_and_keeps_finish_rules(self):
        self.assertIn("'out_runner_id',players[", SQL)
        self.assertIn("'third_out',terminal", SQL)
        self.assertIn('PERFORM public.swl_v56_close_after_play(g);', SQL)
        self.assertNotIn('V57_THIRD_OUT_NOT_ENABLED', SQL)


if __name__ == '__main__':
    unittest.main()
