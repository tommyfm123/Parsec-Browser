# Auditoría de seguridad y rendimiento de Parsec

Fecha: 30 de septiembre de 2026. Base auditada: `470a13a`. Rama: `fix/security-performance-audit`.

Se revisaron navegación WebKit, credenciales, permisos de cámara y micrófono, perfiles, ventanas privadas, descargas, filtros, favicons, suspensión y archivado, acciones del asistente, transporte de API y llamadas MCP. Se corrigieron las causas descritas abajo. La verificación usa código de producción y WebKit real, con datos temporales y un servidor de prueba en loopback; no lee contraseñas del usuario ni envía consultas a proveedores de IA.

## Fallos confirmados y correcciones

| Área | Impacto y evidencia del código anterior | Corrección |
| --- | --- | --- |
| Credenciales: alto | `candidateHosts` subía hasta dominios de dos etiquetas, incluso `co.uk`; `matches` aceptaba dominios padre e hijos. | Coincidencia exacta del host, sin ascenso a dominios padre; consultas limitadas a entradas creadas por Parsec. |
| Relleno: alto | Se verificaba el host antes de autenticar, pero no después; la página podía navegar durante Touch ID. | Validación de HTTPS, puerto, origen, navegación y documento antes de entregar el secreto. El script valida nuevamente documento, origen y destino del formulario. |
| Privacidad: medio | Un almacén no persistente estático compartía cookies entre todas las ventanas privadas. Los favicons y las descargas podían dejar registros persistentes. | Almacén por ventana, liberación al cerrar, ausencia de historial y caché de favicon privados, y exclusión de descargas privadas del registro persistente. Los archivos que el usuario descarga siguen guardándose. |
| Perfiles: medio | `loadPage` usaba el perfil del Space activo al cargar pestañas o popups pertenecientes a otro Space. | Resolución del perfil dueño de la pestaña y conservación del perfil de origen de popups. |
| Cámara y micrófono: medio | La autorización se persistía por host, sin distinguir protocolo y puerto; no se revalidaba la navegación al responder al permiso. | Permisos por origen completo, validación del frame principal y rechazo de respuestas tardías tras navegar. Las autorizaciones antiguas por host requieren volver a autorizar. |
| Excepción HTTP: alto | Una URL `parsec-http-continue:` proveniente de una página podía agregar cualquier host a las excepciones HTTP. | Solo funciona desde el aviso interno, mediante un enlace al destino exacto de un fallo de actualización a HTTPS pendiente. Se revoca al navegar. |
| Contexto de IA: alto | La observación de elementos utilizaba `element.value`, también para contraseñas, tarjetas y códigos. | Exclusión de valores sensibles y rechazo de escritura en estos campos. |
| Acciones de IA | La ruta de acciones de chat admitía destinos `file:` y `data:`. Los IDs del agente se almacenaban en atributos DOM modificables por las páginas. | Solo URLs HTTP/HTTPS para acciones de navegación; referencias de elementos en el mundo aislado. Los clics en botones requieren confirmación y vuelven a validar el elemento después de la animación. |
| MCP: alto | La declaración `readOnlyHint` del servidor evitaba la confirmación aunque una herramienta realizara una escritura. | Confirmación de cada llamada a través del cliente MCP de Parsec, con cancelar como opción predeterminada. |
| Suspensión | Un callback tardío de reproducción podía descargar una pestaña recién seleccionada. El archivado comprobaba captura, pero no reproducción de audio. | Revalidación de visibilidad, identidad de página y actividad; conservación de páginas que cargan, capturan, reproducen o son usadas por el agente. |
| Favicons | Cada actualización del mismo icono reiniciaba una descarga; el fallback volvía a descargar el HTML de la raíz. Decodificación y conversión de imágenes ocurrían en el actor de UI. | Peticiones agrupadas, reutilización del resultado, espera antes de reintentar errores, eliminación de la descarga redundante de HTML y decodificación fuera del actor principal. |
| Inicio del bloqueador | La carga inicial podía comenzar antes de compilar los filtros; las actualizaciones no alcanzaban todas las ventanas privadas, auxiliares y vistas previas. | Espera de reglas preparadas antes de navegar, registro débil de todos los controllers y reutilización de reglas compiladas. Si falla una lista descargada se usa la incluida; si no puede iniciarse la protección se muestra un error. |

## Endurecimiento adicional

