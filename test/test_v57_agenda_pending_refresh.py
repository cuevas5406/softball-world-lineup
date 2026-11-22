import pathlib
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "lib" / "main.dart"

class AgendaPendingRefreshTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_refresh_queued_during_loading(self):
        self.assertIn("if (_loadingAgenda) {\n      _agendaRefreshPending = true;", self.source)
        self.assertIn("if (_agendaRefreshPending) {\n          _agendaRefreshPending = false;\n          await _refreshAgenda();", self.source)

    def test_pending_cleared_on_team_switch(self):
        self.assertIn("_agendaRefreshPending = false;\n      _inbox = [];", self.source)

    def test_future_date_required(self):
        self.assertIn("if (!selectedAt.isAfter(DateTime.now()))", self.source)
        self.assertIn("Selecciona una fecha y hora futuras", self.source)
