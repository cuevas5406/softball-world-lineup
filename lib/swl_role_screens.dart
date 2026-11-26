import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'swl_official_box_score.dart';
import 'swl_advanced_scoreboard.dart';
import 'swl_live_scoreboard_snapshot.dart';
import 'swl_team_lookup.dart';

bool _missingRpc(Object error) =>
    error is PostgrestException &&
    (error.code == 'PGRST202' || error.code == '42883');

class SwlPlayerScreen extends StatefulWidget {
  const SwlPlayerScreen({super.key});

  @override
  State<SwlPlayerScreen> createState() => _SwlPlayerScreenState();
}

class _SwlPlayerScreenState extends State<SwlPlayerScreen> {
  final _client = Supabase.instance.client;
  static const _bucket = 'swl-player-photos';
  late Future<Map<String, dynamic>?> _profile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _profile = _read();
  }

  Future<Map<String, dynamic>?> _read() async {
    final row = await _client
        .rpc('swl_v57_my_player')
        .timeout(const Duration(seconds: 12));
    if (row == null) return null;
    final profile = Map<String, dynamic>.from(row as Map);
    if (profile['photo_path'] case final String path) {
      try {
        profile['photo'] = await _client.storage
            .from(_bucket)
            .createSignedUrl(path, 900)
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Se puede consultar el perfil si la foto está temporalmente inaccesible.
      }
    }
    return profile;
  }

  void _reload() => setState(() => _profile = _read());

  Future<void> _mutate(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is PostgrestException
                  ? error.message
                  : 'No se pudo confirmar el cambio. Actualiza el perfil.',
            ),
          ),
        );
    } finally {
      if (mounted)
        setState(() {
          _profile = _read();
          _busy = false;
        });
    }
  }

  Future<String?> _prompt(
    String title,
    String label, {
    String initial = '',
    required int limit,
    bool secret = false,
  }) async {
    var value = initial;
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          initialValue: initial,
          autofocus: true,
          obscureText: secret,
          maxLength: limit,
          onChanged: (text) => value = text,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, value.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _claim() async {
    final token = await _prompt(
      'Vincular mi ficha',
      'Invitación verificada',
      limit: 64,
      secret: true,
    );
    if (!mounted || token == null || token.isEmpty) return;
    await _mutate(
      () async => await _client
          .rpc('swl_v57_claim_player', params: {'p_token': token})
          .timeout(const Duration(seconds: 12)),
    );
  }

  Future<void> _changeBio(Map<String, dynamic> profile) async {
    final bio = await _prompt(
      'Editar perfil',
      'Sobre mí',
      initial: profile['bio']?.toString() ?? '',
      limit: 300,
    );
    if (!mounted || bio == null) return;
    await _mutate(
      () async => await _client
          .rpc(
            'swl_v57_update_my_player',
            params: {'p_bio': bio, 'p_photo_path': null},
          )
          .timeout(const Duration(seconds: 12)),
    );
  }

  Future<void> _changePhoto(Map<String, dynamic> profile) async {
    await _mutate(() async {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return;
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (!mounted || image == null || _client.auth.currentUser?.id != uid)
        return;
      if (await image.length() > 2 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selecciona una foto JPEG de hasta 2 MB.'),
            ),
          );
        }
        return;
      }
      final bytes = await image.readAsBytes();
      if (bytes.length < 3 ||
          bytes[0] != 255 ||
          bytes[1] != 216 ||
          bytes[2] != 255) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selecciona una foto JPEG de hasta 2 MB.'),
            ),
          );
        return;
      }
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';
      await _client.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          )
          .timeout(const Duration(seconds: 25));
      if (_client.auth.currentUser?.id != uid) {
        // La sesión cambió durante la subida: nunca vincular la foto a otra cuenta.
        return;
      }
      await _client
          .rpc(
            'swl_v57_update_my_player',
            params: {'p_bio': profile['bio'], 'p_photo_path': path},
          )
          .timeout(const Duration(seconds: 12));
    });
  }

  String _stats(Iterable<Map<String, dynamic>> rows, {bool pitching = false}) {
    int total(String field) =>
        rows.fold(0, (sum, row) => sum + ((row[field] as num?)?.toInt() ?? 0));
    if (pitching) {
      final outs = total('outs');
      return '${outs ~/ 3}.${outs % 3} IP · ${total('h')} H · ${total('bb')} BB · ${total('k')} K';
    }
    String availableTotal(String field) =>
        rows.every((row) => row[field] is num) ? total(field).toString() : '—';
    final atBats = total('ab');
    final average = atBats == 0
        ? '—'
        : (total('h') / atBats).toStringAsFixed(3);
    return '$average AVG · $atBats AB · ${availableTotal('r')} R · '
        '${total('h')} H · ${availableTotal('doubles')} 2B · ${availableTotal('triples')} 3B · '
        '${total('hr')} HR · ${availableTotal('rbi')} RBI · ${total('bb')} BB · ${total('k')} K';
  }

  Widget _showProfile(Map<String, dynamic> profile) {
    final games = swlRows(profile['games']);
    final pitching = swlRows(profile['pitching']);
    String team(Map<String, dynamic> row) =>
        row['team_name']?.toString() ?? 'Equipo sin atribución confirmada';
    final teams = {
      for (final row in [...games, ...pitching]) row['team_id']: team(row),
    };
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _profile;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: CircleAvatar(
              foregroundImage: profile['photo'] is String
                  ? NetworkImage(profile['photo'] as String)
                  : null,
              child: const Icon(Icons.person_outline),
            ),
            title: Text(profile['name']?.toString() ?? 'Pelotero'),
            subtitle: Text(
              [
                profile['code'],
                if (profile['number'] != null) '#${profile['number']}',
                profile['position'],
                profile['secondary_position'],
              ].whereType<String>().join(' · '),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _changePhoto(profile),
                child: const Text('Cambiar foto'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _changeBio(profile),
                child: const Text('Editar información'),
              ),
            ],
          ),
          if (profile['bio'] is String)
            ListTile(title: Text(profile['bio'] as String)),
          const ListTile(title: Text('Mis equipos')),
          for (final roster in swlRows(profile['teams']))
            ListTile(
              title: Text(roster['name']?.toString() ?? 'Equipo'),
              subtitle: Text(
                roster['refuerzo'] == true ? 'Refuerzo' : 'Principal',
              ),
            ),
          const ListTile(title: Text('Estadísticas oficiales acumuladas')),
          if (games.isEmpty && pitching.isEmpty)
            const ListTile(
              title: Text('Aún no hay estadísticas oficiales acreditadas.'),
            ),
          if (games.isNotEmpty)
            ListTile(title: const Text('Bateo'), subtitle: Text(_stats(games))),
          if (pitching.isNotEmpty)
            ListTile(
              title: const Text('Pitcheo'),
              subtitle: Text(_stats(pitching, pitching: true)),
            ),
          for (final entry in teams.entries)
            ListTile(
              title: Text(entry.value),
              subtitle: Text(
                [
                  if (games.any((row) => row['team_id'] == entry.key))
                    _stats(games.where((row) => row['team_id'] == entry.key)),
                  if (pitching.any((row) => row['team_id'] == entry.key))
                    _stats(
                      pitching.where((row) => row['team_id'] == entry.key),
                      pitching: true,
                    ),
                ].join('\n'),
              ),
            ),
          const ListTile(title: Text('Historial de partidos oficiales')),
          for (final match in {
            ...games.map((row) => row['code']),
            ...pitching.map((row) => row['code']),
          })
            ListTile(
              title: Text(match?.toString() ?? 'Partido'),
              subtitle: Text(
                [
                  for (final row in games.where((row) => row['code'] == match))
                    '${team(row)} · ${_stats([row])}',
                  for (final row in pitching.where(
                    (row) => row['code'] == match,
                  ))
                    '${team(row)} · ${_stats([row], pitching: true)}',
                ].join('\n'),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    future: _profile,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError)
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _missingRpc(snapshot.error!)
                    ? 'La vinculación de peloteros requiere habilitación en LAB.'
                    : 'No se pudo consultar el perfil.',
              ),
              TextButton(onPressed: _reload, child: const Text('Reintentar')),
            ],
          ),
        );
      final profile = snapshot.data;
      if (profile != null) return _showProfile(profile);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Para vincular tu ficha, solicita una invitación a un administrador que pueda verificar tu identidad.',
              ),
              FilledButton(
                onPressed: _busy ? null : _claim,
                child: const Text('Vincular mi ficha'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class SwlFanScreen extends StatefulWidget {
  const SwlFanScreen({super.key});

  @override
  State<SwlFanScreen> createState() => _SwlFanScreenState();
}

class _SwlFanScreenState extends State<SwlFanScreen> {
  final _client = Supabase.instance.client;
  final _preferences = SharedPreferencesAsync();
  final _favorites = <String, String>{};
  final _savingFavorites = <String>{};
  List<Map<String, dynamic>>? _games;
  Map<String, Map<String, dynamic>> _teams = {};
  late final RealtimeChannel _channel;
  Timer? _timer;
  bool _loading = false;
  bool _queued = false;
  bool _error = false;
  bool _favoritesReady = false;
  bool _more = true;
  int _offset = 0;
  bool _onlyFavorites = false;
  String? _teamScope;
  String _section = 'IN_PROGRESS';
  int _revision = 0;
  late final String _key;

  @override
  void initState() {
    super.initState();
    _key = 'swl.favorites.${_client.auth.currentUser?.id}';
    _loadFavorites();
    _channel = _client
        .channel('swl-fan-games-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'swl_live_games',
          callback: (_) {
            if (_section != 'favorite') unawaited(_refresh());
          },
        )
        .subscribe();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_section == 'IN_PROGRESS') unawaited(_refresh());
    });
    _refresh();
  }

  Future<void> _loadFavorites() async {
    try {
      final saved = await _preferences.getStringList(_key) ?? [];
      if (!mounted) return;
      setState(() {
        for (var i = 0; i + 1 < saved.length; i += 2) {
          _favorites[saved[i]] = saved[i + 1];
        }
        _favoritesReady = true;
      });
      unawaited(_refresh());
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudieron recuperar los favoritos de este dispositivo.',
            ),
          ),
        );
    }
  }

  Future<void> _toggleFavorite(String key, String label) async {
    if (!_favoritesReady || _savingFavorites.isNotEmpty) return;
    final next = {..._favorites};
    if (next.remove(key) == null) next[key] = label;
    setState(() => _savingFavorites.add(key));
    try {
      await _preferences.setStringList(_key, [
        for (final item in next.entries) ...[item.key, item.value],
      ]);
      if (mounted)
        setState(() {
          _favorites.clear();
          _favorites.addAll(next);
          _revision++;
        });
      if (mounted) unawaited(_refresh());
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el favorito.')),
        );
    } finally {
      if (mounted) setState(() => _savingFavorites.remove(key));
    }
  }

  List<String> get _favoriteTeams => [
    for (final key in _favorites.keys)
      if (key.startsWith('team:')) key.substring(5),
  ];

  bool _favored(Map<String, dynamic> row) =>
      _favorites.containsKey('team:${row['home_team_id']}') ||
      _favorites.containsKey('team:${row['away_team_id']}');

  Future<void> _refresh({bool append = false}) async {
    if (_loading) {
      _queued = true;
      return;
    }
    _loading = true;
    final revision = _revision;
    final section = _section;
    final favoriteIds = _favoriteTeams;
    final scope = _teamScope;
    final restricted = scope != null || _onlyFavorites;
    final filters = scope == null ? favoriteIds : [scope];
    final offset = append ? _offset : 0;
    try {
      Future<List<Map<String, dynamic>>> fetch(
        int from,
        List<String>? ids,
      ) async {
        if (ids != null && ids.isEmpty) return [];
        var query = _client
            .from('swl_live_games')
            .select(
              'id,game_pin,created_at,home_team_id,away_team_id,home_runs,away_runs,inning,is_top,status',
            )
            .eq('status', section);
        if (ids != null) {
          final teams = ids.join(',');
          query = query.or('home_team_id.in.($teams),away_team_id.in.($teams)');
        }
        return query
            .order('created_at', ascending: false)
            .order('id')
            .range(from, from + 29)
            .timeout(const Duration(seconds: 12));
      }

      List<Map<String, dynamic>> page = [];
      List<Map<String, dynamic>> priority = [];
      if (section != 'favorite') {
        final pages = await Future.wait([
          fetch(offset, restricted ? filters : null),
          if (!restricted && !append && favoriteIds.isNotEmpty)
            fetch(0, favoriteIds),
        ]);
        page = pages.first;
        if (pages.length > 1) priority = pages[1];
      }
      final ids =
          <String>{
                ...favoriteIds,
                for (final game in [...page, ...priority])
                  for (final side in ['home', 'away'])
                    if (game['${side}_team_id'] case final String id) id,
              }
              .where((id) => !_teams.containsKey(id) || section == 'favorite')
              .toList();
      final teams = <Map<String, dynamic>>[];
      for (var i = 0; i < ids.length; i += 40) {
        final batch = ids.skip(i).take(40).toList();
        teams.addAll(
          await swlQueryTeams(
            (columns) async => await _client
                .from('teams')
                .select(columns)
                .inFilter('id', batch)
                .timeout(const Duration(seconds: 12)),
          ),
        );
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        final merged = {
          for (final row in [if (append) ...?_games, ...priority, ...page])
            row['id']: row,
        }.values;
        _games = [
          ...merged.where(_favored),
          ...merged.where((row) => !_favored(row)),
        ];
        _teams.addEntries(
          teams.map((team) => MapEntry(team['id'].toString(), team)),
        );
        _offset = offset + page.length;
        _more = page.length == 30;
        _error = false;
      });
    } catch (_) {
      if (mounted && revision == _revision) setState(() => _error = true);
    } finally {
      _loading = false;
      if (_queued && mounted) {
        _queued = false;
        unawaited(_refresh());
      }
    }
  }

  void _switchSection(String value, {String? team, bool keepTeam = false}) {
    setState(() {
      _section = value;
      if (!keepTeam || value == 'favorite') _teamScope = team;
      _revision++;
      _games = null;
      _offset = 0;
      _error = false;
    });
    unawaited(_refresh());
  }

  Future<void> _openGame(String id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SwlFanGame(
          gameId: id,
          favorites: _favorites,
          knownTeams: Map.of(_teams),
          toggleFavorite: _toggleFavorite,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_client.removeChannel(_channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final games = _games ?? [];
    return Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final (value, label) in [
              ('IN_PROGRESS', 'En vivo'),
              ('OFFICIAL', 'Resultados'),
              ('favorite', 'Favoritos'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _section == value,
                onSelected: (_) => _switchSection(value, keepTeam: true),
              ),
          ],
        ),
        if (_section != 'favorite')
          if (_teamScope case final String id)
            InputChip(
              label: Text(
                _teams[id]?['name']?.toString() ??
                    _favorites['team:$id'] ??
                    'Equipo',
              ),
              onDeleted: () => _switchSection(_section),
            )
          else
            FilterChip(
              label: const Text('Solo mis equipos favoritos'),
              selected: _onlyFavorites,
              onSelected: (value) {
                _onlyFavorites = value;
                _switchSection(_section);
              },
            ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_section == 'favorite') ...[
                  if (_error)
                    const ListTile(
                      title: Text(
                        'No se pudieron actualizar los logos de favoritos.',
                      ),
                    ),
                  const ListTile(title: Text('Mis equipos favoritos')),
                  if (_favoriteTeams.isEmpty)
                    const ListTile(
                      subtitle: Text('Añade equipos desde un partido.'),
                    ),
                  for (final id in _favoriteTeams)
                    ListTile(
                      leading: SwlTeamBadge(url: swlTeamLogo(_teams[id])),
                      title: Text(
                        _teams[id]?['name']?.toString() ??
                            _favorites['team:$id']!,
                      ),
                      onTap: () => _switchSection('IN_PROGRESS', team: id),
                      trailing: IconButton(
                        icon: const Icon(Icons.star, color: Colors.amber),
                        tooltip: 'Quitar equipo favorito',
                        onPressed: () => _toggleFavorite(
                          'team:$id',
                          _favorites['team:$id']!,
                        ),
                      ),
                    ),
                  const ListTile(title: Text('Mis peloteros favoritos')),
                  if (!_favorites.keys.any((key) => key.startsWith('player:')))
                    const ListTile(
                      subtitle: Text(
                        'Marca la estrella de un pelotero en Alineaciones.',
                      ),
                    ),
                  for (final item in _favorites.entries.where(
                    (item) => item.key.startsWith('player:'),
                  ))
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(item.value),
                      trailing: IconButton(
                        icon: const Icon(Icons.star, color: Colors.amber),
                        tooltip: 'Quitar pelotero favorito',
                        onPressed: () => _toggleFavorite(item.key, item.value),
                      ),
                    ),
                ] else ...[
                  if (_error)
                    ListTile(
                      title: const Text('No se pudo actualizar el marcador.'),
                      trailing: IconButton(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  if (_games == null && !_error)
                    const Center(child: CircularProgressIndicator()),
                  if (_games != null && games.isEmpty)
                    ListTile(
                      title: Text(
                        _section == 'IN_PROGRESS'
                            ? 'No hay partidos en vivo.'
                            : 'Aún no hay resultados oficiales.',
                      ),
                    ),
                  for (final row in games) _gameTile(row),
                  if (games.isNotEmpty && _more)
                    TextButton(
                      onPressed: () => _refresh(append: true),
                      child: const Text('Ver más'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _gameTile(Map<String, dynamic> row) {
    final home = _teams[row['home_team_id']];
    final away = _teams[row['away_team_id']];
    final favored =
        _favorites.containsKey('team:${row['home_team_id']}') ||
        _favorites.containsKey('team:${row['away_team_id']}');
    return ListTile(
      leading: SwlTeamBadge(url: swlTeamLogo(away)),
      title: Text(
        "${away?['name'] ?? 'Visitante'} ${row['away_runs']} – ${row['home_runs']} ${home?['name'] ?? 'Local'}",
      ),
      subtitle: Text(
        row['status'] == 'OFFICIAL'
            ? "${row['game_pin']} · Oficial"
            : "${row['game_pin']} · En vivo · ${row['is_top'] == true
                  ? 'Alta'
                  : row['is_top'] == false
                  ? 'Baja'
                  : 'Entrada'} ${row['inning']}",
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (favored) const Icon(Icons.star, color: Colors.amber, size: 18),
          SwlTeamBadge(url: swlTeamLogo(home)),
        ],
      ),
      onTap: () => _openGame(row['id'] as String),
    );
  }
}

class _SwlFanGame extends StatefulWidget {
  const _SwlFanGame({
    required this.gameId,
    required this.favorites,
    required this.knownTeams,
    required this.toggleFavorite,
  });
  final String gameId;
  final Map<String, String> favorites;
  final Map<String, Map<String, dynamic>> knownTeams;
  final Future<void> Function(String, String) toggleFavorite;

  @override
  State<_SwlFanGame> createState() => _SwlFanGameState();
}

class _SwlFanGameState extends State<_SwlFanGame> {
  final _client = Supabase.instance.client;
  late final RealtimeChannel _channel;
  late final Timer _timer;
  Map<String, dynamic>? _game;
  SwlLiveScoreboardSnapshot? _snapshot;
  bool _liveDetailsAvailable = false;
  bool _loading = false;
  bool _queued = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _channel = _client
        .channel('swl-fan-detail-${widget.gameId}-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'swl_live_games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.gameId,
          ),
          callback: (_) => unawaited(_read()),
        )
        .subscribe();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_snapshot?.status != 'OFFICIAL') unawaited(_read());
    });
    _read();
  }

  Future<void> _read() async {
    if (_loading) {
      _queued = true;
      return;
    }
    _loading = true;
    try {
      // La ficha pública conserva logos, alineaciones y estadísticas oficiales.
      // El marcador detallado usa la misma fila oficial que la pizarra del mánager.
      final reads = await Future.wait<Map<String, dynamic>?>([
        swlReadSpectatorGame(widget.gameId)
            .then<Map<String, dynamic>?>((value) => value)
            .catchError((Object _) => null),
        _client
            .from('swl_live_games')
            .select(
              'id,game_pin,status,version,inning,is_top,balls,strikes,outs,bases_state,'
              'home_team_id,away_team_id,home_runs,away_runs,home_hits,away_hits,'
              'home_errors,away_errors,home_innings,away_innings,'
              'swl_regulation_innings,swl_final_half_completed,swl_finish_reason',
            )
            .eq('id', widget.gameId)
            .inFilter('status', [
              'IN_PROGRESS',
              'FINAL',
              'OFFICIAL',
              'CANCELED',
              'CANCELLED',
            ])
            .maybeSingle()
            .timeout(const Duration(seconds: 8))
            .catchError((Object _) => null),
      ]);
      final row = reads.last;
      if (!mounted) return;
      if (reads.first == null && row == null) {
        throw StateError('Marcador no disponible.');
      }
      final game =
          reads.first ??
          _game ??
          <String, dynamic>{
            'code': row?['game_pin'],
            for (final side in ['home', 'away'])
              side: widget.knownTeams[row?['${side}_team_id']],
          };
      final publicState = <String, dynamic>{
        'id': widget.gameId,
        'game_pin': game['code'],
        'status': game['status'],
        'version': game['version'],
        'inning': game['inning'],
        'swl_finish_reason': game['finish'],
        for (final side in ['home', 'away'])
          if (game[side] case final Map team) ...{
            '${side}_team_id': team['id'],
            for (final field in ['runs', 'hits', 'errors', 'innings'])
              '${side}_$field': team[field],
          },
      };
      final direct = row == null
          ? null
          : SwlLiveScoreboardSnapshot.fromGame(row);
      final reduced = SwlLiveScoreboardSnapshot.fromGame(publicState);
      final detailed = direct != null && direct.version >= reduced.version;
      final incoming = detailed ? direct : reduced;
      final current = _snapshot;
      if (current != null &&
          (incoming.version < current.version ||
              (incoming.version == current.version &&
                  _liveDetailsAvailable &&
                  !detailed)))
        return;
      setState(() {
        _game = game;
        _snapshot = incoming;
        _liveDetailsAvailable = detailed;
        _failed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      _loading = false;
      if (_queued && mounted) {
        _queued = false;
        unawaited(_read());
      }
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    unawaited(_client.removeChannel(_channel));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final snapshot = _snapshot;
    if (game == null || snapshot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Partido')),
        body: Center(
          child: _failed
              ? TextButton(
                  onPressed: _read,
                  child: const Text('Volver a consultar el marcador'),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    Map<String, dynamic> team(String side, String id) => {
      ...?widget.knownTeams[id],
      if (game[side] case final Map publicTeam)
        for (final entry in publicTeam.entries)
          if (entry.key is String && entry.value != null)
            entry.key as String: entry.value,
    };
    final home = team('home', snapshot.homeTeamId);
    final away = team('away', snapshot.awayTeamId);
    return SwlAdvancedScoreboard(
      gamePin: snapshot.pin,
      homeTeam: home['name']?.toString() ?? 'Local',
      awayTeam: away['name']?.toString() ?? 'Visitante',
      homeLogo: swlTeamLogo(home),
      awayLogo: swlTeamLogo(away),
      liveSnapshot: snapshot,
      spectator: SwlSpectatorView(
        publicGame: game,
        detailed: _liveDetailsAvailable,
        isFavorite: widget.favorites.containsKey,
        toggleFavorite: (key, label) async {
          await widget.toggleFavorite(key, label);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}
