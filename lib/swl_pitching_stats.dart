import 'package:supabase_flutter/supabase_flutter.dart';

class SwlPitchingTotals {
  int outs = 0;
  int strikeouts = 0;
  int walks = 0;
  int hits = 0;
  int pitches = 0;
  int balls = 0;
  int strikes = 0;
  int inPlay = 0;
  bool _hasPitchData = false;
  bool _hasLegacyRows = false;

  String get pitchLine => _hasPitchData
      ? '$pitches PITCHES · $balls B · $strikes S · $inPlay en juego${_hasLegacyRows ? ' (parcial)' : ''}'
      : 'Pitcheos sin datos';

  String get innings => '${outs ~/ 3}.${outs % 3}';

  void add(Map<String, dynamic> event) {
    outs += (event['outs'] as num?)?.toInt() ?? 0;
    strikeouts += (event['strikes_out'] as num?)?.toInt() ?? 0;
    walks += (event['walks'] as num?)?.toInt() ?? 0;
    hits += (event['hits'] as num?)?.toInt() ?? 0;
    final count = event['pitch_count'];
    final ballCount = event['pitch_balls'];
    final strikeCount = event['pitch_strikes'];
    final contactCount = event['pitch_in_play'];
    if (count is int &&
        ballCount is int &&
        strikeCount is int &&
        contactCount is int &&
        count == ballCount + strikeCount + contactCount) {
      _hasPitchData = true;
      pitches += count;
      balls += ballCount;
      strikes += strikeCount;
      inPlay += contactCount;
    } else {
      _hasLegacyRows = true;
    }
  }
}

Future<Map<String, SwlPitchingTotals>?> swlLoadPitching(
  SupabaseClient client,
  String gameId,
  int throughVersion,
) async {
  final totals = <String, SwlPitchingTotals>{};
  const size = 250;
  try {
    for (var offset = 0; ; offset += size) {
      final page = await client
          .from('swl_v56_pitching_events')
          .select()
          .eq('game_id', gameId)
          .lte('version', throughVersion)
          .order('version')
          .range(offset, offset + size - 1)
          .timeout(const Duration(seconds: 12));
      for (final row in page) {
        final id = row['pitcher_id']?.toString();
        if (id != null) totals.putIfAbsent(id, SwlPitchingTotals.new).add(row);
      }
      if (page.length < size) return totals;
    }
  } on PostgrestException catch (error) {
    if (error.code == 'PGRST205' || error.code == '42P01') return null;
    rethrow;
  }
}
