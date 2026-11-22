import pathlib, unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'lib/main.dart').read_text()

class PrepareLinkedGameTests(unittest.TestCase):
    def test_prepare_acknowledgement_is_tracked(self):
        self.assertIn("preparedOnServer = action == 'PREPARE'", SOURCE)
    def test_missing_pin_is_not_silent(self):
        self.assertIn('El partido vinculado todavía no tiene un PIN disponible.', SOURCE)
    def test_prepare_failure_advises_open_not_retry(self):
        self.assertIn('no lo prepares otra vez.', SOURCE)
    def test_failed_action_refreshes_server_state(self):
        part = SOURCE.split('Future<void> _changeChallenge(', 1)[1].split('Widget _challengeCard(', 1)[0]
        self.assertIn('await _refreshAgenda();', part.split('catch (error)',1)[1])

if __name__ == '__main__': unittest.main()
