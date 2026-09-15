# Native macOS Spaces feasibility

Estado: investigación abierta para BlazaresSpaces 0.3.0. Este documento no
introduce APIs privadas ni cambia el comportamiento de producción.

## Resumen ejecutivo

Las APIs públicas de macOS no ofrecen una interfaz estable para administrar los
Spaces de Mission Control como objetos de una aplicación. AppKit expone la
configuración `NSScreen.screensHaveSeparateSpaces`, información de pantallas y
comportamientos de ventanas relacionados con Spaces. Accessibility expone la
jerarquía de ventanas, foco, posición, tamaño y acciones soportadas por cada
aplicación. Ninguna de esas APIs expone un identificador público y durable del
Space actual, una lista pública de Spaces, ni operaciones públicas para crear,
eliminar, seleccionar o asignar una ventana de otra aplicación a un Space
concreto.

Por tanto, **la administración nativa completa no está expuesta como API
pública, estable y verificable**. La decisión entre MODE B y un MODE C híbrido
queda abierta hasta investigar la activación mediante atajos de Mission Control
y validarla físicamente, especialmente con Spaces separados desactivados.

## Matriz de capacidades públicas

| Operación | Clasificación | Qué sí puede hacer la aplicación | Límite decisivo |
| --- | --- | --- | --- |
| Observar Spaces nativos | **PUBLIC + LIMITED** | Leer si las pantallas tienen Spaces separados; observar indirectamente ventanas y cambios de topología mediante AppKit/Accessibility | No hay API pública para enumerar Spaces, obtener su cantidad, conocer el Space actual o asociar un Space con un display y una ventana |
| Crear Space nativo | **NOT PUBLICLY SUPPORTED** | El usuario puede crearlo desde Mission Control | No existe API pública AppKit/NSWorkspace/CoreGraphics para solicitar la creación |
| Eliminar Space nativo | **NOT PUBLICLY SUPPORTED** | El usuario puede eliminarlo desde Mission Control | No existe API pública; el sistema reubica ventanas al borrar un Space |
| Cambiar al Space nativo | **NOT PUBLICLY SUPPORTED** | El usuario puede usar Mission Control, gestos o atajos del sistema | No hay selector público de Space. Publicar eventos de teclado no es un controlador de Spaces documentado ni ofrece confirmación fiable |
| Mover ventana a un Space nativo concreto | **NOT PUBLICLY SUPPORTED** | Accessibility puede mover/redimensionar una ventana si la aplicación lo permite; AppKit define comportamientos para ventanas propias | AX no define un atributo público de Space. `NSWindow`/`NSWorkspace` no permiten asignar ventanas de otras apps a un Space concreto |
| Determinar el display | **PUBLIC + RELIABLE** | `NSScreen`, `CGDisplayBounds`, `NSScreenNumber` y geometría de ventana permiten determinar el display que contiene o interseca una ventana | La relación display/Space no está expuesta; la geometría no es una identidad de Space |
| Sincronizar cambio de Space entre displays | **PUBLIC + LIMITED** | Con Spaces separados desactivados, macOS presenta un modelo global que el usuario puede cambiar; la app puede reaccionar a cambios observables | La app no puede seleccionar ni confirmar programáticamente el Space destino. Con Spaces separados activados no puede seleccionar el Space correspondiente de cada display |

## Evidencia de APIs públicas

- Apple documenta `NSScreen.screensHaveSeparateSpaces` como una lectura de la
  preferencia “Displays have separate Spaces”; indica si cada pantalla puede
  tener su propio conjunto de Spaces, pero no expone esos Spaces como objetos
  administrables.
- La documentación de `AXUIElement` y de los atributos de Accessibility cubre
  ventanas, foco, posición, tamaño, visibilidad, minimización y acciones. No
  documenta un atributo `Space`, un ID de Space o una operación de cambio de
  Space.
