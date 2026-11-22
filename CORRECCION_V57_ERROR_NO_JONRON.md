# V5.7 — validación defensiva de jonrón y error

Se corrigió la RPC propuesta `swl_v57_batted_ball`: ahora rechaza `p_action = ERROR` con `p_batter_base = 4`. Flutter ya impedía esa selección en la interfaz, pero faltaba validarla en el servidor para evitar solicitudes inconsistentes desde otros clientes. Un jonrón válido (`HIT_WITH_OUT`, base 4) permanece permitido.

Se añadió una prueba estática del contrato SQL/UI. No se instaló la RPC en LAB ni se compiló Flutter. Producción intacta.
