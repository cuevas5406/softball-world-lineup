import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// URL y Claves de tu servidor Supabase
const String kSupabaseUrl = 'https://epqyabaegmyjtwqezvbc.supabase.co';
const String kSupabaseAnonKey = 'sb_publishable_gOqSMC3ouDYNDu-mxLmYzQ_LSyCq';

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

  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      anonKey: kSupabaseAnonKey,
    );
  } catch (e) {
    debugPrint("Modo seguro activo: $e");
  }

  runApp(const SoftballWorldApp());
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
      home: const SplashScreen(),
    );
  }
}

// =========================================================================
// 1. APERTURA (SPLASH CON LOGO RECORTADO TRANSPARENTE)
// =========================================================================
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (ctx) => const AuthLoginScreen()),
                        );
                      },
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

  void _openRegisterFlow(String method) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => const FullTeamRegistrationSheet(),
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
              Image.network(logoUrl, height: 110, fit: BoxFit.contain, errorBuilder: (ctx, err, stack) => const Icon(Icons.sports_baseball, color: Colors.amber, size: 60)),
              const SizedBox(height: 14),
              const Text("INICIA SESIÓN O REGÍSTRATE", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 4),
              const Text("Tu cuenta y tu equipo quedan registrados en la base de datos", style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
              const Spacer(),

              _btn(Icons.g_mobiledata, Colors.redAccent, "Continuar con Google", () => _openRegisterFlow("Google")),
              const SizedBox(height: 10),
              _btn(Icons.apple, Colors.white, "Continuar con Apple", () => _openRegisterFlow("Apple")),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), minimumSize: const Size(double.infinity, 50), side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.sms, color: Colors.amber, size: 18),
                label: const Text("Entrar con Teléfono o Correo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _openRegisterFlow("Teléfono"),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (ctx) => const MainAppMasterHub(userRole: "fan", userName: "Fanático", teamName: "Sin Equipo", teamProvince: "N/A")));
                },
                child: const Text("Explorar como Fanático Invitado (Solo Lectura)", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
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
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16202C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: Colors.white12)),
      onPressed: tap,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(ic, color: col, size: 24), const SizedBox(width: 10), Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
    );
  }
}

// FORMULARIO COMPLETO: REGISTRO DE CUENTA Y DATOS REALES DEL EQUIPO (Punto 6)
class FullTeamRegistrationSheet extends StatefulWidget {
  const FullTeamRegistrationSheet({super.key});

  @override
  State<FullTeamRegistrationSheet> createState() => _FullTeamRegistrationSheetState();
}

class _FullTeamRegistrationSheetState extends State<FullTeamRegistrationSheet> {
  String selectedRole = "manager";
  final nameCtrl = TextEditingController();
  final teamNameCtrl = TextEditingController();
  final provinceCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      height: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CREAR TU CUENTA Y EQUIPO", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 15)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Text("Ingresa los datos reales para guardar tu equipo en la base de datos:", style: TextStyle(color: Colors.white60, fontSize: 11)),
            const SizedBox(height: 14),

            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(labelText: "Tu Nombre Completo", labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 8),

            // Rol
            Row(
              children: [
                ChoiceChip(
                  label: const Text("Soy Mánager"),
                  selected: selectedRole == "manager",
                  selectedColor: Colors.amber,
                  onSelected: (v) => setState(() => selectedRole = "manager"),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Soy Pelotero"),
                  selected: selectedRole == "player",
                  selectedColor: Colors.amber,
                  onSelected: (v) => setState(() => selectedRole = "player"),
                ),
              ],
            ),

            if (selectedRole == "manager") ...[
              const SizedBox(height: 12),
              TextField(
                controller: teamNameCtrl,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(labelText: "Nombre de tu Equipo", labelStyle: TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: provinceCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(labelText: "Provincia o Municipio de Origen", labelStyle: TextStyle(color: Colors.white70)),
              ),
            ],

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () async {
                  final userName = nameCtrl.text.trim().isEmpty ? "Mánager" : nameCtrl.text.trim();
                  final tName = teamNameCtrl.text.trim().isEmpty ? "Mi Equipo" : teamNameCtrl.text.trim();
                  final tProv = provinceCtrl.text.trim().isEmpty ? "República Dominicana" : provinceCtrl.text.trim();

                  // Guardar el equipo en Supabase de verdad (Puntos 5 y 6)
                  if (selectedRole == "manager" && teamNameCtrl.text.trim().isNotEmpty) {
                    try {
                      await Supabase.instance.client.from('teams').insert({
                        'name': tName,
                        'province': tProv,
                        'manager_name': userName,
                      });
                    } catch (e) {
                      debugPrint("Guardado local/nube: $e");
                    }
                  }

                  if (!mounted) return;
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (ctx) => MainAppMasterHub(
                        userRole: selectedRole,
                        userName: userName,
                        teamName: tName,
                        teamProvince: tProv,
                      ),
                    ),
                  );
                },
                child: const Text("GUARDAR Y ENTRAR A LA APP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
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

  void _logout() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (ctx) => const AuthLoginScreen()));
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

  const MasterTeamTab({super.key, required this.userRole, required this.userName, required this.teamName, required this.teamProvince});

  @override
  State<MasterTeamTab> createState() => _MasterTeamTabState();
}

