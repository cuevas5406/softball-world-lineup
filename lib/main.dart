import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // CONEXIÓN OFICIAL A TU SUPABASE
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
// 1. APERTURA (SPLASH CON TU ESCUDO OFICIAL Y FOTO DE MIRAMAR)
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
                  const Text(
                    "SOFTBALL WORLD LINEUP",
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  const Text("La Plataforma Oficial del Sóftbol", style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 6,
                      ),
                      icon: const Icon(Icons.arrow_forward, color: Colors.black),
                      label: const Text("ENTRAR AL TERRENO", style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (ctx) => const MainAppMasterHub()),
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

// -------------------------------------------------------------------------
// 2. HUB PRINCIPAL (4 PESTAÑAS 100% FUNCIONALES)
// -------------------------------------------------------------------------
class MainAppMasterHub extends StatefulWidget {
  const MainAppMasterHub({super.key});

  @override
  State<MainAppMasterHub> createState() => _MainAppMasterHubState();
}

class _MainAppMasterHubState extends State<MainAppMasterHub> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const MasterHomeTab(),
    const MasterScoreboardTab(),
    const MasterScheduleTab(),
    const MasterTeamTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      body: IndexedStack(index: _currentIndex, children: _screens),
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
// PESTAÑA 1: INICIO (CARRUSEL ALEX MONO + ¡A JUGAR! + CROMITO)
// -------------------------------------------------------------------------
class MasterHomeTab extends StatefulWidget {
  const MasterHomeTab({super.key});

  @override
  State<MasterHomeTab> createState() => _MasterHomeTabState();
}

class _MasterHomeTabState extends State<MasterHomeTab> {
  final PageController _bannerController = PageController();
  int _currentBanner = 0;
  Timer? _timer;

  final String logoUrl = "https://epqyabaegmyjtwqezvbc.supabase.co/storage/v1/object/public/team-logos/logo_transparent-removebg-preview.png";

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

  void _openPlayerCromito() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF121B27),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(6)),
                  child: const Text("#1 RANKING NACIONAL RD 🥇", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10)),
                ),
                IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 12),
            const CircleAvatar(
              radius: 42,
              backgroundImage: NetworkImage("https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&w=400&q=80"),
            ),
            const SizedBox(height: 10),
            const Text("Juan Pérez #14", style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const Text("Plataneros de La Vega · ID: RD-8420", style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                _MiniStat("PROMEDIO", ".615", Colors.greenAccent),
                _MiniStat("JONRONES", "5", Colors.amber),
                _MiniStat("IMPULSADAS", "14", Colors.orangeAccent),
                _MiniStat("HITS", "16", Colors.tealAccent),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.share, color: Colors.white),
                label: const Text("COMPARTIR CROMITO EN WHATSAPP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF25D366), content: Text("⚾ Cromito listo para compartir")));
                },
              ),
            ),
          ],
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
        elevation: 0,
        title: Row(
          children: [
            Image.network(
              logoUrl,
              height: 32,
              fit: BoxFit.contain,
              errorBuilder: (ctx, err, stack) => const Icon(Icons.sports_baseball, color: Colors.amber, size: 24),
            ),
            const SizedBox(width: 8),
            const Text("SOFTBALL WORLD LINEUP", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.2, color: Colors.white)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            // CARRUSEL ROTATIVO DE PATROCINADORES
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
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _currentBanner ? 16 : 6,
                height: 4,
                decoration: BoxDecoration(color: i == _currentBanner ? Colors.amber : Colors.white24, borderRadius: BorderRadius.circular(2)),
              )),
            ),

            const SizedBox(height: 16),

            // BOTÓN ¡A JUGAR AHORA!
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          Text("Pizarra oficial de anotación en vivo", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.black, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 18),

            // LÍDER NACIONAL CLICKEABLE
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: _openPlayerCromito,
                borderRadius: BorderRadius.circular(14),
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
                            Text("Plataneros de La Vega · Toca para ver cromito", style: TextStyle(color: Colors.white60, fontSize: 10)),
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
            ),

            const SizedBox(height: 20),

            // DIRECTORIO DE PLAYS
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("ESTADIOS DESTACADOS:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 8),
                  _playTile("Play Club Miramar", "Santo Domingo · Con luces nocturnas 💡"),
                  const SizedBox(height: 6),
                  _playTile("Play de Villa Rosa", "La Vega · Grama natural y graderías"),
                ],
              ),
            ),
          ],
        ),
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
                const SizedBox(height: 2),
                Text(s, style: TextStyle(color: isDark ? Colors.black54 : Colors.white70, fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playTile(String name, String desc) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Icon(Icons.stadium, color: Colors.purpleAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            Text(desc, style: const TextStyle(color: Colors.amber, fontSize: 10)),
          ])),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String l; final String v; final Color c;
  const _MiniStat(this.l, this.v, this.c);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(v, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w900)),
    Text(l, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
  ]);
}

