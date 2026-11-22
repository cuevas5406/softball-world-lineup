from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
UI = (ROOT/'lib/main.dart').read_text()
SQL = (ROOT/'propuestas_lab/02_retos.sql').read_text()
class AgendaIsolation(unittest.TestCase):
    def test_team_switch_invalidates_drafts_and_requests(self):
        block = UI[UI.index('void didUpdateWidget(covariant MasterScheduleTab'):UI.index('void dispose()',UI.index('void didUpdateWidget(covariant MasterScheduleTab'))]
        self.assertIn('matches.clear();',block)
        self.assertIn('_agendaRequest++;',block)
    def test_send_challenge_does_not_update_new_team(self):
        block = UI[UI.index('Future<void> _sendChallenge'):UI.index('void _showAgendaActionError')]
        self.assertIn('final teamAtStart = widget.teamId;',block)
        self.assertIn('widget.teamId != teamAtStart',block)
    def test_challenge_rpc_signature_matches_client(self):
        for arg in ('p_home_team_id','p_away_team_id','p_external_team_name','p_scheduled_at','p_stadium'):
            self.assertIn("'"+arg+"':", UI)
            self.assertIn(arg, SQL)
if __name__=='__main__': unittest.main()
