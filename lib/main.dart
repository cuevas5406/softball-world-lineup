import 'swl_team_logo_editor.dart';
import 'swl_team_lookup.dart';
import 'swl_live_lobby.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// URL y Claves de tu servidor Supabase
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const String kLabUrl = 'https://wgeziptdoabyicufnrfk.supabase.co';
// Debe coincidir con AndroidManifest.xml y la allowlist de Supabase LAB.
const String kAuthRedirectUrl = 'com.softballworld.lineup://login-callback';

// FUNCIÓN PARA ABRIR ENLACES EXTERNOS (WHATSAPP O WEB DE PATROCINADORES)
Future<void> openExternalUrl(String urlString) async {
  final Uri uri = Uri.parse(urlString);
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint("Error abriendo enlace: $e");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Fail closed: nunca permitir que una compilación de pruebas escriba en producción.
  if (kSupabaseUrl != kLabUrl || kSupabaseAnonKey.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: EdgeInsets.all(24),
      child: Text('Configuración de LAB ausente o incorrecta. Esta versión no se conectará a producción.', textAlign: TextAlign.center),
    )))));
    return;
  }

  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
    runApp(const SoftballWorldApp());
  } catch (e) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('No se pudo iniciar la conexión con LAB.')))));
  }
}

class SoftballWorldApp extends StatelessWidget {
  const SoftballWorldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Softball World Lineup',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080D14),
        primaryColor: Colors.amber,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          surface: Color(0xFF16202C),
        ),
      ),
      home: const AuthTestGate(),
    );
  }
}

// FASE 1 - PRUEBA AISLADA DE AUTENTICACIÓN.
// No otorga permisos ni consulta una tabla profiles inexistente.
class AuthTestGate extends StatefulWidget {
  const AuthTestGate({super.key});
  @override
  State<AuthTestGate> createState() => _AuthTestGateState();
}

class _AuthTestGateState extends State<AuthTestGate> {
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  bool _showLogin = false;
  bool _available = true;
  Future<Map<String, dynamic>?>? _profileLookup;
  String? _profileUserId;
  Future<List<Map<String, dynamic>>>? _authorizedTeamsLookup;
  String? _authorizedTeamsUserId;

  @override
  void initState() {
    super.initState();
    try {
      final auth = Supabase.instance.client.auth;
      _session = auth.currentSession;
      _prepareProfileLookup(_session);
      _subscription = auth.onAuthStateChange.listen((event) {
        if (!mounted) return;
        setState(() {
          _session = event.session;
          _prepareProfileLookup(_session);
        });
      }, onError: (Object error) {
        debugPrint('Error de escucha de sesión: $error');
      });
    } catch (error) {
      _available = false;
      debugPrint('Supabase no inicializado: $error');
    }
  }

  // Lectura únicamente. Nunca se asignan roles ni se insertan perfiles desde esta pantalla.
  void _prepareProfileLookup(Session? session, {bool force = false}) {
    final id = session?.user.id;
    if (id == null) {
      _profileUserId = null;
      _profileLookup = null;
      _authorizedTeamsLookup = null;
      _authorizedTeamsUserId = null;
      return;
    }
    if (force || _profileUserId != id || _profileLookup == null) {
      _profileUserId = id;
      _profileLookup = Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email, player_id, role')
          .eq('id', id)
          .maybeSingle();
    }
  }

  Future<List<Map<String, dynamic>>> _teamsForUser(String userId) {
    if (_authorizedTeamsUserId != userId || _authorizedTeamsLookup == null) {
      _authorizedTeamsUserId = userId;
      _authorizedTeamsLookup = swlAuthorizedTeams();
    }
    return _authorizedTeamsLookup!;
  }

  void _refreshProfile() {
    setState(() {
      _prepareProfileLookup(_session, force: true);
      _authorizedTeamsLookup = null;
      _authorizedTeamsUserId = null;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) {
      return const Scaffold(body: Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No se pudo iniciar Supabase. Comprueba la conexión y reinicia la aplicación.', textAlign: TextAlign.center),
      )));
    }
    final user = _session?.user;
    if (user != null) {
      return Scaffold(
       appBar: null,
        body: SafeArea(child: FutureBuilder<Map<String, dynamic>?>(
          future: _profileLookup,
          builder: (context, snapshot) {
            // V4.3: con sesion y perfil validos, entrar directamente al Hub.
            // El rol fan es visual; los permisos de escritura siguen en Supabase.
            if (snapshot.connectionState == ConnectionState.done &&
                !snapshot.hasError && snapshot.data != null) {
              final profile = snapshot.data!;
              final fullName = profile['full_name']?.toString().trim() ?? '';
              return FutureBuilder<List<Map<String, dynamic>>>(
                future: _teamsForUser(user.id),
                builder: (context, teamsSnapshot) {
                  if (teamsSnapshot.hasError) {
                    return Center(child: SingleChildScrollView(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 48),
                        const SizedBox(height: 12),
                        const Text('No se pudieron verificar tus equipos autorizados.', textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        SelectableText('${teamsSnapshot.error}', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _refreshProfile, child: const Text('REINTENTAR')),
                      ]),
                    )));
                  }
                  if (!teamsSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Colors.amber));
                  }
                  final authorized = teamsSnapshot.data!;
                  return MainAppMasterHub(
                    userRole: authorized.isNotEmpty ? 'manager' : ((profile['role'] == 'player' || profile['role'] == 'manager') ? profile['role'].toString() : 'fan'),
                    userName: fullName.isNotEmpty ? fullName : 'Usuario',
                    teamName: authorized.isNotEmpty ? (authorized.first['name']?.toString() ?? 'Mi equipo') : 'Mi perfil',
                    teamProvince: authorized.isNotEmpty ? (authorized.first['province']?.toString() ?? '') : '',
                    authorizedTeams: authorized,
                  );
                },
              );
            }
            Widget message;
            if (snapshot.connectionState != ConnectionState.done) {
              message = const Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: Colors.amber),
                SizedBox(height: 18),
                Text('Consultando tu perfil en Supabase LAB...'),
              ]);
            } else if (snapshot.hasError) {
              message = Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber, color: Colors.amber, size: 54),
                const SizedBox(height: 12),
                const Text('No se pudo consultar tu perfil.', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text('Revisa la conexión, los permisos SELECT de profiles y que el usuario esté autenticado.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                SelectableText('Detalle técnico: ${snapshot.error}', textAlign: TextAlign.center),
              ]);
            } else if (snapshot.data == null) {
              message = const Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_off_outlined, color: Colors.amber, size: 54),
                SizedBox(height: 12),
                Text('Tu sesión está activa, pero aún no existe un perfil vinculado.', textAlign: TextAlign.center),
                SizedBox(height: 8),
                Text('No se ha creado un perfil ni asignado permisos automáticamente. La recuperación segura queda pendiente.', textAlign: TextAlign.center),
              ]);
            } else {
              message = const Text('No fue posible resolver el perfil. Intenta de nuevo.');
            }
            return Center(child: SingleChildScrollView(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                message,
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _refreshProfile,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a consultar perfil'),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      await Supabase.instance.client.auth.signOut();
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No se pudo cerrar sesión.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                ),
              ]),
            )));
          },
        )),
      );
    }
    if (!_showLogin) {
      return SplashScreen(
        onContinue: () => setState(() => _showLogin = true),
        onWatch: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const SwlLiveLobby(authorizedTeams: [], readOnly: true),
        )),
      );
    }
    return AuthLoginScreen(onClose: () => setState(() => _showLogin = false));
  }
}

// FASE 1: creación y lectura de equipos exclusivamente mediante Supabase LAB.
// No concede permisos por el rol solicitado durante el registro.
class SwlTeamLabPanel extends StatefulWidget {
  const SwlTeamLabPanel({super.key});

  @override
  State<SwlTeamLabPanel> createState() => _SwlTeamLabPanelState();
}

