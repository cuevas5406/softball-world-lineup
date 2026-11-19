import 'swl_play_rules.dart';

/// Adaptador de lectura para conectar la pizarra deportiva original al estado
/// persistente de un partido. No ejecuta anotaciones ni modifica Supabase.
/// Los nombres y equipos provienen del partido, nunca de constantes de prueba.
class SwlLiveScoreboardSnapshot {
  final String gameId;
  final String pin;
  final String homeTeamId;
  final String awayTeamId;
  final int version;
  final int inning;
  final bool isTop;
  final bool hasKnownHalf;
  final int balls;
  final int strikes;
  final int outs;
  final int homeRuns;
  final int awayRuns;
  final int homeHits;
  final int awayHits;
  final int homeErrors;
  final int awayErrors;
  final bool firstOccupied;
  final bool secondOccupied;
  final bool thirdOccupied;
  final String? homeManagerId;
  final String? awayManagerId;
  final String status;
  final List<int?> homeInnings;
  final List<int?> awayInnings;

  const SwlLiveScoreboardSnapshot({
    required this.gameId,
    required this.pin,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.version,
    required this.inning,
    required this.isTop,
    this.hasKnownHalf = true,
    required this.balls,
    required this.strikes,
    required this.outs,
    required this.homeRuns,
    required this.awayRuns,
    required this.homeHits,
    required this.awayHits,
    required this.homeErrors,
    required this.awayErrors,
    required this.firstOccupied,
    required this.secondOccupied,
    required this.thirdOccupied,
    required this.homeManagerId,
    required this.awayManagerId,
    required this.status,
    required this.homeInnings,
    required this.awayInnings,
  });

  static int _number(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static bool _occupied(dynamic value) => value == true || value == 'true';
  static List<int?> _innings(dynamic value) {
    if (value is! List) return const [];
    return value.map<int?>((v) => v == null ? null : _number(v)).toList(growable: false);
  }

  factory SwlLiveScoreboardSnapshot.fromGame(Map<String, dynamic> game) {
    final bases = game['bases_state'];
    final baseMap = bases is Map ? bases : const <String, dynamic>{};
    return SwlLiveScoreboardSnapshot(
      gameId: game['id']?.toString() ?? '',
      pin: game['game_pin']?.toString() ?? '',
      homeTeamId: game['home_team_id']?.toString() ?? '',
      awayTeamId: game['away_team_id']?.toString() ?? '',
      version: _number(game['version']),
      inning: _number(game['inning']),
      isTop: game['is_top'] == true,
      hasKnownHalf: game['is_top'] is bool,
      balls: _number(game['balls']),
      strikes: _number(game['strikes']),
      outs: _number(game['outs']),
      homeRuns: _number(game['home_runs']),
      awayRuns: _number(game['away_runs']),
      homeHits: _number(game['home_hits']),
      awayHits: _number(game['away_hits']),
      homeErrors: _number(game['home_errors']),
      awayErrors: _number(game['away_errors']),
      firstOccupied: _occupied(baseMap['first']),
      secondOccupied: _occupied(baseMap['second']),
      thirdOccupied: _occupied(baseMap['third']),
      homeManagerId: game['home_manager_id']?.toString(),
      awayManagerId: game['away_manager_id']?.toString(),
      status: game['status']?.toString() ?? 'SCHEDULED',
      homeInnings: _innings(game['home_innings']),
      awayInnings: _innings(game['away_innings']),
    );
  }

  SwlPlayState get playState => SwlPlayState(
    balls: balls, strikes: strikes, outs: outs, inning: inning,
    homeRuns: homeRuns, awayRuns: awayRuns, isTop: isTop,
    first: firstOccupied, second: secondOccupied, third: thirdOccupied,
  );

  String? get battingManagerId => isTop ? awayManagerId : homeManagerId;
  String get battingTeamId => isTop ? awayTeamId : homeTeamId;
  String? scoringBlock(String? userId, {bool authorized = true}) {
    if (!authorized || userId == null || userId.isEmpty) return 'Modo de solo lectura.';
    if (homeManagerId == null || homeManagerId!.isEmpty ||
        awayManagerId == null || awayManagerId!.isEmpty ||
        homeManagerId == awayManagerId || homeTeamId.isEmpty ||
        awayTeamId.isEmpty || homeTeamId == awayTeamId) {
      return 'Verifica la asignación de los dos equipos y mánagers.';
    }
    if (status == 'SCHEDULED') return 'El partido está programado. El local debe iniciarlo desde la preparación.';
    if (status == 'FINAL' || status == 'OFFICIAL') return 'Partido finalizado.';
    if (status != 'IN_PROGRESS') return 'El partido no está en curso ($status).';
    if (!hasKnownHalf) return 'No se pudo confirmar qué equipo está al bate.';
    if (userId != battingManagerId) return 'Solo anota el mánager del equipo al bate.';
    return null;
  }

  bool canScore(String? userId) => scoringBlock(userId) == null;
}