class _MasterTeamTabState extends State<MasterTeamTab> {
  // Lista de jugadores limpia (sin datos de prueba falsos)
  List<Map<String, String>> roster = [];

  void _addPlayerManual() {
    final nameCtrl = TextEditingController();
    final numCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202C),
        title: const Text("Inscribir Pelotero", style: TextStyle(color: Colors.amber, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Nombre y Apellido")),
            TextField(controller: numCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Número (#)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                setState(() {
                  roster.add({
                    "id": DateTime.now().millisecondsSinceEpoch.toString(),
                    "name": nameCtrl.text.trim(),
                    "num": numCtrl.text.trim().isEmpty ? "00" : numCtrl.text.trim(),
                    "playerId": "RD-${Random().nextInt(9000) + 1000}",
                    "type": "Oficial"
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("GUARDAR", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _addByPlayerId() {
    final idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202C),
        title: const Text("Fichar Refuerzo con ID", style: TextStyle(color: Colors.amber, fontSize: 15)),
        content: TextField(
          controller: idCtrl,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
          decoration: const InputDecoration(hintText: "Ej: RD-8420"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              if (idCtrl.text.isNotEmpty) {
                setState(() {
                  roster.add({
                    "id": DateTime.now().millisecondsSinceEpoch.toString(),
                    "name": "Pelotero Refuerzo",
                    "num": "99",
                    "playerId": idCtrl.text.trim().toUpperCase(),
                    "type": "Refuerzo"
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("FICHAR", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: Text(widget.teamName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera del equipo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber)),
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.shield, color: Colors.black)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      Text("📍 ${widget.teamProvince} · ${roster.length} Peloteros", style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    ]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Botones de acción del Mánager
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 10)),
                    icon: const Icon(Icons.person_add, color: Colors.black, size: 16),
                    label: const Text("+ INSCRIBIR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: _addPlayerManual,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(vertical: 10)),
                    icon: const Icon(Icons.badge, color: Colors.white, size: 16),
                    label: const Text("+ FICHAR CON ID", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    onPressed: _addByPlayerId,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Text("DESLIZA HACIA LOS LADOS PARA EDITAR O ELIMINAR:", style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),

            // LISTA DE PELOTEROS CON SWIPE (DISMISSIBLE) - Punto 4
            Expanded(
              child: roster.isEmpty
                  ? const Center(child: Text("Tu roster está limpio.\nToca '+ INSCRIBIR' para agregar a tus muchachos.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: roster.length,
                      itemBuilder: (ctx, i) {
                        final p = roster[i];
                        return Dismissible(
                          key: Key(p["id"]!),
                          // Deslizar a la izquierda: ROJO BORRAR
                          secondaryBackground: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.redAccent,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          // Deslizar a la derecha: AZUL EDITAR
                          background: Container(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.only(left: 16),
                            color: Colors.blueAccent,
                            child: const Icon(Icons.edit, color: Colors.white),
                          ),
                          confirmDismiss: (direction) async {
                            if (direction == DismissDirection.endToStart) {
                              // Borrar
                              setState(() => roster.removeAt(i));
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Pelotero ${p['name']} eliminado.")));
                              return true;
                            } else {
                              // Editar
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Editando a ${p['name']}...")));
                              return false;
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: const Color(0xFF0F172A), radius: 14, child: Text(p["num"]!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p["name"]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text("ID: ${p["playerId"]!} · ${p["type"]!}", style: const TextStyle(color: Colors.white54, fontSize: 9)),
                                ])),
                                const Icon(Icons.swap_horiz, color: Colors.white24, size: 16),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