class _SwlTeamLabPanelState extends State<SwlTeamLabPanel> {
  final _nameController = TextEditingController();
  final _provinceController = TextEditingController();
  Future<List<Map<String, dynamic>>>? _teamsFuture;
  bool _creating = false;
  String? _notice;
  String? _createdTeamId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _teamsFuture = Supabase.instance.client
          .from('teams')
          .select('id, name, province, created_by')
          .order('name');
    });
  }

  Future<void> _createTeam() async {
    if (_creating) return;
    final name = _nameController.text.trim();
    final province = _provinceController.text.trim();
    if (name.isEmpty || province.isEmpty) {
      setState(() => _notice = 'Completa el nombre y la provincia.');
      return;
    }
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null) {
      setState(() => _notice = 'Debes iniciar sesión para crear un equipo.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar creación de equipo'),
        content: Text('¿Crear el equipo "$name" en $province en Supabase LAB? Esta operación guardará datos reales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear equipo')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _creating = true; _notice = null; });
    try {
      // La RPC comprueba autorización y crea los registros que su lógica defina.
      // Nunca insertar directamente en teams o team_admins desde Flutter.
      final result = await Supabase.instance.client.rpc(
        'swl_create_team',
        params: {'p_name': name, 'p_province': province},
      );
      if (result == null || result.toString().isEmpty) {
        throw StateError('La función no devolvió un identificador de equipo.');
      }
      if (!mounted) return;
      setState(() {
        _createdTeamId = result.toString();
        _notice = 'Solicitud completada. Equipo creado con ID: $_createdTeamId. Los permisos se verifican por separado.';
      });
      _reload();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _notice = 'Supabase rechazó la creación: ${e.message} (código: ${e.code ?? "sin código"}).');
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = 'No se pudo confirmar la creación. Revisa la tabla teams antes de volver a intentarlo. Detalle: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _provinceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16202C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Equipos — Supabase LAB', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber)),
            const SizedBox(height: 8),
            const Text('Crea un equipo mediante la función segura swl_create_team. Crear un equipo no te convierte en mánager deportivo.'),
            const SizedBox(height: 12),
            TextField(controller: _nameController, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre del equipo')),
            TextField(controller: _provinceController, maxLength: 100, decoration: const InputDecoration(labelText: 'Provincia o municipio')),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _creating ? null : _createTeam,
              icon: _creating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_circle_outline),
              label: Text(_creating ? 'Creando equipo...' : 'Crear equipo en LAB'),
            ),
            if (_notice != null) ...[
              const SizedBox(height: 10),
              SelectableText(_notice!),
            ],
            const SizedBox(height: 16),
            const Divider(height: 28),
            Row(children: [
              const Expanded(child: Text('Equipos visibles', style: TextStyle(fontWeight: FontWeight.bold))),
              IconButton(onPressed: _reload, tooltip: 'Actualizar equipos', icon: const Icon(Icons.refresh)),
            ]),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _teamsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return SelectableText('No se pudo leer teams. Comprueba la política SELECT. Detalle: ${snapshot.error}');
                }
                final teams = snapshot.data ?? <Map<String, dynamic>>[];
                if (teams.isEmpty) return const Text('No hay equipos visibles para esta sesión.');
                return Column(
                  children: teams.map((team) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${team['name'] ?? 'Sin nombre'}'),
                    subtitle: Text('${team['province'] ?? 'Provincia no indicada'}'),
                    trailing: team['id']?.toString() == _createdTeamId
                        ? const Icon(Icons.check_circle, color: Colors.amber)
                        : null,
                  )).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// FASE 1 — registro y fichaje independientes; toda escritura exige confirmación.
// Los permisos efectivos los determina Supabase, no el rol solicitado en Flutter.
// V4.2: los equipos visibles no implican permisos de administración.
Future<List<Map<String, dynamic>>> swlAuthorizedTeams() async {
  final client = Supabase.instance.client;
  if (client.auth.currentUser == null) return [];
  const pageSize = 100;
  const permissionBatchSize = 8;
  final allowed = <Map<String, dynamic>>[];
  String? lastId;
  while (true) {
    final query = client.from('teams').select('id, name, province');
    final page = await (lastId == null ? query : query.gt('id', lastId))
        .order('id').limit(pageSize).timeout(const Duration(seconds: 12));
    if (page.isEmpty) break;
    for (var start = 0; start < page.length; start += permissionBatchSize) {
      final batch = page.skip(start).take(permissionBatchSize);
      final checks = await Future.wait(batch.map((team) async {
        final allowed = await client.rpc('swl_can_manage_roster',
            params: {'p_team_id': team['id']}).timeout(const Duration(seconds: 8));
        return allowed == true ? team : null;
      }));
      allowed.addAll(checks.whereType<Map<String, dynamic>>());
    }
    lastId = page.last['id'].toString();
    if (page.length < pageSize) break;
  }
  allowed.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
  return allowed;
}

class SwlPlayersLabPanel extends StatefulWidget {
  final bool registerMode;
  final String? initialTeamId;
  const SwlPlayersLabPanel({super.key, required this.registerMode, this.initialTeamId});
  @override
  State<SwlPlayersLabPanel> createState() => _SwlPlayersLabPanelState();
}

