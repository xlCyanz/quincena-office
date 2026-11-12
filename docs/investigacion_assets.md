# Investigación: assets para la lógica y las mecánicas

Fecha: 12 de noviembre de 2026. Alcance: addons, plugins y herramientas de Godot 4.7 que mejoren la **lógica** del juego
(no el arte). Solo investigación: no se instaló ni se cambió nada en el proyecto.

## 1. Punto de partida

Lo que ya está hecho a mano (hitos 0–37) y funciona:

| Sistema | Cómo está hoy | ¿Pide un addon? |
| --- | --- | --- |
| Personajes | `OfficeCharacter` con un `enum Activity` de 4 estados (fuera, caminando al puesto, sentado, saliendo); `main.gd` le dice cada hora si debe estar (`Staff.is_expected`) | Todavía no. Crece en la fase 5 (rasgos, necesidades, eventos) |
| Caminos | `OfficePathfinder` con `AStarGrid2D` a doble resolución para las paredes de borde | No. Es la solución nativa y correcta para paredes en bordes |
| Simulación | Autoloads con estado (`Staff`, `Projects`, `Bank`, `Company`…) y funciones puras (`Production`, `Embargo`, `WorkSchedule`) | No. Es lógica de hoja de cálculo, no de nodos |
| Datos | JSON en `data/` leídos por catálogos (`StaffCatalog`, `ContractCatalog`…) | Sí, como mejora de edición y validación |
| Guardado | `SaveManager` junta `export_state()`/`import_state()` en JSON; `FORMAT_VERSION` = 1 y un archivo de otra versión no carga | Ideas sí; addon no |
| Eventos entre sistemas | `EventBus` con 44 señales | Sí, para depurarlo |
| Pruebas | Runner propio `tests/test_all.gd` con 38 partes (~10 000 líneas), sin ventana | Opcional |
| Balance | `test_phase3` simula meses e imprime resúmenes | Sí, para ver curvas en vivo |

Conclusión general: el núcleo del juego es simulación por datos y funciones puras, y eso no lo reemplaza ningún addon.
Lo que más rinde es **herramienta de desarrollo** (depurar, balancear, validar estilo) y, para la fase 5, **IA de
personajes** y **eventos con tarjetas**.

## 2. Filtro aplicado (reglas de `CLAUDE.md`)

Se descarta o se penaliza lo que:

- obliga a C# o no deja usar GDScript con tipado estático;
- comunica sistemas por referencias directas en lugar de `EventBus`;
- saca los valores de diseño de `data/` o los esconde en recursos binarios;
- necesita Forward+/Vulkan o no exporta a Android/iOS (futuro móvil, renderizador Compatibility);
- está en alfa, abandonado o sin compatibilidad comprobada con Godot 4.6/4.7.

Los addons **solo de desarrollo** (consolas, depuradores, linters) pesan menos en el filtro porque no viajan en la
exportación: se excluyen con el filtro de exportación (`addons/<addon>/*`).

## 3. Tabla priorizada

Leyenda de costo: **bajo** = menos de medio día y nada que migrar; **medio** = uno o dos días o tocar varios sistemas;
**alto** = migrar código existente o cambiar la arquitectura.

### Adoptar ya

