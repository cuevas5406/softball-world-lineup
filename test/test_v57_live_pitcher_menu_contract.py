from pathlib import Path
import unittest

LOBBY = (Path(__file__).resolve().parents[1] / 'lib/swl_live_lobby.dart').read_text()


class LivePitcherMenuContract(unittest.TestCase):
    def test_pitcher_action_requires_no_active_count(self):
        self.assertIn("live?.balls == 0 && live?.strikes == 0", LOBBY)
        self.assertIn("!_substitutionPending && _uncertainSubstitutionVersion == null", LOBBY)

    def test_pitcher_action_reloads_lineup_before_selection(self):
        self.assertIn("await _loadSavedLineups();\n                if (mounted) await _changePitcher(live);", LOBBY)

    def test_batter_substitution_refreshes_game_and_rejects_overlapping_actions(self):
        self.assertIn("await _refreshGame(afterCurrent: true);", LOBBY)
        self.assertIn("!_recording && !_confirmingPlay && !_uncertainPlay", LOBBY)
        self.assertIn("if (mounted && context.mounted)", LOBBY)
        self.assertIn("await _substituteBatter(team, _name(team), dialogHost: context);", LOBBY)

    def test_pitcher_change_uses_server_rpc(self):
        self.assertIn("swl_v56_change_pitcher", LOBBY)
        self.assertIn("'p_expected_version': snapshot.version", LOBBY)


if __name__ == '__main__':
    unittest.main()
