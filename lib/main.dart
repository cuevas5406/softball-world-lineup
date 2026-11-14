import 'dart:async';
import 'dart:math';
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
      anonKey: kSupabaseAnonKey,
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
      return;
    }
    if (force || _profileUserId != id || _profileLookup == null) {
      _profileUserId = id;
      _profileLookup = Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email, player_id')
          .eq('id', id)
          .maybeSingle();
    }
  }

  void _refreshProfile() {
    setState(() => _prepareProfileLookup(_session, force: true));
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
        appBar: AppBar(title: const Text('Verificación de perfil — LAB')),
        body: SafeArea(child: FutureBuilder<Map<String, dynamic>?>(
          future: _profileLookup,
          builder: (context, snapshot) {
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
              final profile = snapshot.data!;
              message = Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.verified_user_outlined, color: Colors.amber, size: 54),
                const SizedBox(height: 12),
                const Text('Perfil encontrado en LAB', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 8),
                Text((profile['full_name'] as String?)?.isNotEmpty == true
                    ? profile['full_name'] as String : 'Usuario autenticado'),
                const SizedBox(height: 12),
                const Text('El acceso al Hub requiere verificar por separado roles y permisos de equipos. No se conceden automáticamente.', textAlign: TextAlign.center),
                const SizedBox(height: 22),
                // Navegación de prueba: nunca deriva privilegios del perfil.
                // El Hub original contiene acciones de demostración; no son
                // operaciones reales de Supabase ni autorizaciones deportivas.
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => MainAppMasterHub(
                        userRole: 'fan',
                        userName: (profile['full_name'] as String?)?.trim().isNotEmpty == true
                            ? (profile['full_name'] as String).trim()
                            : 'Usuario',
                        teamName: 'Explorar equipos — LAB',
                        teamProvince: '',
                      ),
                    ));
                  },
                  icon: const Icon(Icons.dashboard_outlined),
                  label: const Text('Explorar menú principal (modo fan / prueba)'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Vista de prueba: no concede permisos de mánager o administrador. '
                  'Algunas acciones del Hub aún son demostraciones.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 22),
                const SwlTeamLabPanel(),
              ]);
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
      return SplashScreen(onContinue: () => setState(() => _showLogin = true));
    }
    return const AuthLoginScreen();
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
            const SwlPlayersLabPanel(),
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
class SwlPlayersLabPanel extends StatefulWidget {
  const SwlPlayersLabPanel({super.key});
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
  Future<List<Map<String, dynamic>>>? _teams;
  Future<List<Map<String, dynamic>>>? _roster;

  @override
  void initState() {
    super.initState();
    _loadTeams();
  }

