"""Comprobaciones estáticas. No abren conexiones a PostgreSQL."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "propuestas_lab"


def body(file_prefix, function):
    sql = next(ROOT.glob(f"{file_prefix}_*.sql")).read_text()
    return re.search(rf"function public\.{function}\(.*?\$\$(.*?)\$\$;", sql, re.S)[1]


class V57ProposalTests(unittest.TestCase):
    def test_error_goes_to_defensive_team_without_a_hit(self):
        play = body("13", "swl_v57_batted_ball")
        self.assertIn("when p_action = 'HIT_WITH_OUT' then 1 else 0", play)
        self.assertIn("home_errors = coalesce(g.home_errors,0) + case when g.is_top then 1-hit_count", play)
        self.assertIn("'ERROR',details,g.version + 1", play)

    def test_combined_play_advances_once_and_calls_close_in_transaction(self):
        play = body("13", "swl_v57_batted_ball")
        self.assertIn("g.outs + made > 3", play)
        self.assertIn("count_runs_on_third_out", play)
        self.assertIn("(last_out_source + 1)..3", play)
        self.assertIn("turn_index % jsonb_array_length(batting) + 1", play)
        self.assertLess(play.index("swl_v56_accumulate_pitching"), play.index("swl_v56_close_after_play"))

    def test_pitcher_dh_and_defensive_swap_preserve_batting_order(self):
        pitcher = body("13", "swl_v56_change_pitcher")
        self.assertIn("candidate_in_order is distinct from l.pitcher_bats", pitcher)
        self.assertIn("p_player_id = l.designated_hitter_id", pitcher)
        swap = body("13", "swl_v57_swap_fielders")
        self.assertIn("first_pos = 'P' or second_pos = 'P'", swap)
        self.assertNotIn("swl_game_batting_turns", swap)
        self.assertNotIn("set lineup", swap)

    def test_close_uses_prior_half_and_preserves_signatures(self):
        close = body("15", "swl_v56_close_after_play")
        self.assertIn("latest.status::text is distinct from 'IN_PROGRESS'", close)
        self.assertIn("prior.is_top and half_ended and lead > 0", close)
        self.assertIn("inning = prior.inning, is_top = prior.is_top", close)
        self.assertIn("when prior.inning = 3 then latest.swl_super_margin", close)
        self.assertIn("when prior.inning >= 4 then latest.swl_knockout_margin", close)
        self.assertNotIn("swl_home_signed", close)
        self.assertNotIn("swl_away_signed", close)

    def test_team_settings_are_authorized_and_version_checked(self):
        for func in ("swl_v57_team_settings", "swl_v57_update_team_settings"):
            self.assertIn("swl_can_manage_roster(p_team_id) is not true", body("14", func))
        self.assertIn("is distinct from p_expected_revision", body("14", "swl_v57_update_team_settings"))


if __name__ == "__main__":
    unittest.main()