- `NSWindow.CollectionBehavior` documenta comportamientos de ventanas propias,
  como participar en Spaces (`managed`), aparecer en todos (`canJoinAllSpaces`)
  o moverse al Space activo (`moveToActiveSpace`). Son políticas del ciclo de
  vida de una ventana AppKit; no son una API para elegir un Space nativo de otra
  aplicación.
- `NSWorkspace` documenta lanzamiento y operaciones sobre archivos, dispositivos
  y aplicaciones. No documenta administración de Mission Control o Spaces.
- CoreGraphics documenta displays, bounds y eventos, pero no el inventario ni el
  control de Spaces de Mission Control.

Fuentes oficiales:

- [NSScreen.screensHaveSeparateSpaces](https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces)
- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Accessibility attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes)
- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Apple Support: Work in multiple spaces on Mac](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)

## “Displays have separate Spaces” — ON

Cada display puede tener su propio conjunto de Spaces. La documentación de
Apple describe precisamente que Mission Control muestra los Spaces y ventanas
del display desde el que se abre, y ofrece asignaciones como “Desktop on Display
[number]”.

BlazaresSpaces puede:

- leer que esta configuración está activa;
- descubrir ventanas accesibles y su geometría/display;
- aplicar su propia semántica de Virtual Space mediante el motor lógico;
- dejar intactas las ventanas no gestionadas.

BlazaresSpaces no puede, usando APIs públicas documentadas:

- garantizar que el Space 2 del display A sea el mismo contexto que el Space 2
  del display B;
- seleccionar el Space nativo correspondiente en cada display;
- verificar de forma estable que una ventana está en el Space nativo esperado;
- crear los Spaces que falten para completar una fila 1..N.

Conclusión para ON: no se debe simular un binding nativo ni afirmar que un
Virtual Space cambia los Spaces de Mission Control. El motor lógico puede
aparcar/restaurar ventanas explícitamente gestionadas, sujeto a las limitaciones
de Accessibility y de las aplicaciones individuales.

## “Displays have separate Spaces” — OFF

Cuando la opción está desactivada, macOS usa un modelo de Spaces compartido por
el conjunto de displays. El usuario puede cambiar entre Spaces con Mission
Control o con los atajos/gestos del sistema, y ese cambio representa un contexto
global del conjunto de pantallas.

Esto hace que el comportamiento nativo sea conceptualmente más cercano a un
Virtual Space global, pero no convierte la operación en una API pública:

- la aplicación puede leer que la opción está desactivada;
- el cambio nativo sigue siendo iniciado por el usuario o por la UI del sistema;
- no hay una API pública para decir “activa el Space n” ni para confirmar su
  identidad posicional;
- no se puede afirmar que el número u orden visible de Mission Control sea una
  lista que BlazaresSpaces pueda leer y persistir.

Conclusión para OFF: BlazaresSpaces puede documentar que el usuario tiene un
modelo nativo global disponible y reaccionar conservadoramente a cambios
observables, pero no debe reimplementarlo con eventos sintetizados ni mezclarlo
automáticamente con el motor lógico. Si BlazaresSpaces activa su Virtual Space,
el mecanismo soportado sigue siendo el lógico.

## Orden y mapeo

El orden visible de Virtual Spaces debe ser posicional y estable para el usuario:

```text
Virtual Space 1 — Work
Virtual Space 2 — Development
Virtual Space 3 — University
Virtual Space 4 — Personal
```

Ese orden **no constituye** un binding a “native Space 1..4”. macOS no garantiza
una API pública para leer esos índices, y el orden/identidad puede cambiar por
Mission Control, pantallas, pantalla completa, Split View, reinicios o cambios
de topología. No se deben persistir IDs internos observados mediante técnicas
privadas ni inferirlos desde coordenadas.

El modelo recomendado es:

```text
VirtualSpace
  id interno durable
  name
  order/index visible
  memberships
  sticky semantics

VirtualSpaceActivationStrategy
  LogicalWindowParkingActivationStrategy  ← implementación 0.3.0
  NativeMacOSSpaceActivationStrategy      ← no disponible públicamente
```