| Candidato | Enlace · licencia | Godot 4.7 / GDScript | Mantenimiento | Qué resuelve | Qué reemplaza | Costo |
| --- | --- | --- | --- | --- | --- | --- |
| Monitores propios de Godot (`Performance.add_custom_monitor`) | Integrado en el motor · MIT | Sí / sí | Motor | Ver en vivo, con gráfica, saldo, nómina del próximo 15/30, puntos por hora, ánimo medio, reputación, deuda… en la pestaña Depurador → Monitores | Nada; complementa los `print` de `test_phase3` | Bajo: un script de depuración que registra monitores leyendo los autoloads |
| Advertencias de GDScript como error (`untyped_declaration`, `unsafe_*`) | Ajustes del proyecto · MIT | Sí / sí | Motor | Hace cumplir «tipado estático siempre» sin depender de revisión manual | Nada | Bajo: cambiar `project.godot` y arreglar lo que salte |
| [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit) (`gdlint`, `gdformat`) | GitHub/PyPI · MIT | 4.x (la serie 4.3.x; la sintaxis de 4.7 no está comprobada) / sí | Activo | Linter y formateador de línea de comandos, fuera del motor: estilo uniforme y nombres `snake_case`/`PascalCase` | Nada | Bajo: `pip install "gdtoolkit==4.*"` y un archivo `gdlintrc`; probar antes en una copia que no rompa con sintaxis nueva |
| [Panku Console](https://github.com/Ark2000/PankuConsole) | GitHub y Asset Library · MIT | 4.x (última 1.7.9; 4.7 sin confirmar) / sí | Activo, ~1 200 ★ | Consola en el juego para ejecutar expresiones (`Economy`, `GameClock`, `Staff`…), monitores de expresiones y registro: saltar días, dar dinero, forzar renuncias al probar hitos 38–39 | Nada | Bajo: solo desarrollo; excluirlo de la exportación. Probar primero en una rama que abra en 4.7.2 sin errores |

### Evaluar

| Candidato | Enlace · licencia | Godot 4.7 / GDScript | Mantenimiento | Qué resuelve | Qué reemplaza | Costo |
| --- | --- | --- | --- | --- | --- | --- |
| [LimboAI](https://github.com/limbonaut/limboai) | GitHub y Asset Library (4.6+) · MIT | Sí: 1.8.1 compilado con 4.7.2-stable / tareas y estados en GDScript (núcleo en C++) | Muy activo (1.6 → 1.8.1 en 2026) | Máquinas de estados jerárquicas y árboles de comportamiento con depurador visual y pizarra (*blackboard*): rutinas ricas de empleados (café, baño, reuniones, rasgos, reacción a eventos) | `OfficeCharacter.Activity` y parte de `update_routine` en `main.gd` | Medio-alto. **Riesgo móvil:** la versión GDExtension trae binarios nativos y su documentación menciona solo Linux, Windows, macOS y Web; hay que confirmar Android/iOS antes de adoptarla, o usar la versión de módulo (motor compilado a mano) |
| [Godot State Charts](https://github.com/derkork/godot-statecharts) | GitHub y Asset Library · MIT | Godot 4.0+ (0.22.5; 4.7 sin confirmar) / GDScript puro | Activo | Diagramas de estados (estados en paralelo, compuestos, transiciones con retardo y guardas) con depurador en el juego; más liviano que LimboAI y sin binarios | `OfficeCharacter.Activity` | Medio: los estados son nodos; las guardas leen expresiones, así que conviene que solo lean estado y emitan por `EventBus` |
| [Beehave](https://github.com/bitbrain/beehave) | GitHub y Asset Library · MIT | Sí: 2.9.3 dice compatible con 4.7 / GDScript | Activo | Árboles de comportamiento con depurador y monitor de rendimiento en el editor | Lo mismo que LimboAI, solo árboles | Medio. Alternativa a LimboAI si el problema de binarios en móvil se confirma |
| [Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager) | GitHub · MIT | v4 para 4.6+, v3.10 para 4.4/4.5 / GDScript | Muy activo | Tarjetas de eventos de la fase 5 (sección 10): texto con variables, 2–3 opciones, condiciones (`if`) y mutaciones que llaman a funciones de autoloads | Un sistema propio de eventos por escribir | Medio. Los textos viven en archivos `.dialogue`, no en `data/*.json`; las mutaciones deberían pasar por una fachada que emita `EventBus` en vez de tocar `Economy` directo. Evaluar contra un `data/events.json` propio, que quizá alcanza |
| [Edit Resources as Table 2](https://github.com/don-tnowe/godot-resources-as-sheets-plugin) | GitHub y Asset Library · MIT | Godot 4 (4.7 sin confirmar) / GDScript | Activo | Editar catálogos como hoja de cálculo dentro del editor, con filtros por expresión e importación/exportación CSV | Edición a mano de `furniture.json`, `contracts.json`, `staff.json` | Alto si se migra a `Resource` (`.tres`): cambia el formato de `data/`. Bajo si solo se usa su modo CSV como paso intermedio. Solo vale si el balance de la fase 5 vuelve penoso editar JSON |
| [GUT](https://github.com/bitwes/Gut) | GitHub · MIT | Sí: 9.7.1, rama `godot_4_7` / GDScript | Muy activo | Framework de pruebas con dobles (*mocks*/*stubs*), esperas por señal, runner de línea de comandos y reporte JUnit para CI | `tests/test_all.gd` y el patrón de las suites | Alto para migrar 38 partes; bajo si solo se usa para pruebas nuevas que necesiten dobles. Hoy el runner propio cumple |
| [gdUnit4](https://github.com/MikeSchulze/gdUnit4) | GitHub y Asset Library · MIT | Sí: 6.2.x corrige errores de 4.7 / GDScript y C# | Muy activo | Igual que GUT, más inspector de pruebas en el editor y aserciones fluidas | Igual que GUT | Igual que GUT. Elegir uno de los dos solo si se decide migrar |
| [Signal Lens](https://github.com/yannlemos/signal-lens) | GitHub y Asset Library · MIT | 4.3+ (4.7 sin confirmar) / GDScript | Poco movimiento | Ver en vivo las conexiones y emisiones de un nodo del árbol remoto: seleccionar `EventBus` muestra qué sistema escucha qué | Nada | Bajo, solo desarrollo |
| [Debug Menu](https://github.com/godot-extended-libraries/godot-debug-menu) (o su fork mantenido Antz Debug Menu) | GitHub y Asset Library · MIT | 4.x / GDScript | Fork activo | Superposición con FPS y tiempos de cuadro (F3): sirve para el riesgo «50 personajes caminando» de la fase 4 | Nada | Bajo, solo desarrollo |

### Descartar

| Candidato | Motivo |
| --- | --- |
| [Dialogic 2](https://github.com/dialogic-godot/dialogic) | Sigue en alfa (Alpha 20) con cambios que rompen; está hecho para novelas visuales con retratos y líneas de tiempo: demasiado para tarjetas de 2–3 opciones |
| [godot-utility-ai](https://github.com/Pennycook/godot-utility-ai) (Pennycook) y go-decide | 7 commits, sin versiones ni Godot declarado; go-decide en desarrollo. La idea (puntuar acciones con curvas) cabe en una función pura de ~50 líneas como `Production`, con los pesos en `data/` |
| [Pandora](https://github.com/bitbrain/pandora) | Alfa, sin actividad desde 2024 y pensado para inventarios de RPG; duplicaría los catálogos JSON |
| [Questify](https://github.com/TheWalruzz/godot-questify) y gestores de misiones | Los objetivos guiados ya están hechos (hito 28) con `data/objectives.json`; un grafo de misiones en `.tres` no aporta |
| Addons de guardado (savestate, SaveGuard, GodotSaveKit, RescueSlot…) | `SaveManager` ya cumple la regla `export_state`/`import_state`. Varios son de pago o nuevos y sin trayectoria. Lo útil son tres ideas que se pueden hacer en casa (ver 4.4) |
| [imgui-godot](https://github.com/pkdawson/imgui-godot) | GDExtension con binarios solo de escritorio y versión de Dear ImGui atada; Panku Console y los monitores cubren lo mismo en GDScript |
| [Easy Charts](https://github.com/fenix-hub/godot-engine.easy-charts) | Último cambio en 2024 y marcado como trabajo en curso; para gráficas del Banco o la Empresa alcanza un `Control` con `_draw()`, y para balance, los monitores del depurador |
| NavigationServer2D / addons de navegación por mallas | Las paredes van en bordes de casilla; `AStarGrid2D` a doble resolución ya lo resuelve. Una malla de navegación complicaría las puertas y la reconstrucción |
| Cualquier addon solo C# (Utility AI C#, Developer Console .NET…) | El proyecto es GDScript |

## 4. Recomendación: las 5 mejores

### 4.1 Monitores propios del depurador — adoptar ya (hito 39 y balance)

Es lo de mejor relación costo/beneficio: sin dependencias, usa el motor. Un script de depuración (por ejemplo en una
escena de herramientas, no en `res://` como prueba suelta) registra con `Performance.add_custom_monitor` el saldo, lo
que se debe, la producción por hora, el ánimo y estrés medios, la reputación y la deuda. La pestaña Monitores los grafica
mientras se juega a 4x. Beneficia el **hito 39** (comprobación de la fase 4) y cualquier ajuste de `data/staff.json`,
`data/stages.json` y `data/contracts.json`.

### 4.2 Panku Console — adoptar ya, solo desarrollo (hitos 38–39 y fase 5)

Una consola en el juego evita escribir pruebas solo para llegar a un estado: «saltar 30 días», «dar $50 000»,
«ánimo 10 a todos». Como las expresiones llaman a los autoloads, conviene exponer comandos que usen las mismas funciones
públicas (`Economy`, `Staff.give_raise`…) para no saltarse `EventBus`. Antes: abrirla en 4.7.2 en una rama de prueba y
excluir `addons/panku_console/*` del preset de exportación.

### 4.3 Tipado y estilo automáticos — adoptar ya (todos los hitos)

Subir a error la advertencia `untyped_declaration` (y revisar las `unsafe_*`) en `project.godot`, y usar `gdlint` y
`gdformat` de gdtoolkit desde la línea de comandos. Convierte en comprobación automática la regla «GDScript con tipado
estático siempre», que hoy depende de revisar a mano.

### 4.4 Mejoras de guardado hechas en casa — en vez de un addon (fase 5)

De los addons de guardado vale copiar tres ideas, sin instalarlos:

1. **Escritura atómica:** escribir en `autosave.json.tmp` y renombrar; así un cierre a mitad no deja el archivo roto.
2. **Copia de respaldo:** mantener `autosave.bak.json` con el guardado anterior y cargarlo si el actual falla.
3. **Migraciones por versión:** hoy `FORMAT_VERSION` distinto impide cargar. Una lista de funciones
   `migrate_1_to_2(state)` aplicadas en orden permitiría subir de versión sin perder partidas (la fase 4 ya pide que «una
   partida de la fase 3 cargue»; hoy se resuelve tolerando claves ausentes).

### 4.5 IA de personajes para la fase 5 — evaluar LimboAI o State Charts

Hoy la rutina es simple y el `enum` de 4 estados alcanza; adoptar ahora sería trabajo adelantado. Cuando la fase 5
agregue rasgos con efecto (noctámbulo, adicto al café, sociable), necesidades y reacciones a eventos, la rutina pasará
de 4 a 10–15 estados y ahí conviene una herramienta:

- **LimboAI** es la más completa y la más mantenida (1.8.1 compilado para 4.7.2), pero trae binarios nativos: confirmar
  la exportación a Android/iOS antes de decidir.
- **Godot State Charts** es GDScript puro, sin ese riesgo, y suficiente si la rutina es «máquina de estados con algunos
  estados en paralelo».
- **Beehave** es la alternativa en GDScript si se prefiere árbol de comportamiento.

En los tres casos la regla es la misma: el personaje decide qué hacer leyendo el estado de los autoloads, y lo que
cambia en la simulación (energía, suciedad, producción) sigue pasando por los sistemas y `EventBus`, no por el árbol.

**Para los eventos con tarjetas** (sección 10, fase 5) la decisión es aparte: probar Dialogue Manager contra un
`data/events.json` propio con condiciones y efectos declarativos. Si las tarjetas son solo texto + 2–3 opciones con
efectos numéricos, el JSON propio respeta mejor las reglas del proyecto; si se quieren textos largos con ramas, Dialogue
Manager ahorra el editor.

## 5. Qué hito o sistema se beneficia

| Recomendación | Hito o sistema |
| --- | --- |
| Monitores del depurador | Hito 39 (comprobación de la fase 4), balance de `data/` y prueba de rendimiento con 50 personajes |
| Panku Console | Hitos 38–39 y la fase 5 (probar eventos, productos y salir a bolsa sin jugar horas) |
| Tipado y estilo automáticos | Todos los hitos siguientes |
| Guardado atómico, respaldo y migraciones | `SaveManager`; partidas viejas en cada fase nueva |
| LimboAI / State Charts / Beehave | `OfficeCharacter`, `Employee`, `main.gd` en la fase 5 (rasgos, ambiente, necesidades) |
| Dialogue Manager o `data/events.json` propio | Eventos con tarjetas y cuenta atrás (fase 5, sección 10) |
| GUT o gdUnit4 | Solo si se quiere CI con reporte JUnit o dobles de prueba; el runner propio sigue sirviendo |

## 6. Advertencias

- Varias compatibilidades con 4.7 salen de notas de versión o del README y no se probaron aquí (marcadas «sin
  confirmar»). Antes de adoptar cualquiera, abrirla en una rama con Godot 4.7.2 y correr `tests/test_all.tscn`.
- Ningún addon debe guardar estado propio fuera de `export_state()`/`import_state()`; si lo hace (por ejemplo, la
  pizarra de LimboAI), hay que exportarlo desde el sistema que lo use.
- Los addons de desarrollo se excluyen del preset de exportación para no inflar la build móvil.

## Fuentes

- LimboAI: [repositorio](https://github.com/limbonaut/limboai), [versiones](https://github.com/limbonaut/limboai/releases), [Asset Library 4.6+](https://godotengine.org/asset-library/asset/4852)
- Beehave: [repositorio](https://github.com/bitbrain/beehave), [versiones](https://github.com/bitbrain/beehave/releases)
- Godot State Charts: [repositorio](https://github.com/derkork/godot-statecharts), [Asset Library](https://godotengine.org/asset-library/asset/1778)
- godot-utility-ai: [repositorio](https://github.com/Pennycook/godot-utility-ai)
- Dialogue Manager: [repositorio](https://github.com/nathanhoad/godot_dialogue_manager)
- Dialogic: [versiones](https://github.com/dialogic-godot/dialogic/releases)
- GUT: [repositorio](https://github.com/bitwes/Gut), [documentación](https://gut.readthedocs.io/)
- gdUnit4: [repositorio](https://github.com/MikeSchulze/gdUnit4), [versiones](https://github.com/MikeSchulze/gdUnit4/releases)
- Edit Resources as Table 2: [repositorio](https://github.com/don-tnowe/godot-resources-as-sheets-plugin)
- Pandora: [repositorio](https://github.com/bitbrain/pandora)
- Questify: [Asset Library](https://godotengine.org/asset-library/asset/2674)
- Panku Console: [repositorio](https://github.com/Ark2000/PankuConsole), [versiones](https://github.com/Ark2000/PankuConsole/releases)
- Signal Lens: [listado](https://project-awesome.org/r/yannlemos-signal-lens); SignalVisualizer: [repositorio](https://github.com/Ericdowney/SignalVisualizer)
- Debug Menu: [repositorio](https://github.com/godot-extended-libraries/godot-debug-menu)
- imgui-godot: [repositorio](https://github.com/pkdawson/imgui-godot)
- gdtoolkit: [repositorio](https://github.com/Scony/godot-gdscript-toolkit), [PyPI](https://pypi.org/project/gdtoolkit)
- Easy Charts: [repositorio](https://github.com/fenix-hub/godot-engine.easy-charts)
- Guardado: [savestate](https://gh.r-mj.com/youssof20/savestate), [SaveGuard](https://forum.godotengine.org/t/saveguard-save-slots-migrations-and-corruption-recovery-for-godot-4/145403), [versionado de guardados](https://uhiyama-lab.com/en/notes/godot/save-data-versioning-migration/)
