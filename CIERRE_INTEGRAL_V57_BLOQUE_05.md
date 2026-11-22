# Cierre integral V5.7 — bloque 05

Se agregó una comprobación opcional de revisión actual de alineación a `SwlSubstitutionRequest.validate`. Cuando el llamador proporciona `currentLineupRevision`, se rechazan solicitudes con revisión antigua o futura. Se agregaron tres pruebas Dart.

**Alcance:** esta validación pura no sustituye la verificación transaccional del servidor y todavía debe conectarse a la ruta real de sustitución en vivo. No se ejecutaron pruebas Dart ni se compiló APK en este entorno. No se ejecutó SQL ni se modificó Supabase.

Se actualizó una aserción estática obsoleta para reflejar la regla vigente: margen de nocaut desde la cuarta entrada en adelante, no solo en la cuarta.
