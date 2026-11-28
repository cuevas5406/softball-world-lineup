# Deshacer doble play · propuesta pendiente de autorización

Flutter consulta el crédito de pitcheo por partido y versiones de DP y
busca el nombre del pitcher por UUID. La vista de fanáticos conserva los
permisos vigentes. Si el crédito es visible, se usa el pitcher histórico,
independientemente del actual. La propuesta además lo incluye en el evento
de los DP nuevos, para conservarlo cuando se retire el crédito por anulación.

El SQL agrega almacenamiento privado de los estados previos a ambos tipos
de DP. El estado se guarda bajo el bloqueo que ya usa la RPC, antes de
cambiar bases o marcador. Deshacer exige que siga siendo la última versión,
que el mánager autorizado corresponda a la mitad previa y que no haya firmas.
Un DP sin estado previo se rechaza. Al aceptar, el servidor restaura el
estado, conserva el DP en el historial y agrega UNDO_OUT con el crédito de
pitcheo retirado. Así el historial conserva la auditoría mientras los
agregados existentes excluyen la jugada revertida.

Si el DP completó tres outs se restaura la mitad anterior. Si produjo un
cierre reglamentario sin firmas, las reglas existentes de participación
pueden impedir reabrir el encuentro cuando haya un conflicto. Los registros
anteriores de decisiones automáticas se conservan para auditoría.

Antes de aplicar en LAB, respaldar las tres definiciones vigentes y verificar
el propietario y los ACL. Ejecutar la prueba adjunta con ROLLBACK y validar
además cierres automáticos, firmas, permisos del mánager y propagación Realtime
a dos dispositivos. El SQL se revisó sintácticamente y no se ejecutó.
