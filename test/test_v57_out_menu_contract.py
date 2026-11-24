from pathlib import Path
import unittest

SCOREBOARD = (Path(__file__).resolve().parents[1] / 'lib/swl_advanced_scoreboard.dart').read_text()


class LiveOutMenuContract(unittest.TestCase):
    def test_primary_out_button_opens_special_play_menu(self):
        self.assertIn("action == 'OUT'\n                  ? _liveOutMenu()", SCOREBOARD)
        self.assertIn("liveButton('OUT', 'OUT'", SCOREBOARD)

    def test_menu_keeps_normal_out_and_double_play(self):
        self.assertIn("await _submitLiveAction('OUT');", SCOREBOARD)
        self.assertIn("await _sendSpecial('DOUBLE_PLAY', {'source': result});", SCOREBOARD)
        self.assertIn("await _chooseSacrifice(game);", SCOREBOARD)

    def test_third_out_stays_one_tap(self):
        self.assertIn("if (game.outs >= 2 || !(game.firstOccupied", SCOREBOARD)


if __name__ == '__main__':
    unittest.main()