class _SwlPlayersLabPanelState extends State<SwlPlayersLabPanel> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _jersey = TextEditingController();
  final _position = TextEditingController();
  final _photo = TextEditingController();
  final _searchCode = TextEditingController();
  Map<String, dynamic>? _selectedPlayer;
  bool _searching = false;
  String? _teamId;
  bool _refuerzo = false;
  bool _busy = false;
  String? _notice;
  Map<String, dynamic>? _pendingRegisteredPlayer;
  String? _pendingTeamId;
  Future<List<Map<String, dynamic>>>? _teams;
  Future<List<Map<String, dynamic>>>? _roster;

  @override
  void initState() {
    super.initState();
    _teamId = widget.initialTeamId;
    // Reutilizar una sola consulta de permisos para selector y equipo inicial.
    _teams = swlAuthorizedTeams();
    _resolveTeam(_teams!);
  }

  Future<void> _resolveTeam(Future<List<Map<String, dynamic>>> teamsFuture) async {
    try {
      final teams = await teamsFuture;
      if (!mounted) return;
      final currentAllowed = teams.any((t) => t['id']?.toString() == _teamId);
      setState(() {
        if (!currentAllowed) _teamId = teams.length == 1 ? teams.first['id'].toString() : null;
      });
      _loadRoster();
    } catch (e) {
      if (mounted) setState(() => _notice = 'No se pudieron verificar los permisos: $e');
    }
  }

  void _loadRoster() {
    final id = _teamId;
    setState(() {
      _roster = id == null ? null : _fetchRoster(id);
    });
  }

  Future<List<Map<String, dynamic>>> _fetchRoster(String teamId) async {
    final data = await Supabase.instance.client.rpc(
      'swl_get_team_roster', params: {'p_team_id': teamId},
    );
    if (data is! List) throw StateError('El roster no devolvió una lista.');
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  // Consulta fresca al servidor antes de repetir una operación potencialmente aplicada.
  // Si el RPC no devuelve identificadores verificables, no se reintenta a ciegas.
  Future<bool> _alreadyInRoster(String teamId, String playerId) async {
    final roster = await _fetchRoster(teamId);
    if (roster.isNotEmpty && !roster.any((row) =>
        row.containsKey('player_id') || row.containsKey('id_player'))) {
      throw StateError('El roster no expone player_id; no es seguro repetir el fichaje automáticamente.');
    }
    return roster.any((row) =>
        (row['player_id'] ?? row['id_player'])?.toString().toLowerCase() == playerId.toLowerCase());
  }

  Future<bool> _confirm(String title, String description) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    ) ?? false;
  }

  Future<void> _register() async {
    if (_busy) return;
    if (_pendingRegisteredPlayer != null) {
      setState(() => _notice = 'Ya hay un registro pendiente de confirmar. Reintenta su fichaje antes de crear otro pelotero.');
      return;
    }
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty || last.isEmpty || first.length > 100 || last.length > 100) {
      setState(() => _notice = 'Nombre y apellido obligatorios (máximo 100 caracteres).');
      return;
    }
    final team = _teamId;
    if (team == null) {
      setState(() => _notice = 'Selecciona un equipo autorizado antes de registrar y fichar.');
      return;
    }
    if (!await _confirm('Registrar y fichar',
        '¿Registrar a $first $last y ficharlo en el equipo seleccionado? Son dos operaciones; si el fichaje falla, conservaremos el ID del pelotero.')) return;
    if (!mounted) return;
    setState(() { _busy = true; _notice = null; });
    String? createdId;
    String? createdCode;
    try {
      final permitted = await Supabase.instance.client.rpc(
        'swl_can_manage_roster', params: {'p_team_id': team});
      if (permitted != true) throw StateError('No tienes autorización activa para administrar ese roster.');
      final data = await Supabase.instance.client.rpc('swl_register_player', params: {
        'p_first_name': first,
        'p_last_name': last,
        'p_jersey_number': _jersey.text.trim(),
        'p_primary_position': _position.text.trim(),
        'p_photo_url': _photo.text.trim(),
      });
      final row = data is List && data.isNotEmpty ? data.first : data;
      if (row is! Map) throw StateError('Respuesta de registro inesperada: $data');
      createdId = (row['v_player_id'] ?? row['player_id'] ?? row['id'])?.toString();
      createdCode = (row['v_universal_id'] ?? row['universal_id'])?.toString();
      if (createdId == null || !RegExp(r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(createdId)) {
        createdId = null;
        throw StateError('Respuesta sin UUID válido. Busca el pelotero antes de volver a registrarlo.');
      }
      _pendingRegisteredPlayer = {
        'player_id': createdId, 'first_name': first, 'last_name': last,
        'universal_id': createdCode ?? '',
      };
      _pendingTeamId = team;
      final rosterId = await Supabase.instance.client.rpc('swl_sign_player', params: {
        'p_team_id': team,
        'p_player_id': createdId,
        'p_is_refuerzo': false,
      });
      if (!mounted) return;
      setState(() {
        _pendingRegisteredPlayer = null;
        _pendingTeamId = null;
        _notice = 'Pelotero registrado y fichado. Código: ${createdCode ?? "no disponible"}. Roster: $rosterId';
      });
      _loadRoster();
    } catch (e) {
      if (!mounted) return;
      setState(() => _notice = createdId != null
        ? 'El pelotero YA fue registrado (ID: $createdId; código: ${createdCode ?? "no disponible"}), '
          'pero el fichaje NO se confirmó. No vuelvas a registrarlo: busca su código para ficharlo. Detalle: $e'
        : e is PostgrestException && e.code == '23505' &&
            e.message.contains('players_universal_id_key')
          ? 'El servidor intentó asignar un código SWL que ya existe. El nuevo pelotero no se registró. El generador de códigos de LAB requiere revisión.'
          : 'No se pudo confirmar el registro. Revisa el catálogo de peloteros antes de reintentar para evitar duplicados. Detalle: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPendingSign() async {
    if (_busy) return;
    final pending = _pendingRegisteredPlayer;
    final team = _pendingTeamId;
    if (pending == null || team == null) return;
    if (!await _confirm('Reintentar fichaje',
        'Se volverá a intentar el fichaje del jugador ya registrado. No se creará otro jugador. Comprueba antes el roster si hubo un error de conexión.')) return;
    if (!mounted) return;
    setState(() { _busy = true; _notice = null; });
    try {
      final permitted = await Supabase.instance.client.rpc(
        'swl_can_manage_roster', params: {'p_team_id': team});
      if (permitted != true) throw StateError('Ya no tienes permiso para este roster.');
      final playerId = pending['player_id']?.toString() ?? '';
      if (await _alreadyInRoster(team, playerId)) {
        if (!mounted) return;
        setState(() {
          _pendingRegisteredPlayer = null;
          _pendingTeamId = null;
          _notice = 'Fichaje ya confirmado en el roster. No se repitió la operación.';
        });
        _loadRoster();
        return;
      }
      final result = await Supabase.instance.client.rpc('swl_sign_player', params: {
        'p_team_id': team,
        'p_player_id': pending['player_id'],
        'p_is_refuerzo': false,
      });
      if (!mounted) return;
      setState(() {
        _pendingRegisteredPlayer = null;
        _pendingTeamId = null;
        _notice = 'Fichaje confirmado. Roster: $result';
      });
      _loadRoster();
    } catch (e) {
      if (mounted) setState(() => _notice =
        'No se confirmó el fichaje. El pelotero sigue registrado; verifica el roster antes de reintentar. Detalle: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findPlayerByCode() async {
    if (_busy || _searching) return;
    final code = _searchCode.text.trim().toUpperCase();
    setState(() { _selectedPlayer = null; _notice = null; });
    if (_teamId != null) _loadRoster();
    if (!RegExp(r'^SWL-[A-Z0-9]+$').hasMatch(code)) {
      setState(() => _notice = 'Escribe el código SWL del pelotero. Ejemplo: SWL-0002.');
      return;
    }
    setState(() => _searching = true);
    try {
      final data = await Supabase.instance.client.rpc(
        'swl_find_player', params: {'p_universal_id': code},
      );
      if (!mounted) return;
      final row = data is List ? (data.isEmpty ? null : data.first) : data;
      if (row is! Map) {
        setState(() => _notice = 'No se encontró un pelotero con ese código.');
        return;
      }
      final player = Map<String, dynamic>.from(row);
      final id = player['player_id'] ?? player['id'];
      if (id == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id.toString())) {
        throw StateError('La búsqueda no devolvió un identificador válido.');
      }
      setState(() => _selectedPlayer = player);
    } catch (e) {
      if (mounted) setState(() => _notice = 'No se pudo buscar el pelotero: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sign() async {
    if (_busy) return;
    final team = _teamId;
    final selected = _selectedPlayer;
    final player = (selected?['player_id'] ?? selected?['id'])?.toString() ?? '';
    if (team == null || selected == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(player)) {
      setState(() => _notice = 'Selecciona equipo y busca un pelotero por su código SWL.');
      return;
    }
    setState(() { _busy = true; _notice = null; });
    try {
      final permission = await Supabase.instance.client.rpc('swl_can_manage_roster', params: {'p_team_id': team});
      if (permission != true) throw StateError('No tienes autorización activa para fichar en ese equipo.');
      if (!mounted) return;
      if (!await _confirm('Confirmar fichaje',
          '¿Fichar a ${selected['first_name'] ?? ''} ${selected['last_name'] ?? ''} (${selected['universal_id'] ?? ''}) en el equipo seleccionado? '
          'Supabase verificará tus permisos. Refuerzo: ${_refuerzo ? "sí" : "no"}.')) return;
      if (!mounted) return;
      if (await _alreadyInRoster(team, player)) {
        if (mounted) setState(() => _notice = 'Este pelotero ya aparece en el roster. No se repitió el fichaje.');
        _loadRoster();
        return;
      }
      final result = await Supabase.instance.client.rpc('swl_sign_player', params: {
        'p_team_id': team,
        'p_player_id': player,
        'p_is_refuerzo': _refuerzo,
      });
      if (!mounted) return;
      setState(() => _notice = 'Fichaje procesado. ID de roster: $result');
      _loadRoster();
    } catch (e) {
      if (mounted) setState(() => _notice = 'No se pudo confirmar el fichaje. '
          'Comprueba el roster antes de reintentar. Detalle: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _teamSelector() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _teams,
    builder: (context, snapshot) {
      if (snapshot.hasError) return SelectableText('Error al verificar equipos autorizados: ${snapshot.error}');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final teams = snapshot.data!;
      if (teams.isEmpty) return const Text('No tienes equipos con autorización activa para fichar.');
      if (teams.length == 1) return Text('Equipo autorizado: ${teams.first['name']} (selección automática)');
      return DropdownButtonFormField<String>(
        value: teams.any((t) => t['id']?.toString() == _teamId) ? _teamId : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Elige el equipo que administras'),
        items: teams.map((t) => DropdownMenuItem<String>(
          value: t['id'].toString(),
          child: Text('${t['name']} — ${t['province'] ?? ''}', overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (id) {
          setState(() {
            _teamId = id;
            _selectedPlayer = null;
            _notice = null;
          });
          _loadRoster();
        },
      );
    },
  );

  @override
  void dispose() {
    for (final c in [_first, _last, _jersey, _position, _photo, _searchCode]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF16202C),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.registerMode ? 'REGISTRAR NUEVO PELOTERO' : 'BUSCAR Y FICHAR PELOTERO',
              style: const TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (widget.registerMode) ...[
            const Text('Registra y ficha al pelotero en un equipo que administras.'),
            _teamSelector(),
            const SizedBox(height: 12),
            TextField(controller: _first, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre *')),
            TextField(controller: _last, maxLength: 100, decoration: const InputDecoration(labelText: 'Apellido *')),
            TextField(controller: _jersey, decoration: const InputDecoration(labelText: 'Número de camiseta (opcional)')),
            TextField(controller: _position, decoration: const InputDecoration(labelText: 'Posición (opcional)')),
            TextField(controller: _photo, decoration: const InputDecoration(labelText: 'URL de fotografía (opcional)')),
            FilledButton.icon(onPressed: (_busy || _pendingRegisteredPlayer != null) ? null : _register,
                icon: const Icon(Icons.person_add_alt_1), label: const Text('Registrar pelotero en LAB')),
            if (_pendingRegisteredPlayer != null) ...[
              const SizedBox(height: 8),
              SelectableText('Registro creado: ${_pendingRegisteredPlayer!['first_name']} ${_pendingRegisteredPlayer!['last_name']} · ID: ${_pendingRegisteredPlayer!['player_id']} · Código: ${_pendingRegisteredPlayer!['universal_id']}'),
              OutlinedButton.icon(
                onPressed: _busy ? null : _retryPendingSign,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar fichaje sin duplicar registro'),
              ),
            ],
          ] else ...[
            const Text('Busca un pelotero registrado mediante su código SWL. Ejemplo: SWL-0002.'),
            _teamSelector(),
            TextField(
              controller: _searchCode,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() { _selectedPlayer = null; _notice = null; }),
              decoration: const InputDecoration(labelText: 'Código SWL del pelotero (ej. SWL-0002)'),
            ),
            OutlinedButton.icon(
              onPressed: (_busy || _searching) ? null : _findPlayerByCode,
              icon: const Icon(Icons.search),
              label: Text(_searching ? 'Buscando...' : 'Buscar pelotero'),
            ),
            if (_selectedPlayer != null) Card(child: ListTile(
              leading: const Icon(Icons.person, color: Colors.amber),
              title: Text('${_selectedPlayer!['first_name'] ?? ''} ${_selectedPlayer!['last_name'] ?? ''}'),
              subtitle: Text('${_selectedPlayer!['universal_id'] ?? ''} · #${_selectedPlayer!['jersey_number'] ?? ''} · ${_selectedPlayer!['primary_position'] ?? ''}'),
            )),
            CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Es refuerzo'),
                value: _refuerzo, onChanged: _busy ? null : (v) => setState(() => _refuerzo = v ?? false)),
            // La comprobación se limita al equipo seleccionado: un pelotero
            // puede estar fichado en otros equipos al mismo tiempo.
            if (_selectedPlayer != null && _teamId != null && _roster != null)
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _roster,
                builder: (context, snapshot) {
                  final selectedId = (_selectedPlayer!['player_id'] ??
                      _selectedPlayer!['id'])?.toString().toLowerCase();
                  final rosterReady = snapshot.hasData && selectedId != null;
                  final rosterHasIds = rosterReady && (snapshot.data!.isEmpty ||
                      snapshot.data!.every((row) =>
                          row.containsKey('player_id') || row.containsKey('id_player')));
                  final alreadySigned = rosterHasIds && snapshot.data!.any((row) =>
                      (row['player_id'] ?? row['id_player'])?.toString().toLowerCase() == selectedId);
                  if (snapshot.hasError || (rosterReady && !rosterHasIds)) {
                    return const Text(
                      'No se pudo verificar el roster de este equipo. '
                      'Por seguridad, el fichaje está deshabilitado hasta actualizar la consulta.',
                      style: TextStyle(color: Colors.amber),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (alreadySigned)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Este pelotero ya está fichado en este equipo.',
                              style: TextStyle(color: Colors.amber)),
                        ),
                      FilledButton.icon(
                        onPressed: (_busy || _searching || !rosterHasIds || alreadySigned)
                            ? null : _sign,
                        icon: Icon(alreadySigned ? Icons.check_circle : Icons.group_add),
                        label: Text(alreadySigned ? 'Ya está fichado en este equipo' : 'Confirmar fichaje en LAB'),
                      ),
                    ],
                  );
                },
              )
            else
              FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.group_add),
                label: const Text('Confirmar fichaje en LAB'),
              ),
          ],
          if (_notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_notice!)),
          if (!widget.registerMode && _roster != null) FutureBuilder<List<Map<String, dynamic>>>(
            future: _roster,
            builder: (context, snapshot) {
              if (snapshot.hasError) return SelectableText('Error de roster: ${snapshot.error}');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              if (snapshot.data!.isEmpty) return const Text('Este equipo no tiene peloteros visibles.');
              return Column(children: snapshot.data!.map((p) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'),
                subtitle: SelectableText('#${p['jersey_number'] ?? ''} · ${p['primary_position'] ?? ''}\n${p['universal_id'] ?? ''}'),
                trailing: p['is_refuerzo'] == true ? const Icon(Icons.star, color: Colors.amber) : null,
              )).toList());
            },
          ),
        ]),
      ),
    );
  }
}