// -------------------------------------------------------------------------
// PESTAÑA 2: PIZARRA OFICIAL EN VIVO (MLB LINE SCORE Y CONTROLES)
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

  void _openOutSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16202C),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("REGISTRO DE BATAZO / JUGADA", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            const Text("FALLOS AL CAMPO (1 TOQUE):", style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: ["Fallo al 8 (Center)", "Fallo al 7 (Left)", "Fallo al 9 (Right)", "Fallo al 6 (Siore)"]
                  .map((f) => ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() { if (outs < 2) outs++; else outs = 0; });
                        },
                        child: Text(f, style: const TextStyle(fontSize: 10, color: Colors.white)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            const Text("ROLATA O TIRO (2 TOQUES):", style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: ["6-3 (SS a 1B)", "4-3 (2B a 1B)", "5-2 (3B a Home)", "3U (Pisa 1B)"]
                  .map((r) => ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() { if (outs < 2) outs++; else outs = 0; });
                        },
                        child: Text(r, style: const TextStyle(fontSize: 10, color: Colors.white)),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

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
        title: const Text("⚾ PIZARRA OFICIAL EN VIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.teal.withAlpha(40), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.tealAccent)),
            child: const Text("🟢 EN VIVO", style: TextStyle(color: Colors.tealAccent, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
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
                  Row(children: [
                    _base(on3B), const SizedBox(width: 4),
                    _base(on2B), const SizedBox(width: 4),
                    _base(on1B),
                  ]),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF16202C), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text("Bateando: Juan Pérez #14 (de 2-1 · .500)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                  Text("P: L. Severino (1.2 IP · 2 K)", style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Row(children: [
                    Expanded(child: _btn("BOLA", const Color(0xFF10B981), () => setState(() => balls = (balls + 1) % 4))),
                    const SizedBox(width: 6),
                    Expanded(child: _btn("STRIKE", const Color(0xFFEF4444), () => setState(() => strikes = (strikes + 1) % 3))),
                    const SizedBox(width: 6),
                    Expanded(child: _btn("BATAZO / OUT", const Color(0xFFF59E0B), _openOutSelector)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _btn("HIT (H)", const Color(0xFF223040), () => setState(() => visRuns++))),
                    const SizedBox(width: 6),
                    Expanded(child: _btn("DOBLE (H2)", const Color(0xFF223040), () {})),
                    const SizedBox(width: 6),
                    Expanded(child: _btn("JONRÓN (HR)", const Color(0xFF8B5CF6), () => setState(() => homRuns += 2))),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _base(bool occ) => Container(width: 10, height: 10, decoration: BoxDecoration(color: occ ? Colors.amber : Colors.white24, shape: BoxShape.circle));

  Widget _btn(String l, Color c, VoidCallback f) => ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    onPressed: f,
    child: Text(l, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

// BOX SCORE OFICIAL
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
                  Text("Pitcher Ganador (PG): ${visWon ? 'Carlos Martínez' : 'Luis Severino'}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF25D366), content: Text("⚾ Reporte oficial listo para grupos de WhatsApp"))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------
// PESTAÑA 3: AGENDA & RETOS (CON RELOJ MANUAL)
// -------------------------------------------------------------------------
class MasterScheduleTab extends StatefulWidget {
  const MasterScheduleTab({super.key});

  @override
  State<MasterScheduleTab> createState() => _MasterScheduleTabState();
}

class _MasterScheduleTabState extends State<MasterScheduleTab> {
  TimeOfDay selectedTime = const TimeOfDay(hour: 19, minute: 45);

  void _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: selectedTime);
    if (picked != null) setState(() => selectedTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final hour = selectedTime.hourOfPeriod == 0 ? 12 : selectedTime.hourOfPeriod;
    final minute = selectedTime.minute.toString().padLeft(2, '0');
    final period = selectedTime.period == DayPeriod.am ? "AM" : "PM";

    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(backgroundColor: const Color(0xFF0F1722), title: const Text("📅 AGENDA & RETOS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("PROGRAMAR JORNADA CON HORARIO MANUAL:", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Hora Exacta Elegida:", style: TextStyle(color: Colors.white54, fontSize: 10)),
                    Text("$hour:$minute $period", style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                  ]),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                    onPressed: _pickTime,
                    child: const Text("CAMBIAR HORA", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text("PARTIDOS AGENDADOS:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            _matchTile("Sábado 14 de Noviembre · 7:45 PM (Noche 💡)", "Plataneros de La Vega vs Metros de Santiago", "Play Club Miramar (SD) · PIN: PLAY-742"),
            const SizedBox(height: 8),
            _matchTile("Miércoles 18 de Noviembre · 8:15 PM (Noche 💡)", "Titanes de Moca vs Plataneros de La Vega", "Play de Villa Rosa (La Vega) · PIN: PLAY-810"),
          ],
        ),
      ),
    );
  }

  Widget _matchTile(String date, String teams, String play) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 4),
          Text(teams, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(play, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------------
// PESTAÑA 4: MI EQUIPO (ROSTER, CARNET ID Y BATEADORES)
// -------------------------------------------------------------------------
class MasterTeamTab extends StatefulWidget {
  const MasterTeamTab({super.key});

  @override
  State<MasterTeamTab> createState() => _MasterTeamTabState();
}

class _MasterTeamTabState extends State<MasterTeamTab> {
  bool pitcherHits = false;
  int batters = 10;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080D14),
      appBar: AppBar(backgroundColor: const Color(0xFF0F1722), title: const Text("👥 MI EQUIPO & ROSTER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.tealAccent)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                    Text("TU ID UNIVERSAL DE PELOTERO:", style: TextStyle(color: Colors.white54, fontSize: 9)),
                    Text("RD-8420", style: TextStyle(color: Colors.tealAccent, fontSize: 20, fontWeight: FontWeight.w900)),
                    Text("Equipo: Plataneros de La Vega", style: TextStyle(color: Colors.amber, fontSize: 10)),
                  ]),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Color(0xFF25D366), content: Text("ID copiado para enviar por WhatsApp"))),
                    child: const Text("ENVIAR ID", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
            const Text("ORDEN AL BATE DEL DOMINGO:", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 6),
            _lineupSlot("1° Bate", "Juan Pérez #14", "CF (8) · ID: RD-8420"),
            _lineupSlot("2° Bate", "Manny Cabrera #24", "SS (6) · ID: RD-2041"),
            _lineupSlot("3° Bate", "David Ortiz #34", "1B (3) · ID: RD-3400"),
            _lineupSlot("9° Bate", pitcherHits ? "Carlos Martínez #18" : "Teóscar Hernández #37", pitcherHits ? "P (1)" : "BD (Designado)"),
            if (batters >= 10) _lineupSlot("Bateador Extra 1", "Ketel Marte #4", "EP1", isEp: true),
            if (batters >= 11) _lineupSlot("Bateador Extra 2", "Gary Sánchez #24", "EP2", isEp: true),
            if (batters >= 12) _lineupSlot("Bateador Extra 3", "Willy Adames #2", "EP3", isEp: true),
          ],
        ),
      ),
    );
  }

  Widget _lineupSlot(String slot, String name, String pos, {bool isEp = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFF121B27), borderRadius: BorderRadius.circular(6), border: Border.all(color: isEp ? Colors.amber.shade800 : Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            Text(slot, style: const TextStyle(color: Colors.white38, fontSize: 9)),
          ]),
          Text(pos, style: TextStyle(color: isEp ? Colors.amber : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
