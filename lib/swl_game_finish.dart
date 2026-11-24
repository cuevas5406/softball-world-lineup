enum SwlFinishReason { normal, superKnockout, knockout }

/// Evalúa la media entrada de la jugada, antes de presentar la siguiente.
/// Durante la baja solo el local puede cerrar por ventaja sin completar outs.
class SwlGameFinishRules {
  const SwlGameFinishRules({
    this.regulation = 6,
    this.superMargin = 15,
    this.knockoutMargin = 10,
  });

  final int regulation;
  final int? superMargin;
  final int? knockoutMargin;

  SwlFinishReason? afterPlay({
    required int inning,
    required bool top,
    required bool halfEnded,
    required int home,
    required int away,
  }) {
    final lead = home - away;
    final margin = switch (inning) {
      3 => superMargin,
      >= 4 => knockoutMargin,
      _ => null,
    };
    if (margin != null && margin > 0) {
      final mercy = top
          ? halfEnded && lead >= margin
          : lead >= margin || (halfEnded && lead <= -margin);
      if (mercy)
        return inning == 3
            ? SwlFinishReason.superKnockout
            : SwlFinishReason.knockout;
    }
    if (inning < regulation) return null;
    if (top ? halfEnded && lead > 0 : lead > 0 || (halfEnded && lead < 0)) {
      return SwlFinishReason.normal;
    }
    return null;
  }
}

/// Completa huecos que el marcador ya certifica como medias entradas jugadas.
/// Una baja omitida al finalizar en alta conserva su guion.
List<int?> swlDisplayInnings(
  List<int?> saved, {
  required int inning,
  required bool top,
  required bool home,
  bool halfEnded = false,
}) {
  final completed =
      inning -
      1 +
      (home ? (!top && halfEnded ? 1 : 0) : (!top || halfEnded ? 1 : 0));
  final length = saved.length > inning ? saved.length : inning;
  return List.generate(length, (index) {
    if (index < saved.length && saved[index] != null && saved[index] != 0) {
      return saved[index];
    }
    return index < completed ? 0 : null;
  });
}