// =========================================================================
// 1. APERTURA (SPLASH CON LOGO RECORTADO TRANSPARENTE)
// =========================================================================
class SplashScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final VoidCallback? onWatch;
  const SplashScreen({super.key, required this.onContinue, this.onWatch});

  final String logoUrl = "https://epqyabaegmyjtwqezvbc.supabase.co/storage/v1/object/public/team-logos/logo_transparent-removebg-preview.png";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.network(
              "https://images.unsplash.com/photo-1540747913346-19e32dc3e97e?auto=format&fit=crop&w=1200&q=80",
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) => Container(color: const Color(0xFF0B1118)),
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withAlpha(245), Colors.black.withAlpha(120)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(color: Colors.amber.withAlpha(150), blurRadius: 45, spreadRadius: 2),
                        ],
                      ),
                      child: Image.network(
                        logoUrl,
                        height: 220,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => const Icon(Icons.sports_baseball, color: Colors.amber, size: 90),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text("SOFTBALL WORLD LINEUP", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text("La Plataforma Oficial del Sóftbol", style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      icon: const Icon(Icons.arrow_forward, color: Colors.black),
                      label: const Text("ENTRAR AL TERRENO", style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      onPressed: onContinue,
                    ),
                  ),
                  if (onWatch != null)
                    TextButton(onPressed: onWatch, child: const Text('VER PARTIDO POR PIN')),
                  const SizedBox(height: 10),
                  const Text("República Dominicana · Internacional", style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// 2. INICIO DE SESIÓN CON REGISTRO COMPLETO DEL EQUIPO
// =========================================================================
class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final String logoUrl = "https://epqyabaegmyjtwqezvbc.supabase.co/storage/v1/object/public/team-logos/logo_transparent-removebg-preview.png";

  void _showProviderPending(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider todavía no está configurado. Usa correo electrónico.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(title: const Text('Softball World Lineup'),
          backgroundColor: const Color(0xFF0F1722)),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(children: [
          Image.network(logoUrl, height: 76, fit: BoxFit.contain,
            errorBuilder: (ctx, err, stack) => const Icon(Icons.sports_baseball,
                color: Colors.amber, size: 54)),
          FullTeamRegistrationSheet(onClose: widget.onClose),
          const SizedBox(height: 12),
          const Text('Otras opciones (pendientes de configurar)',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 8),
          _btn(Icons.g_mobiledata, Colors.redAccent, 'Continuar con Google',
              () => _showProviderPending('Google')),
          const SizedBox(height: 8),
          _btn(Icons.apple, Colors.white, 'Continuar con Apple',
              () => _showProviderPending('Apple')),
        ]),
      )),
    );
  }

  Widget _btn(IconData ic, Color col, String txt, VoidCallback tap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF16202C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: const BorderSide(color: Colors.white12),
      ),
      onPressed: tap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ic, color: col, size: 24),
          const SizedBox(width: 10),
          Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// Registro e inicio de sesión con correo electrónico.
