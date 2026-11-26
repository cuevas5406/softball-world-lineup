import 'package:flutter_test/flutter_test.dart';
import 'package:softball_world_lineup/swl_lineup_identity.dart';
import 'package:softball_world_lineup/swl_live_scoreboard_snapshot.dart';
import 'package:softball_world_lineup/swl_play_rules.dart';
import 'package:softball_world_lineup/swl_scoring_recovery.dart';

void main() {
  test('distingue SQLSTATE de fallos de transporte HTTP', () {
    for (final code in [
      'P0001',
      '57014',
      '23505',
      '40001',
      '42501',
      'PGRST202',
      '400',
    ]) {
      expect(swlIsUncertainHttpStatus(code), isFalse, reason: code);
    }
    for (final code in ['408', '500', '502', '503', '504']) {
      expect(swlIsUncertainHttpStatus(code), isTrue, reason: code);
    }
  });

  test('una lectura atrasada o ausente conserva el envío pendiente', () {
    for (final version in [null, 9]) {
      expect(
        swlScoringRecovery(
          sentVersion: 10,
          officialVersion: version,
          explicitRefresh: true,
        ),
        SwlScoringRecovery.waitForRead,
      );
    }
    expect(
      swlScoringRecovery(
        sentVersion: 10,
        officialVersion: 10,
        explicitRefresh: false,
      ),
      SwlScoringRecovery.waitForRead,
    );
    expect(
      swlScoringRecovery(
        sentVersion: 10,
        officialVersion: 10,
        explicitRefresh: true,
      ),
      SwlScoringRecovery.retryAfterReview,
    );
    expect(
      swlScoringRecovery(
        sentVersion: 10,
        officialVersion: 11,
        explicitRefresh: false,
      ),
      SwlScoringRecovery.reviewAdvanced,
    );
  });

  for (final action in ['ERROR', 'HIT']) {
    test('secuencia de SWL-567892 con $action y reintento versionado', () {
      // Modelo local de la respuesta oficial. No se ejecuta ninguna RPC.
      var state = const SwlPlayState(
        balls: 0,
        strikes: 0,
        outs: 0,
        inning: 1,
        isTop: true,
        homeRuns: 0,
        awayRuns: 0,
        first: false,
        second: false,
        third: false,
      );
      final lineups = {
        for (final team in ['home', 'away'])
          team: [
            // Alineación con orden declarado distinto de la posición en JSON.
            for (final number in [2, 1, 3, 4, 5, 6, 7, 8, 9])
              {
                number == 1 ? 'batting_order' : 'order': number,
                'player_id': '$team-$number',
              },
          ],
      };
      final cursors = <String, Map<String, int>>{};
      var version = 0;
      final events = <String>[];
      final hits = {'home': 0, 'away': 0};
      final errors = {'home': 0, 'away': 0};
      var completedTurns = 0;

      SwlLiveScoreboardSnapshot read() => SwlLiveScoreboardSnapshot.fromGame({
        'id': 'regresion-local',
        'status': 'IN_PROGRESS',
        'version': version,
        'home_team_id': 'home',
        'away_team_id': 'away',
        'home_manager_id': 'local',
        'away_manager_id': 'visitante',
        'inning': state.inning,
        'is_top': state.isTop,
        'balls': state.balls,
        'outs': state.outs,
        'home_runs': state.homeRuns,
        'away_runs': state.awayRuns,
        'home_hits': hits['home'],
        'away_hits': hits['away'],
        'home_errors': errors['home'],
        'away_errors': errors['away'],
      });

      bool register(
        int expected,
        String manager,
        String play,
        String batter, {
        required SwlPlayState Function(SwlPlayState) update,
        bool completesTurn = true,
      }) {
        final game = read();
        if (game.version != expected || !game.canScore(manager)) return false;
        final team = game.battingTeamId;
        final turn = swlResolveBattingTurn(lineups[team], cursors[team])!;
        if (turn.playerId != batter) return false;
        state = update(state);
        if (completesTurn) {
          cursors[team] = {
            'next_order': turn.order % lineups[team]!.length + 1,
          };
          completedTurns++;
        }
        if (play == 'HIT' || play == 'HR') hits[team] = hits[team]! + 1;
        if (play == 'ERROR') {
          final defense = team == 'home' ? 'away' : 'home';
          errors[defense] = errors[defense]! + 1;
        }
        events.add(play);
        version++;
        return true;
      }

      expect(
        register(
          0,
          'visitante',
          'HIT',
          'away-1',
          update: (s) => s.hit(batterBase: 1),
        ),
        isTrue,
      );
      expect(
        register(
          1,
          'visitante',
          'HR',
          'away-2',
          update: (s) => s.hit(batterBase: 4, firstTo: 0),
        ),
        isTrue,
      );
      expect(
        register(
          2,
          'visitante',
          'K',
          'away-3',
          update: (s) => s.copy(strikes: 2).strikeout(),
        ),
        isTrue,
      );
      expect(
        register(
          3,
          'visitante',
          'BB',
          'away-4',
          update: (s) => s.copy(balls: 3).walk(),
        ),
        isTrue,
      );
      expect(
        register(
          4,
          'visitante',
          'DP',
          'away-5',
          update: (s) => s.batterRunnerDoublePlay(runnerBase: 1),
        ),
        isTrue,
      );

      final phone = read();
      final tablet = read();
      expect(phone.version, tablet.version);
      expect(
        (phone.inning, phone.isTop, phone.awayRuns, phone.awayHits),
        (1, false, 2, 2),
      );
      expect(phone.canScore('local'), isTrue);
      expect(phone.canScore('visitante'), isFalse);
      expect(cursors['away']?['next_order'], 6);
      expect(cursors['home'], isNull);
      expect(swlResolveBattingTurn(lineups['home'], null)?.playerId, 'home-1');

      expect(
        register(
          5,
          'local',
          'BALL',
          'home-1',
          completesTurn: false,
          update: (s) => s.copy(balls: 1),
        ),
        isTrue,
      );
      expect(read().balls, 1);
      expect(cursors['home'], isNull);
      expect(
        register(
          6,
          'local',
          action,
          'home-2',
          update: (s) => s.hit(batterBase: 1),
        ),
        isFalse,
      );
      expect(
        register(
          6,
          'local',
          action,
          'home-1',
          update: (s) => s.hit(batterBase: 1),
        ),
        isTrue,
      );
      // Se pierde la respuesta. La actualización lee versión 7 y el turno 2.
      final refreshed = read();
      expect(
        swlScoringRecovery(
          sentVersion: 6,
          officialVersion: refreshed.version,
          explicitRefresh: true,
        ),
        SwlScoringRecovery.reviewAdvanced,
      );
      expect(
        register(
          6,
          'local',
          action,
          'home-1',
          update: (s) => s.hit(batterBase: 1),
        ),
        isFalse,
      );
      expect(
        swlResolveBattingTurn(lineups['home'], cursors['home'])?.playerId,
        'home-2',
      );
      expect(
        swlResolveBattingTurn(lineups['away'], cursors['away'])?.playerId,
        'away-6',
      );
      expect(events, ['HIT', 'HR', 'K', 'BB', 'DP', 'BALL', action]);
      expect(completedTurns, 6);
      expect(
        (read().awayRuns, read().homeRuns, read().homeHits, read().awayErrors),
        (2, 0, action == 'HIT' ? 1 : 0, action == 'ERROR' ? 1 : 0),
      );
    });
  }

  test('un cursor inválido se distingue del primer turno implícito', () {
    const lineup = [
      {'order': 1, 'player_id': 'p1'},
    ];
    expect(swlResolveBattingTurn(lineup, null)?.playerId, 'p1');
    expect(swlResolveBattingTurn(lineup, {'next_order': '1'})?.playerId, 'p1');
    for (final cursor in [
      {'next_order': null},
      {'next_order': 1.5},
      {'next_order': 2},
    ]) {
      expect(swlResolveBattingTurn(lineup, cursor), isNull);
    }
  });
}