No existe un `VirtualSpaceBinding` nativo persistible en 0.3.0. Un descriptor
de display puede seguir siendo útil para geometría y matching, pero no debe
describirse como identidad de un Space.

## Decisión arquitectónica

**Seleccionado: MODE B — Logical Virtual Spaces.**

Razones:

1. La creación, eliminación, selección y asignación nativas no tienen APIs
   públicas soportadas.
2. La observación nativa completa tampoco es fiable: leer la preferencia de
   Spaces separados y observar ventanas no equivale a conocer el Space actual.
3. MODE A exigiría afirmar una sincronización que el sistema no ofrece.
4. MODE C no aporta un subconjunto nativo suficientemente sólido para usarlo
   como fuente de verdad; la única capacidad general disponible es la lectura de
   la preferencia `screensHaveSeparateSpaces`.
5. El motor actual ya satisface la semántica de contextos globales con
   autorización explícita, exclusiones, sticky, parking, restauración y recovery.

La terminología pública debe ser:

- `Virtual Space` para los contextos administrados por BlazaresSpaces;
- `macOS Space` o `Native Space` para los escritorios de Mission Control;
- nunca presentar un Virtual Space como si fuera un macOS Space.

## Implicaciones para producción y migración

Esta investigación no requiere cambios de producción ni migración de datos. La
configuración existente puede conservar sus IDs internos y memberships; el
cambio de producto es terminológico y de activación conceptual. Si se adopta
“Virtual Space” en UI, debe migrarse únicamente el texto/presentación, no
reinterpretar IDs nativos inexistentes.

La integración de focused-window sigue siendo compatible: Accessibility puede
identificar la ventana enfocada y las acciones explícitas pueden gestionarla
mediante el motor lógico. Eso no prueba ni promete su pertenencia a un macOS
Space concreto.

## Qué se debe probar físicamente en Mac

- ON: confirmar que Mission Control mantiene contextos por display y que un
  cambio nativo no es confundido con un cambio de Virtual Space.
- OFF: confirmar que el cambio nativo afecta al conjunto global de displays.
- En ambos modos: verificar que BlazaresSpaces solo mueve ventanas explícitamente
  gestionadas, que exclusiones y ventanas no gestionadas permanecen intactas, y
  que una pérdida de Accessibility/topología pausa la activación.
- Probar pantalla completa, Split View, hot-plug y ventanas que rechazan AX.

## Ruta adicional: activación por atajos públicos de Mission Control

Esta fase investiga exclusivamente la integración con el mecanismo de usuario:
atajos de Mission Control, `CGEvent` para publicar teclado y
`NSWorkspace.activeSpaceDidChangeNotification` para observar una transición.
No es una API de administración de Spaces ni expone una identidad nativa.

La hipótesis de MODE C es `Virtual Space N → Switch to Desktop N`. BlazaresSpaces
conservaría nombres, orden, membresías, exclusiones y fallback lógico; macOS
ejecutaría el cambio físico mediante el atajo configurado por el usuario.
`CGEventCreateKeyboardEvent` y `CGEvent.post` son APIs públicas, pero Apple no
garantiza que un evento sintetizado active Mission Control en todos los estados
de foco, layouts, conflictos o versiones.

`NSWorkspace.activeSpaceDidChangeNotification` es pública y debe observarse en
`NSWorkspace.shared.notificationCenter`; no tiene `userInfo` ni contiene el
índice, nombre, display o ID destino. Confirma una transición observable, no
que se alcanzó Desktop N.

### Precondiciones y protocolo seguro

Los atajos “Switch to Desktop N” deben ser habilitados y configurados por el
usuario en System Settings. No hay API pública fiable para leer, verificar o
cambiar esas asignaciones; la app no debe modificar preferencias globales
silenciosamente. Control-Left/Control-Right es navegación relativa y no
sustituye automáticamente al atajo absoluto Desktop N.

