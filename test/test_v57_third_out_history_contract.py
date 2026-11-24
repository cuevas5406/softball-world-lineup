from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCOREBOARD = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
LOBBY = (ROOT / 'lib/swl_live_lobby.dart').read_text()


class ThirdOutHistoryContract(unittest.TestCase):
    def test_third_out_is_shown_in_history(self):
        self.assertIn("data['third_out'] == true", SCOREBOARD)
        self.assertIn("' · tercer out · cambio de media entrada'", SCOREBOARD)
        self.assertIn("final creditedRuns = int.tryParse", SCOREBOARD)
        self.assertIn("$outDetail$thirdOutDetail$runsDetail", SCOREBOARD)

    def test_runner_out_identity_is_loaded(self):
        self.assertIn("'out_runner_id'", SCOREBOARD)
        self.assertIn("players[data['out_runner_id']?.toString()]", SCOREBOARD)

    def test_single_runner_out_can_be_confirmed_but_multiple_outs_stay_blocked(self):
        self.assertIn("(outCount > 1 || (defensiveError && outCount > 0))", SCOREBOARD)
        self.assertNotIn("outCount != 1 || live.outs >= 2", SCOREBOARD)
        self.assertIn("'count_runs_on_third_out': timePlay && countRunsOnThirdOut", SCOREBOARD)

    def test_stale_history_does_not_replace_newer_score(self):
        self.assertIn("_currentLiveSnapshot?.version != live.version", SCOREBOARD)
        self.assertIn("_historyQueued = true;\n        return;", SCOREBOARD)
        self.assertIn("await _refreshLiveHistory();", SCOREBOARD)

    def test_remote_version_change_refreshes_history_immediately(self):
        self.assertIn("if (versionChanged) unawaited(_refreshLiveHistory());", SCOREBOARD)
        self.assertIn("if (versionChanged || accessChanged)", SCOREBOARD)

    def test_lobby_routes_through_server_rpc(self):
        self.assertIn("swl_v57_batted_ball", LOBBY)
        self.assertIn("'p_batter_id': plateBatterId", LOBBY)


if __name__ == '__main__':
    unittest.main()
