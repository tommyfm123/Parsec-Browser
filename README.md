<p align="center">
  <img src="Support/logo.png" alt="Parsec" width="120" height="120">
</p>

<h1 align="center">Parsec</h1>

<p align="center">
  <strong>El navegador ultraliviano para Mac.</strong><br>
  Nativo, rápido desde el primer clic y con un agente de IA que navega por ti.
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-AppKit-0A84FF">
  <img alt="WebKit" src="https://img.shields.io/badge/engine-WebKit-5E5CE6">
</p>

---

Parsec es un navegador para macOS inspirado en Arc, construido desde cero con **SwiftUI, AppKit y WebKit**. Pesa unos pocos megas y usa el motor de Safari, así que es liviano y cuida la batería. Además, integra la IA sin que se sienta un chatbot pegado al costado.

## Qué tiene

**Navegación**
- **Sidebar vertical que se esconde.** Aparece al acercar el mouse al borde; <kbd>⌘</kbd><kbd>S</kbd> lo fija. También hay un modo con pestañas arriba.
- **Perfiles y Spaces.** Cada perfil tiene sus propias cookies y sesiones, y cada Space sus favoritos, carpetas con íconos y pestañas fijadas.
- **Temas por Space**, con degradado, grano y transparencia.
- **Barra de comandos** (<kbd>⌘</kbd><kbd>T</kbd>) para buscar, abrir pestañas, ejecutar acciones o preguntarle a la IA. Es configurable.
- **Vista dividida** de hasta 4 paneles, **Peek**, **Little Arc** para links externos y ventanas privadas.
- **Pestañas livianas.** Se cargan cuando las abres, se suspenden si no las usas y las de "hoy" se archivan solas.
- **Importa tu sidebar de Arc:** Spaces, favoritos, carpetas y colores.

**IA integrada**
- **"¿Qué quieres saber hoy?".** Cada pestaña nueva tiene un input con los modos Buscar, IA y Agente. La conversación sigue a página completa en esa misma pestaña.
- **Agente que navega por ti** (`/navegar`, `/market-research`). Abre páginas, hace clic y escribe, con un cursor visible que muestra lo que hace. Al terminar te entrega el resultado con citas y fuentes.
- **Panel lateral** (<kbd>⌘</kbd><kbd>J</kbd>) para charlar sobre la página actual, el Space entero o las pestañas que elijas.
- **Historial de conversaciones** (<kbd>⌘</kbd><kbd>Y</kbd>) con buscador. Todo queda guardado solo en tu Mac.
- **Tú eliges el modelo.** Funciona con Claude Code, Codex (ChatGPT), la API de Anthropic, la API de OpenAI, modelos locales con Ollama o cualquier servicio compatible con OpenAI.

**Privacidad y seguridad**
- Bloqueo de anuncios y rastreadores (EasyList + EasyPrivacy), cookies de terceros bloqueadas y solo HTTPS.
- Aviso de sitios fraudulentos, confirmación antes de descargas de riesgo y cuarentena de Gatekeeper para lo que descargas.
- Permisos de cámara y micrófono por sitio. Las notificaciones web están desactivadas.
- Contraseñas en el Llavero de macOS, que se rellenan solo cuando lo pides y con Touch ID. Las API keys también se guardan en el Llavero.
- Por defecto, el agente navega en un perfil temporal sin tus sesiones y te pide permiso antes de enviar cualquier formulario.
- Modo desarrollador opcional, con inspector web y menú Desarrollador.

## Requisitos

