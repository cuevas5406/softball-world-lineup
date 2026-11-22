from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'lib' / 'main.dart'

class TeamPermissionRefreshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_permission_reload_revokes_stale_team(self):
        block = self.source.split('Future<void> _reloadAuthorizedTeams() async {', 1)[1].split('Future<void> _autoSelectTeam()', 1)[0]
        self.assertIn('stillAuthorized', block)
        self.assertIn('_selectedTeamId = null', block)
        self.assertIn('_roster = null', block)
        self.assertIn('_canRemovePlayer = null', block)

    def test_async_permission_result_guarded(self):
        block = self.source.split('Future<void> _reloadAuthorizedTeams() async {', 1)[1].split('Future<void> _autoSelectTeam()', 1)[0]
        self.assertIn('requestVersion != _teamRequestVersion', block)
        self.assertIn('!identical(_teams, pending)', block)

    def test_create_team_refreshes_permissions(self):
        block = self.source.split('Future<void> _openCreateTeam() async {', 1)[1].split('Future<void> _openPlayerAction', 1)[0]
        self.assertIn('await _reloadAuthorizedTeams()', block)

if __name__ == '__main__':
    unittest.main()