- Los documentos HTML locales reciben permiso de lectura únicamente sobre el archivo abierto, en vez del directorio completo. Las navegaciones de páginas remotas a archivos locales se rechazan explícitamente. Los recursos locales vecinos dejan de estar accesibles automáticamente.
- Los nombres de descarga se reducen a un nombre de archivo, eliminan controles de dirección y no pueden elegir un dotfile. Se reservan destinos mientras hay descargas simultáneas. WebKit ya normaliza algunos nombres; esto agrega una comprobación nativa independiente.
- La cuarentena de macOS se verifica al terminar: un error deja la descarga en estado fallido y evita abrirla desde Parsec como completada.
- Los clientes de IA usan sesiones efímeras sin cookies, HTTPS salvo loopback, rechazo de credenciales incrustadas y de redirecciones, y límite para cuerpos de error. Los favicons tienen un máximo de 512 KiB y se decodifican como thumbnails de hasta 64 píxeles.
- Claude Code se inicia en modo `--restricted`, sin permisos interactivos y con la lectura automática limitada a `attachments`. Se contrastó la sintaxis con la ayuda de la versión instalada. Una versión anterior sin ese modo falla al iniciar en lugar de retirar la restricción silenciosamente.
- Las búsquedas usan `URLQueryItem`, conservando `&`, `#` y otros separadores como parte de la consulta.
- Se eliminó el doble despacho de carga al navegar desde una pestaña vacía y al crear una pestaña desde un enlace.
- Los procesos WebKit terminados en segundo plano liberan la página; las páginas visibles tienen un intento de recuperación automática por carga explícita.

## Verificación y medición

`./scripts/run-audit-checks.sh` pasó **54 comprobaciones**, incluyendo:

- cookies entre ventanas privadas, aislamiento de perfiles y popups;
- permisos por origen, rechazo de frames embebidos y navegación durante una autorización;
- documentos de credenciales válidos, IDs caducados, cambio de origen y formularios con destino externo;
- rechazo de campos sensibles y de destinos locales de la IA;
- intento de falsificar la excepción HTTP y de navegar a un archivo local;
- descarga real dentro del directorio configurado, cuarentena y ausencia de registro privado;
- conservación de pestañas visibles, selección durante callbacks, reproducción de audio real y liberación al detenerla;
- fallback desde filtros descargados corruptos y límites/reintentos de favicons;
- rechazo de redirecciones del cliente API sin contactar el destino.

Comparación con `FaviconStore` de la base auditada, usando el mismo servidor y dos grupos de 20 solicitudes del mismo icono:

| Métrica | Antes | Después |
| --- | ---: | ---: |
| Descargas del mismo favicon | 40 | 1 |
| Reducción de peticiones en ese escenario | — | 97,5% |

Esta medición demuestra la eliminación de trabajo redundante para favicons; no equivale a una mejora porcentual del tiempo total de navegación. No se midió una mejora global de RAM, batería ni carga de sitios reales.

También pasaron `swift build`, `./scripts/run-checks.sh`, la compilación de producción y la verificación estricta de la firma. Se abrió una ventana nativa con los componentes de producción y se guardaron capturas de la página y la ventana en `.gstack/audit/evidence/`. Hay advertencias previas de SwiftUI por concatenación de `Text` y de rutas del linker del toolchain.

## Límites y riesgos pendientes

1. **El proceso principal sigue sin App Sandbox.** Los procesos de páginas de WebKit conservan su aislamiento del sistema, pero la aplicación nativa y los proveedores CLI/MCP locales tienen acceso a recursos del usuario. Para cerrar este riesgo hay que separar esos proveedores en un helper y diseñar sus permisos; activar un entitlement sin esa separación rompe funciones existentes. `--restricted` limita herramientas de Claude, pero no sustituye un sandbox del sistema operativo.
2. **La firma sigue siendo ad-hoc con hardened runtime, sin notarización ni identidad de distribución.** Una distribución con Developer ID y notarización requiere una identidad y credenciales de firma del propietario.
3. **Touch ID real, cámara/micrófono físicos y los permisos de proveedores externos no se probaron con datos personales.** Las pruebas verifican los límites en WebKit con fixtures; no prueban la pantalla biométrica ni el comportamiento de cada proveedor. Los conectores nativos opcionales de Claude Code siguen sujetos a la política de ese CLI; la confirmación por llamada de Parsec aplica a sus servidores de Plugins & MCPs.
4. **Los clics de páginas con JavaScript pueden producir efectos arbitrarios.** Se protege el envío nativo y los botones, pero un enlace o un evento de escritura puede tener efectos definidos por un sitio. El agente usa un perfil sin sesiones por defecto; habilitar sesiones aumenta su alcance. Las instrucciones externas tampoco se convierten en datos confiables por incluirlas en un prompt.
5. **El conversor de EasyList/EasyPrivacy continúa siendo parcial.** Soporta reglas de dominio y cookies; no implementa toda la gramática de esas listas. No se certifica bloqueo completo de rastreadores.
6. **La coincidencia estricta de credenciales no comparte secretos entre `www`, dominios padre y subdominios.** Una entrada antigua que perdió `www` durante el guardado puede necesitar guardarse otra vez desde el host exacto. No se migraron secretos automáticamente.

## Fuentes primarias

- [Apple: almacenes no persistentes de WebKit](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent()) explica que cada creación devuelve un almacén nuevo que conserva los datos en memoria.
- [Apple: alcance de lectura de archivos locales](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:)) recomienda el mismo archivo como alcance para impedir el acceso a otro contenido.
- [MCP: seguridad de las anotaciones de herramientas](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) establece que las anotaciones deben considerarse no confiables salvo que provengan de servidores confiables.
