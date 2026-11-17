/// Contabilidad pura de carreras por entrada para la previsualización V5.3.
/// No escribe en Supabase. La autoridad final debe ser el RPC transaccional.
class SwlInningTotals {
  final List<int> home;
  final List<int> away;
  const SwlInningTotals({required this.home, required this.away});

  /// Compara el estado anterior y posterior de UNA jugada.
  /// Rechaza restas, saltos de entrada y cambios inesperados de equipo.
  SwlInningTotals record({required int inningBefore,
    required bool topBefore, required int inningAfter,
    required bool topAfter, required int homeBefore,
    required int awayBefore, required int homeAfter,
    required int awayAfter}) {
    if (inningBefore < 1 || inningAfter < inningBefore ||
        inningAfter > inningBefore + 1 || homeBefore < 0 ||
        awayBefore < 0 || homeAfter < homeBefore || awayAfter < awayBefore ||
        home.any((v) => v < 0) || away.any((v) => v < 0)) {
      throw StateError('Estado o transición de entrada inválidos');
    }
    final expectedInning = topBefore ? inningBefore : inningBefore + 1;
    if (topAfter != topBefore && inningAfter != expectedInning) {
      throw StateError('Cambio de mitad inválido');
    }
    if (topAfter == topBefore && inningAfter != inningBefore) {
      throw StateError('No puede saltarse una entrada');
    }
    final deltaHome = homeAfter - homeBefore;
    final deltaAway = awayAfter - awayBefore;
    if ((topBefore && deltaHome != 0) || (!topBefore && deltaAway != 0)) {
      throw StateError('Carreras asignadas al equipo equivocado');
    }
    if (home.fold<int>(0, (sum, v) => sum + v) != homeBefore ||
        away.fold<int>(0, (sum, v) => sum + v) != awayBefore) {
      throw StateError('Descuadre entre marcador y carreras por entrada');
    }
    if (home.length > inningBefore || away.length > inningBefore) {
      throw StateError('Hay entradas futuras en el historial');
    }
    final h = List<int>.from(home), a = List<int>.from(away);
    while (h.length < inningBefore) { h.add(0); }
    while (a.length < inningBefore) { a.add(0); }
    h[inningBefore - 1] += deltaHome;
    a[inningBefore - 1] += deltaAway;
    return SwlInningTotals(home: List.unmodifiable(h), away: List.unmodifiable(a));
  }
}
