# V5.3 — Box score individual preliminar

- Agrupa los eventos identificados por equipo local y visitante.
- Muestra VB, H, 1B, 2B, 3B, HR, BB y K, con subtotales por equipo.
- Distingue participantes actualmente en alineación, sustituidos y entrantes a partir de alineaciones e historial consultado.
- La clasificación de sustituciones requiere cargar el historial reciente; el historial está limitado y puede omitir sustituciones antiguas. Por eso no se presenta como historial exhaustivo.
- La RPC `swl_v53_batting_stats` calcula estadísticas preliminares; no sustituye el box score oficial ni valida reglas completas.
- No se alteraron tablas, funciones ni permisos de Supabase.
- Pendiente: pruebas Flutter, dispositivos reales, y reglas completas de apariciones al plato.
