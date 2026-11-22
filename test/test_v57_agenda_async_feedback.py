from pathlib import Path
import unittest

UI = (Path(__file__).resolve().parents[1] / 'lib/main.dart').read_text()

class AgendaAsyncFeedback(unittest.TestCase):
    def test_send_error_only_for_original_team(self):
        start = UI.index('Future<void> _sendChallenge(')
        end = UI.index('void _showAgendaActionError(', start)
        block = UI[start:end]
        self.assertIn('if (mounted && widget.teamId == teamAtStart) _showAgendaActionError(error);', block)

    def test_action_error_only_for_original_team(self):
        start = UI.index('Future<void> _changeChallenge(')
        end = UI.index('Widget _challengeCard(', start)
        block = UI[start:end]
        self.assertIn('if (mounted && widget.teamId == team) {', block)
        self.assertIn('_showAgendaActionError(error);', block)

if __name__ == '__main__': unittest.main()
