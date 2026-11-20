"""Static checks of the SQL proposals. These tests never connect to a database."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "propuestas_lab"


def proposal(number):
    return next(ROOT.glob(f"{number}_*.sql")).read_text()


def function(sql, name):
    pattern = rf"create (?:or replace )?function public\.{name}\(.*?\$\$(.*?)\$\$;"
    return re.search(pattern, sql, re.S).group(1)


class ContractTests(unittest.TestCase):
    def test_lineup_contract_delegates_revision_and_validates_pitcher_and_dh(self):
        body = function(proposal("01"), "swl_v56_save_lineup")
        self.assertIn("p_pitcher_id = any(p_player_ids)", body)
        self.assertIn("p_defensive_positions ->> p_pitcher_id::text", body)
        self.assertIn("p_defensive_positions ? p_designated_hitter_id::text", body)
        self.assertIn("group by p.value having count(*) > 1", body)
        self.assertNotIn("primary_position", body)
        self.assertLess(body.index("swl_v53_save_lineup_checked"),
                        body.index("update public.swl_game_lineups"))
        self.assertIn("p_game_id, p_team_id, p_player_ids, p_expected_revision", body)

    def test_position_proposal_reuses_registration_and_checks_roster_on_edit(self):
        sql = proposal("12")
        register = function(sql, "swl_v56_register_player_positions")
        edit = function(sql, "swl_v56_edit_player_positions")
        self.assertIn("swl_register_player(", register)
        self.assertIn("swl_can_manage_roster(p_team_id)", register)
        self.assertIn("swl_can_manage_roster(p_team_id)", edit)
        self.assertIn("removed_at is null", edit)
        self.assertIn("is_refuerzo is false for update", edit)
        self.assertIn("swl_v56_set_position_values(p_player_id, p_primary_position, p_secondary_position)", edit)

    def test_pitcher_position_change_preserves_individual_history(self):
        sql = proposal("05")
        body = function(sql, "swl_v56_change_pitcher")
        self.assertIn("jsonb_build_object(l.pitcher_id::text, previous_position)", body)
        self.assertIn("insert into public.swl_v56_pitcher_changes", body)
        self.assertNotIn("swl_v56_pitching_events", body)

    def test_pitch_classes_from_actual_sql(self):
        sql = proposal("11")
        body = function(sql, "swl_v56_accumulate_pitching")
        categories = []
        for variable in ("ball", "strike", "in_play"):
            condition = re.search(
                rf"{variable} integer := case when (.*?) then 1 else 0 end;", body
            ).group(1)
            categories.append(set(re.findall(r"'([A-Z_]+)'", condition)))
        for action, expected in {
            "BALL": (1, 0, 0),
            "STRIKE": (0, 1, 0),
            "FOUL": (0, 1, 0),
            "HIT": (0, 0, 1),
            "OUT": (0, 0, 1),
            "SACRIFICE_FLY": (0, 0, 1),
            "DOUBLE_PLAY": (0, 0, 1),
            "RUNNER_OUT": (0, 0, 0),
            "RUNNER_MOVE": (0, 0, 0),
            "GHOST_RUNNER": (0, 0, 0),
        }.items():
            with self.subTest(action=action):
                actual = tuple(int(action in category) for category in categories)
                self.assertEqual(actual, expected)
                self.assertLessEqual(sum(actual), 1)
        self.assertIn("pitch_count = pitch_balls + pitch_strikes + pitch_in_play", sql)
        self.assertEqual(body.count("insert into public.swl_v56_pitching_events"), 1)
        self.assertIn("primary key (game_id, version)", proposal("06"))

    def test_rpc_wrappers_keep_versioned_attribution_and_close_order(self):
        for number in ("08", "09"):
            for rpc, legacy in (("record_plate_action", "record_plate_action"),
                                ("apply_hit", "apply_hit_for_player")):
                with self.subTest(proposal=number, rpc=rpc):
                    body = function(proposal(number), f"swl_v56_{rpc}")
                    self.assertLess(body.index(f"swl_v53_{legacy}"),
                                    body.index("swl_v56_accumulate_pitching"))
                    self.assertLess(body.index("swl_v56_accumulate_pitching"),
                                    body.index("swl_v56_close_after_play"))
                    self.assertEqual(body.count("swl_v56_accumulate_pitching"), 1)
        foul = function(proposal("11"), "swl_v56_record_foul")
        self.assertIn("least(g.strikes + 1,2)", foul)
        self.assertEqual(foul.count("swl_v56_accumulate_pitching"), 1)

    def test_close_checks_transition_and_persists_the_completed_half(self):
        close = function(proposal("08"), "swl_v56_close_after_play")
        self.assertIn("latest.version is distinct from prior.version + 1", close)
        self.assertIn("half_ended := latest.is_top <> prior.is_top", close)
        self.assertIn("prior.inning + (case when half_ended and not prior.is_top then 1 else 0 end)", close)
        self.assertIn("half_ended and lead <= -threshold", close)
        self.assertIn("half_ended and lead < 0", close)
        self.assertIn("status = 'FINAL', inning = prior.inning, is_top = prior.is_top", close)
        self.assertIn("swl_final_half_completed = half_ended", close)

    def test_runner_tracker_checks_occupancy_including_unknown_ids(self):
        sql = proposal("09")
        tracker = function(sql, "swl_v56_track_base_players")
        self.assertIn("occupied[i] is distinct from (moves[i] is not null)", tracker)
        self.assertIn("if resulting[moves[i]]", tracker)
        self.assertIn("new_players[moves[i]] := players[i]", tracker)
        self.assertIn("players[3] := players[2]", tracker)
        self.assertIn("players[2] := players[1]", tracker)
        self.assertIn("resulting is distinct from public.swl_v56_base_occupancy(g.bases_state)", tracker)
        self.assertLess(tracker.index("validate_base_players(resulting,players)"),
                        tracker.index("set swl_base_players"))
        guard = function(sql, "swl_v56_validate_base_players")
        self.assertIn("players[i] is not null and occupied[i] is not true", guard)
        self.assertIn("group by id having count(*) > 1", guard)


if __name__ == "__main__":
    unittest.main()
