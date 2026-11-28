bool swlCanDoublePlay(Set<int> occupied, int outs) =>
    outs >= 0 && outs < 2 && occupied.isNotEmpty;

String? swlDoublePlayError(
  Set<int> occupied,
  int outs,
  int source,
  Map<int, int> advances, {
  required bool timePlay,
}) {
  if (!swlCanDoublePlay(occupied, outs) || !occupied.contains(source)) {
    return 'Selecciona un corredor en base con menos de dos outs.';
  }
  if (advances.keys.any((base) => !occupied.contains(base) || base == source)) {
    return 'Solo pueden avanzar los corredores restantes.';
  }
  var previous = 4;
  for (final base in [3, 2, 1]) {
    if (!occupied.contains(base) || base == source) continue;
    final dest = advances[base] ?? base;
    if (dest < 0 || dest > 3 || (dest != 0 && dest < base)) {
      return 'El destino debe ser la misma base, una posterior o home.';
    }
    final position = dest == 0 ? 4 : dest;
    if (position > previous || (position == previous && position != 4)) {
      return 'Los corredores no pueden rebasarse ni compartir una base.';
    }
    if (dest == 0 && outs == 1 && (!timePlay || base < source)) {
      return 'La carrera no cuenta con un tercer out forzado o de un corredor precedente.';
    }
    previous = position;
  }
  return null;
}
