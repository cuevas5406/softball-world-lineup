from pathlib import Path
import unittest
S = (Path(__file__).resolve().parents[1]/'lib/main.dart').read_text()
class HubTeamSync(unittest.TestCase):
    def test_hub_has_mutable_authorized_team_state(self):
        hub=S.split('class _MainAppMasterHubState',1)[1].split('// =========================================================================\n// PESTAÑA',1)[0]
        self.assertIn('late List<Map<String, dynamic>> _authorizedTeams;',hub)
        self.assertIn('onAuthorizedTeamsChanged: _applyAuthorizedTeams',hub)
        self.assertIn('authorizedTeams: _authorizedTeams',hub)
    def test_revoked_active_team_cleared(self):
        hub=S.split('void _applyAuthorizedTeams(',1)[1].split('Future<void> _editMyRole',1)[0]
        self.assertIn('valid.isNotEmpty ? valid.first',hub)
        self.assertIn('teams.length == 1 ? teams.first : null',hub)
    def test_child_reloads_server_permissions_to_hub(self):
        child=S.split('Future<void> _reloadAuthorizedTeams() async {',1)[1].split('Future<void> _autoSelectTeam()',1)[0]
        self.assertIn('widget.onAuthorizedTeamsChanged?.call(teams)',child)
        self.assertIn('requestVersion != _teamRequestVersion',child)
if __name__=='__main__':unittest.main()
