# Auditoría estática V5.7 — 20 noviembre 2026

Se normaliza `LAST_OUT` con `btrim` tanto en la validación inicial como en la rama que lo procesa, para que ambos controles coincidan.

Se agregó `scripts/test_v57_special_sql_contract.py`, que comprueba nueve invariantes textuales importantes del contrato SQL. Ejecución local: `python scripts/test_v57_special_sql_contract.py`.

**Alcance:** comprobaciones estáticas; NO equivalen a compilación PostgreSQL, pruebas transaccionales, validación de RLS, pruebas Flutter ni sincronización entre teléfonos.

**Pendiente crítico:** instalar las migraciones 13 y 18 exclusivamente en Supabase LAB tras comprobar dependencias; ejecutar escenarios con autenticación real y revisar eventos/scoreboard. No tocar producción.
