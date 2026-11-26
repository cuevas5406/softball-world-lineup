from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
LOBBY = (ROOT / 'lib/swl_live_lobby.dart').read_text()
SCOREBOARD = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()


class LivePitcherMenuContract(unittest.TestCase):
    def test_pitcher_action_requires_no_active_count(self):
        self.assertIn("live?.balls == 0 && live?.strikes == 0", LOBBY)
        change_pitcher = LOBBY.split("Future<void> _changePitcher(", 1)[1]
        guard = change_pitcher.split("final lineup", 1)[0]
        self.assertIn("_substitutionPending || _uncertainSubstitutionVersion != null", guard)

    def test_pitcher_action_reloads_lineup_before_selection(self):
        self.assertIn("await _loadSavedLineups();\n                if (mounted) await _changePitcher(live);", LOBBY)

    def test_batter_substitution_refreshes_game_and_rejects_overlapping_actions(self):
        self.assertIn("await _refreshGame(afterCurrent: true);", LOBBY)
        substitution = LOBBY.split("Future<void> _substituteBatter(", 1)[1]
        guard = substitution.split("final gameId", 1)[0]
        self.assertIn("_recording || _confirmingPlay", guard)
        self.assertIn("_uncertainPlay || _substitutionPending", guard)
        self.assertIn("if (mounted && context.mounted)", LOBBY)
        self.assertIn("await _substituteBatter(team, _name(team), dialogHost: context);", LOBBY)

    def test_pitcher_change_uses_server_rpc(self):
        self.assertIn("swl_v56_change_pitcher", LOBBY)
        self.assertIn("'p_expected_version': snapshot.version", LOBBY)

    def test_defensive_swap_and_reconciliation_are_available_from_scoreboard(self):
        self.assertIn("widget.onLiveSwapFielders?.call()", SCOREBOARD)
        self.assertIn("await _swapFielders(live)", LOBBY)
        self.assertIn("await widget.onLiveRefresh?.call()", SCOREBOARD)
        self.assertIn("onLiveRefresh: _myTeamId(game) == null ? null : _refreshOfficialScoring", LOBBY)
        refresh = LOBBY.split("Future<void> _refreshOfficialScoring()", 1)[1].split("void _subscribe", 1)[0]
        self.assertIn("await _reviewPendingSubstitution()", refresh)
        self.assertIn("await _recoverScoring(explicit: true)", refresh)


if __name__ == '__main__':
    unittest.main()
