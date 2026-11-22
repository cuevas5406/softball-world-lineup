import pathlib, unittest
SOURCE = (pathlib.Path(__file__).resolve().parents[1] / 'lib/swl_live_lobby.dart').read_text()
JOIN = SOURCE.split('Future<void> _joinFromPin(', 1)[1].split('Future<void> _searchTeams(', 1)[0]

class PinJoinContractTests(unittest.TestCase):
    def test_pin_requires_six_digits(self):
        self.assertIn(r"RegExp(r'^\d{6}$')", JOIN)
    def test_read_only_never_joins(self):
        self.assertIn('!widget.readOnly && userId != null', JOIN)
    def test_away_authorization_required(self):
        self.assertIn('authorizedIds.contains(awayId)', JOIN)
    def test_completed_games_not_claimed(self):
        self.assertIn("status != 'FINAL' && status != 'OFFICIAL'", JOIN)
    def test_server_result_matches_requested_pin(self):
        self.assertIn("linked['game_pin']?.toString().trim().toUpperCase() != pin", JOIN)
    def test_unexpected_response_rejected(self):
        self.assertIn('result is! Map', JOIN)

if __name__ == '__main__': unittest.main()
