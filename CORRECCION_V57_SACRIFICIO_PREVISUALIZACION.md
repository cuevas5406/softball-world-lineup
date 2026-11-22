# V5.7 — Previsualización de elevado de sacrificio

El motor local `SwlPlayState.sacrificeFly` permitía escenarios que el RPC SQL `swl_v56_special_play` rechaza: jugada con dos outs, sin corredor en tercera o sin carrera desde tercera. Esto podía mostrar una jugada como válida en Flutter que fallaría al guardarse.

Se alinearon las precondiciones del motor Dart con el contrato SQL existente: menos de dos outs, corredor en tercera y `thirdTo == 0`. No se alteraron las reglas del servidor ni Supabase.

La implementación actual del elevado de sacrificio modela específicamente el elevado que produce una carrera desde tercera; otros elevados de sacrificio requieren ampliar ambos contratos en una versión posterior.

Verificación: pruebas Python estáticas. No se ejecutaron Dart, Flutter, APK ni RPC reales.
