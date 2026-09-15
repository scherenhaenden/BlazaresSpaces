# Native macOS Spaces feasibility

Estado: investigación documental para BlazaresSpaces 0.3.0. Este documento no
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

Por tanto, **la sincronización nativa completa no es posible de forma pública,
estable y verificable**. La decisión para 0.3.0 es **MODE B — Logical Virtual
Spaces**: conservar el motor seguro de parking/restauración y presentar sus
contextos como Virtual Spaces, con orden posicional y nombres definidos por el
usuario. Los macOS Spaces siguen siendo una capa del sistema separada.

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

## Respuesta final

La sincronización de macOS Spaces entre displays, incluyendo seleccionar el
Space posicional correspondiente y mover ventanas de otras apps a él, **no es
posible de forma fiable sin APIs privadas o automatización no documentada**.
BlazaresSpaces debe usar MODE B y ofrecer Virtual Spaces lógicos, dejando claro
que son contextos propios y no una segunda representación controlable de Mission
Control.