// La creación del perfil y del equipo queda pendiente de una estructura
// profiles/relaciones confirmada; nunca se asignan permisos desde el cliente.
class FullTeamRegistrationSheet extends StatefulWidget {
  const FullTeamRegistrationSheet({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<FullTeamRegistrationSheet> createState() => _FullTeamRegistrationSheetState();
}

class _FullTeamRegistrationSheetState extends State<FullTeamRegistrationSheet> {
  bool isRegistering = false;
  bool isSubmitting = false;
  bool obscurePassword = true;
  String? feedbackMessage;
  bool feedbackIsError = false;
  String selectedRole = "fan";

  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      feedbackMessage = message;
      feedbackIsError = error;
    });
  }

  Future<void> _submit() async {
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      _showMessage('Escribe un correo electrónico válido.', error: true);
      return;
    }
    if (password.length < 6) {
      _showMessage('La contraseña debe tener al menos 6 caracteres.', error: true);
      return;
    }
    if (isRegistering && nameCtrl.text.trim().isEmpty) {
      _showMessage('Escribe tu nombre completo.', error: true);
      return;
    }

    setState(() {
      isSubmitting = true;
      feedbackMessage = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (isRegistering) {
        final response = await auth.signUp(
          email: email,
          password: password,
          emailRedirectTo: kAuthRedirectUrl,
          data: {
            'full_name': nameCtrl.text.trim(),
            // Es una solicitud de rol, NO un permiso autorizado.
            'requested_role': selectedRole,
          },
        );

        if (!mounted) return;
        if (response.session == null) {
          _showMessage('Cuenta creada. Confirma el correo desde este teléfono para regresar a la aplicación. Si el enlace no abre la app, revisa Redirect URLs de Supabase LAB.');
        } else {
          _showMessage('Cuenta creada y autenticada. El perfil de la aplicación aún debe configurarse.');
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
        if (!mounted) return;
        // AuthTestGate ya escucha onAuthStateChange y sustituye el formulario
        // por la verificación de perfil. NO hacer Navigator.pop(): este
        // formulario forma parte de la ruta raíz y cerrarla deja pantalla negra.
        // Si el evento tarda en llegar, el gate sincroniza la sesión al volver
        // a construir el árbol por el propio listener de autenticación.
      }
    } on AuthException catch (e) {
      _showMessage(e.message, error: true);
    } on PostgrestException catch (e) {
      _showMessage('Error de datos: ${e.message}', error: true);
    } catch (e) {
      _showMessage('No se pudo completar la operación. Comprueba tu conexión e inténtalo de nuevo.', error: true);
      debugPrint('Error de autenticación: $e');
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 22,
          bottom: MediaQuery.of(context).viewInsets.bottom + 22,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (feedbackMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: feedbackIsError ? const Color(0xFF5A2020) : const Color(0xFF203C31),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(feedbackMessage!, style: const TextStyle(color: Colors.white)),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isRegistering ? 'CREAR TU CUENTA' : 'INICIAR SESIÓN',
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: isSubmitting ? null : widget.onClose,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (isRegistering) ...[
                _field(nameCtrl, 'Tu nombre completo', textCapitalization: TextCapitalization.words),
                const SizedBox(height: 10),
              ],
              _field(emailCtrl, 'Correo electrónico', keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              TextField(
                controller: passwordCtrl,
                obscureText: obscurePassword,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Contraseña (mínimo 6 caracteres)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                    icon: Icon(obscurePassword ? Icons.visibility : Icons.visibility_off, color: Colors.white60),
                  ),
                ),
              ),
              if (isRegistering) ...[
                const SizedBox(height: 16),
                const Text('¿CÓMO PARTICIPARÁS?', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: const Color(0xFF162131),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Tipo de cuenta', labelStyle: TextStyle(color: Colors.white70)),
                  items: const [
                    DropdownMenuItem(value: 'fan', child: Text('Fanático')),
                    DropdownMenuItem(value: 'player', child: Text('Pelotero')),
                    DropdownMenuItem(value: 'manager', child: Text('Mánager')),
                  ],
                  onChanged: isSubmitting ? null : (value) { if (value != null) setState(() => selectedRole = value); },
                ),
                const SizedBox(height: 10),
                const Text('Elegir Mánager no concede acceso a otros equipos. La administración requiere autorización del equipo.',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isSubmitting ? null : _submit,
                  child: isSubmitting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(
                          isRegistering ? 'CREAR CUENTA' : 'INICIAR SESIÓN',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: isSubmitting ? null : () => setState(() => isRegistering = !isRegistering),
                  child: Text(
                    isRegistering ? '¿Ya tienes cuenta? Inicia sesión' : '¿No tienes cuenta? Regístrate',
                    style: const TextStyle(color: Colors.amber),
                  ),
                ),
              ),
              if (!isRegistering)
                Center(
                  child: TextButton(
                    onPressed: isSubmitting ? null : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        _showMessage('Escribe tu correo para enviarte el enlace de recuperación.', error: true);
                        return;
                      }
                      try {
                        await Supabase.instance.client.auth.resetPasswordForEmail(email);
                        _showMessage('Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña.');
                      } on AuthException catch (e) {
                        _showMessage(e.message, error: true);
                      } catch (e) {
                        _showMessage('No se pudo enviar la solicitud. Inténtalo más tarde.', error: true);
                      }
                    },
                    child: const Text('Olvidé mi contraseña', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'El equipo y los permisos se vincularán después de configurar y verificar tu perfil.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
      ),
    );
  }
}

// =========================================================================
// 3. HUB PRINCIPAL DE LA APLICACIÓN
// =========================================================================
class MainAppMasterHub extends StatefulWidget {
  final String userRole;
  final String userName;
  final String teamName;
  final String teamProvince;
  final List<Map<String, dynamic>> authorizedTeams;

  const MainAppMasterHub({
    super.key,
    required this.userRole,
    required this.userName,
    required this.teamName,
    required this.teamProvince,
    this.authorizedTeams = const [],
  });

  @override
  State<MainAppMasterHub> createState() => _MainAppMasterHubState();
}

class _MainAppMasterHubState extends State<MainAppMasterHub> {
  int _currentIndex = 0;
  Map<String, dynamic>? _activeTeam;
  String? _chosenRole;

  @override
  void initState() {
    super.initState();
    if (widget.authorizedTeams.isNotEmpty) _activeTeam = widget.authorizedTeams.first;
  }

  void _changeActiveTeam(Map<String, dynamic> team) {
    if (!widget.authorizedTeams.any((t) => t['id']?.toString() == team['id']?.toString())) return;
    setState(() => _activeTeam = team);
  }

  Future<void> _editMyRole() async {
    String next = _chosenRole ?? widget.userRole;
    if (next == 'super_admin') return;
    final selected = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF162131),
      title: const Text('Mi tipo de cuenta', style: TextStyle(color: Colors.amber)),
      content: StatefulBuilder(builder: (ctx, update) => DropdownButton<String>(
        value: next, dropdownColor: const Color(0xFF162131),
        items: const [
          DropdownMenuItem(value: 'fan', child: Text('Fanático', style: TextStyle(color: Colors.white))),
          DropdownMenuItem(value: 'player', child: Text('Pelotero', style: TextStyle(color: Colors.white))),
          DropdownMenuItem(value: 'manager', child: Text('Mánager', style: TextStyle(color: Colors.white))),
        ],
        onChanged: (v) { if (v != null) update(() => next = v); },
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
        TextButton(onPressed: () => Navigator.pop(ctx, next), child: const Text('GUARDAR')),
      ],
    ));
    if (selected == null) return;
    try {
      await Supabase.instance.client.rpc('swl_set_my_role', params: {'p_role': selected});
      if (!mounted) return;
      setState(() => _chosenRole = selected);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tipo de cuenta actualizado. Los permisos del equipo no cambian.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo actualizar el tipo de cuenta: $e')));
    }
  }

  String? pendingJoinPin;
  String? scheduledOpponent;
  String? scheduledHomeId;
  int lobbyRequest = 0;

  void _openGameLobby({String? pin, String? opponent, String? opponentId, String? homeId}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SwlLiveLobby(
        authorizedTeams: widget.authorizedTeams,
        initialOpponent: opponent,
        initialOpponentId: opponentId,
        initialJoinPin: pin,
        preferredHomeId: homeId ?? _activeTeam?['id']?.toString(),
      ),
    ));
  }

  void _activateMatch(String opponent, String homeId, String opponentId) =>
      _openGameLobby(opponent: opponent, homeId: homeId, opponentId: opponentId);

  Future<void> _logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo cerrar la sesión.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeName = _activeTeam?['name']?.toString() ?? widget.teamName;
    final activeProvince = _activeTeam?['province']?.toString() ?? widget.teamProvince;
    final List<Widget> screens = [
      MasterHomeTab(
        onPlayNowTap: () => _openGameLobby(),
        onGameJoined: (pin) => _openGameLobby(pin: pin),
      ),
      MasterScoreboardTab(
        teamId: _activeTeam?['id']?.toString(),
        authorizedTeams: widget.authorizedTeams,
      ),
      MasterScheduleTab(
        myTeamName: activeName,
        teamId: _activeTeam?['id']?.toString(),
        onActivateMatch: _activateMatch,
        onOpenLinkedGame: (pin) => _openGameLobby(pin: pin),
      ),
      MasterTeamTab(
        userRole: widget.userRole,
        userName: widget.userName,
        teamName: activeName,
        teamProvince: activeProvince,
        authorizedTeams: widget.authorizedTeams,
        activeTeam: _activeTeam,
        onTeamChanged: _changeActiveTeam,
      ),
    ];

    String visibleRole = widget.authorizedTeams.isNotEmpty ? "manager" : (_chosenRole ?? widget.userRole);
    String badge = visibleRole == "manager" ? "MÁNAGER" : (visibleRole == "player" ? "PELOTERO" : "FANÁTICO");

    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)),
              child: Text(badge, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 9)),
            ),
            const SizedBox(width: 8),
            Expanded(child: widget.authorizedTeams.length > 1
              ? DropdownButtonHideUnderline(child: DropdownButton<String>(
                  value: _activeTeam?['id']?.toString(),
                  isExpanded: true,
                  dropdownColor: const Color(0xFF16202C),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  items: widget.authorizedTeams.map((team) => DropdownMenuItem<String>(
                    value: team['id']?.toString(),
                    child: Text('${team['name']} · ${team['province'] ?? ''}', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (id) {
                    for (final team in widget.authorizedTeams) {
                      if (team['id']?.toString() == id) { _changeActiveTeam(team); break; }
                    }
                  },
                ))
              : Text(_activeTeam != null ? '$activeName · $activeProvince' : widget.userName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white))),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.manage_accounts, color: Colors.amber), tooltip: 'Mi tipo de cuenta', onPressed: _editMyRole),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
            tooltip: "Cerrar Sesión",
            onPressed: _logout,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0F1722),
        indicatorColor: Colors.amber,
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: Colors.black), label: "Inicio"),
          NavigationDestination(icon: Icon(Icons.sports_baseball_outlined), selectedIcon: Icon(Icons.sports_baseball, color: Colors.black), label: "Pizarra"),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month, color: Colors.black), label: "Agenda"),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups, color: Colors.black), label: "Mi Equipo"),
        ],
      ),
    );
  }
}

// =========================================================================
// PESTAÑA 1: INICIO (PATROCINADORES CON CLIC DIRECTO A WHATSAPP/WEB)
// =========================================================================
class MasterHomeTab extends StatefulWidget {
  final VoidCallback onPlayNowTap;
  final Function(String) onGameJoined;
  const MasterHomeTab({super.key, required this.onPlayNowTap, required this.onGameJoined});

  @override
  State<MasterHomeTab> createState() => _MasterHomeTabState();
}

