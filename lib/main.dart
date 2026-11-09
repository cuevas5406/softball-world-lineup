import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// FUNCIÓN OFICIAL PARA ABRIR WHATSAPP DIRECTO EN ANDROID
Future<void> sendToWhatsApp(String message) async {
  final Uri url = Uri.parse("https://api.whatsapp.com/send?text=${Uri.encodeComponent(message)}");
  try {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint("Error abriendo WhatsApp: $e");
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://epqyabaegmyjtwqezvbc.supabase.co',
      anonKey: 'sb_publishable_gOqSMC3ouDYNDu-mxLmYzQ_LSyCq',
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

// -------------------------------------------------------------------------
// 1. SPLASH: PANTALLA DE APERTURA CON LOGO OFICIAL
// -------------------------------------------------------------------------
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
                  const Text("República Dominicana · Santo Domingo · Cibao", style: TextStyle(color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 2. INICIO DE SESIÓN / REGISTRO REAL CON ELECCIÓN DE ROL
// -------------------------------------------------------------------------
class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({super.key});

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final String logoUrl = "https://epqyabaegmyjtwqezvbc.supabase.co/storage/v1/object/public/team-logos/logo_transparent-removebg-preview.png";

  void _selectRoleAndProceed(String method) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => OnboardingRoleSheet(method: method),
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
              const Text("Elige cómo deseas entrar para configurar tus accesos:", style: TextStyle(color: Colors.white60, fontSize: 12), textAlign: TextAlign.center),
              const Spacer(),

              _socialBtn(icon: Icons.g_mobiledata, iconColor: Colors.redAccent, text: "Continuar con Google", onTap: () => _selectRoleAndProceed("Google")),
              const SizedBox(height: 10),
              _socialBtn(icon: Icons.apple, iconColor: Colors.white, text: "Continuar con Apple", onTap: () => _selectRoleAndProceed("Apple")),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), minimumSize: const Size(double.infinity, 50), side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.sms, color: Colors.amber, size: 18),
                label: const Text("Entrar con Teléfono o Correo", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () => _selectRoleAndProceed("Teléfono"),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Entra como fanático directo
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (ctx) => const MainAppMasterHub(userRole: "fan", userName: "Fanático Invitado")),
                  );
                },
                child: const Text("Explorar como Fanático Invitado (Sin Cuenta)", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12, decoration: TextDecoration.underline)),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialBtn({required IconData icon, required Color iconColor, required String text, required VoidCallback onTap}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16202C), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: const BorderSide(color: Colors.white12)),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 10),
          Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// SELECCIÓN DE ROL (DEFINE LO QUE PUEDE HACER CADA USUARIO)
// -------------------------------------------------------------------------
class OnboardingRoleSheet extends StatefulWidget {
  final String method;
  const OnboardingRoleSheet({super.key, required this.method});

  @override
  State<OnboardingRoleSheet> createState() => _OnboardingRoleSheetState();
}

