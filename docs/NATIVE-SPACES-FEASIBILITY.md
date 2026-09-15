# Native macOS Spaces feasibility

Estado: implementado únicamente como inspección read-only experimental para
BlazaresSpaces 0.3.0. Este documento no habilita mutaciones de Spaces.

La aplicación mantiene el motor lógico como comportamiento de producción y
solo expone un lector experimental de topología nativa. La activación mediante
Mission Control, la administración directa basada en SkyLight/SLS y cualquier
operación estructural permanecen deshabilitadas.

## Regla de clean-room y licencia

yabai es GPL-3.0 y BlazaresSpaces es MIT. yabai se utiliza únicamente como
referencia técnica para estudiar comportamiento, arquitectura, algoritmos,
compatibilidad y nombres de interacción observados en versiones actuales.

No se copiará código fuente, se traducirán funciones línea por línea, se
pegarán headers completos ni se incorporarán cuerpos de implementación de
yabai. Cualquier futura implementación de BlazaresSpaces deberá ser una
implementación independiente, mínima y compatible con MIT, con declaraciones
propias únicamente para símbolos estrictamente necesarios. Los símbolos
privados se tratarán como detalles de runtime no soportados por Apple.

Referencias de investigación: [yabai CHANGELOG](https://github.com/asmvik/yabai/blob/master/CHANGELOG.md),
[space_manager.c](https://github.com/asmvik/yabai/blob/master/src/space_manager.c),
[yabai wiki](https://github.com/koekeishiya/yabai/wiki) y
[LICENSE de yabai](https://github.com/asmvik/yabai/blob/master/LICENSE).

## Matriz de capacidades

Las etiquetas distinguen disponibilidad pública, dependencia privada, efecto
de SIP, privilegios del Dock, compatibilidad observada en macOS 26 y soporte
que BlazaresSpaces puede prometer.

| Capacidad | Camino público | Camino privado estudiado | SIP | Dock / scripting addition | macOS 26 | Soporte de BlazaresSpaces |
| --- | --- | --- | --- | --- | --- | --- |
| Leer displays y geometría | `NSScreen`, CoreGraphics | No necesario | Completo | No | Público | Soportado |
| Leer preferencia Separate Spaces | `NSScreen.screensHaveSeparateSpaces` | No necesario | Completo | No | Público | Soportado, limitado |
| Leer topología de Spaces | No hay inventario público | `SLSCopyManagedDisplaySpaces` y relacionados, sujetos a verificación | Completo en investigación | No necesariamente | Debe verificarse por versión/arquitectura | Experimental read-only; falla explícitamente si no puede leer |
| Leer Space actual, IDs, UUIDs y tipos | No expuesto por AppKit/NSWorkspace | Funciones SLS observadas en herramientas de terceros | Completo en investigación | No necesariamente | Firmas y resultados deben verificarse en Tahoe 26.x | No prometido |
| Enfocar Space existente | Atajos/Mission Control; `CGEvent` solo solicita acción del usuario | `space --focus` usa interacción SkyLight/SLS en yabai actual | yabai reporta soporte con SIP habilitado desde 7.1.19 | No necesariamente para ese camino | Reportado con fixes continuos | Solo experimental, no implementado |
| Mover ventana a Space existente | AX puede mover la ventana físicamente, pero no asignarla a un Space | Operaciones SLS/bridged y/o scripting addition según versión | yabai reporta soporte con SIP habilitado de nuevo desde 7.1.25 | Puede ser necesario para rutas concretas | Requiere validación específica | Solo experimental, no implementado |
| Crear Space | Mission Control por acción del usuario | Operaciones privadas / scripting addition | Requiere evaluar estado de SIP | Dock necesario según la operación | Fixes de yabai no equivalen a API estable | No soportado |
| Eliminar Space | Mission Control por acción del usuario | Operaciones privadas / scripting addition | Requiere evaluar estado de SIP | Dock necesario según la operación | No promesa estable | No soportado |
| Reordenar Space | Mission Control por acción del usuario | Operaciones privadas / scripting addition | Requiere evaluar estado de SIP | Dock necesario según la operación | No promesa estable | No soportado |
| Mover Space entre displays | Mission Control por acción del usuario | Operaciones privadas / scripting addition | Requiere evaluar estado de SIP | Dock necesario según la operación | No promesa estable | No soportado |
| Ventana → Space nativo | No existe asignación pública por índice/ID | Posible mediante APIs privadas investigadas | Depende de la ruta | Puede requerir Dock | Debe probarse por build | No implementado |
| Confirmar Space destino | `activeSpaceDidChangeNotification` solo confirma una transición | Relectura SLS puede aportar identidad runtime | Completo | No | Notificación y SLS deben correlacionarse | No verificable públicamente |

Conclusión de la matriz: leer, enfocar y mover ventanas son problemas distintos.
Las capacidades de lectura no implican capacidad de mutación; enfocar un Space
no implica mover una ventana; y mover una ventana no implica que la app pueda
crear, eliminar, reordenar o trasladar Spaces entre displays.

## Separación arquitectónica

El dominio solo conoce `VirtualSpace`, su nombre, orden, membresías, sticky y
estado de seguridad. No depende de SkyLight, SLS, Dock ni IDs runtime privados.

La frontera de activación puede tener estas implementaciones:

```text
VirtualSpaceActivationStrategy
├── LogicalWindowActivationStrategy       (MODE B, actual y determinista)
└── NativeSpacesReadOnlyProvider          (experimental, solo lectura)
```

El backend lógico conserva parking/restauración AX y sigue siendo el único
camino de mutación de ventanas. El lector nativo vive en Infrastructure y no
contiene controlador, eventos de teclado ni operaciones de Spaces.

Los IDs privados, UUIDs y descriptores nativos son runtime-only hasta que se
demuestre estabilidad. No se deben persistir como IDs durables ni mostrar en
la UI. El binding preferido es posicional:

```text
Virtual Space 1 — Work        → primera desktop normal elegible
Virtual Space 2 — Development → segunda desktop normal elegible
Virtual Space 3 — Personal    → tercera desktop normal elegible
```

Los Spaces fullscreen, tiled/Split View o de tipo desconocido no se cuentan
como posiciones ordinarias salvo evidencia reproducible de lo contrario.
Con Separate Spaces ON el binding es por display; con OFF debe modelarse como
un contexto global compartido, sin asumir que existe un ID público global.

## Investigación del backend nativo

La investigación de yabai 7.1.x indica que cambios recientes permiten enfocar
Spaces con SIP habilitado desde 7.1.19 y mover ventanas con SIP habilitado de
nuevo desde 7.1.25. Eso demuestra que SIP habilitado no descarta toda la
capacidad observada en yabai; no demuestra que esas operaciones sean APIs
públicas, estables o apropiadas para BlazaresSpaces.

Los símbolos de interés incluyen `SLSCopyManagedDisplaySpaces`,
`SLSManagedDisplayGetCurrentSpace`, `SLSSpaceGetType`,
`SLSCopySpacesForWindows`, `SLSCopyWindowsWithOptionsAndTags` y
`SLSCopyManagedDisplayForWindow`. Sus firmas, disponibilidad, tipos de Space y
resultado deben verificarse en macOS 26.x para cada arquitectura antes de
considerar cualquier prototipo. No se usarán APIs privadas durante esta fase
documental, ni se inyectará código en Dock.

El objetivo mínimo, si se aprueba una implementación posterior, es:

1. read-only de displays, Spaces, tipos y Space actual;
2. binding posicional sin persistir IDs privados;
3. focus de un Space ya existente;
4. movimiento de una ventana exacta a un Space ya existente;
5. fallback lógico ante cualquier resultado ambiguo.

Crear, destruir, reordenar o mover Spaces entre displays queda fuera del primer
backend y se clasifica como capacidad estructural avanzada. No se crearán
Spaces silenciosamente para completar Virtual Spaces faltantes.

## Ruta pública mediante Mission Control

La aplicación puede estudiar `CGEvent` para publicar Control-Left/Right o un
atajo “Switch to Desktop N” configurado manualmente. `NSWorkspace` puede
observar `activeSpaceDidChangeNotification` desde
`NSWorkspace.shared.notificationCenter`, pero la notificación no contiene el
índice, UUID, display ni destino. Solo confirma que se observó una transición.

El usuario debe habilitar y configurar los atajos en System Settings. La app no
debe leer o modificar preferencias globales no documentadas. El protocolo
experimental debe registrar el observador antes de publicar el evento, usar
timeout, marcar el resultado como `transitionObserved`, `unconfirmed` o
`timedOut`, y conservar el fallback lógico. Nunca debe afirmar
`destinationNVerified` ni mezclar parking y cambio nativo en una misma
transacción sin diseño explícito.

Separate Spaces OFF es el único candidato para probar un contexto global entre
displays. Separate Spaces ON no garantiza que un atajo cambie coordinadamente
la posición equivalente en todos los displays. “Automatically rearrange Spaces
based on most recent use”, reordenamiento manual, fullscreen, Split View,
reinicios y cambios de topología pueden invalidar el mapping; la app solo debe
advertir, invalidar y degradar, nunca cambiar esa preferencia automáticamente.

## Fases manuales de validación

Estas fases son manuales y no deben automatizar mutaciones sobre el Mac de
Edward. Los tests unitarios usarán fakes de proveedores/controladores nativos.

### Fase 1 — Investigación y read-only

- Registrar versión exacta de macOS 26, arquitectura, SIP y configuración de
  Separate Spaces.
- Comparar topología visible de Mission Control con cualquier lectura
  read-only experimental; no modificar ventanas ni Spaces.
- Identificar tipos normales, fullscreen y tiled; rechazar tipos ambiguos.
- Confirmar que un cambio de display invalida el binding.

### Fase 2 — Focus de Space existente

- Preparar manualmente tres Spaces normales, sin crear ninguno desde la app.
- Probar focus posicional con SIP habilitado y registrar éxito, latencia,
  errores y notificaciones.
- Repetir con Separate Spaces OFF y ON, un display y dos displays.
- Tratar toda correlación sin identidad pública como experimental.

### Fase 3 — Movimiento de una ventana exacta

- Usar dos ventanas independientes de la misma aplicación.
- Mover solo la ventana enfocada a un Space existente y verificar que la otra
  no cambia.
- Probar exclusiones NEVER MANAGE, ventana no enrolada e identidad obsoleta.
- No usar `NSRunningApplication.hide()` ni ocultación app-wide.

### Fase 4 — Robustez y capacidades estructurales

- Probar fullscreen, Split View, Space eliminado/reordenado y uso reciente.
- Probar hot-plug y configuraciones ON/OFF sin intentar corregirlas desde la
  app.
- Documentar por separado qué operaciones requieren Dock/scripting addition o
  cambios de SIP; no habilitar create/delete/reorder/move-display.

### Fase 5 — Decisión de producto

Solo después de las fases anteriores se decide si ofrecer un backend nativo
opt-in. Requisitos mínimos: read model correcto, focus y movimiento exactos,
fallback sin doble movimiento, seguridad NEVER MANAGE, y degradación segura
ante pérdida de identidad o cambio de topología. Si no se cumplen, MODE B
permanece predeterminado y el camino público por atajos queda experimental.

## Puerta de decisión A/B/C

| Modo | Activación | Fuente de verdad | ON | OFF | Estado |
| --- | --- | --- | --- | --- | --- |
| MODE A | Administración nativa directa completa | APIs privadas/SkyLight | No soportable como promesa | No soportable como promesa | No seleccionado |
| MODE B | Parking/restauración AX | BlazaresSpaces | Viable | Viable | Predeterminado seguro |
| MODE C-public | Atajos Mission Control + `CGEvent` | — | — | — | Deshabilitado |
| MODE C-native | SkyLight/SLS mínimo, aislado en Infrastructure | Topología runtime + binding posicional | — | — | Solo read-only; sin activación |

No se selecciona un backend nativo de mutación como predeterminado. SIP se
mantiene completamente habilitado. La integración privada actual solo lee la
topología, muestra un binding posicional temporal en la UI y reporta errores;
no activa, crea, elimina, reordena ni mueve Spaces o ventanas.

## Fuentes

- [NSScreen.screensHaveSeparateSpaces](https://developer.apple.com/documentation/appkit/nsscreen/screenshaveseparatespaces)
- [NSWorkspace.activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)
- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [CGEvent keyboard initializer](https://developer.apple.com/documentation/coregraphics/cgevent/init%28keyboardeventsource%3Avirtualkey%3Akeydown%3A%29)
- [CGEvent.post](https://developer.apple.com/documentation/coregraphics/cgevent/post%28tap%3A%29)
- [Apple Support: Work in multiple spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)
- [Apple Support: Desktop & Dock settings](https://support.apple.com/guide/mac-help/-mchlp1119/mac/26)
- [yabai CHANGELOG](https://github.com/asmvik/yabai/blob/master/CHANGELOG.md)
- [yabai space_manager.c](https://github.com/asmvik/yabai/blob/master/src/space_manager.c)
- [yabai wiki](https://github.com/koekeishiya/yabai/wiki)
- [yabai GPL-3.0 license](https://github.com/asmvik/yabai/blob/master/LICENSE)
