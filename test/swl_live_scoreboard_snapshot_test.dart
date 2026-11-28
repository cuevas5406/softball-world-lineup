import 'package:flutter_test/flutter_test.dart';

import '../lib/swl_live_scoreboard_snapshot.dart';

void main() {
  Map<String, dynamic> game({bool top = true, String status = 'IN_PROGRESS'}) =>
      {
        'id': 'game-1',
        'game_pin': 'SWL-123',
        'home_team_id': 'home-uuid',
        'away_team_id': 'away-uuid',
        'home_manager_id': 'home-manager',
        'away_manager_id': 'away-manager',
        'is_top': top,
        'status': status,
        'version': 5,
        'inning': 2,
        'balls': 1,
        'strikes': 2,
        'outs': 1,
        'bases_state': {'first': true, 'second': false, 'third': true},
      };

  test('Alta: solo el mánager visitante puede anotar', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(game());
    expect(snapshot.canScore('away-manager'), isTrue);
    expect(snapshot.canScore('home-manager'), isFalse);
    expect(snapshot.battingTeamId, 'away-uuid');
    expect(snapshot.firstOccupied, isTrue);
    expect(snapshot.thirdOccupied, isTrue);
  });

  test('Baja: solo el mánager local puede anotar', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(game(top: false));
    expect(snapshot.canScore('home-manager'), isTrue);
    expect(snapshot.canScore('away-manager'), isFalse);
    expect(snapshot.battingTeamId, 'home-uuid');
  });

  test('Partidos no iniciados o finalizados no admiten anotaciones', () {
    for (final status in ['SCHEDULED', 'FINAL', 'OFFICIAL']) {
      final snapshot = SwlLiveScoreboardSnapshot.fromGame(game(status: status));
      expect(snapshot.canScore('away-manager'), isFalse);
    }
  });

  test('Un espectador no puede anotar', () {
    expect(SwlLiveScoreboardSnapshot.fromGame(game()).canScore('fan'), isFalse);
    expect(SwlLiveScoreboardSnapshot.fromGame(game()).canScore(null), isFalse);
  });
  test('Un partido programado presenta la causa del bloqueo', () {
    final pending = SwlLiveScoreboardSnapshot.fromGame(
      game(status: 'SCHEDULED'),
    );
    expect(pending.scoringBlock('away-manager'), contains('programado'));
    expect(
      pending.scoringBlock('away-manager', authorized: false),
      contains('solo lectura'),
    );
  });

  test('Una mitad desconocida jamás habilita al local', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(
      game()..remove('is_top'),
    );
    expect(snapshot.canScore('home-manager'), isFalse);
    expect(snapshot.canScore('away-manager'), isFalse);
  });

  test('La misma cuenta no puede asumir ambos lados', () {
    final snapshot = SwlLiveScoreboardSnapshot.fromGame(
      game()..['away_manager_id'] = 'home-manager',
    );
    expect(snapshot.canScore('home-manager'), isFalse);
  });
  test('Solicitud desde quinta y respuesta exclusiva del otro mánager', () {
    final row = {...game(), 'inning': 5, 'home_runs': 4, 'away_runs': 3};
    expect(
      SwlLiveScoreboardSnapshot.fromGame(row).matchActions('home-manager'),
      {'REQUEST'},
    );
    row['swl_finish_requested_by'] = 'home-manager';
    final requested = SwlLiveScoreboardSnapshot.fromGame(row);
    expect(requested.matchActions('home-manager'), isEmpty);
    expect(requested.matchActions('away-manager'), {'ACCEPT', 'REJECT'});
    expect(requested.matchActions('espectador'), isEmpty);
    row.remove('swl_finish_requested_by');
    expect(
      SwlLiveScoreboardSnapshot.fromGame(row).matchActions('away-manager'),
      {'REQUEST'},
    );
  });

  test(
    'Ambos mánagers pueden solicitar la cancelación y solo el otro responde',
    () {
      final row = game(status: 'SCHEDULED');
      final scheduled = SwlLiveScoreboardSnapshot.fromGame(row);
      expect(scheduled.cancellationActions('home-manager'), {'CANCEL_REQUEST'});
      expect(scheduled.cancellationActions('away-manager'), {'CANCEL_REQUEST'});
      row['swl_cancel_requested_by'] = 'away-manager';
      final requested = SwlLiveScoreboardSnapshot.fromGame(row);
      expect(requested.cancellationActions('away-manager'), isEmpty);
      expect(requested.cancellationActions('home-manager'), {
        'CANCEL_ACCEPT',
        'CANCEL_REJECT',
      });
      expect(requested.cancellationActions('fan'), isEmpty);
      row['status'] = 'CANCELLED';
      final cancelled = SwlLiveScoreboardSnapshot.fromGame(row);
      expect(cancelled.cancellationActions('home-manager'), isEmpty);
      expect(cancelled.canScore('away-manager'), isFalse);
    },
  );

  test(
    'Cancelación local permite responder solo al visitante durante el juego',
    () {
      final row = game()..['swl_cancel_requested_by'] = 'home-manager';
      final pending = SwlLiveScoreboardSnapshot.fromGame(row);
      expect(pending.cancellationActions('home-manager'), isEmpty);
      expect(pending.cancellationActions('away-manager'), {
        'CANCEL_ACCEPT',
        'CANCEL_REJECT',
      });
      expect(pending.canScore('away-manager'), isTrue);

      final rejected = SwlLiveScoreboardSnapshot.fromGame({
        ...row,
        'swl_cancel_requested_by': null,
      });
      expect(rejected.cancellationActions('away-manager'), {'CANCEL_REQUEST'});
      expect(rejected.canScore('away-manager'), isTrue);

      final cancelled = SwlLiveScoreboardSnapshot.fromGame({
        ...row,
        'status': 'CANCELLED',
        'swl_cancel_requested_by': null,
      });
      expect(cancelled.cancellationActions('away-manager'), isEmpty);
      expect(cancelled.cancellationActions('home-manager'), isEmpty);
      expect(
        cancelled.scoringBlock('away-manager'),
        'Partido cancelado. No se pueden registrar jugadas.',
      );
    },
  );

  test(
    'la consulta de knockout congela anotación y registra un voto por lado',
    () {
      final row = game()..['swl_knockout_pending'] = {'away_continue': true};
      final pending = SwlLiveScoreboardSnapshot.fromGame(row);
      expect(pending.canScore('away-manager'), isFalse);
      expect(pending.canVoteKnockout('away-manager'), isFalse);
      expect(pending.canVoteKnockout('home-manager'), isTrue);
      expect(pending.canVoteKnockout('fan'), isFalse);
      expect(pending.matchActions('home-manager'), isEmpty);
    },
  );

  test('En FINAL se bloquea la anotación y la firma es individual', () {
    final row = {...game(status: 'FINAL'), 'swl_home_signed': true};
    final finalGame = SwlLiveScoreboardSnapshot.fromGame(row);
    expect(finalGame.canScore('away-manager'), isFalse);
    expect(finalGame.matchActions('home-manager'), isEmpty);
    expect(finalGame.matchActions('away-manager'), {'SIGN'});
    expect(
      SwlLiveScoreboardSnapshot.fromGame({...row, 'status': 'OFFICIAL'})
          .matchActions('away-manager'),
      isEmpty,
    );
  });
}
