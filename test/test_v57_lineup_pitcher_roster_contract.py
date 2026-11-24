from pathlib import Path
import unittest

EDITOR = (Path(__file__).resolve().parents[1] / 'lib/swl_lineup_editor.dart').read_text()


class PitcherRosterContract(unittest.TestCase):
    def test_pitcher_can_be_chosen_from_full_roster(self):
        self.assertIn("labelText: 'Pitcher titular (roster completo)'", EDITOR)
        self.assertIn("for (final player in widget.roster.values)", EDITOR)
        self.assertIn("widget.draft.assign(id, 'P');", EDITOR)

    def test_pitcher_batting_and_full_order_are_guarded(self):
        self.assertIn("widget.draft.selected.length >= 13", EDITOR)
        self.assertIn("Retira uno del orden antes de", EDITOR)
        self.assertIn("widget.draft.pitcherBats = false;", EDITOR)
        self.assertIn("widget.draft.designatedId = null;", EDITOR)


if __name__ == '__main__':
    unittest.main()
