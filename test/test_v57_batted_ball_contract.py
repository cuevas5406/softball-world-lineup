from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'propuestas_lab/13_v57_batazos_y_defensa.sql').read_text()

class BattedBallContract(unittest.TestCase):
    def test_validation_before_conversion(self):
        start = SQL.index('create or replace function public.swl_v57_batted_ball(')
        end = SQL.index('revoke all on function public.swl_v57_batted_ball', start)
        body = SQL[start:end]
        assert body.index('jsonb_typeof(p_data)') < body.index('drives := array[')
        assert body.index('jsonb_each(p_data)') < body.index('batter_base := (p_data')
        assert body.index('auth.uid() is null') < body.index('drives := array[')

    def test_negative_destinations_for_runner_outs(self):
        # -2, -3 y -4 representan outs en segunda, tercera y home.
        assert "field.value::text !~ '^(-[1-4]|[0-4])$'" in SQL
        assert "field.key = 'p_batter_base' and field.value::text !~ '^[1-4]$'" in SQL
        assert 'if dest < 0 then' in SQL

    def test_third_out_timing_and_forced_out(self):
        assert 'count_runs_on_third_out' in SQL
        assert 'drives[last_out_source] = -(last_out_source + 1)' in SQL
        assert re.search(r'for i in \(last_out_source \+ 1\)\.\.3 loop\s+if drives\[i\] = 0', SQL)

    def test_last_out_available_after_multi_out_play(self):
        assert "'last_out_player_id',case when made >= 1 then last_out end" in SQL
        assert 'last_out := g.swl_base_players[i]' in SQL

    def test_last_out_chronology_contract(self):
        assert 'chosen_last_out_source := (p_data->>\'p_last_out_source\')::integer;' in SQL
        assert 'last_out := g.swl_base_players[chosen_last_out_source];' in SQL
        assert 'drives[chosen_last_out_source] >= 0' in SQL
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        assert '¿Cuál corredor fue el último out?' in ui
        assert "'p_last_out_source': lastOutSource" in ui
        assert '(outCount > 1 && live.outs + outCount == 3 && lastOutSource == null)' in ui

    def test_homerun_and_routing(self):
        assert 'or batter_base not between 1 and 4' in SQL
        assert 'if batter_base < 4 then' in SQL
        assert 'runs := 1; -- El bateador anota en jonrón.' in SQL
        assert 'batter_base = 4 and dest <> 0' in SQL
        assert "if g.outs + made > 3 then" in SQL
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        assert "action == 'HIT' ? 'HIT_WITH_OUT' : action" in ui
        lobby = (ROOT / 'lib/swl_live_lobby.dart').read_text()
        assert "extendedBall ? <String, dynamic>{" in lobby
        assert "action == 'DOUBLE_PLAY' ? <String, dynamic>{" in lobby
        assert "'p_data': <String, dynamic>{" in lobby
        assert "'p_batter_id': plateBatterId," in lobby
        assert "...hitParams!," in lobby
        assert "'swl_v56_record_plate_action', params: rpcParams" in lobby

    def test_homerun_regression_cases_present(self):
        rules = (ROOT / 'test/swl_play_rules_test.dart').read_text()
        for scenario in ('Jonrón solitario suma una carrera',
                         'Jonrón con corredores en primera y tercera suma tres carreras',
                         'Jonrón no permite retirar a un corredor'):
            self.assertIn(scenario, rules)
        self.assertIn('if batter_base = 4 and dest <> 0 then', SQL)
        self.assertIn('runs := 1; -- El bateador anota en jonrón.', SQL)

    def test_lineup_order_matches_flutter_contract(self):
        identity = (ROOT / 'lib/swl_lineup_identity.dart').read_text()
        self.assertIn("slot['order'] ?? slot['batting_order']", identity)
        self.assertIn("coalesce(slot->>'order',slot->>'batting_order') = turn_index::text", SQL)
        self.assertNotIn("(slot->>'order')::integer = turn_index", SQL)

    def test_special_plays_use_declared_batting_order(self):
        special = (ROOT / 'propuestas_lab/18_v57_jugadas_especiales_revision_corredores.sql').read_text()
        self.assertIn("coalesce(slot.item ->> 'order', slot.item ->> 'batting_order') = turn_order::text", special)
        self.assertIn("select coalesce(slot.item ->> 'order', slot.item ->> 'batting_order')::integer into turn_order", special)
        self.assertNotIn('slot.ordinality = turn_order', special)
        self.assertNotIn('slot.ordinality::integer into turn_order', special)

    def test_error_cannot_be_recorded_as_homerun(self):
        self.assertIn("or (p_action = 'ERROR' and batter_base = 4)", SQL)
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn('[1, 2, 3, if (!defensiveError) 4]', ui)
        self.assertIn("batter_base = 4 and dest <> 0", SQL)

    def test_history_refresh_after_committed_play(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertEqual(ui.count('await _refreshLiveScore();\n      await _refreshLiveHistory();'), 2)
        self.assertNotIn('unawaited(_refreshLiveHistory());\n      await _refreshLiveScore();', ui)
        self.assertIn('_historyQueued = true;', ui)

    def test_history_queued_refresh_is_awaited(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn('Completer<void>? _historyIdleCompleter;', ui)
        self.assertIn('await _historyIdleCompleter?.future;', ui)
        self.assertIn('await _refreshLiveHistory();', ui)
        self.assertNotIn('if (mounted) unawaited(_refreshLiveHistory());', ui)

    def test_manual_refresh_loads_lineups_once(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn('Future<void> _refreshLiveScore({bool forceLineups = false}) async {', ui)
        self.assertIn('if (forceLineups || versionChanged ||', ui)
        self.assertIn('await _refreshLiveScore(forceLineups: true);', ui)
        self.assertNotIn('await _refreshLiveScore();\n                if (!mounted) return;\n                await _loadLiveLineups();', ui)

    def test_score_refresh_waits_for_in_flight_poll(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn('bool _scoreQueued = false;', ui)
        self.assertIn('await _scoreIdleCompleter?.future;', ui)
        self.assertIn('if (_scoreQueued && mounted)', ui)
        self.assertIn('await _refreshLiveScore();', ui)
        self.assertNotIn('snapshot.gameId.isEmpty || _refreshInFlight) return;', ui)

    def test_history_resolves_runner_out_identity(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn("for (final key in ['batter_id', 'runner_id', 'last_out_player_id', 'out_runner_id'])", ui)
        self.assertIn("action == 'RUNNER_OUT' || action == 'DOUBLE_PLAY'", ui)
        self.assertIn("data['last_out_player_id'] ?? data['runner_id'] ?? data['batter_id']", ui)

    def test_sacrifice_preview_matches_server_preconditions(self):
        dart = (ROOT / 'lib/swl_play_rules.dart').read_text()
        special = (ROOT / 'propuestas_lab/18_v57_jugadas_especiales_revision_corredores.sql').read_text()
        self.assertIn('if (outs >= 2 || !third || thirdTo != 0)', dart)
        self.assertIn('if g.outs >= 2 or not occupied[3] or players[3] is null', special)
        self.assertIn('or destinations[3] is distinct from 0', special)

    def test_sacrifice_runner_order_matches_rpc(self):
        dart = (ROOT / 'lib/swl_play_rules.dart').read_text()
        special = (ROOT / 'propuestas_lab/18_v57_jugadas_especiales_revision_corredores.sql').read_text()
        self.assertIn('for (final base in [3, 2, 1])', dart)
        self.assertIn('effectiveDestination > previousDestination', dart)
        self.assertIn('effectiveDestination == previousDestination && effectiveDestination != 4', dart)
        self.assertIn('if next_dest > previous_dest or (next_dest = previous_dest and next_dest <> 4)', special)

    def test_runner_advancement_cannot_pass_lead_runner(self):
        dart = (ROOT / 'lib/swl_play_rules.dart').read_text()
        self.assertIn('Un corredor no puede rebasar al corredor que va delante', dart)
        self.assertIn('effectiveDestination > previousDestination', dart)
        tests = (ROOT / 'test/swl_play_rules_test.dart').read_text()
        self.assertIn("test('Avance no permite rebasar al corredor adelantado'", tests)
        self.assertIn("test('Avance permite que dos corredores anoten'", tests)

    def test_home_out_and_third_out_regressions(self):
        rules = (ROOT / 'test/swl_play_rules_test.dart').read_text()
        for scenario in ('Out en home no suma carrera',
                         'Tercer out en home limpia bases',
                         'Tercer out de tiempo sin confirmación',
                         'Tercer out de tiempo confirmado'):
            self.assertIn(scenario, rules)
        dart = (ROOT / 'lib/swl_play_rules.dart').read_text()
        self.assertIn('countRunsOnThirdOut && outCount == 1 && !forced', dart)
        self.assertIn('moves.skip(retired + 1).where((dest) => dest == 0)', dart)
        self.assertIn("if (outs >= 2 || !third || thirdTo != 0)", dart)
        self.assertNotIn('if (outs == 2) {', dart[dart.index('SwlPlayState sacrificeFly('):dart.index('SwlPlayState runnerOut(')])

    def test_double_play_history_shows_batter_and_runner(self):
        scoreboard = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn("data['last_out_player_id'] ?? data['runner_id'] ?? data['batter_id']", scoreboard)
        self.assertIn("final dpBatter = players[data['batter_id']?.toString()]", scoreboard)
        self.assertIn("'DOUBLE_PLAY' => ('DP', dpDescription)", scoreboard)
        self.assertIn("'Doble play · bateador: $dpBatterName'", scoreboard)

    def test_manual_refresh_waits_for_score_lineup_and_history(self):
        ui = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        section = ui[ui.index("tooltip: 'Actualizar pizarra'"):]
        section = section[:section.index('if (widget.onLiveSubstitute')]
        self.assertIn('await _refreshLiveScore(forceLineups: true);', section)
        self.assertNotIn('await _loadLiveLineups();', section)
        self.assertIn('await _refreshLiveHistory();', section)
        self.assertLess(section.index('await _refreshLiveScore(forceLineups: true);'),
                        section.index('await _refreshLiveHistory();'))
        self.assertNotIn('unawaited(_refreshLiveHistory())', section)

    def test_queued_lineup_refresh_is_awaited(self):
        dart = (ROOT / 'lib/swl_advanced_scoreboard.dart').read_text()
        self.assertIn('Completer<void>? _lineupsIdleCompleter;', dart)
        self.assertIn('await _lineupsIdleCompleter?.future;', dart)
        self.assertIn('await _loadLiveLineups();', dart)
        self.assertNotIn('if (mounted) unawaited(_loadLiveLineups());', dart)

    def test_version_and_event_write(self):
        assert 'version = g.version + 1' in SQL
        assert "'HIT',details,g.version + 1" in SQL
        assert "'ERROR',details,g.version + 1" in SQL

if __name__ == '__main__':
    unittest.main()
