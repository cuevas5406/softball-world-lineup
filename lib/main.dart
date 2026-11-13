
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

  // Solo lectura: no crea perfiles ni asigna permisos.
  void _prepareProfileLookup(
    Session? session, {
    bool force = false,
  }) {
    final id = session?.user.id;

    if (id == null) {
      _profileUserId = null;
      _profileLookup = null;
      return;
    }

    if (force ||
        _profileUserId != id ||
        _profileLookup == null) {
      _profileUserId = id;

      _profileLookup = Supabase.instance.client
          .from('profiles')
          .select('id, full_name, email, player_id')
          .eq('id', id)
          .maybeSingle();
    }
  }

  void _refreshProfile() {
    setState(() {
      _prepareProfileLookup(_session, force: true);
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
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No se pudo iniciar Supabase. '
              'Comprueba la conexión y reinicia la aplicación.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final user = _session?.user;

    if (user != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Verificación de perfil — LAB'),
        ),
        body: SafeArea(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _profileLookup,
            builder: (context, snapshot) {
              Widget message;

              if (snapshot.connectionState !=
                  ConnectionState.done) {
                message = const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Colors.amber,
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Consultando tu perfil en Supabase LAB...',
                    ),
                  ],
                );
              } else if (snapshot.hasError) {
                message = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.amber,
                      size: 54,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No se pudo consultar tu perfil.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Revisa la conexión, los permisos SELECT '
                      'de profiles y que el usuario esté autenticado.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      'Detalle técnico: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              } else if (snapshot.data == null) {
                message = const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      color: Colors.amber,
                      size: 54,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Tu sesión está activa, pero aún no '
                      'existe un perfil vinculado.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'No se ha creado un perfil ni asignado '
                      'permisos automáticamente. La recuperación '
                      'segura queda pendiente.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              } else {
                final profile = snapshot.data!;

                message = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: Colors.amber,
                      size: 54,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Perfil encontrado en LAB',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (profile['full_name'] as String?)
                                  ?.isNotEmpty ==
                              true
                          ? profile['full_name'] as String
                          : 'Usuario autenticado',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'El acceso al Hub requiere verificar '
                      'por separado roles y permisos de equipos. '
                      'No se conceden automáticamente.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }

              return Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        message,
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: _refreshProfile,
                          icon: const Icon(Icons.refresh),
                          label: const Text(
                            'Volver a consultar perfil',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: () async {
                            try {
                              await Supabase.instance.client.auth
                                  .signOut();
                            } catch (error) {
                              if (!context.mounted) return;

                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'No se pudo cerrar sesión.',
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar sesión'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    if (!_showLogin) {
      return SplashScreen(
        onContinue: () {
          setState(() => _showLogin = true);
        },
      );
    }

    return const AuthLoginScreen();
  }
}
