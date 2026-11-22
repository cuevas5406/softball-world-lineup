# V5.7 — último out con espacios en blanco

Se normalizan mediante `btrim` los campos `last_out_player_id`, `runner_id` y `batter_id` antes de escoger el identificador del último out. Los campos compuestos solo por espacios se tratan como vacíos y permiten usar el identificador alternativo. Se mantiene la validación UUID previa al cast. No se aplicó SQL a Supabase.