class _OnboardingRoleSheetState extends State<OnboardingRoleSheet> {
  String selectedRole = "manager"; // 'manager', 'player', 'fan'
  final nameCtrl = TextEditingController(text: "Mánager");

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      height: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("CONFIGURAR TU PERFIL", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 15)),
              IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const Text("Indica tu función para darte los permisos correctos:", style: TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 12),

          TextField(
            controller: nameCtrl,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            decoration: const InputDecoration(
              labelText: "Tu Nombre Completo",
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
            ),
          ),

          const SizedBox(height: 16),

          _roleOption("manager", "Soy Mánager / Dirigente", "Crear mi equipo, inscribir roster, armar lineup y agendar retos.", Icons.shield),
          const SizedBox(height: 8),
          _roleOption("player", "Soy Pelotero / Jugador", "Ver mi promedio, mi carnet con ID y compartir cromito.", Icons.sports_baseball),
          const SizedBox(height: 8),
          _roleOption("fan", "Soy Fanático", "Solo ver juegos en vivo y seguir el torneo.", Icons.favorite),

          const Spacer(),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                final user = nameCtrl.text.trim().isEmpty ? "Usuario" : nameCtrl.text.trim();
                Navigator.pop(context);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (ctx) => MainAppMasterHub(userRole: selectedRole, userName: user)),
                );
              },
              child: const Text("GUARDAR Y ENTRAR A LA APP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleOption(String id, String title, String subtitle, IconData icon) {
    final isSelected = selectedRole == id;
    return InkWell(
      onTap: () => setState(() => selectedRole = id),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withAlpha(25) : const Color(0xFF0B1118),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.amber : Colors.white12, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.amber : Colors.white70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// 3. HUB PRINCIPAL (CON BOTÓN DE SALIR Y CONTROL DE ROLES)
// -------------------------------------------------------------------------
class MainAppMasterHub extends StatefulWidget {
  final String userRole; // 'manager', 'player', 'fan'
  final String userName;
  const MainAppMasterHub({super.key, this.userRole = "manager", this.userName = "Mánager"});

  @override
  State<MainAppMasterHub> createState() => _MainAppMasterHubState();
}

class _MainAppMasterHubState extends State<MainAppMasterHub> {
  int _currentIndex = 0;

  // CERRAR SESIÓN / SALIR DE TODO
  void _logout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202C),
        title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.amber, fontSize: 16)),
        content: const Text("¿Deseas salir de tu cuenta y volver a la pantalla de inicio?", style: TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (ctx) => const AuthLoginScreen()));
            },
            child: const Text("SALIR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      MasterHomeTab(
        onPlayNowTap: () => setState(() => _currentIndex = 1), // ¡A JUGAR AHORA! manda a la Pizarra
      ),
      const MasterScoreboardTab(),
      const MasterScheduleTab(),
      MasterTeamTab(userRole: widget.userRole, userName: widget.userName),
    ];

    String roleBadge = "MÁNAGER";
    if (widget.userRole == "player") roleBadge = "PELOTERO";
    if (widget.userRole == "fan") roleBadge = "FANÁTICO";

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
              child: Text(roleBadge, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 9)),
            ),
            const SizedBox(width: 8),
            Text(widget.userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
          ],
        ),
        actions: [
          // BOTÓN DE SALIR / CERRAR SESIÓN
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
            tooltip: "Cerrar Sesión",
            onPressed: _logout,
          ),
          const SizedBox(width: 6),
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