Un adaptador experimental debe comprobar Accessibility y
`NSScreen.screensHaveSeparateSpaces`, registrar el observador antes de publicar
el evento, enviar el atajo mediante `CGEvent`, y esperar con timeout corto.
El resultado solo puede ser `transitionObserved`, `unconfirmed` o `timedOut`,
nunca `destinationNVerified`. Topología insegura, solicitudes concurrentes o
timeout deben cancelar/degradar y conservar el motor lógico como fallback; no
deben provocar parking parcial ni cambios de membresía.

### Riesgos del mapeo posicional

“Automatically rearrange Spaces based on most recent use” puede cambiar el
orden y romper `Virtual Space N = Desktop N`; para probar mapping estable el
usuario debe desactivarlo manualmente. La app no debe cambiarlo. Crear,
eliminar o reordenar Spaces, reiniciar sesión, fullscreen, Split View y displays
adicionales pueden introducir o desplazar Spaces. Fullscreen debe tratarse
como una fuente de desincronización.

Con **Spaces separados OFF**, el contexto global compartido es el mejor
candidato para MODE C, pero requiere pruebas reales con varios displays. Con
**ON**, un atajo no garantiza sincronización del mismo índice en cada display y
MODE C no debe presentarse como soporte multi-display.

### Matriz de integración y puerta A/B/C

| Capacidad | Mecanismo público | Verificación | Estado |
| --- | --- | --- | --- |
| Activar Desktop N | Atajo configurado + `CGEvent` | Notificación, sin índice | Pendiente de prueba |
| Observar transición | `activeSpaceDidChangeNotification` | Cambio ocurrido | Disponible, limitada |
| Leer/configurar atajos | System Settings | No hay API fiable | Acción manual |
| Activar con OFF | Atajo + notificación | Posible contexto global | Candidato experimental |
| Activar con ON | Atajo + notificación | Destino por display ambiguo | No apto para promesa |
| Crear/eliminar/mover a Space N | Mission Control/AX | No verificable | No soportado |

| Modo | Activación | ON | OFF | Estado |
| --- | --- | --- | --- | --- |
| MODE A | Administración nativa directa | No viable | No viable | Descartado |
| MODE B | Parking/restauración AX | Viable | Viable | Fallback determinista |
| MODE C | Atajos `CGEvent` + fallback lógico | No prometer | Candidato a validar | No decidido |

No se selecciona todavía MODE B o MODE C como estrategia predeterminada.
La decisión queda pendiente de pruebas físicas con atajos configurados y
ausentes, reordenamiento, fullscreen, conflictos, timeout, y Spaces OFF/ON.

### Plan de validación física

Con uno y dos displays, crear tres Spaces, desactivar Spaces separados y el
reordenamiento automático, configurar Desktop 1..3, y probar cada Virtual
Space desde la app. Confirmar visualmente la ventana esperada y registrar la
notificación. Repetir con atajo ausente/en conflicto, solicitudes rápidas,
cambio manual concurrente, Space eliminado, fullscreen, topología cambiada y
Spaces separados activados. Aprobar MODE C solo si OFF conserva una
correspondencia estable y todos los fallos producen estado incierto/degradado
con fallback seguro.

Fuentes oficiales: [CGEvent keyboard initializer](https://developer.apple.com/documentation/coregraphics/cgevent/init%28keyboardeventsource%3Avirtualkey%3Akeydown%3A%29),
[CGEvent.post](https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29),
[activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification),
[Work in multiple spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac) y
[Desktop & Dock settings](https://support.apple.com/guide/mac-help/-mchlp1119/mac/26).

## Respuesta final

La administración nativa directa de macOS Spaces no está disponible mediante
API pública. MODE C queda abierto como integración experimental basada en
atajos públicos, especialmente con Spaces separados OFF; no proporciona IDs,
no verifica semánticamente Desktop N y debe mantener MODE B como fallback.