- **macOS 26 (Tahoe) o posterior**, en Apple Silicon o Intel.
- **Swift 6**: con [Xcode 26](https://developer.apple.com/xcode/) o solo las Command Line Tools (`xcode-select --install`).
- Opcional, para la IA, cualquiera de estos:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code), que usa tu suscripción de Claude;
  - [Codex CLI](https://github.com/openai/codex), que usa tu suscripción de ChatGPT;
  - una API key de Anthropic u OpenAI;
  - [Ollama](https://ollama.com), para modelos locales.

## Cómo levantarlo

```bash
git clone https://github.com/tommyfm123/Parsec-Browser.git
cd Parsec-Browser
./scripts/build-app.sh release
open build/Parsec.app
```

El script compila con Swift Package Manager, arma el `Parsec.app` en `build/` y lo firma localmente (firma ad-hoc con hardened runtime).

Para dejarlo instalado:

```bash
cp -R build/Parsec.app /Applications/
```

> **Primera apertura.** Como la app no está notarizada por Apple, si la compilaste en otra Mac y la copiaste, macOS puede bloquearla. Ábrela con clic derecho → **Abrir**. Si la compilas en tu propia Mac, no hace falta.

Para usarlo como navegador predeterminado: **Configuración → General → Navegador predeterminado**.

### Desarrollo

```bash
swift build                    # compilación de desarrollo
./scripts/build-app.sh debug   # app de desarrollo en build/Parsec.app
./scripts/run-checks.sh        # verificaciones rápidas
```

## Conectar la IA

Abre **Configuración → IA** y elige un proveedor:

| Proveedor | Qué necesitas |
| --- | --- |
| Claude Code | Tener `claude` instalado y la sesión iniciada |
| Codex (ChatGPT) | Tener `codex` instalado y la sesión iniciada |
| API de Anthropic / OpenAI | Pegar tu API key, que se guarda en el Llavero |
| Modelos locales | Instalar y abrir Ollama; los modelos se descargan desde Parsec |
| Personalizado | Una URL base compatible con la API de OpenAI (LM Studio, OpenRouter, Groq…) |

## Atajos principales

| Atajo | Acción |
| --- | --- |
| <kbd>⌘</kbd><kbd>T</kbd> | Barra de comandos |
| <kbd>⌘</kbd><kbd>S</kbd> | Fijar o esconder el sidebar |
| <kbd>⌥</kbd><kbd>⌘</kbd><kbd>S</kbd> | Cambiar entre sidebar y pestañas arriba |
| <kbd>⌘</kbd><kbd>J</kbd> | Panel de IA |
| <kbd>⌘</kbd><kbd>Y</kbd> | Historial de conversaciones |
| <kbd>⌃</kbd><kbd>⌘</kbd><kbd>=</kbd> | Vista dividida |
| <kbd>⌘</kbd><kbd>\\</kbd> | Rellenar contraseña |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>N</kbd> | Ventana privada |

Todos se pueden cambiar en **Configuración → Atajos**.

## Tecnología

- **Swift 6** (en modo de lenguaje 5), empaquetado con **Swift Package Manager**, sin dependencias externas.
- **SwiftUI + AppKit**, con Liquid Glass de macOS 26.
- **WebKit**: `WKWebView` con un almacén de datos por perfil, `WKContentRuleList` para los bloqueos y content worlds aislados para autocompletar y para el agente.
- **SQLite3** para el historial de navegación.
- **Security + LocalAuthentication** para el Llavero y Touch ID.
- **IA:** procesos locales (`claude -p`, `codex exec`) y streaming por SSE para las APIs.

## Estructura

```
Sources/Parsec
├── App/         Ciclo de vida, ventanas, menús y atajos
├── Model/       Estado: perfiles, Spaces, pestañas, configuración
├── Web/         WebKit: páginas, navegación, errores y seguridad
├── Services/    Historial, favicons, bloqueador, contraseñas, descargas, conversaciones
├── Assistant/   Proveedores de IA, agente que navega, panel y modelos
└── Views/       Interfaz: sidebar, contenido, inicio, configuración
Support/         Info.plist, entitlements, ícono y listas de filtros
scripts/         Build, verificaciones e ícono
```

## Tus datos

Parsec no tiene servidores ni telemetría. Todo vive en tu Mac:

- **Estado, historial y conversaciones:** `~/Library/Application Support/Parsec/`
- **Contraseñas y API keys:** Llavero de macOS
- **Cookies y sesiones:** el almacén de WebKit de cada perfil

Solo sale lo que tú le envías al proveedor de IA que elijas.

---

<p align="center">Hecho con cariño para Mac.</p>