// -------------------------------------------------------------------------
// PESTAÑA 1: INICIO (CON BOTÓN ¡A JUGAR AHORA! CONECTADO)
// -------------------------------------------------------------------------
class MasterHomeTab extends StatefulWidget {
  final VoidCallback onPlayNowTap;
  const MasterHomeTab({super.key, required this.onPlayNowTap});

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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 10),
          // BANNERS ALEX MONO, CREDIGO, DYNASTY
          SizedBox(
            height: 120,
            child: PageView(
              controller: _bannerController,
              onPageChanged: (i) => setState(() => _currentBanner = i),
              children: [
                _bannerCard("PRESTAMOS ALEX MONO", "Las mejores condiciones de pago", const Color(0xFF2563EB), Colors.black, "🐵"),
                _bannerCard("CrediGo", "Celulares a crédito sin papeleo en RD", const Color(0xFF0FA0EA), Colors.white, "📱", isDark: true),
                _bannerCard("DYNASTY", "Nuts & Fruit Lovers · El snack del play", const Color(0xFFDC2626), const Color(0xFFFFFBEB), "👑", isDark: true),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // BOTÓN ¡A JUGAR AHORA! (AHORA SÍ FUNCIONA Y TE MANDA A LA PIZARRA)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              onTap: widget.onPlayNowTap, // Salta directo a la Pizarra
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
                          Text("Toca aquí para abrir la pizarra y anotar", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.black, size: 18),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // LÍDER NACIONAL VIRAL
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF121B27),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundImage: NetworkImage("https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80"),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Juan Pérez #14", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        Text("Plataneros de La Vega · ID: RD-8420", style: TextStyle(color: Colors.white60, fontSize: 10)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      Text(".615", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 20)),
                      Text("LÍDER NACIONAL", style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerCard(String t, String s, Color c, Color bg, String ico, {bool isDark = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c, width: 1.5)),
      child: Row(
        children: [
          Text(ico, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t, style: TextStyle(color: isDark ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                Text(s, style: TextStyle(color: isDark ? Colors.black54 : Colors.white70, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// PESTAÑA 2: PIZARRA OFICIAL EN VIVO (CON CONTROLES Y BOX SCORE)
// -------------------------------------------------------------------------
class MasterScoreboardTab extends StatefulWidget {
  const MasterScoreboardTab({super.key});

  @override
  State<MasterScoreboardTab> createState() => _MasterScoreboardTabState();
}

class _MasterScoreboardTabState extends State<MasterScoreboardTab> {
  String visitor = "La Vega";
  String home = "Santiago";
  int inning = 6;
  bool isTop = false;

  List<int?> visInnings = [0, 2, 1, 0, 1, 0];
  List<int?> homInnings = [1, 0, 3, 0, 2, null];

  int visRuns = 4; int homRuns = 6;
  int visHits = 6; int homHits = 8;
  int visErr = 2; int homErr = 1;

  int balls = 1; int strikes = 2; int outs = 2;
  bool on1B = true; bool on2B = false; bool on3B = false;

  void _finishGameAndGoToBoxScore() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => MasterBoxScoreScreen(
          visitor: visitor, home: home, visRuns: visRuns, homRuns: homRuns,
          visHits: visHits, homHits: homHits, visErr: visErr, homErr: homErr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1722),
        title: const Text("⚾ PIZARRA EN VIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
            onPressed: _finishGameAndGoToBoxScore,
            child: const Text("FINALIZAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10)),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.8),
                  1: FlexColumnWidth(1), 2: FlexColumnWidth(1), 3: FlexColumnWidth(1),
                  4: FlexColumnWidth(1), 5: FlexColumnWidth(1), 6: FlexColumnWidth(1),
                  7: FlexColumnWidth(1.2), 8: FlexColumnWidth(1.2), 9: FlexColumnWidth(1.2),
                },
                children: [
                  TableRow(children: [
                    const Text("EQUIPO", style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    ...List.generate(6, (i) => Center(child: Text("${i + 1}", style: TextStyle(color: inning == i + 1 ? Colors.amber : Colors.white60, fontSize: 10)))),
                    const Center(child: Text("C", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11))),
                    const Center(child: Text("H", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                    const Center(child: Text("E", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11))),
                  ]),
                  TableRow(children: [
                    Text(visitor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ...visInnings.map((r) => Center(child: Text(r != null ? "$r" : "-", style: const TextStyle(color: Colors.white70, fontSize: 11)))),
                    Center(child: Text("$visRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 12))),
                    Center(child: Text("$visHits", style: const TextStyle(color: Colors.white, fontSize: 11))),
                    Center(child: Text("$visErr", style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
                  ]),
                  TableRow(children: [
                    Text(home, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ...homInnings.map((r) => Center(child: Text(r != null ? "$r" : "-", style: const TextStyle(color: Colors.white70, fontSize: 11)))),
                    Center(child: Text("$homRuns", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, fontSize: 12))),
                    Center(child: Text("$homHits", style: const TextStyle(color: Colors.white, fontSize: 11))),
                    Center(child: Text("$homErr", style: const TextStyle(color: Colors.orangeAccent, fontSize: 11))),
                  ]),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Text("B: $balls", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 10),
                    Text("S: $strikes", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 10),
                    Text("O: $outs", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                  Text("${inning}ra ${isTop ? 'ALTA' : 'BAJA'}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(child: _btn("BOLA", const Color(0xFF10B981), () => setState(() => balls = (balls + 1) % 4))),
                  const SizedBox(width: 6),
                  Expanded(child: _btn("STRIKE", const Color(0xFFEF4444), () => setState(() => strikes = (strikes + 1) % 3))),
                  const SizedBox(width: 6),
                  Expanded(child: _btn("HIT (+1 C)", const Color(0xFF223040), () => setState(() => homRuns++))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String l, Color c, VoidCallback f) => ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    onPressed: f,
    child: Text(l, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

// BOX SCORE CON BOTÓN QUE ABRE WHATSAPP
class MasterBoxScoreScreen extends StatelessWidget {
  final String visitor; final String home; final int visRuns; final int homRuns;
  final int visHits; final int homHits; final int visErr; final int homErr;
  const MasterBoxScoreScreen({super.key, required this.visitor, required this.home, required this.visRuns, required this.homRuns, required this.visHits, required this.homHits, required this.visErr, required this.homErr});

  @override
  Widget build(BuildContext context) {
    final bool visWon = visRuns > homRuns;
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(backgroundColor: const Color(0xFF0F1722), title: const Text("BOX SCORE OFICIAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  const Text("FINAL DEL JUEGO", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    Column(children: [Text(visitor, style: const TextStyle(color: Colors.white70, fontSize: 15)), Text("$visRuns", style: TextStyle(color: visWon ? Colors.greenAccent : Colors.white, fontSize: 36, fontWeight: FontWeight.w900))]),
                    const Text("VS", style: TextStyle(color: Colors.white24, fontSize: 14)),
                    Column(children: [Text(home, style: const TextStyle(color: Colors.white70, fontSize: 15)), Text("$homRuns", style: TextStyle(color: !visWon ? Colors.greenAccent : Colors.white, fontSize: 36, fontWeight: FontWeight.w900))]),
                  ]),
                  const Divider(color: Colors.white24, height: 20),
                  Text("Ganador Oficial: ${visWon ? visitor : home}", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.share, color: Colors.white),
                label: const Text("COMPARTIR RESUMEN POR WHATSAPP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  sendToWhatsApp(
                    "⚾ ¡FINAL DEL JUEGO! - Softball World Lineup ⚾\n\n"
                    "🏆 Ganador: ${visWon ? visitor : home}\n"
                    "• $visitor: $visRuns Carreras | $visHits Hits\n"
                    "• $home: $homRuns Carreras | $homHits Hits\n\n"
                    "Sigue el torneo en vivo en Softball World Lineup.",
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

// -------------------------------------------------------------------------
// PESTAÑA 3: AGENDA Y RETOS (CALENDARIO DE DÍAS Y RELOJ MANUAL)
// -------------------------------------------------------------------------
class MasterScheduleTab extends StatefulWidget {
  const MasterScheduleTab({super.key});

  @override
  State<MasterScheduleTab> createState() => _MasterScheduleTabState();
}

class _MasterScheduleTabState extends State<MasterScheduleTab> {
  DateTime selectedDate = DateTime(2026, 11, 14); // Sábado
  TimeOfDay selectedTime = const TimeOfDay(hour: 19, minute: 45); // 7:45 PM

  List<Map<String, String>> matches = [
    {
      "date": "Sábado 14 de Noviembre · 7:45 PM (Noche 💡)",
      "matchup": "Plataneros de La Vega vs Metros de Santiago",
      "play": "Play Club Miramar (SD) · PIN: PLAY-742",
      "status": "CONFIRMADO ✅"
    },
    {
      "date": "Miércoles 18 de Noviembre · 8:15 PM (Noche 💡)",
      "matchup": "Titanes de Moca vs Plataneros de La Vega",
      "play": "Play de Villa Rosa (La Vega) · PIN: PLAY-810",
      "status": "CONFIRMADO ✅"
    },
  ];

  void _openScheduleDialog() {
    String rival = "Metros de Santiago";
    String stadium = "Play Club Miramar (SD)";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16202C),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final hour = selectedTime.hourOfPeriod == 0 ? 12 : selectedTime.hourOfPeriod;
            final minute = selectedTime.minute.toString().padLeft(2, '0');
            final period = selectedTime.period == DayPeriod.am ? "AM" : "PM";
            final formattedTime = "$hour:$minute $period";

            return Container(
              padding: const EdgeInsets.all(20),
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("📅 PROGRAMAR NUEVO RETO", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Text("Elige el día, pon la hora en el reloj y elige el play:", style: TextStyle(color: Colors.white60, fontSize: 11)),
                  const SizedBox(height: 14),

                  // RELOJ MANUAL INTERACTIVO
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: selectedTime);
                      if (picked != null) setModalState(() => selectedTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFF0B1118), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.access_time, color: Colors.amber, size: 24),
                              const SizedBox(width: 10),
                              Text("Hora: $formattedTime", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(6)),
                            child: const Text("CAMBIAR HORA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  DropdownButtonFormField<String>(
                    value: rival,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                    decoration: const InputDecoration(labelText: "Equipo Rival", labelStyle: TextStyle(color: Colors.white70)),
                    items: ["Metros de Santiago", "Titanes de Moca", "Cacaoteros de SFM", "Guerreros de Los Prados"].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setModalState(() => rival = v!),
                  ),

                  const SizedBox(height: 10),

                  DropdownButtonFormField<String>(
                    value: stadium,
                    dropdownColor: const Color(0xFF0F172A),
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                    decoration: const InputDecoration(labelText: "Play / Estadio", labelStyle: TextStyle(color: Colors.white70)),
                    items: ["Play Club Miramar (SD)", "Play de Villa Rosa (La Vega)", "Play Chiquito (Santiago)"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setModalState(() => stadium = v!),
                  ),

                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      icon: const Icon(Icons.send, color: Colors.black),
                      label: Text("AGENDAR JUEGO A LAS $formattedTime", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          matches.insert(0, {
                            "date": "Sábado · $formattedTime",
                            "matchup": "Tu Equipo vs $rival",
                            "play": "$stadium · PIN: PLAY-${100 + matches.length}",
                            "status": "RETO ENVIADO ⏳"
                          });
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.teal, content: Text("⚾ ¡Reto agendado con éxito!")));
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

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
            onPressed: _openScheduleDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(14),
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
                    Text(m["status"]!, style: const TextStyle(color: Colors.tealAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(m["matchup"]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                Text(m["play"]!, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------------
// PESTAÑA 4: MI EQUIPO (CON GESTIÓN REAL PARA MÁNAGERS Y CARNET PARA PELOTEROS)
// -------------------------------------------------------------------------
class MasterTeamTab extends StatefulWidget {
  final String userRole; // 'manager', 'player', 'fan'
  final String userName;
  const MasterTeamTab({super.key, required this.userRole, required this.userName});

  @override
  State<MasterTeamTab> createState() => _MasterTeamTabState();
}

class _MasterTeamTabState extends State<MasterTeamTab> {
  String teamName = "Los Plataneros de La Vega";
  String province = "La Vega";
  bool pitcherHits = false;
  int batters = 10;

  List<Map<String, String>> roster = [
    {"name": "Juan Pérez", "num": "14", "pos": "CF (8)", "id": "RD-8420", "type": "Oficial"},
    {"name": "Manny Cabrera", "num": "24", "pos": "SS (6)", "id": "RD-2041", "type": "Oficial"},
    {"name": "David Ortiz", "num": "34", "pos": "1B (3)", "id": "RD-3400", "type": "Oficial"},
    {"name": "Teóscar Hernández", "num": "37", "pos": "LF (7)", "id": "RD-5090", "type": "Refuerzo"},
  ];

  // AGREGAR POR ID
  void _openAddByIdDialog() {
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
          decoration: const InputDecoration(hintText: "Ej: RD-9901", hintStyle: TextStyle(color: Colors.white30)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              if (idCtrl.text.isNotEmpty) {
                setState(() {
                  roster.add({"name": "Refuerzo Fichado", "num": "99", "pos": "EP", "id": idCtrl.text.trim().toUpperCase(), "type": "Refuerzo"});
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.teal, content: Text("✅ Pelotero agregado al roster por su ID.")));
              }
            },
            child: const Text("FICHAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // AGREGAR JUGADOR NUEVO MANUAL
  void _openAddManualPlayerDialog() {
    final nameCtrl = TextEditingController();
    final numCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16202C),
        title: const Text("Agregar Pelotero al Roster", style: TextStyle(color: Colors.amber, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Nombre")),
            TextField(controller: numCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Número")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () {
              if (nameCtrl.text.isNotEmpty) {
                setState(() {
                  roster.add({"name": nameCtrl.text.trim(), "num": numCtrl.text.trim(), "pos": "EP", "id": "RD-${1000 + roster.length}", "type": "Oficial"});
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("GUARDAR", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // VISTA DEL PELOTERO (SU CARNET PERSONAL)
    if (widget.userRole == "player") {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.amber, width: 2)),
              child: Column(
                children: [
                  const Text("CARNET OFICIAL DEL PELOTERO", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 14),
                  const CircleAvatar(radius: 40, backgroundImage: NetworkImage("https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80")),
                  const SizedBox(height: 10),
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text("Plataneros de La Vega · Equipo Oficial", style: TextStyle(color: Colors.white54, fontSize: 11)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0xFF080D14), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.tealAccent)),
                    child: const Text("ID: RD-8420", style: TextStyle(color: Colors.tealAccent, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ),
                  const SizedBox(height: 10),
                  const Text("Comparte este ID con cualquier mánager para que te agregue a su equipo:", style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.share, color: Colors.white),
                label: const Text("ENVIAR MI ID AL MÁNAGER POR WHATSAPP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  sendToWhatsApp("⚾ Mánager, agrégame con mi ID universal de pelotero: RD-8420 (${widget.userName})");
                },
              ),
            ),
          ],
        ),
      );
    }

    // VISTA DEL MÁNAGER / DIRIGENTE (CONTROL TOTAL DEL ROSTER Y LINEUP)
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tarjeta del Equipo
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.amber)),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Colors.amber, child: Icon(Icons.shield, color: Colors.black)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(teamName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text("📍 $province · ${roster.length} Jugadores en Roster", style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
                  icon: const Icon(Icons.badge, color: Colors.black, size: 16),
                  label: const Text("+ FICHAR POR ID", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 11)),
                  onPressed: _openAddByIdDialog,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 10)),
                  icon: const Icon(Icons.person_add, color: Colors.amber, size: 16),
                  label: const Text("+ CREAR NUEVO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: _openAddManualPlayerDialog,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Switch BD vs Picher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(pitcherHits ? "El picher batea hoy (P)" : "Batea un Designado (BD) por el picher", style: TextStyle(color: pitcherHits ? Colors.tealAccent : Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                Switch(value: pitcherHits, activeColor: Colors.tealAccent, onChanged: (v) => setState(() => pitcherHits = v)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Selector 9 a 12 bateadores
          Row(
            children: [9, 10, 11, 12].map((cnt) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: batters == cnt ? Colors.amber : const Color(0xFF121B27)),
                  onPressed: () => setState(() => batters = cnt),
                  child: Text("$cnt ${cnt > 9 ? '(+EP)' : ''}", style: TextStyle(color: batters == cnt ? Colors.black : Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
            )).toList(),
          ),

          const SizedBox(height: 14),

          const Text("PLANTILLA Y ROSTER:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),

          ...roster.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                CircleAvatar(backgroundColor: const Color(0xFF0F172A), radius: 14, child: Text(p["num"]!, style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold))),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p["name"]!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  Text("Posición: ${p["pos"]!} · ID: ${p["id"]!}", style: const TextStyle(color: Colors.white54, fontSize: 9)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: p["type"] == "Refuerzo" ? Colors.teal.shade900 : const Color(0xFF080D14), borderRadius: BorderRadius.circular(4)),
                  child: Text(p["type"]!, style: TextStyle(color: p["type"] == "Refuerzo" ? Colors.tealAccent : Colors.white38, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