class _MasterHomeTabState extends State<MasterHomeTab> {
  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (t) {
      if (_bannerController.hasClients) {
        _currentBanner = (_currentBanner + 1) % 3;
        _bannerController.animateToPage(_currentBanner, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  // DIÁLOGO PARA GENERAR PIN O ENLAZAR CON PIN (Punto 3)
  void _openPlayDialog() {
    final pinCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("⚾ SALTAR AL TERRENO", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            // Crear nuevo con PIN aleatorio real
            ListTile(
              tileColor: const Color(0xFF0F172A),
              leading: const Icon(Icons.add_circle, color: Colors.amber),
              title: const Text("Crear Partido Nuevo (Generar PIN Dinámico)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text("Abre la creación real del partido", style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () {
                Navigator.pop(ctx);
                // Nunca anunciar un PIN sin crear realmente el partido.
                widget.onPlayNowTap();
              },
            ),

            const SizedBox(height: 8),

            // Unirse con PIN escrito
            ListTile(
              tileColor: const Color(0xFF0F172A),
              leading: const Icon(Icons.key, color: Colors.tealAccent),
              title: const Text("Unirse con PIN de Juego (Teléfono 2)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text("Escribe el PIN que generó el otro celular para enlazarse", style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF16202C),
                    title: const Text("Ingresar PIN de Juego", style: TextStyle(color: Colors.amber, fontSize: 15)),
                    content: TextField(
                      controller: pinCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                      decoration: const InputDecoration(hintText: "Ej: SWL-482"),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text("CANCELAR")),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                        onPressed: () {
                          if (pinCtrl.text.isNotEmpty) {
                            Navigator.pop(dCtx);
                            widget.onGameJoined(pinCtrl.text.trim().toUpperCase());
                          }
                        },
                        child: const Text("ENLAZAR", style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 10),

          // CARRUSEL: PATROCINADORES CON CLIC REAL A WHATSAPP O WEB (Punto 1)
          SizedBox(
            height: 120,
            child: PageView(
              controller: _bannerController,
              onPageChanged: (i) => setState(() => _currentBanner = i),
              children: [
                // ALEX MONO -> ABRE WHATSAPP
                _sponsorCard(
                  title: "PRESTAMOS ALEX MONO",
                  subtitle: "Las mejores condiciones de pago en RD",
                  color: const Color(0xFF2563EB),
                  bg: Colors.black,
                  icon: "🐵",
                  btnText: "WHATSAPP",
                  onTap: () => openExternalUrl("https://api.whatsapp.com/send?text=Hola%20Alex%20Mono%20solicito%20informacion%20de%20prestamo"),
                ),
                // CREDIGO -> ABRE SU PÁGINA WEB
                _sponsorCard(
                  title: "CrediGo",
                  subtitle: "Celulares a crédito sin papeleo en RD",
                  color: const Color(0xFF0FA0EA),
                  bg: Colors.white,
                  isDark: true,
                  icon: "📱",
                  btnText: "VER WEB",
                  onTap: () => openExternalUrl("https://credigo.do"),
                ),
                // DYNASTY -> ABRE SU PÁGINA
                _sponsorCard(
                  title: "DYNASTY",
                  subtitle: "Nuts & Fruit Lovers · El snack oficial del play",
                  color: const Color(0xFFDC2626),
                  bg: const Color(0xFFFFFBEB),
                  isDark: true,
                  icon: "👑",
                  btnText: "CONOCER",
                  onTap: () => openExternalUrl("https://instagram.com"),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // BOTÓN ¡A JUGAR AHORA!
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: _openPlayDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.amber.withAlpha(90), blurRadius: 15, offset: const Offset(0, 6))],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.sports_baseball, color: Colors.black, size: 34),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("¡A JUGAR AHORA!", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 19)),
                          Text("Crear partido con PIN o enlazar dos teléfonos", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.black, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sponsorCard({required String title, required String subtitle, required Color color, required Color bg, required String icon, required String btnText, required VoidCallback onTap, bool isDark = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: color, width: 1.5)),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                Text(subtitle, style: TextStyle(color: isDark ? Colors.black54 : Colors.white70, fontSize: 9)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            onPressed: onTap,
            child: Text(btnText, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// =========================================================================
// PESTAÑA 2: PARTIDOS DE MI EQUIPO (SIN FORMULARIO DE CREACIÓN)
// =========================================================================
class MasterScoreboardTab extends StatefulWidget {
  final String? teamId;
  final List<Map<String, dynamic>> authorizedTeams;
  const MasterScoreboardTab({super.key, required this.teamId,
    required this.authorizedTeams});

  @override
  State<MasterScoreboardTab> createState() => _MasterScoreboardTabState();
}

class _MasterScoreboardTabState extends State<MasterScoreboardTab> {
  late Future<List<Map<String, dynamic>>> _games;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant MasterScoreboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) _reload();
  }

  void _reload() {
    final id = widget.teamId;
    _games = id == null ? Future.value(<Map<String, dynamic>>[]) :
        _fetchGames(id);
  }

  Future<List<Map<String, dynamic>>> _fetchGames(String id) async {
    final rows = await Supabase.instance.client.from('swl_live_games')
        .select('id,game_pin,home_team_id,away_team_id,status,inning,is_top,home_runs,away_runs,created_at')
        .or('home_team_id.eq.$id,away_team_id.eq.$id')
        .order('created_at', ascending: false).limit(100)
        .timeout(const Duration(seconds: 15));
    return [for (final row in rows) Map<String, dynamic>.from(row)];
  }

  void _refresh() => setState(_reload);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF080D14),
    appBar: AppBar(title: const Text('⚾ PARTIDOS DE MI EQUIPO'),
      actions: [IconButton(onPressed: _refresh,
        tooltip: 'Actualizar partidos', icon: const Icon(Icons.refresh))]),
    body: widget.teamId == null
      ? const Center(child: Padding(padding: EdgeInsets.all(24),
          child: Text('No tienes un equipo autorizado seleccionado.',
            textAlign: TextAlign.center)))
      : FutureBuilder<List<Map<String, dynamic>>>(
          future: _games,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Column(mainAxisSize: MainAxisSize.min,
                children: [const Text('No se pudieron cargar los partidos.'),
                  TextButton(onPressed: _refresh, child: const Text('REINTENTAR'))]));
            }
            final games = snapshot.data ?? [];
            if (games.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(24),
                child: Text('Tu equipo todavía no tiene partidos registrados. '
                  'Para crear uno, ve a Inicio → ¡A JUGAR AHORA!',
                  textAlign: TextAlign.center)));
            }
            return RefreshIndicator(onRefresh: () async {
              _refresh();
              await _games;
            }, child: ListView.builder(
              itemCount: games.length,
              itemBuilder: (context, index) {
                final game = games[index];
                final status = game['status']?.toString() ?? 'SCHEDULED';
                final pin = game['game_pin']?.toString() ?? '';
                return Card(color: const Color(0xFF172334),
                  child: ListTile(
                    leading: const Icon(Icons.sports_baseball, color: Colors.amber),
                    title: Text('Partido $pin'),
                    subtitle: Text('$status · Entrada ${game['inning'] ?? 1} · '
                      '${game['away_runs'] ?? 0} - ${game['home_runs'] ?? 0}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: pin.isEmpty ? null : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => SwlLiveLobby(
                        authorizedTeams: widget.authorizedTeams,
                        openGameId: game['id']?.toString(),
                        preferredHomeId: widget.teamId,
                      ))).then((_) { if (mounted) _refresh(); }),
                  ));
              },
            ));
          },
        ),
  );
}

// =========================================================================
// PESTAÑA 3: AGENDA & RETOS (CONECTADA CON EQUIPOS REALES DE SUPABASE)
// =========================================================================
class MasterScheduleTab extends StatefulWidget {
  final String myTeamName;
  final String? teamId;
  final void Function(String opponent, String homeId, String opponentId) onActivateMatch;
  final ValueChanged<String> onOpenLinkedGame;

  const MasterScheduleTab({
    super.key,
    required this.myTeamName,
    required this.teamId,
    required this.onActivateMatch,
    required this.onOpenLinkedGame,
  });

  @override
  State<MasterScheduleTab> createState() => _MasterScheduleTabState();
}

class _MasterScheduleTabState extends State<MasterScheduleTab> {
  final List<Map<String, String>> matches = [];

  final _client = Supabase.instance.client;
  List<Map<String, dynamic>> _inbox = [];
  Map<String, Map<String, dynamic>> _agendaTeams = {};
  bool _loadingAgenda = false;
  bool _changingChallenge = false;
  bool _agendaAvailable = true;
  Set<String>? _observedIncoming;
  String? _agendaError;
  int _agendaRequest = 0;
  Timer? _agendaTimer;

