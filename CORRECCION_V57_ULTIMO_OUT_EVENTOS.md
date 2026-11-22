# V5.7 — Validación del último out en historial

La RPC ahora obtiene el ID del último out como texto, valida su formato UUID y solo después lo convierte. Si un evento histórico tiene un identificador ausente o mal formado, devuelve un mensaje claro y la transacción no altera el partido.

No ejecutado en Supabase LAB ni producción. Sin compilación Flutter.
