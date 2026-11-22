# V5.7: validación explícita de NULL en SQL

Se corrigió el chequeo de estado para que los valores NULL de inning, outs, balls, strikes y carreras no pasen inadvertidos por la lógica ternaria de PostgreSQL. También se exige configurar swl_allow_roster_ghost para corredor fantasma. Sin migración ejecutada.
