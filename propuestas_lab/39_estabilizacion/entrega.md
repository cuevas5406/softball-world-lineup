# Estabilización SWL V5.7

Base `75ecf94`, rama `pruebas-de-V5.7`.

## Instalación pendiente en LAB

El único archivo de instalación es `SWL-Estabilizacion-transaccion-LAB.sql`.
Verificar su hash en `SHA256SUMS` y el proyecto
`wgeziptdoabyicufnrfk` antes de ejecutarlo. Los componentes SQL sirven
para revisar la propuesta. Las pruebas separadas suponen que las funciones
de la propuesta están instaladas. Ejecutar el archivo único como un lote
en la misma conexión, con interrupción al primer error.

El lote guarda las definiciones y propiedades de las dos funciones existentes
en tablas temporales. Revisa la configuración de Realtime y captura las
huellas del partido protegido y su historial, alineaciones, lanzamientos,
cambios de pitcher, turnos y decisiones. Las pruebas corren en un savepoint
y sus datos se revierten antes de comprobar las huellas y los permisos. Un
fallo crítico deja la transacción abortada y obliga a revertirla completa.

- AUTO conserva el cierre por margen. DISABLED conserva el cierre
  reglamentario y omite el cierre por margen. CONSULT congela la anotación,
  registra un voto de continuación por mánager, cierra si un mánager vota
  por finalizar y reevalúa el margen al terminar una entrada posterior.
  La oficialización sigue requiriendo las firmas existentes.
- El error defensivo admite retirar hasta tres corredores según los outs
  disponibles. Si hay varios retiros y se completa el tercero, el anotador
  identifica cuál fue el último. Se conservan los corredores no forzados
  que permanezcan en su base. El evento acredita al pitcher, guarda todos
  los corredores retirados y registra una aparición y un contacto sin hit.
- El fanático abre un Box Score de solo lectura que usa los mismos cálculos y
  exportador del mánager. Una RPC de lectura entrega una proyección de
  las tablas oficiales de una sola versión. Excluye los identificadores de
  los mánagers y campos privados. Los PNG y PDF completos requieren
  estado OFFICIAL y esa RPC en LAB.
- La defensa individual requiere créditos explícitos de PO, A y E.
  `defensa_individual.md` documenta la captura propuesta y el tratamiento
  de los datos históricos desconocidos.

Los contratos transaccionales requieren ejecución futura en LAB. La
comparación con dos sesiones reales, permisos efectivos en ambos dispositivos,
logos descargados desde LAB y el flujo de compartir en WhatsApp quedan
pendientes de validación física. Las muestras incluyen el logotipo original
SWL y usan datos sintéticos identificados como tales.