  @override
  void initState() {
    super.initState();
    _refreshAgenda();
    _agendaTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_agendaAvailable) _refreshAgenda();
    });
  }

  @override
  void didUpdateWidget(covariant MasterScheduleTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _loadingAgenda = false;
      _inbox = [];
      _agendaTeams = {};
      _observedIncoming = null;
      _refreshAgenda();
    }
  }

  @override
  void dispose() {
    _agendaTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAgenda() async {
    final team = widget.teamId;
    if (team == null || _loadingAgenda) return;
    final request = ++_agendaRequest;
    setState(() { _loadingAgenda = true; _agendaError = null; });
    try {
      final rows = await _client.from('swl_v56_challenges').select()
          .or('home_team_id.eq.$team,away_team_id.eq.$team')
          .order('scheduled_at', ascending: false).limit(100)
          .timeout(const Duration(seconds: 12));
      final ids = {
        for (final row in rows)
          for (final key in ['home_team_id', 'away_team_id'])
            if (row[key] != null) row[key].toString(),
      };
      final teams = ids.isEmpty ? <Map<String, dynamic>>[] :
          await swlQueryTeams((columns) async =>
            await _client.from('teams').select(columns).inFilter('id', ids.toList())
              .timeout(const Duration(seconds: 12)));
      if (!mounted || request != _agendaRequest || widget.teamId != team) return;
      final incoming = {
        for (final row in rows)
          if (row['away_team_id'] == team && row['status'] == 'SENT') row['id'].toString(),
      };
      final previous = _observedIncoming;
      _observedIncoming = incoming;
      if (previous != null && incoming.difference(previous).isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recibiste un reto. Puedes responder desde Agenda.')),
        );
      }
      setState(() {
        _agendaAvailable = true;
        _inbox = rows;
        _agendaTeams = {for (final item in teams) item['id'].toString(): item};
      });
    } on PostgrestException catch (error) {
      if (!mounted || request != _agendaRequest || widget.teamId != team) return;
      setState(() {
        _agendaAvailable = error.code != 'PGRST205' && error.code != '42P01';
        _agendaError = _agendaAvailable ? 'No se pudo leer la Agenda compartida.' :
            'Agenda compartida pendiente de habilitación en LAB.';
      });
    } catch (_) {
      if (mounted && request == _agendaRequest && widget.teamId == team) {
        setState(() => _agendaError = 'No se pudo leer la Agenda compartida.');
      }
    } finally {
      if (mounted && request == _agendaRequest) setState(() => _loadingAgenda = false);
    }
  }

  Future<void> _sendChallenge(Map<String, String> draft) async {
    if (_changingChallenge || widget.teamId != draft['homeId']) return;
    setState(() => _changingChallenge = true);
    try {
      await _client.rpc('swl_v56_send_challenge', params: {
        'p_home_team_id': draft['homeId'],
        'p_away_team_id': draft['awayId'],
        'p_external_team_name': draft['awayId'] == null ? draft['away'] : null,
        'p_scheduled_at': draft['scheduledAt'],
        'p_stadium': draft['play'],
      }).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => matches.remove(draft));
      await _refreshAgenda();
    } catch (error) {
      _showAgendaActionError(error);
    } finally {
      if (mounted) setState(() => _changingChallenge = false);
    }
  }

  void _showAgendaActionError(Object error) {
    if (!mounted) return;
    final message = error is PostgrestException
        ? (error.code == 'PGRST202' ? 'La Agenda compartida aún no está habilitada en LAB.' : error.message)
        : 'No se confirmó la operación. Actualiza la Agenda antes de reintentar.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeChallenge(Map<String, dynamic> challenge, String action) async {
    if (_changingChallenge) return;
    setState(() => _changingChallenge = true);
    final team = widget.teamId;
    try {
      final result = action == 'OPEN' ? challenge :
          await _client.rpc('swl_v56_act_challenge', params: {
            'p_id': challenge['id'], 'p_action': action,
          }).timeout(const Duration(seconds: 12));
      final row = result is List ? result.single : result;
      if (row is! Map) throw StateError('Respuesta de Agenda incompleta.');
      if (row['game_id'] != null && (action == 'OPEN' || action == 'PREPARE')) {
        final game = await _client.from('swl_live_games').select('game_pin')
            .eq('id', row['game_id']).single().timeout(const Duration(seconds: 12));
        final pin = game['game_pin']?.toString();
        if (mounted && widget.teamId == team && pin != null) widget.onOpenLinkedGame(pin);
      }
      if (mounted) await _refreshAgenda();
    } catch (error) {
      _showAgendaActionError(error);
    } finally {
      if (mounted) setState(() => _changingChallenge = false);
    }
  }

  Widget _challengeCard(Map<String, dynamic> challenge) {
    final isHome = challenge['home_team_id'] == widget.teamId;
    final status = challenge['status'];
    final homeTeam = _agendaTeams[challenge['home_team_id']];
    final home = homeTeam?['name'] ?? 'Local';
    final awayTeam = _agendaTeams[challenge['away_team_id']];
    final away = awayTeam?['name'] ?? challenge['external_team_name'] ?? 'Visitante';
    final scheduled = DateTime.tryParse(challenge['scheduled_at']?.toString() ?? '')?.toLocal();
    final date = scheduled == null ? '' : '${MaterialLocalizations.of(context).formatShortDate(scheduled)} · '
      '${TimeOfDay.fromDateTime(scheduled).format(context)}';
    final label = switch (status) {
      'SENT' => isHome ? 'ENVIADO' : 'RETO RECIBIDO',
      'ACCEPTED' => 'ACEPTADO',
      'REJECTED' => 'RECHAZADO',
      'CANCELLED' => 'CANCELADO',
      'EXTERNAL' => 'PROGRAMADO · RIVAL EXTERNO',
      _ => 'ESTADO PENDIENTE',
    };
    Widget action(String label, String code) => TextButton(
      onPressed: _changingChallenge ? null : () => _changeChallenge(challenge, code),
      child: Text(label),
    );
    return Card(child: Column(children: [
      ListTile(leading: SwlTeamBadge(url: swlTeamLogo(awayTeam)), title: Text('$home vs $away'),
        subtitle: Text('$label · $date · ${challenge['stadium'] ?? ''}')),
      Wrap(children: [
        if (status == 'SENT' && !isHome) ...[
          action('ACEPTAR', 'ACCEPT'), action('RECHAZAR', 'REJECT'),
        ],
        if (status == 'ACCEPTED' && challenge['game_id'] != null)
          action('ABRIR PARTIDO', 'OPEN')
        else ...[
          if (isHome && status == 'ACCEPTED') action('PREPARAR PARTIDO EN VIVO', 'PREPARE'),
          if (isHome && ['SENT', 'ACCEPTED', 'EXTERNAL'].contains(status))
            action('CANCELAR ENCUENTRO', 'CANCEL'),
        ],
      ]),
    ]));
  }

  Future<void> _scheduleChallenge() async {
    final homeId = widget.teamId;
    if (homeId == null) return;
    var rival = '';
    Map<String, dynamic>? rivalTeam;
    var stadium = '';
    final today = DateUtils.dateOnly(DateTime.now());
    var date = today;
    var time = TimeOfDay.now();
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
        final localization = MaterialLocalizations.of(ctx);
        return AlertDialog(
          backgroundColor: const Color(0xFF16202C),
          title: const Text('Retar a un Equipo', style: TextStyle(color: Colors.amber)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwlTeamLookup(excludeId: homeId, onSelection: (name, team) => update(() {
              rival = name;
              rivalTeam = team;
            })),
            TextField(
              onChanged: (value) => stadium = value.trim(),
              decoration: const InputDecoration(labelText: 'Estadio'),
            ),
            TextButton(
              onPressed: () async {
                final value = await showDatePicker(context: ctx, initialDate: date,
                    firstDate: today, lastDate: DateTime(today.year + 2));
                if (value != null && ctx.mounted) update(() => date = value);
              },
              child: Text(localization.formatMediumDate(date)),
            ),
            TextButton(
              onPressed: () async {
                final value = await showTimePicker(context: ctx, initialTime: time);
                if (value != null && ctx.mounted) update(() => time = value);
              },
              child: Text(localization.formatTimeOfDay(time)),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCELAR')),
            FilledButton(
              onPressed: rival.isEmpty ? null : () => Navigator.pop(ctx, {
                'scheduledAt': DateTime(date.year, date.month, date.day,
                  time.hour, time.minute).toUtc().toIso8601String(),
                'date': '${localization.formatMediumDate(date)} · ${localization.formatTimeOfDay(time)}',
                'away': rival,
                if (rivalTeam != null) 'awayId': rivalTeam!['id'].toString(),
                if (swlTeamLogo(rivalTeam) case final String url) 'awayLogo': url,
                'home': widget.myTeamName,
                'homeId': homeId,
                'play': stadium,
              }),
              child: const Text('GUARDAR BORRADOR'),
            ),
          ],
        );
      }),
    );
    if (mounted && draft != null && widget.teamId == homeId) {
      final duplicate = matches.any((other) => other['homeId'] == homeId &&
          other['scheduledAt'] == draft['scheduledAt'] &&
          (draft['awayId'] != null ? other['awayId'] == draft['awayId'] :
            other['awayId'] == null && other['away']?.toLowerCase() == draft['away']?.toLowerCase()));
      if (duplicate) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ya existe un borrador para este rival y horario.')),
        );
      } else {
        setState(() => matches.add(draft));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamMatches = matches.where((row) => row['homeId'] == widget.teamId).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: const Text("📅 AGENDA & RETOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          IconButton(onPressed: _refreshAgenda, tooltip: 'Actualizar Agenda', icon: const Icon(Icons.refresh)),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            icon: const Icon(Icons.add, color: Colors.black, size: 16),
            label: const Text("RETAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
            onPressed: widget.teamId != null ? _scheduleChallenge : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_loadingAgenda) const LinearProgressIndicator(),
          if (_agendaError != null) ListTile(title: Text(_agendaError!)),
          if (teamMatches.isEmpty && _inbox.isEmpty && !_loadingAgenda)
            const ListTile(title: Text('Tu equipo aún no tiene encuentros en la Agenda.')),
          for (final challenge in _inbox) _challengeCard(challenge),
          for (final m in teamMatches)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(m["date"]!, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
                          const Text("BORRADOR", style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ListTile(
                        leading: SwlTeamBadge(url: m['awayLogo']),
                        title: Text('${m['home']} vs ${m['away']}'),
                        subtitle: Text(m['awayId'] == null ? 'Equipo externo' : 'Equipo registrado'),
                      ),
                      TextButton(
                        onPressed: _changingChallenge ? null : () => _sendChallenge(m),
                        child: Text(m['awayId'] == null ? 'PROGRAMAR EXTERNO' : 'ENVIAR RETO'),
                      ),
                      if (m['play']?.isNotEmpty == true)
                        Text(m['play']!, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                          icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                          label: const Text("🟢 PREPARAR PARTIDO EN VIVO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          onPressed: m['awayId'] == null ? null :
                              () => widget.onActivateMatch(m['away']!, m['homeId']!, m['awayId']!),
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

// =========================================================================
// PESTAÑA 4: MI EQUIPO (CON SWIPE PARA BORRAR/EDITAR Y + FICHAR CON ID)
// =========================================================================
class MasterTeamTab extends StatefulWidget {
  final String userRole;
  final String userName;
  final String teamName;
  final String teamProvince;
  final List<Map<String, dynamic>>? authorizedTeams;
  final Map<String, dynamic>? activeTeam;
  final ValueChanged<Map<String, dynamic>>? onTeamChanged;

  const MasterTeamTab({super.key, required this.userRole, required this.userName,
    required this.teamName, required this.teamProvince,
    this.authorizedTeams, this.activeTeam, this.onTeamChanged});

  @override
  State<MasterTeamTab> createState() => _MasterTeamTabState();
}

class _MasterTeamTabState extends State<MasterTeamTab> {
  late Future<List<Map<String, dynamic>>> _teams;
  Future<List<Map<String, dynamic>>>? _roster;
  String? _selectedTeamId;
  String? _selectedTeamName;
  String? _selectedProvince;
  Future<bool>? _canRemovePlayer;
  bool _removalInProgress = false;

  @override
  void initState() {
    super.initState();
    _teams = widget.authorizedTeams != null
        ? Future.value(widget.authorizedTeams!) : swlAuthorizedTeams();
    if (widget.activeTeam != null) {
      _selectTeam(widget.activeTeam!);
    } else {
      _autoSelectTeam();
    }
  }

  @override
  void didUpdateWidget(covariant MasterTeamTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextId = widget.activeTeam?['id']?.toString();
    if (nextId != null && nextId != _selectedTeamId) {
      _selectTeam(widget.activeTeam!);
    }
  }

  Future<void> _autoSelectTeam() async {
    try {
      final teams = await _teams;
      if (mounted && teams.length == 1) _selectTeam(teams.first);
    } catch (_) { /* FutureBuilder muestra el error de permisos. */ }
  }

  Future<List<Map<String, dynamic>>> _fetchRoster(String teamId) async {
    final rows = await Supabase.instance.client.rpc(
      'swl_get_team_roster', params: {'p_team_id': teamId});
    if (rows is! List) throw StateError('Respuesta de roster inesperada.');
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  void _selectTeam(Map<String, dynamic> team) {
    final id = team['id']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      _selectedTeamId = id;
      _selectedTeamName = team['name']?.toString();
      _selectedProvince = team['province']?.toString();
      _roster = _fetchRoster(id);
      _canRemovePlayer = Supabase.instance.client.rpc(
        'swl_can_manage_roster', params: {'p_team_id': id}
      ).then((value) => value == true).catchError((_) => false);
    });
  }

  void _refreshRoster() {
    final id = _selectedTeamId;
    if (id != null) setState(() => _roster = _fetchRoster(id));
  }

  // V4.5: retiro autorizado desde Supabase; nunca eliminar directamente en Flutter.
  Future<bool> _confirmRemovePlayer(Map<String, dynamic> player) async {
    final teamId = _selectedTeamId;
    final playerId = player['player_id']?.toString();
    if (teamId == null || playerId == null || playerId.isEmpty ||
        _removalInProgress) return false;
    // La autorización se comprueba otra vez, incluso si la pantalla
    // quedó abierta después de revocar permisos.
    try {
      final allowed = await Supabase.instance.client.rpc(
        'swl_can_manage_roster', params: {'p_team_id': teamId});
      if (allowed != true || !mounted || _selectedTeamId != teamId) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No tienes permiso para retirar peloteros.')));
        return false;
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron verificar los permisos.')));
      return false;
    }
    final name = '${player['first_name'] ?? ''} ${player['last_name'] ?? ''}'.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Retirar del equipo?'),
        content: Text('¿Deseas retirar a $name de ${_selectedTeamName ?? 'este equipo'}?\n\n'
            'Conservará su código SWL, su perfil y los fichajes en otros equipos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar retiro',
                  style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    setState(() => _removalInProgress = true);
    try {
      // El RPC verifica de nuevo los permisos del administrador/mánager.
      final removed = await Supabase.instance.client.rpc(
        'swl_remove_player_from_team',
        params: {'p_team_id': teamId, 'p_player_id': playerId},
      );
      if (!mounted || _selectedTeamId != teamId) return false;
      if (removed != true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El pelotero ya no figura como activo. Actualiza el roster.'),
        ));
        _refreshRoster();
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$name fue retirado de este equipo.'),
      ));
      _refreshRoster();
      // El FutureBuilder reconstruye la lista con los datos del servidor.
      // No permitir que Dismissible elimine la fila localmente.
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo retirar al pelotero: $e'),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _removalInProgress = false);
    }
  }

  // V4.9: ficha de consulta. Solo muestra datos recibidos del roster real.
  // No escribe en Supabase ni altera los permisos de retiro/fichaje.
  void _showPlayerDetails(Map<String, dynamic> player) {
    String field(String key) {
      final value = player[key]?.toString().trim() ?? '';
      return value.isEmpty ? 'No registrado' : value;
    }
    final name = '${field('first_name')} ${field('last_name')}';
    final teamName = _selectedTeamName ?? widget.teamName;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121B27),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('FICHA DEL PELOTERO',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold,
                fontSize: 17)),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 20,
              fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _playerDetailRow('Código SWL', field('universal_id')),
            _playerDetailRow('Número', field('jersey_number')),
            _playerDetailRow('Posición', field('primary_position')),
            _playerDetailRow('Equipo', teamName),
            _playerDetailRow('Condición',
              player['is_refuerzo'] == true ? 'Refuerzo' : 'Regular'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Cerrar ficha'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _playerDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 110, child: Text(label,
        style: const TextStyle(color: Colors.white60))),
      Expanded(child: SelectableText(value,
        style: const TextStyle(color: Colors.white,
          fontWeight: FontWeight.w600))),
    ]),
  );

  // V4.8: cada operación tiene su pantalla. Se conservan los widgets y RPC
  // de V4.7 sin cambiar la lógica de registro, fichaje o retiro.
  Future<void> _openCreateTeam() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF080D14),
        appBar: AppBar(
          title: const Text('Crear equipo'),
          backgroundColor: const Color(0xFF0F1722),
        ),
        body: const SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(12),
          child: SwlTeamLabPanel(),
        )),
      ),
    ));
    // Una creación puede cambiar los equipos autorizados. Se vuelven a
    // consultar los permisos del servidor, nunca se conceden desde Flutter.
    if (!mounted) return;
    setState(() { _teams = swlAuthorizedTeams(); });
  }

  Future<void> _openPlayerAction(bool registerMode) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF080D14),
        appBar: AppBar(title: Text(registerMode ? 'Registrar pelotero' : 'Buscar y fichar pelotero'),
          backgroundColor: const Color(0xFF0F1722)),
        body: SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SwlPlayersLabPanel(registerMode: registerMode,
              initialTeamId: _selectedTeamId))),
      ),
    ));
    if (mounted) _refreshRoster();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: Text(_selectedTeamName ?? widget.teamName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [IconButton(onPressed: _refreshRoster,
          tooltip: 'Actualizar roster', icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF121B27),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber)),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Colors.amber,
                child: Icon(Icons.shield, color: Colors.black)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selectedTeamName ?? widget.teamName,
                    style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(_selectedProvince ?? widget.teamProvince,
                    style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ])),
            ]),
          ),
          const SizedBox(height: 12),
          if (_selectedTeamId case final String teamId)
            SwlTeamLogoEditor(key: ValueKey(teamId), teamId: teamId),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _teams,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('No se pudieron consultar equipos: ${snapshot.error}',
                style: const TextStyle(color: Colors.orangeAccent));
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final teams = snapshot.data!;
              if (teams.isEmpty) return const Text('No tienes equipos con permisos activos de administración.');
              if (teams.length == 1) return Text('Equipo autorizado: ${teams.first['name']} (selección automática)');
              return DropdownButtonFormField<String>(
                value: teams.any((t) => t['id']?.toString() == _selectedTeamId)
                  ? _selectedTeamId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Equipo que administras en Supabase LAB'),
                items: teams.map((t) => DropdownMenuItem<String>(
                  value: t['id'].toString(),
                  child: Text('${t['name']} — ${t['province'] ?? ''}',
                    overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (id) {
                  for (final team in teams) {
                    if (team['id']?.toString() == id) { _selectTeam(team); widget.onTeamChanged?.call(team); break; }
                  }
                },
              );
            },
          ),
          const SizedBox(height: 10),
          const Text('GESTIÓN DEL EQUIPO', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openCreateTeam,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Crear equipo'),
          ),
          const SizedBox(height: 12),
          const Text('GESTIÓN DE PELOTEROS', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _selectedTeamId == null ? null : () => _openPlayerAction(true),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Registrar nuevo pelotero'),
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: _selectedTeamId == null ? null : () => _openPlayerAction(false),
            icon: const Icon(Icons.search, color: Colors.black),
            label: const Text('Buscar y fichar pelotero',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: _canRemovePlayer,
            builder: (context, permission) => Text(
              permission.data == true
                ? 'ROSTER REAL · DESLIZA A LA IZQUIERDA PARA RETIRAR'
                : 'ROSTER REAL',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _roster == null
            ? const Center(child: Text('Selecciona un equipo para consultar su roster.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54)))
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: _roster,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: SelectableText(
                    'Error al consultar el roster: ${snapshot.error}'));
                  if (!snapshot.hasData) return const Center(
                    child: CircularProgressIndicator());
                  final roster = snapshot.data!;
                  if (roster.isEmpty) return const Center(child: Text(
                    'Este equipo todavía no tiene peloteros fichados.',
                    style: TextStyle(color: Colors.white54)));
                  return ListView.builder(
                    itemCount: roster.length,
                    itemBuilder: (context, index) {
                      final p = roster[index];
                      return FutureBuilder<bool>(
                        future: _canRemovePlayer,
                        builder: (context, permission) => Dismissible(
                        key: ValueKey('roster-${_selectedTeamId}-${p['roster_id']}'),
                        direction: permission.data == true && !_removalInProgress
                            ? DismissDirection.endToStart
                            : DismissDirection.none,
                        confirmDismiss: (_) => _confirmRemovePlayer(p),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: const Color(0xFF9E2929),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.end,
                            children: [Icon(Icons.person_remove, color: Colors.white),
                              SizedBox(width: 8),
                              Text('Retirar', style: TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold))]),
                        ),
                        child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF121B27),
                          borderRadius: BorderRadius.circular(8)),
                        child: InkWell(
                        onTap: () => _showPlayerDetails(p),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(children: [
                          CircleAvatar(backgroundColor: const Color(0xFF0F172A),
                            radius: 16, child: Text('${p['jersey_number'] ?? '00'}',
                              style: const TextStyle(color: Colors.amber, fontSize: 10))),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p['first_name'] ?? ''} ${p['last_name'] ?? ''}',
                                style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold, fontSize: 12)),
                              Text('${p['universal_id'] ?? ''} · ${p['primary_position'] ?? ''}'
                                '${p['is_refuerzo'] == true ? ' · Refuerzo' : ''}',
                                style: const TextStyle(color: Colors.white54, fontSize: 10)),
                            ])),
                          const Icon(Icons.chevron_right,
                            color: Colors.white54, size: 18),
                        ]),
                        ),
                        ),
                        ),
                      );
                    },
                  );
                },
              )),
        ]),
      ),
    );
  }
}