  void _loadTeams() {
    setState(() {
      _teams = Supabase.instance.client.from('teams')
          .select('id, name, province').order('name');
    });
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
    final first = _first.text.trim();
    final last = _last.text.trim();
    if (first.isEmpty || last.isEmpty || first.length > 100 || last.length > 100) {
      setState(() => _notice = 'Nombre y apellido obligatorios (máximo 100 caracteres).');
      return;
    }
    if (!await _confirm('Registrar pelotero',
        '¿Registrar a $first $last en Supabase LAB? Esto crea una identidad deportiva, pero NO lo ficha en ningún equipo.')) return;
    if (!mounted) return;
    setState(() { _busy = true; _notice = null; });
    try {
      final data = await Supabase.instance.client.rpc('swl_register_player', params: {
        'p_first_name': first,
        'p_last_name': last,
        'p_jersey_number': _jersey.text.trim(),
        'p_primary_position': _position.text.trim(),
        'p_photo_url': _photo.text.trim(),
      });
      if (!mounted) return;
      // La función devuelve una fila con ID y universal_id; no se presupone
      // el nombre de sus columnas para no ocultar errores de firma.
      final row = data is List && data.isNotEmpty ? data.first : data;
      if (row is! Map) throw StateError('Respuesta de registro inesperada: $data');
      final id = row['v_player_id'] ?? row['player_id'] ?? row['id'];
      final universal = row['v_universal_id'] ?? row['universal_id'];
      setState(() {
        // No se ficha automáticamente: el usuario debe buscar y confirmar.
        _notice = 'Registro completado. ID: ${id ?? "no identificado"}. '
            'Código SWL: ${universal ?? "revisar respuesta"}. '
            'Para incorporarlo a un equipo utiliza Fichar pelotero.';
      });
    } catch (e) {
      if (mounted) setState(() => _notice = 'No se pudo confirmar el registro. '
          'Revisa players antes de reintentar para evitar duplicados. Detalle: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findPlayerByCode() async {
    if (_busy || _searching) return;
    final code = _searchCode.text.trim().toUpperCase();
    setState(() { _selectedPlayer = null; _notice = null; });
    if (!RegExp(r'^SWL-[A-Z0-9]+$').hasMatch(code)) {
      setState(() => _notice = 'Escribe el código SWL completo del pelotero.');
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
    if (!await _confirm('Confirmar fichaje',
        '¿Fichar a ${selected['first_name'] ?? ''} ${selected['last_name'] ?? ''} (${selected['universal_id'] ?? ''}) en el equipo seleccionado? '
        'Supabase verificará tus permisos. Refuerzo: ${_refuerzo ? "sí" : "no"}.')) return;
    if (!mounted) return;
    setState(() { _busy = true; _notice = null; });
    try {
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
          const Text('Peloteros y roster — LAB',
              style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Registrar crea la identidad del pelotero. Fichar lo incorpora a un equipo autorizado.'),
          TextField(controller: _first, maxLength: 100, decoration: const InputDecoration(labelText: 'Nombre *')),
          TextField(controller: _last, maxLength: 100, decoration: const InputDecoration(labelText: 'Apellido *')),
          TextField(controller: _jersey, decoration: const InputDecoration(labelText: 'Número de camiseta (opcional)')),
          TextField(controller: _position, decoration: const InputDecoration(labelText: 'Posición (opcional)')),
          TextField(controller: _photo, decoration: const InputDecoration(labelText: 'URL de fotografía (opcional)')),
          FilledButton.icon(onPressed: _busy ? null : _register,
              icon: const Icon(Icons.person_add_alt_1), label: const Text('Registrar pelotero en LAB')),
          const Divider(height: 28),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _teams,
            builder: (context, snapshot) {
              if (snapshot.hasError) return SelectableText('Error al leer equipos: ${snapshot.error}');
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final teams = snapshot.data!;
              return DropdownButtonFormField<String>(
                value: teams.any((t) => t['id']?.toString() == _teamId) ? _teamId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Equipo para fichaje y roster'),
                items: teams.map((t) => DropdownMenuItem<String>(
                  value: t['id'].toString(), child: Text('${t['name']} — ${t['province'] ?? ''}', overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (id) { _teamId = id; _loadRoster(); },
              );
            },
          ),
          TextField(
            controller: _searchCode,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() { _selectedPlayer = null; _notice = null; }),
            decoration: const InputDecoration(labelText: 'Código universal del pelotero (SWL-...)'),
          ),
          OutlinedButton.icon(
            onPressed: (_busy || _searching) ? null : _findPlayerByCode,
            icon: const Icon(Icons.search),
            label: Text(_searching ? 'Buscando...' : 'Buscar pelotero por código'),
          ),
          if (_selectedPlayer != null) Card(
            child: ListTile(
              leading: const Icon(Icons.person, color: Colors.amber),
              title: Text('${_selectedPlayer!['first_name'] ?? ''} ${_selectedPlayer!['last_name'] ?? ''}'),
              subtitle: Text('${_selectedPlayer!['universal_id'] ?? ''} · #${_selectedPlayer!['jersey_number'] ?? ''} · ${_selectedPlayer!['primary_position'] ?? ''}'),
            ),
          ),
          CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Es refuerzo'),
              value: _refuerzo, onChanged: _busy ? null : (v) => setState(() => _refuerzo = v ?? false)),
          FilledButton.icon(onPressed: (_busy || _searching || _selectedPlayer == null || _teamId == null) ? null : _sign,
              icon: const Icon(Icons.group_add), label: const Text('Fichar pelotero en LAB')),
          OutlinedButton.icon(onPressed: _loadRoster,
              icon: const Icon(Icons.refresh), label: const Text('Actualizar roster')),
          if (_notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: SelectableText(_notice!)),
          if (_roster != null) FutureBuilder<List<Map<String, dynamic>>>(
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
  const SplashScreen({super.key, required this.onContinue});

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
  const AuthLoginScreen({super.key});

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final String logoUrl = "https://epqyabaegmyjtwqezvbc.supabase.co/storage/v1/object/public/team-logos/logo_transparent-removebg-preview.png";

  void _openCredentialsFlow() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const FullTeamRegistrationSheet(),
    );
  }

  void _showProviderPending(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$provider todavía no está configurado. Usa correo electrónico.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Image.network(
                logoUrl,
                height: 110,
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) =>
                    const Icon(Icons.sports_baseball, color: Colors.amber, size: 60),
              ),
              const SizedBox(height: 14),
              const Text(
                "INICIA SESIÓN O REGÍSTRATE",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
              const SizedBox(height: 4),
              const Text(
                "Tu cuenta se protegerá con autenticación de Supabase",
                style: TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _btn(Icons.g_mobiledata, Colors.redAccent, "Continuar con Google",
                  () => _showProviderPending("Google")),
              const SizedBox(height: 10),
              _btn(Icons.apple, Colors.white, "Continuar con Apple",
                  () => _showProviderPending("Apple")),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.email_outlined, color: Colors.amber, size: 18),
                label: const Text(
                  "Entrar o registrarme con correo",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _openCredentialsFlow,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Modo invitado pendiente de revisión de permisos. Usa correo para esta prueba.'),
                  ));
                },
                child: const Text(
                  "Explorar como Fanático Invitado (Solo Lectura)",
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
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
  const FullTeamRegistrationSheet({super.key});

  @override
  State<FullTeamRegistrationSheet> createState() => _FullTeamRegistrationSheetState();
}

class _FullTeamRegistrationSheetState extends State<FullTeamRegistrationSheet> {
  bool isRegistering = true;
  bool isSubmitting = false;
  bool obscurePassword = true;
  String? feedbackMessage;
  bool feedbackIsError = false;
  String selectedRole = "manager";

  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final teamNameCtrl = TextEditingController();
  final provinceCtrl = TextEditingController();

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    passwordCtrl.dispose();
    teamNameCtrl.dispose();
    provinceCtrl.dispose();
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
    if (isRegistering && selectedRole == 'manager' &&
        (teamNameCtrl.text.trim().isEmpty || provinceCtrl.text.trim().isEmpty)) {
      _showMessage('Completa el nombre del equipo y la provincia.', error: true);
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
        // Cerrar el formulario: AuthTestGate escuchará la sesión y consultará profiles.
        Navigator.of(context).pop();
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
                    onPressed: isSubmitting ? null : () => Navigator.pop(context),
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
                const SizedBox(height: 14),
                const Text('Tipo de cuenta solicitado', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Soy Mánager'),
                      selected: selectedRole == 'manager',
                      selectedColor: Colors.amber,
                      onSelected: isSubmitting ? null : (v) => setState(() => selectedRole = 'manager'),
                    ),
                    ChoiceChip(
                      label: const Text('Soy Pelotero'),
                      selected: selectedRole == 'player',
                      selectedColor: Colors.amber,
                      onSelected: isSubmitting ? null : (v) => setState(() => selectedRole = 'player'),
                    ),
                  ],
                ),
                if (selectedRole == 'manager') ...[
                  const SizedBox(height: 10),
                  _field(teamNameCtrl, 'Nombre de tu equipo'),
                  const SizedBox(height: 10),
                  _field(provinceCtrl, 'Provincia o municipio'),
                ],
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

  const MainAppMasterHub({
    super.key,
    required this.userRole,
    required this.userName,
    required this.teamName,
    required this.teamProvince,
  });

  @override
  State<MainAppMasterHub> createState() => _MainAppMasterHubState();
}

class _MainAppMasterHubState extends State<MainAppMasterHub> {
  int _currentIndex = 0;

  // Estado del juego activo en vivo
  String activePin = "SWL-101";
  String activeHome = "Santiago";
  String activeAway = "La Vega";
  String activePlay = "Play Club Miramar";

  void _activateMatch(String pin, String home, String away, String play) {
    setState(() {
      activePin = pin;
      activeHome = home;
      activeAway = away;
      activePlay = play;
      _currentIndex = 1; // Salta a la pizarra de inmediato
    });
  }

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
    final List<Widget> screens = [
      MasterHomeTab(
        onPlayNowTap: () => setState(() => _currentIndex = 1),
        onGameJoined: (pin) => setState(() {
          activePin = pin;
          _currentIndex = 1;
        }),
      ),
      MasterScoreboardTab(
        userRole: widget.userRole,
        gamePin: activePin,
        homeTeam: activeHome,
        awayTeam: activeAway,
        stadium: activePlay,
      ),
      MasterScheduleTab(
        myTeamName: widget.teamName,
        onActivateMatch: _activateMatch,
      ),
      MasterTeamTab(
        userRole: widget.userRole,
        userName: widget.userName,
        teamName: widget.teamName,
        teamProvince: widget.teamProvince,
      ),
    ];

    String badge = widget.userRole == "manager" ? "MÁNAGER" : (widget.userRole == "player" ? "PELOTERO" : "FANÁTICO");

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
            Expanded(child: Text(widget.teamName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white))),
          ],
        ),
        actions: [
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
              subtitle: const Text("Crea una sala en la base de datos con un código nuevo", style: TextStyle(color: Colors.white54, fontSize: 10)),
              onTap: () {
                final randomPin = "SWL-${Random().nextInt(900) + 100}"; // Genera PIN dinámico (ej: SWL-482)
                Navigator.pop(ctx);
                widget.onGameJoined(randomPin);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.teal.shade800, content: Text("🎉 Nuevo partido creado con PIN: $randomPin")));
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
// PESTAÑA 2: PIZARRA OFICIAL EN VIVO (CONECTADA POR PIN DINÁMICO)
// =========================================================================
class MasterScoreboardTab extends StatefulWidget {
  final String userRole;
  final String gamePin;
  final String homeTeam;
  final String awayTeam;
  final String stadium;

  const MasterScoreboardTab({
    super.key,
    required this.userRole,
    required this.gamePin,
    required this.homeTeam,
    required this.awayTeam,
    required this.stadium,
  });

  @override
  State<MasterScoreboardTab> createState() => _MasterScoreboardTabState();
}

class _MasterScoreboardTabState extends State<MasterScoreboardTab> {
  int inning = 1;
  bool isTop = true;

  int visRuns = 0; int homRuns = 0;
  int visHits = 0; int homHits = 0;

  int balls = 0; int strikes = 0; int outs = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("⚾ SALA EN VIVO: ${widget.gamePin}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.amber)),
            Text("${widget.awayTeam} vs ${widget.homeTeam}", style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // Marcador
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      Text(widget.awayTeam, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                      Text("$visRuns", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    ]),
                    Text("${inning}ra ${isTop ? 'ALTA' : 'BAJA'}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                    Column(children: [
                      Text(widget.homeTeam, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                      Text("$homRuns", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                    ]),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // B-S-O
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text("B: $balls", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    Text("S: $strikes", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    Text("O: $outs", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Botones de anotar
              Row(
                children: [
                  Expanded(child: _btn("BOLA", const Color(0xFF10B981), () => setState(() => balls = (balls + 1) % 4))),
                  const SizedBox(width: 6),
                  Expanded(child: _btn("STRIKE", const Color(0xFFEF4444), () => setState(() => strikes = (strikes + 1) % 3))),
                  const SizedBox(width: 6),
                  Expanded(child: _btn("OUT", const Color(0xFFF59E0B), () => setState(() => outs = (outs + 1) % 3))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _btn("HIT (+1 C)", const Color(0xFF223040), () => setState(() {
                    if (isTop) visRuns++; else homRuns++;
                  }))),
                  const SizedBox(width: 6),
                  Expanded(child: _btn("CAMBIAR ENTRADA", const Color(0xFF2563EB), () => setState(() {
                    if (isTop) { isTop = false; } else { isTop = true; inning++; }
                    balls = 0; strikes = 0; outs = 0;
                  }))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(String l, Color c, VoidCallback f) => ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    onPressed: f,
    child: Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
  );
}

// =========================================================================
// PESTAÑA 3: AGENDA & RETOS (CONECTADA CON EQUIPOS REALES DE SUPABASE)
// =========================================================================
class MasterScheduleTab extends StatefulWidget {
  final String myTeamName;
  final Function(String pin, String home, String away, String play) onActivateMatch;

  const MasterScheduleTab({super.key, required this.myTeamName, required this.onActivateMatch});

  @override
  State<MasterScheduleTab> createState() => _MasterScheduleTabState();
}

class _MasterScheduleTabState extends State<MasterScheduleTab> {
  DateTime selectedDate = DateTime(2026, 11, 14); // Sábado
  TimeOfDay selectedTime = const TimeOfDay(hour: 19, minute: 45); // 7:45 PM
  List<Map<String, String>> matches = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: const Text("📅 AGENDA & RETOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            icon: const Icon(Icons.add, color: Colors.black, size: 16),
            label: const Text("RETAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
            onPressed: () {
              // Dialogo de retar
              final rivalCtrl = TextEditingController();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF16202C),
                  title: const Text("Retar a un Equipo", style: TextStyle(color: Colors.amber, fontSize: 15)),
                  content: TextField(
                    controller: rivalCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(labelText: "Nombre del Equipo Rival"),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                      onPressed: () {
                        if (rivalCtrl.text.isNotEmpty) {
                          final pin = "SWL-${Random().nextInt(900) + 100}";
                          setState(() {
                            matches.add({
                              "date": "Sábado · 7:45 PM",
                              "home": rivalCtrl.text.trim(),
                              "away": widget.myTeamName,
                              "play": "Play Club Miramar",
                              "pin": pin,
                            });
                          });
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text("RETAR", style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: matches.isEmpty
          ? const Center(child: Text("No hay partidos agendados aún.\nToca '+ RETAR' para programar el primero.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: matches.length,
              itemBuilder: (ctx, i) {
                final m = matches[i];
                return Container(
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
                          Text("PIN: ${m["pin"]!}", style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("${m["away"]!} vs ${m["home"]!}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
                          icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                          label: const Text("🟢 ACTIVAR Y COMENZAR PARTIDO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          onPressed: () => widget.onActivateMatch(m["pin"]!, m["home"]!, m["away"]!, m["play"]!),
                        ),
                      ),
                    ],
                  ),
                );
              },
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

  const MasterTeamTab({super.key, required this.userRole, required this.userName,
    required this.teamName, required this.teamProvince});

  @override
  State<MasterTeamTab> createState() => _MasterTeamTabState();
}

class _MasterTeamTabState extends State<MasterTeamTab> {
  late Future<List<Map<String, dynamic>>> _teams;
  Future<List<Map<String, dynamic>>>? _roster;
  String? _selectedTeamId;
  String? _selectedTeamName;
  String? _selectedProvince;

  @override
  void initState() {
    super.initState();
    _teams = _fetchTeams();
  }

  Future<List<Map<String, dynamic>>> _fetchTeams() async {
    final rows = await Supabase.instance.client.from('teams')
        .select('id, name, province').order('name');
    return List<Map<String, dynamic>>.from(rows);
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
    });
  }

  void _refreshRoster() {
    final id = _selectedTeamId;
    if (id != null) setState(() => _roster = _fetchRoster(id));
  }

  Future<void> _openLabActions() async {
    // El panel existente conserva sus confirmaciones y validaciones RPC.
    // El usuario debe seleccionar el equipo también dentro del panel.
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFF080D14),
        appBar: AppBar(title: const Text('Registrar y fichar — LAB'),
          backgroundColor: const Color(0xFF0F1722)),
        body: const SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(12), child: SwlPlayersLabPanel())),
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
        title: Text(widget.teamName,
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
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _teams,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('No se pudieron consultar equipos: ${snapshot.error}',
                style: const TextStyle(color: Colors.orangeAccent));
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final teams = snapshot.data!;
              return DropdownButtonFormField<String>(
                value: teams.any((t) => t['id']?.toString() == _selectedTeamId)
                  ? _selectedTeamId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Selecciona el equipo real de Supabase LAB'),
                items: teams.map((t) => DropdownMenuItem<String>(
                  value: t['id'].toString(),
                  child: Text('${t['name']} — ${t['province'] ?? ''}',
                    overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (id) {
                  for (final team in teams) {
                    if (team['id']?.toString() == id) { _selectTeam(team); break; }
                  }
                },
              );
            },
          ),
          const SizedBox(height: 10),
          const Text('El roster muestra datos reales de LAB. Para registrar o fichar, '
            'selecciona el equipo nuevamente en el formulario de operaciones.',
            style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: _openLabActions,
            icon: const Icon(Icons.person_add, color: Colors.black),
            label: const Text('INSCRIBIR / FICHAR EN LAB',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          const Text('ROSTER REAL · SOLO LECTURA EN ESTA PANTALLA',
            style: TextStyle(color: Colors.white54, fontSize: 10)),
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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFF121B27),
                          borderRadius: BorderRadius.circular(8)),
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
                        ]),
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
