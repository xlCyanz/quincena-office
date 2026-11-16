# Quincena Office: documento de diseño

Nov 11, 2026 · @Johan Ezequiel Sierra Linares

Este documento reúne las decisiones de diseño tomadas hasta ahora, en trece secciones, más las ideas para versiones futuras y el plan de desarrollo de la primera fase.

## Índice

- [1. Visión general](#m0x07y26p1s.11888)
- [2. Construcción y decoración](#m0x07y26p1s.71)
  - [2.1 Tipos de habitación](#m0x07y26p1s.915)
  - [2.2 Alcance de la primera versión](#m0x07y26p1s.1306)
- [3. Escala y terreno](#m0x07y26p1s.3688)
  - [3.1 Compra de terreno](#m0x07y26p1s.4135)
- [4. Jerarquía y departamentos](#m0x07y26p1s.4798)
  - [4.1 Departamentos](#m0x07y26p1s.8968)
- [5. Empleados](#m0x07y26p1s.6072)
  - [5.1 Roles de apoyo](#m0x07y26p1s.8603)
  - [5.2 Contratación](#m0x07y26p1s.18421)
  - [5.3 Despidos y renuncias](#m0x07y26p1s.19397)
- [6. Equipos y horarios](#m0x07y26p1s.1531)
  - [6.1 Reloj y calendario](#m0x07y26p1s.13757)
  - [6.2 Horas extra](#m0x07y26p1s.14321)
- [7. Ingresos y proyectos](#m0x07y26p1s.5581)
  - [7.1 Contratos de clientes](#m0x07y26p1s.15380)
  - [7.2 Avance del trabajo](#m0x07y26p1s.16092)
  - [7.3 Errores](#m0x07y26p1s.16548)
  - [7.4 Entrega](#m0x07y26p1s.16968)
  - [7.5 Productos propios](#m0x07y26p1s.17234)
- [8. Banco](#m0x07y26p1s.9682)
  - [8.1 Cuenta empresarial](#m0x07y26p1s.9827)
  - [8.2 Préstamos](#m0x07y26p1s.10055)
  - [8.3 Calificación de crédito](#m0x07y26p1s.10728)
  - [8.4 Atrasos y embargo](#m0x07y26p1s.11042)
- [9. Metas y progresión](#m0x07y26p1s.20750)
  - [9.1 Etapas de la empresa](#m0x07y26p1s.20882)
  - [9.2 Reputación](#m0x07y26p1s.21678)
  - [9.3 Valor de la empresa](#m0x07y26p1s.21885)
  - [9.4 Objetivos guiados](#m0x07y26p1s.22080)
  - [9.5 Final: salir a bolsa](#m0x07y26p1s.22314)
- [10. Eventos](#m0x07y26p1s.23334)
  - [10.1 Reglas](#m0x07y26p1s.23478)
  - [10.2 Lista inicial de eventos](#m0x07y26p1s.24116)
- [11. Catálogo de muebles](#m0x07y26p1s.27035)
  - [11.1 Reglas](#m0x07y26p1s.27185)
  - [11.2 Lista de objetos](#m0x07y26p1s.27775)
- [12. Interfaz](#m0x07y26p1s.31526)
  - [12.1 Principios](#m0x07y26p1s.31648)
  - [12.2 Elementos siempre visibles](#m0x07y26p1s.32296)
  - [12.3 Menús](#m0x07y26p1s.32970)
  - [12.4 Ficha de empleado](#m0x07y26p1s.33614)
  - [12.5 Guardado](#m0x07y26p1s.33850)
- [13. Economía](#m0x07y26p1s.12514)
  - [13.1 Punto de partida](#m0x07y26p1s.35136)
  - [13.2 Salarios mensuales](#m0x07y26p1s.35487)
  - [13.3 Producción](#m0x07y26p1s.35950)
  - [13.4 Contratos](#m0x07y26p1s.36257)
  - [13.5 Productos propios](#m0x07y26p1s.36686)
  - [13.6 Banco](#m0x07y26p1s.37000)
  - [13.7 Precios de muebles](#m0x07y26p1s.37438)
  - [13.8 Comprobación](#m0x07y26p1s.37928)
- [14. Ideas para versiones futuras](#m0x07y26p1s.25847)

* [15. Plan de desarrollo: fase 1](#m0x07y26p1s.39696)
  - [15.1 Alcance](#m0x07y26p1s.39952)
  - [15.2 Decisiones técnicas](#m0x07y26p1s.40509)
  - [15.3 Estructura de carpetas](#m0x07y26p1s.41784)
  - [15.4 Hitos](#m0x07y26p1s.42264)
  - [15.5 Orden y dependencias](#m0x07y26p1s.44370)
  - [15.6 Cómo trabajar con Claude Code](#m0x07y26p1s.44770)
  - [15.7 Riesgos de esta fase](#m0x07y26p1s.45295)
* [16. Plan de desarrollo: fase 2](#16-plan-de-desarrollo-fase-2)
  - [16.1 Alcance](#161-alcance)
  - [16.2 Decisiones técnicas](#162-decisiones-técnicas)
  - [16.3 Hitos](#163-hitos)
  - [16.4 Orden y dependencias](#164-orden-y-dependencias)
  - [16.5 Riesgos de esta fase](#165-riesgos-de-esta-fase)
  - [16.6 Fases siguientes](#166-fases-siguientes)
* [17. Plan de desarrollo: fase 3](#17-plan-de-desarrollo-fase-3)
  - [17.1 Alcance](#171-alcance)
  - [17.2 Decisiones técnicas](#172-decisiones-técnicas)
  - [17.3 Hitos](#173-hitos)
  - [17.4 Orden y dependencias](#174-orden-y-dependencias)
  - [17.5 Riesgos de esta fase](#175-riesgos-de-esta-fase)
* [18. Plan de desarrollo: fase 4](#18-plan-de-desarrollo-fase-4)
  - [18.1 Alcance](#181-alcance)
  - [18.2 Decisiones técnicas](#182-decisiones-técnicas)
  - [18.3 Hitos](#183-hitos)
  - [18.4 Orden y dependencias](#184-orden-y-dependencias)
  - [18.5 Riesgos de esta fase](#185-riesgos-de-esta-fase)
* [19. Plan de desarrollo: fase 5](#19-plan-de-desarrollo-fase-5)
  - [19.1 Alcance](#191-alcance)
  - [19.2 Decisiones técnicas](#192-decisiones-técnicas)
  - [19.3 Hitos](#193-hitos)
  - [19.4 Orden y dependencias](#194-orden-y-dependencias)
  - [19.5 Riesgos de esta fase](#195-riesgos-de-esta-fase)
* [20. Plan de desarrollo: fase 6](#20-plan-de-desarrollo-fase-6)
  - [20.1 Alcance](#201-alcance)
  - [20.2 Decisiones técnicas](#202-decisiones-técnicas)
  - [20.3 Hitos](#203-hitos)
  - [20.4 Orden y dependencias](#204-orden-y-dependencias)
  - [20.5 Riesgos de esta fase](#205-riesgos-de-esta-fase)
* [21. Plan de desarrollo: fase 7](#21-plan-de-desarrollo-fase-7)
  - [21.1 Alcance](#211-alcance)
  - [21.2 Decisiones técnicas](#212-decisiones-técnicas)
  - [21.3 Hitos](#213-hitos)
  - [21.4 Orden y dependencias](#214-orden-y-dependencias)
  - [21.5 Riesgos de esta fase](#215-riesgos-de-esta-fase)

## 1. Visión general

El jugador es el CEO de una empresa de tecnología y software: contrata empleados, arma su oficina, toma contratos, paga la nómina y hace crecer la empresa sin que el banco la embargue.

| Aspecto | Decisión |
| --- | --- |
| Nombre | Quincena Office |
| Género | Gestión de oficina en pixel art |
| Vista | Isométrica |
| Plataforma | Solo escritorio (macOS, Windows y Linux) |
| Motor | Godot 4, desarrollado con Claude Code |
| Arte | Muebles y sprites generados por Claude Code mediante MCP con una herramienta de arte |
| Tiempo | Reloj de 24 horas con pausa y velocidades |
| Tono | Mezcla de gestión seria y humor de oficina |
| Derrota | Embargo total de la empresa por el banco |

## 2. Construcción y decoración

El jugador decora la oficina y organiza las habitaciones sobre la cuadrícula isométrica.

- **Modo construcción:** al entrar, el tiempo se pausa. Herramientas: paredes, pisos, puertas, muebles, rotar y vender (se recupera parte del precio).
- **Habitaciones:** el jugador coloca las paredes pieza por pieza. Cuando un espacio queda cerrado y con puerta, el juego lo detecta como habitación y se le asigna un tipo. Cada tipo exige un tamaño mínimo y ciertos muebles para funcionar.
- **Puesto de trabajo:** escritorio + silla + computadora. La calidad de la computadora (básica, media, pro) afecta la velocidad de quien se sienta ahí.
- **Decoración:** plantas, cuadros, alfombras e iluminación suben el "ambiente" de la habitación, que a su vez sube el ánimo. Amontonar escritorios lo baja.
- **Expansión:** la empresa nunca se muda. Se empieza con un local pequeño y se amplía el mismo comprando terreno adyacente; el jugador decide cuántos metros compra y paga según la cantidad.

### 2.1 Tipos de habitación

| Habitación | Cantidad | Función |
| --- | --- | --- |
| Oficina Ejecutiva | Una sola, obligatoria | Oficina del CEO; donde atiende eventos y clientes. Funciona con dos sillas: la suya y una de visita, donde se sienta el entrevistado |
| Oficina única | Varias | Oficina individual para altos cargos. Como la Ejecutiva, necesita una silla de visita además de la de quien la usa |
| Sala de reuniones | Varias | Necesaria para cerrar contratos grandes |
| Baños | Varios; mínimo dos obligatorios, uno por sexo | Necesidad básica de los empleados |
| Sala de descanso y cafetería | Una sola | Recupera energía y ánimo |
| Área de trabajo | Varias | Escritorios; donde se produce |
| Sala de servidores | Una sola | Requisito para productos propios |
| Recepción | Una sola, obligatoria | Contiene la puerta de entrada de la oficina; solo se puede colocar junto a una pared exterior. Puesto del recepcionista. Su puerta de entrada se puede cambiar por la puerta doble de vidrio (21.6) |

### 2.2 Alcance de la primera versión

Este es el sistema más caro de programar de todo el juego. La primera versión incluye paredes libres pieza por pieza desde el inicio, en lugar de habitaciones rectangulares con paredes automáticas. Por su costo, conviene construirlo y probarlo antes que los demás sistemas.

## 3. Escala y terreno

1 metro equivale a 1 casilla isométrica de 64×32 píxeles; todo el arte se dibuja a esa escala.

| Elemento | Tamaño |
| --- | --- |
| Casilla de piso (1 m²) | 64×32 px |
| Empleado de pie | Unos 32×64 px; ocupa 1 casilla |
| Escritorio con computadora | 1 casilla (2 si es grande) |
| Altura de pared | Unos 96 px |
| Oficina inicial de 6×8 m | 48 casillas |

En Godot 4, el TileMapLayer va en modo isométrico con casilla de 64×32 y filtro de texturas "Nearest".

### 3.1 Compra de terreno

- **Unidad:** 1 casilla = 1 m². El jugador elige un lado del local (norte, sur, este u oeste) y escribe ancho × fondo, por ejemplo 4 × 3 = 12 m². El juego muestra la vista previa del terreno y calcula cuánto dinero cuesta esa expansión antes de confirmar.
- **Adyacencia:** solo se compra terreno que toque el local actual, para que no queden islas sueltas.
- **Costo:** un pago único por metro, más un aumento del gasto mensual proporcional a los metros totales.
- **Límite:** el solar tiene un tamaño máximo, que es el tope de crecimiento del juego.

## 4. Jerarquía y departamentos

La empresa tiene cinco niveles: CEO, ejecutivos, gerentes, líderes de equipo y empleados.

| Cargo | A quién dirige | Dónde trabaja |
| --- | --- | --- |
| CEO (el jugador) | Toda la empresa | Oficina Ejecutiva |
| Ejecutivo | Su departamento completo, sin límite de empleados | Oficina única |
| Gerente | Hasta 5 líderes de equipo y sus equipos | Oficina única |
| Líder de equipo | Un equipo de hasta 10 empleados | Área de trabajo, junto a su equipo |
| Empleado | Nadie | Área de trabajo |

- **Capacidad:** un líder de equipo cubre hasta 10 empleados y un gerente hasta 5 líderes de equipo. Cada ejecutivo tiene su propia oficina y dirige su departamento completo, sin límite de empleados por ahora.
- **Niveles vacíos:** si un departamento existe y no tiene ejecutivo, el CEO se hace cargo de él. Al inicio el jugador dirige todos los departamentos; al crecer, contrata ejecutivos y delega.
- **Ascensos:** un Senior puede ascender a líder de equipo sin requisitos adicionales de experiencia, siempre que haya una vacante; al ascender sube de cargo y de sueldo.

### 4.1 Departamentos

Hay cuatro departamentos, cada uno con su ejecutivo. Un departamento existe desde que tiene al menos un empleado.

| Departamento | Quiénes lo forman |
| --- | --- |
| Desarrollo | Programadores y QA |
| Diseño | Diseñadores |
| Ventas | Vendedores y recepcionistas |
| Administración | Contadores y limpieza |

Mientras más departamentos dirige el CEO personalmente, peor rinde cada uno. Un ejecutivo devuelve su departamento al 100% y le suma una ventaja según su habilidad.

| Departamentos a cargo del CEO | Rendimiento de cada uno |
| --- | --- |
| 1 | 100% |
| 2 | 85% |
| 3 | 70% |
| 4 | 55% |

## 5. Empleados

Cada empleado tiene una ficha con rasgos de personalidad, nivel y datos de su trabajo. Lo siguiente es una propuesta por revisar.

| Bloque de la ficha | Contenido |
| --- | --- |
| Identidad | Nombre, sexo, edad y apariencia |
| Cargo y especialidad | Programador, diseñador, QA, vendedor, servicio al cliente (recepcionista), contabilidad o limpieza |
| Nivel | Pasante, Junior, SemiSenior y Senior |
| Habilidades (1–100) | Programación, diseño, pruebas, ventas y liderazgo |
| Desempeño | Velocidad, calidad (menos errores) y puntualidad |
| Estado | Energía, ánimo y estrés |
| Contrato | Salario, antigüedad, horario, equipo y puesto asignado |
| Rasgos | De 1 a 3 por empleado |
| Historial | Proyectos entregados, errores causados y ausencias |

- **Experiencia:** para subir de nivel (Pasante → Junior → SemiSenior → Senior) el empleado debe cumplir dos requisitos: proyectos trabajados y tiempo de juego en la empresa (propuesta: 3 proyectos y 30 días para Junior, 8 y 90 para SemiSenior, 15 y 180 para Senior). Cumplidos, el jugador decide si lo asciende y con qué sueldo. Para los vendedores, en lugar de proyectos cuentan las ventas cerradas. Recepcionistas, contadores y personal de limpieza no tienen niveles por ahora; solo se les puede subir el sueldo.
- **Rasgos de ejemplo:** noctámbulo (rinde más de noche), perfeccionista (más lento, menos errores), adicto al café, sociable (sube el ánimo del equipo, se distrae), impuntual, mentor (acelera a los juniors), ambicioso (pide ascensos) y leal (difícilmente renuncia).
- **Candidatos:** al contratar se ve parte de la ficha; los rasgos se descubren con el tiempo.
- **Renuncias:** un empleado con ánimo bajo o estrés alto por mucho tiempo se va.

### 5.1 Roles de apoyo

| Rol | Qué aporta |
| --- | --- |
| Recepcionista | Atiende a los clientes que visitan la oficina; sin él se pierden contratos |
| Contador | Reduce gastos y evita multas por errores en la nómina |
| Limpieza | Mantiene la oficina limpia; la suciedad baja el ánimo |

### 5.2 Contratación

La partida empieza con el CEO solo, en un local pequeño con su oficina. Todo lo demás se contrata.

- **Vacante:** el jugador elige el cargo, el nivel y el sueldo que ofrece. Publicarla es gratis; con publicidad cuesta $100 y atrae más candidatos. En los días siguientes llegan candidatos; llegan más y mejores con buena reputación, buen sueldo y buen ambiente en la oficina.
- **Requisito:** hace falta un puesto de trabajo libre. Un gerente o un ejecutivo necesitan su oficina.
- **Lo que se ve del candidato:** nombre, cargo, nivel, sueldo que pide y habilidades en rangos aproximados.
- **Lo que no se ve:** sus rasgos de personalidad y sus valores exactos.
- **Entrevista:** opcional. Se cita para el próximo día en que trabaja quien la hace, a su hora de entrada (el CEO a las 8:00); si ya hay citas ese día, en el siguiente hueco de media hora antes de su almuerzo. El candidato citado no se va mientras espera su cita; ese día llega entre 10 y 25 minutos antes, espera de pie en la Recepción (o junto a la entrada) y a la hora camina a la silla de visita de la oficina de quien lo entrevista; la entrevista empieza cuando se sienta (si no llega en hora y media, empieza igual). Si quien entrevista no está dos horas después de la hora citada, la cita se cancela con aviso y se lo puede volver a citar. Ocupa media hora de juego de quien la hace, desde el minuto en que empieza (el CEO rinde la mitad de esa hora); se va al terminar, y revela un rasgo y los valores reales. Al inicio las hace el CEO; cuando hay un ejecutivo de Administración, el jugador puede delegárselas y las hace él.
- **Caducidad:** un candidato espera pocos días; después lo contrata otra empresa.
- **Oferta:** si el sueldo propuesto iguala o supera lo que pide, acepta. Si queda por debajo, puede rechazar o hacer una contraoferta.

### 5.3 Despidos y renuncias

- **Despido:** cuesta el sueldo que el empleado lleva ganado hasta ese día. Además baja el ánimo de sus compañeros, más si se despide a varios seguidos.
- **Por qué renuncian:** ánimo bajo o estrés alto por mucho tiempo, sueldo por debajo de lo que vale su nivel, nómina sin pagar o un ascenso negado.
- **Aviso:** el empleado avisa unos días antes. En ese plazo el jugador puede retenerlo con un aumento o un ascenso, si corresponde.
- **Aumentos:** de vez en cuando alguien pide aumento; negarlo le baja el ánimo.
- **Competencia:** a veces otra empresa le hace una oferta a un buen empleado. El rasgo "leal" lo protege; el "ambicioso" lo hace más probable.

## 6. Equipos y horarios

Los horarios se asignan por equipo o por empleado, sobre un reloj de 24 horas.

- **Turnos:** plantillas con nombre, hora de entrada, hora de salida y días (por ejemplo "Diurno 8–17, lun–vie").
- **Equipos:** grupos de empleados con un turno, un líder de equipo y un proyecto asignados.
- **Individual:** cualquier empleado puede tener un horario propio que reemplaza el de su equipo.
- **Supervisión real:** el líder de equipo solo cuenta mientras su horario coincide con el del equipo. Un turno de noche sin jefe rinde menos.
- **Turno nocturno:** cuesta un extra de salario y desgasta más el ánimo.
- **Vista de agenda:** pantalla tipo calendario para ver quién trabaja a qué hora y detectar huecos.

### 6.1 Reloj y calendario

Un día de juego dura 24 minutos reales a velocidad normal: cada hora del reloj es 1 minuto real (antes 10 segundos; cambiado después del hito 69). Una quincena dura 6 horas reales a 1x y 1 h 30 min a 4x; con la oficina vacía el reloj salta a la próxima llegada.

| Elemento | Valor |
| --- | --- |
| Reloj | 24 horas, visible siempre junto con el día y la fecha |
| Velocidades | Pausa, 1x, 2x, 4x, 8x y 16x (las dos últimas, agregadas en la fase 8) |
| Un día de juego | 4 minutos a 1x; 1 minuto a 4x |
| Mes | 30 días (1 hora real a 1x) |
| Nómina | Cada 15 días: los días 15 y 30 de cada mes |
| Gastos mensuales y cuotas del banco | Día 1 de cada mes |
| Jornada normal | 8 horas, con pausa de almuerzo |
| Horario y días de trabajo | Los decide el jugador; cada empleado debe tener al menos 1 día de descanso por semana |

Cuando la oficina queda vacía, el tiempo salta solo hasta la próxima hora de entrada.

### 6.2 Horas extra

Las horas que pasan de la jornada de 8 horas son horas extra.

- **Pago:** cada hora extra se paga a 1.5 veces la hora normal y se suma a la nómina siguiente.
- **Límite:** hasta 4 horas extra por día por empleado.
- **Desgaste:** bajan la energía y el ánimo, y suben el estrés. Un empleado agotado trabaja más lento y comete más errores.
- **Quién las asigna:** el jugador, al definir el turno de un equipo o el horario de un empleado.

## 7. Ingresos y proyectos

El dinero entra por contratos de clientes y por productos propios.

- **Contratos:** pago único al entregar, con fecha límite y requisitos de programación, diseño y pruebas. Entregar tarde tiene penalidad y baja la reputación.
- **Productos propios:** se desarrollan, se lanzan y generan ingreso diario. Requieren sala de servidores y mantenimiento; sin actualizaciones, el ingreso decae.
- **Progresión:** contratos al inicio para sobrevivir; productos propios como meta a mediano plazo.

### 7.1 Contratos de clientes

- **Cómo llegan:** aparecen ofertas en una bandeja. Cuántas y de qué tamaño depende de la reputación y de los vendedores. Algunos clientes visitan la oficina; sin recepcionista, se van.
- **Qué trae cada oferta:** cliente, tipo de proyecto (sitio web, app móvil, tienda en línea, sistema interno), tamaño, plazo en días, pago y penalidad por atraso.
- **Trabajo requerido:** tres barras de puntos: diseño, programación y pruebas.
- **Anticipo:** algunos contratos pagan un anticipo al aceptar (propuesta: 30%) y el resto al entregar; otros pagan todo al entregar. Si se cancela un contrato con anticipo, hay que devolverlo.
- **Requisitos:** los contratos grandes exigen sala de reuniones y cierta reputación.

### 7.2 Avance del trabajo

- **Asignación:** el jugador asigna el proyecto a un equipo. Un equipo trabaja en un proyecto a la vez.
- **Producción:** cada empleado genera puntos por hora trabajada en su especialidad. Influyen su nivel, habilidad, energía, ánimo, la calidad de su computadora y si su líder de equipo está presente.
- **Fases:** diseño, luego programación, luego pruebas, en orden y con solapamiento: una fase puede empezar cuando la anterior va por la mitad.

### 7.3 Errores

- **De dónde salen:** al programar se generan errores ocultos. Salen más con empleados cansados, de bajo nivel o de poca calidad.
- **Quién los quita:** QA los encuentra durante la fase de pruebas y los programadores los corrigen. Sin QA, casi todos llegan al cliente.
- **Qué cuestan:** entregar con errores reduce el pago final y la reputación. El jugador decide cuándo entregar: a tiempo con errores, o tarde y limpio.

### 7.4 Entrega

| Resultado | Consecuencia |
| --- | --- |
| A tiempo y limpio | Pago completo y sube la reputación |
| A tiempo con errores | Pago reducido y baja la reputación |
| Tarde | Penalidad por cada día de atraso |
| Cancelado | Se devuelve el anticipo, si lo hubo, y cae la reputación |

### 7.5 Productos propios

- **Desarrollo:** el jugador elige tipo y tamaño. Se construye igual que un contrato, pero sin cliente, sin plazo y sin anticipo: la empresa lo paga todo hasta lanzarlo.
- **Requisito:** sala de servidores. Su capacidad limita cuántos productos y usuarios se pueden sostener.
- **Lanzamiento:** el producto empieza a dar ingreso diario, según su calidad (diseño y pocos errores) y los vendedores.
- **Ciclo de vida:** los usuarios crecen, se estancan y luego caen. Una actualización, que es un proyecto pequeño, lo reaviva.
- **Errores en producción:** los que se colaron hacen perder usuarios hasta que se corrigen.

## 8. Banco

El banco guarda todo el dinero de la empresa, presta, y embarga si no se le paga. Se accede desde un botón del menú; no es una habitación.

### 8.1 Cuenta empresarial

Hay una sola cuenta con todo el dinero. Ahí entran los pagos de contratos y productos, y de ahí salen la nómina, el alquiler, las compras y las cuotas. El banco muestra el saldo y el historial de movimientos.

### 8.2 Préstamos

- **Solicitud:** el jugador elige el monto y el plazo en meses. El juego muestra la tasa de interés, la cuota mensual y el total a pagar antes de aceptar.
- **Cuota:** se cobra sola cada mes, el mismo día que el alquiler.
- **Límite:** cuánto presta el banco depende de la calificación de crédito.
- **Pago anticipado:** se puede saldar antes y ahorrar parte de los intereses.
- **Refinanciar:** una sola vez por préstamo se puede alargar el plazo para bajar la cuota, a cambio de una tasa más alta.
- **Préstamo de emergencia:** si el día de nómina no hay dinero, el banco ofrece un préstamo rápido con tasa muy alta. Rechazarlo significa no pagar la nómina, con golpe al ánimo y renuncias.

### 8.3 Calificación de crédito

Una nota de la A a la E calculada con los ingresos mensuales, el valor de los bienes, la antigüedad de la empresa y el historial de pagos. Sube pagando puntual y cae con cada atraso. Con un contador en nómina se consiguen mejores tasas y un aviso antes de una cuota que no se podrá cubrir.

### 8.4 Atrasos y embargo

| Situación | Consecuencia |
| --- | --- |
| 1 cuota atrasada | Recargo por mora y baja la calificación |
| 2 cuotas seguidas | Aviso de embargo; el banco no presta más |
| 3 cuotas seguidas | Embargo |

- **Qué se evalúa:** el banco suma el valor de reventa de todos los muebles y equipos de la oficina y lo compara con la deuda del préstamo.
- **Si alcanza:** se lleva muebles hasta cubrir la deuda, el préstamo queda saldado y la partida sigue. Se lleva primero la decoración y deja los puestos de trabajo para el final.
- **Si no alcanza:** el banco embarga la empresa completa y el jugador pierde la partida.
- **Terreno:** no entra en el embargo.

El embargo total es la única forma de perder. No pagar la nómina cuesta ánimo y renuncias, pero no termina la partida.

## 9. Metas y progresión

La empresa crece por cinco etapas que van desbloqueando el juego, con una meta final opcional: salir a bolsa.

### 9.1 Etapas de la empresa

Los números son una propuesta inicial y se ajustan al definir la economía.

| Etapa | Requisito para llegar | Qué desbloquea |
| --- | --- | --- |
| 1. Emprendimiento | Inicio de la partida | CEO solo, contratos pequeños, préstamos pequeños |
| 2. Startup | 5 empleados y 3 contratos entregados | Líderes de equipo, contratos medianos |
| 3. Pequeña empresa | 15 empleados y 2 equipos completos | Gerentes, oficinas únicas, sala de servidores, productos propios |
| 4. Mediana empresa | 40 empleados y 1 producto lanzado | Ejecutivos, contratos grandes, préstamos grandes |
| 5. Corporación | 4 ejecutivos y 3 productos activos | Tamaño máximo del solar, clientes de élite |

La sala de reuniones no depende de la etapa: aparece para construir solo cuando llega el primer contrato que amerita una reunión, no antes.

### 9.2 Reputación

Una nota de 1 a 5 estrellas. Sube al entregar a tiempo y sin errores, y baja con atrasos, errores y cancelaciones. Determina qué clientes ofrecen contratos y qué tan buenos candidatos llegan.

### 9.3 Valor de la empresa

Un número siempre visible que funciona como puntuación: el dinero en la cuenta, más el valor de los bienes, más lo que generan los productos, menos la deuda con el banco.

### 9.4 Objetivos guiados

Una lista corta de tareas que cambia según el avance, como "contrata a tu primer programador" o "entrega tu primer contrato". Hace de tutorial sin interrumpir, y cada objetivo cumplido da una recompensa pequeña.

### 9.5 Final: salir a bolsa

Cuando la empresa es Corporación y su valor supera los $5,000,000, el jugador puede salir a bolsa. Ve una pantalla de cierre con sus estadísticas (días jugados, empleados contratados, proyectos entregados) y después sigue jugando en modo libre.

## 10. Eventos

Los eventos son situaciones que aparecen de vez en cuando como una tarjeta con un texto corto y, casi siempre, dos o tres opciones.

### 10.1 Reglas

- **Respuesta:** el tiempo sigue corriendo y el jugador tiene al menos 2 minutos reales para elegir, sin importar la velocidad del juego. Si no elige, el juego toma una opción al azar.
- **Cuándo no ocurren:** no aparecen eventos con el juego en pausa ni en modo construcción.
- **Frecuencia:** uno cada pocos días al inicio; más seguidos mientras más grande es la empresa.
- **Dependen del estado de la oficina:** con empleados agotados salen más eventos de errores; sin contador, más problemas de impuestos; sin limpieza, más problemas de higiene.
- **Se pueden prevenir:** los roles de apoyo y ciertos muebles reducen o anulan eventos malos.
- **Balance:** más o menos mitad buenos y mitad malos.

### 10.2 Lista inicial de eventos

| Categoría | Evento | Opciones o efecto |
| --- | --- | --- |
| Empleados | Despliegue de viernes: un junior rompió producción a las 5 de la tarde | Todos se quedan a arreglarlo (horas extra) o se arregla el lunes (se pierden usuarios) |
| Empleados | Cumpleaños en la oficina | Comprar bizcocho (sube el ánimo) o ignorarlo (baja un poco) |
| Empleados | Guerra por el aire acondicionado | Mediar (horas del CEO) o dejarlo pasar (baja el ánimo de dos empleados) |
| Empleados | Se acabó el café | Compra de emergencia más cara, o los adictos al café rinden menos ese día |
| Empleados | La reunión que pudo ser un correo | Un equipo pierde dos horas; con un buen líder de equipo no ocurre |
| Clientes | El cliente cambia los requisitos a mitad del proyecto | Aceptar (más trabajo, mismo pago), negociar (más pago y plazo) o negarse (baja la reputación) |
| Clientes | El cliente se atrasa con el pago | Esperar, o mandar al contador a cobrar |
| Clientes | Un cliente satisfecho recomienda la empresa | Llega una oferta mejor de lo normal |
| Técnicos | Apagón | Se pierde el trabajo del día, salvo que haya baterías de respaldo |
| Técnicos | Se cae el servidor | Los productos pierden usuarios hasta que un programador lo levanta |
| Técnicos | Se daña una computadora | Reparar (barato, tarda) o reemplazar (caro, inmediato) |
| Negocio | Inspección de impuestos | Con contador, pasa sin problemas; sin contador, multa |
| Negocio | Un competidor lanza un producto parecido | El producto pierde usuarios; una actualización los recupera |
| Negocio | Premio de la industria | Sube la reputación y llegan mejores candidatos |
| Oficina | Baño dañado | Baja el ánimo hasta pagar la reparación |
| Oficina | Oficina sucia | Solo ocurre sin personal de limpieza; baja el ánimo de todos |

## 11. Catálogo de muebles

El catálogo tiene unos 40 objetos, que son también la lista de arte por generar. Los precios se fijan al definir la economía.

### 11.1 Reglas

- **Datos de cada objeto:** precio, tamaño en casillas, habitación donde se permite, efecto y valor de reventa, que es el que cuenta el banco en un embargo.
- **Rotación:** todos se pueden girar en las 4 direcciones.
- **Calidades:** los objetos clave vienen en básico, medio y pro. Mejor calidad cuesta más y da más efecto.
- **Silla y escritorio:** son objetos separados; el jugador coloca cada uno.
- **Computadora:** no es un objeto suelto. Se instala sobre un escritorio y se mejora desde ahí.
- **Estructura:** paredes, puertas, ventanas (suben el ambiente), la puerta doble de vidrio de la entrada (21.6) y tres pisos: alfombra, madera y cerámica.

### 11.2 Lista de objetos

| Categoría | Objeto | Tamaño | Efecto |
| --- | --- | --- | --- |
| Puesto de trabajo | Escritorio sencillo | 1 casilla | Un puesto de trabajo |
| Puesto de trabajo | Escritorio largo | 2 casillas | Un puesto; admite hasta 2 pantallas extra con computadora pro |
| Puesto de trabajo | Escritorio ejecutivo | 2 casillas | Para oficinas del CEO, ejecutivos y gerentes |
| Puesto de trabajo | Silla básica / ergonómica | 1 casilla | La ergonómica hace que la energía baje más lento |
| Puesto de trabajo | Computadora básica / media / pro | Sobre el escritorio | Velocidad de trabajo |
| Puesto de trabajo | Segundo monitor | Sobre el escritorio | Pequeño extra de velocidad |
| Recepción | Mostrador de recepción | 2 casillas | Puesto del recepcionista; obligatorio en la recepción |
| Recepción | Sofá de espera | 2 casillas | Los clientes esperan más antes de irse |
| Reuniones | Mesa de reuniones | 4 casillas | Obligatoria en la sala de reuniones |
| Reuniones | Pizarra | En pared | Las reuniones duran menos |
| Reuniones | Pantalla de presentaciones | En pared | Mejora las probabilidades de cerrar un contrato |
| Descanso y cafetería | Cafetera | 1 casilla | Recupera energía; imprescindible para los adictos al café |
| Descanso y cafetería | Nevera y microondas | 1 casilla cada uno | Permiten almorzar en la oficina; el almuerzo dura menos |
| Descanso y cafetería | Mesa de comedor | 2 casillas | Asientos para almorzar |
| Descanso y cafetería | Sofá | 2 casillas | Recupera energía en los descansos |
| Descanso y cafetería | Dispensador de agua | 1 casilla | Pequeña mejora de ánimo |
| Descanso y cafetería | Mesa de ping pong | 4 casillas | Sube mucho el ánimo, pero la gente se distrae |
| Descanso y cafetería | Máquina expendedora | 1 casilla | Sube el ánimo y da un ingreso mínimo |
| Baños | Inodoro y lavamanos | 1 casilla cada uno | Obligatorios en cada baño; un inodoro por cada 10 empleados |
| Servidores | Rack de servidores | 1 casilla | Capacidad para productos y usuarios |
| Servidores | Baterías de respaldo | 1 casilla | Anulan el evento de apagón |
| Servicios | Aire acondicionado | En pared | Sube el ánimo de la habitación; obligatorio en la sala de servidores |
| Servicios | Impresora | 1 casilla | Los contadores trabajan más rápido |
| Servicios | Archivero | 1 casilla | Reduce las multas de la inspección de impuestos |
| Servicios | Zafacón | 1 casilla | La oficina se ensucia más lento |
| Decoración | Planta pequeña / grande | 1 casilla | Ambiente |
| Decoración | Cuadro y reloj de pared | En pared | Ambiente |
| Decoración | Alfombra | 2 a 4 casillas | Ambiente; se puede caminar encima |
| Decoración | Lámpara de pie | 1 casilla | Ambiente |
| Decoración | Pecera | 2 casillas | Mucho ambiente; baja el estrés de quien trabaja cerca |

## 12. Interfaz

La oficina es el fondo a pantalla completa y toda la interfaz flota superpuesta encima, en paneles pequeños.

### 12.1 Principios

- **Oficina de fondo:** no hay barras de borde a borde. La oficina se ve entre los paneles y hasta las esquinas.
- **Todo con ratón:** ninguna acción depende del teclado. Los atajos de teclado son un extra.
- **Menús superpuestos:** al abrir un menú, su panel aparece encima de la oficina sin taparla entera.
- **Clic para inspeccionar:** un clic en un empleado, un mueble o una habitación abre su ficha.
- **Cámara:** se arrastra para mover y tiene zoom en niveles fijos. Se mueve libre por todo el solar (el mapa fijo de 40×40 con la oficina en el centro) y se detiene en su borde. Al empezar encuadra la oficina completa; el botón «Ver oficina» (o la tecla F) la vuelve a encuadrar.
- **Idioma:** solo español por el momento.

### 12.2 Elementos siempre visibles

| Elemento | Posición | Contenido |
| --- | --- | --- |
| Estado de la empresa | Arriba a la izquierda | Dinero, reputación y valor de la empresa |
| Reloj | Arriba a la derecha | Fecha, cuenta atrás de la próxima nómina, hora, pausa y velocidades |
| Objetivos | Izquierda, plegable | Lista corta de objetivos guiados |
| Eventos | Derecha, plegable | Tarjeta con el texto, las opciones y la cuenta atrás |
| Avisos | Junto a los eventos | Mensajes breves que no piden decisión; un clic lleva a la ficha correspondiente |
| Barra de menús | Abajo, centrada | Los siete menús |
| Iconos de estado | Sobre cada empleado | Aparecen cuando algo va mal: cansado, molesto, sin puesto o sin tarea |

### 12.3 Menús

| Menú | Qué contiene |
| --- | --- |
| Construir | Paredes, pisos, puertas, tipos de habitación, catálogo de muebles y compra de terreno. Pausa el tiempo |
| Personal | Lista de empleados con filtros, vacantes abiertas, candidatos y organigrama por departamento |
| Proyectos | Bandeja de ofertas, proyectos en curso con sus tres barras y productos lanzados |
| Horarios | Plantillas de turno, equipos y la agenda semanal |
| Banco | Saldo, movimientos, préstamos activos, calificación de crédito y solicitud de préstamo |
| Empresa | Etapa actual y requisitos de la siguiente, reputación, e ingresos y gastos del mes |
| Ajustes | Guardar, cargar, sonido y opciones |

### 12.4 Ficha de empleado

Muestra nombre, cargo, nivel y equipo; barras de energía, ánimo y estrés; habilidades; rasgos descubiertos y sueldo. Tiene botones para subir el sueldo, ascender, cambiar de equipo, cambiar el horario y despedir.

### 12.5 Guardado

El juego se guarda solo al final de cada día de juego, y el jugador también puede guardar manualmente en cualquier momento desde Ajustes.

## 13. Economía

Estos son los valores de partida, calculados para que cuadren entre sí; se afinan cuando el juego se pueda probar.

### 13.1 Punto de partida

| Concepto | Valor |
| --- | --- |
| Capital inicial | $20,000 |
| Local inicial | 6×8 m (48 m²), con la oficina del CEO |
| Terreno | $150 por m², pago único |
| Mantenimiento del local | $5 por m² al mes |
| Solar máximo | 40×40 m (1,600 m²) |
| Publicar una vacante | Gratis; con publicidad, $100 |
| Meta para salir a bolsa | Valor de la empresa de $5,000,000 |

### 13.2 Salarios mensuales

Se pagan en dos mitades, los días 15 y 30. El CEO no tiene sueldo por el momento.

| Cargo | Pasante | Junior | SemiSenior | Senior |
| --- | --- | --- | --- | --- |
| Programador | $600 | $1,200 | $2,000 | $3,200 |
| Diseñador | $500 | $1,000 | $1,700 | $2,700 |
| QA | $500 | $900 | $1,500 | $2,400 |
| Vendedor | $500 | $1,000 | $1,600 | $2,500 |

| Cargo sin niveles | Sueldo |
| --- | --- |
| Limpieza | $500 |
| Recepcionista | $700 |
| Contador | $1,300 |
| Líder de equipo | $4,200 |
| Gerente | $6,000 |
| Ejecutivo | $9,000 |

### 13.3 Producción

| Nivel | Puntos por hora | Puntos por jornada de 8 h |
| --- | --- | --- |
| Pasante | 1 | 8 |
| Junior | 2 | 16 |
| SemiSenior | 3 | 24 |
| Senior | 4.5 | 36 |

- **CEO:** produce como un SemiSenior cuando trabaja él mismo.
- **Sin líder de equipo presente:** el equipo rinde al 75%.
- **Computadora:** básica sin extra, media +15%, pro +30%.

### 13.4 Contratos

Pagan unos $8 por punto de trabajo los pequeños y unos $11 los medianos (ajustado en el hito 39 para que crecer con equipos deje margen); los grandes, unos $9.5.

| Tamaño | Trabajo total | Plazo | Pago |
| --- | --- | --- | --- |
| Pequeño | 150 a 300 puntos | 7 a 12 días | $1,200 a $2,400 |
| Mediano | 800 a 1,500 puntos | 20 a 30 días | $9,000 a $16,500 |
| Grande | 4,000 a 8,000 puntos | 45 a 75 días | $38,000 a $76,000 |

- **Atraso:** 5% del pago por cada día, hasta un máximo del 50%.
- **Errores entregados:** 2% del pago por cada uno, hasta un máximo del 30%.

### 13.5 Productos propios

| Tamaño | Trabajo | Ingreso diario en su mejor momento | Racks necesarios |
| --- | --- | --- | --- |
| Pequeño | 1,500 puntos | $150 | 1 |
| Mediano | 5,000 puntos | $600 | 3 |
| Grande | 15,000 puntos | $2,200 | 8 |

El ingreso real va de la mitad al 150% de esa cifra según la calidad. Cada rack cuesta $100 al mes de mantenimiento.

### 13.6 Banco

| Calificación | Interés mensual | Límite de préstamo |
| --- | --- | --- |
| A | 2% | 6 veces el ingreso mensual |
| B | 3% | 4 veces |
| C | 4.5% | 3 veces |
| D | 6% | 2 veces |
| E | 8% | 1 vez |

- **Empresa nueva:** empieza en C, con un límite fijo de $5,000 hasta tener ingresos.
- **Plazo:** de 3 a 24 meses, con interés simple.
- **Mora:** 5% de la cuota atrasada.
- **Préstamo de emergencia:** 12% mensual.
- **Reventa de muebles:** 50% del precio, que es lo que cuenta en un embargo.

### 13.7 Precios de muebles

Un puesto básico completo (escritorio, silla y computadora) cuesta $710. Los objetos que no aparecen aquí están por definir.

| Objeto | Precio |
| --- | --- |
| Escritorio sencillo / largo / ejecutivo | $150 / $350 / $900 |
| Silla básica / ergonómica | $60 / $250 |
| Computadora básica / media / pro | $500 / $1,200 / $2,500 |
| Mesa de reuniones | $1,200 |
| Mostrador de recepción | $600 |
| Rack de servidores | $3,000 |
| Baterías de respaldo | $1,500 |
| Cafetera | $200 |
| Nevera / microondas / mesa de comedor (provisional, fase 6) | $400 / $150 / $300 |
| Sofá / dispensador de agua (provisional, fase 6) | $500 / $120 |
| Mesa de ping pong / máquina expendedora (provisional, fase 6) | $700 / $900 |
| Impresora / pizarra / ventana (provisional, fase 6) | $350 / $250 / $200 |
| Decoración | $30 a $500 |

### 13.8 Comprobación

- **CEO solo:** produce 24 puntos al día. Un contrato pequeño de 200 puntos toma unos 8 días y paga $1,600, contra $240 de mantenimiento al mes.
- **Primer equipo:** 2 programadores y 1 diseñador Junior producen 48 puntos al día, unos 1,050 al mes con trabajo continuo. Son $8,400 de ingresos contra $3,400 de sueldos.
- **El riesgo real:** los días sin contrato. Los sueldos corren igual; ahí entran los vendedores y, con descuido, el banco.

## 14. Ideas para versiones futuras

Ideas aprobadas que no entran en la primera versión.

- **Inversionista:** un evento donde un inversionista ofrece efectivo inmediato a cambio de un porcentaje de los ingresos futuros de la empresa. Entra en la fase 6 (hito 58).
- **Versión móvil:** descartada; el juego sale solo en escritorio.
- **Otros idiomas:** la primera versión sale solo en español.

## 15. Plan de desarrollo: fase 1

La fase 1 entrega una oficina funcional sin empleados: proyecto de Godot 4 configurado, oficina isométrica construible, reloj, CEO, dinero y guardado. Se construye en diez hitos, cada uno probado antes de pasar al siguiente.

### 15.1 Alcance

| Entra en la fase 1 | Queda para fases siguientes |
| --- | --- |
| Configuración del proyecto | Empleados, contratación y jerarquía |
| Cuadrícula isométrica, cámara y local inicial | Contratos, proyectos y productos |
| Reloj de 24 horas con pausa y velocidades | Equipos, turnos y horas extra |
| CEO que camina y usa su escritorio | Banco, préstamos y embargo |
| Modo construcción: pisos, paredes, puertas y muebles | Eventos, etapas y objetivos dinámicos |
| Detección y tipos de habitación | Compra de terreno |
| Dinero, interfaz mínima y guardado | Arte final y sonido |

### 15.2 Decisiones técnicas

- **Motor y lenguaje:** Godot 4 en su versión estable más reciente (4.3 o superior, por el nodo TileMapLayer), con GDScript.
- **Pantalla:** resolución base de 1280×720, modo de estirado `canvas_items` y aspecto `expand`. Filtro de texturas por defecto en `Nearest`.
- **Cuadrícula:** TileMapLayer isométrico con casilla de 64×32. Toda la lógica trabaja en coordenadas de cuadrícula y solo convierte a píxeles para dibujar.
- **Paredes:** van en los bordes de las casillas, no ocupan casilla. Se guardan como una lista de bordes y bloquean el paso entre las dos casillas que separan.
- **Orden de dibujo:** un nodo con ordenamiento por Y contiene paredes, muebles y personajes.
- **Caminos:** AStarGrid2D sobre la cuadrícula lógica, recalculado al construir.
- **Datos fuera del código:** el catálogo de muebles, los tipos de habitación y los valores de economía viven en archivos de datos (Resources o JSON), para cambiar números sin tocar scripts.
- **Sistemas globales (autoload):** reloj, economía, estado de la oficina, guardado y un bus de señales para que los sistemas se avisen entre sí sin depender unos de otros.
- **Arte provisional:** rombos y cajas de colores hasta que el arte final esté listo. Cada objeto apunta a su sprite desde los datos, así el cambio posterior no toca la lógica.

### 15.3 Estructura de carpetas

| Carpeta | Contenido |
| --- | --- |
| `scenes/` | Escena principal, oficina, personajes e interfaz |
| `scripts/autoload/` | Reloj, economía, estado de la oficina, guardado y bus de señales |
| `scripts/office/` | Cuadrícula, construcción, paredes, muebles y habitaciones |
| `scripts/characters/` | Movimiento, caminos y rutina del CEO |
| `scripts/ui/` | Paneles de la interfaz superpuesta |
| `data/` | Catálogo de muebles, tipos de habitación y economía |
| `assets/` | Sprites, tiles y fuentes |

### 15.4 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 0. Proyecto | Proyecto de Godot, ajustes de pantalla y texturas, carpetas, autoloads vacíos, git y un `CLAUDE.md` con las reglas del proyecto | El proyecto abre y corre una escena vacía sin errores |
| 1. Cuadrícula y cámara | Piso isométrico del local de 6×8, cámara que se arrastra, zoom en 3 niveles fijos y resaltado de la casilla bajo el cursor | El cursor resalta la casilla correcta en todo el local y en cada nivel de zoom |
| 2. Reloj | Reloj de 24 horas, fecha, mes de 30 días, pausa y velocidades 1x, 2x y 4x, con señales de cambio de hora y de día | Un día dura 4 minutos a 1x y 1 minuto a 4x; en pausa nada avanza |
| 3. Inicio de partida | Nueva partida con el local inicial, la Oficina Ejecutiva ya construida, el CEO y $20,000 | Al pulsar "Nueva partida" aparece la oficina lista para jugar |
| 4. CEO | Personaje que camina por la cuadrícula, esquiva obstáculos, se sienta en su escritorio en horario de trabajo y se va al terminar | El CEO llega a su escritorio por un camino válido y queda bien ordenado respecto a los muebles |
| 5. Construcción: pisos y paredes | Modo construcción que pausa el tiempo, con pisos, paredes pieza por pieza, puertas y venta | Las paredes bloquean el paso, las puertas lo permiten y cada acción cobra o devuelve dinero |
| 6. Muebles | Colocar, rotar y vender escritorio, silla, computadora sobre el escritorio y una planta | No se puede colocar sobre otro objeto ni bloquear el único acceso; la reventa devuelve el 50% |
| 7. Habitaciones | Detección de espacios cerrados con puerta, asignación de tipo y validación de requisitos | Al cerrar un espacio con puerta se puede marcar como habitación; la Recepción exige pared exterior |
| 8. Dinero e interfaz | Cuenta empresarial, cobro del mantenimiento el día 1 y la interfaz superpuesta mínima: dinero, reloj, velocidades y botón Construir | El saldo cambia con cada compra y el día 1 se descuenta $5 por m² |
| 9. Guardado | Autoguardado al final de cada día y guardado manual, con carga desde el menú | Tras guardar, cerrar y cargar, la oficina, el dinero y la fecha son idénticos |

### 15.5 Orden y dependencias

- **Base:** los hitos 0, 1 y 2 no dependen de nada más y van primero, en ese orden.
- **Partida jugable:** el 3 y el 4 necesitan la cuadrícula y el reloj.
- **Construcción:** el 5, el 6 y el 7 van en cadena; cada uno se apoya en el anterior.
- **Cierre:** el 8 puede adelantarse en parte, porque la construcción necesita cobrar. El 9 va al final, cuando ya existe todo lo que hay que guardar.

### 15.6 Cómo trabajar con Claude Code

- **Un hito por sesión:** pedir un solo hito, probarlo en Godot y hacer commit antes de pedir el siguiente.
- **Este documento como referencia:** guardar una copia en el repositorio y citar la sección que corresponde a cada hito.
- **Reglas en `CLAUDE.md`:** versión de Godot, casilla de 64×32, lógica en coordenadas de cuadrícula, datos fuera del código y textos en español.
- **Criterio de aceptación:** cada petición incluye la columna "Cómo se comprueba" del hito, para que Claude Code sepa cuándo terminó.

### 15.7 Riesgos de esta fase

- **Paredes y orden de dibujo:** en isométrico, una pared en un borde puede dibujarse delante o detrás de quien no debe. Conviene resolverlo en el hito 5 con una prueba de un personaje rodeando una pared.
- **Detección de habitaciones:** con paredes libres, saber qué casillas forman un espacio cerrado requiere un recorrido de relleno desde cada casilla. Hay que recalcularlo solo al salir del modo construcción.
- **Guardado tardío:** si el formato de guardado se deja para el final, cada sistema debe exponer desde el inicio una función para exportar y otra para restaurar su estado.

## 16. Plan de desarrollo: fase 2

La fase 2 cierra el ciclo básico del juego: contratar empleados, ponerlos a trabajar, tomar contratos, entregarlos, cobrar y pagar la nómina el 15 y el 30. Al terminarla, el juego ya se puede ganar y perder dinero de verdad. Se construye en diez hitos, numerados después de los de la fase 1.

### 16.1 Alcance

| Entra en la fase 2 | Queda para fases siguientes |
| --- | --- |
| Vacantes, candidatos y contratación (5.2) | Banco: préstamos, calificación, mora y embargo |
| Empleados que llegan, trabajan en su puesto y se van | Compra de terreno |
| Ficha de empleado con energía, ánimo y estrés | Etapas de la empresa, valor de la empresa y objetivos guiados |
| Nómina los días 15 y 30, y despidos | Jerarquía: líderes, gerentes, ejecutivos y departamentos |
| Bandeja de contratos pequeños y medianos | Ascensos por experiencia y horas extra |
| Equipos con un turno y un proyecto | Recepcionista con visitas de clientes, contador y limpieza |
| Producción por puntos y las tres fases del trabajo | Productos propios y sala de servidores |
| Errores, pruebas y entrega con penalidades | Eventos y salir a bolsa |
| Reputación de 1 a 5 estrellas | Ambiente y decoración con efecto |
| Ánimo, aviso de renuncia y aumentos | Arte final y sonido |

### 16.2 Decisiones técnicas

- **Sistemas nuevos (autoload):** `Staff` (empleados, vacantes y candidatos) y `Projects` (ofertas, contratos y producción). Se comunican con los demás por `EventBus`, igual que en la fase 1.
- **Datos fuera del código:** cargos, niveles, sueldos y producción en `data/staff.json`; tamaños, pagos y penalidades de contratos en `data/contracts.json`; nombres y rasgos en `data/names.json`. Son los valores de las secciones 5, 7 y 13.
- **Azar reproducible:** todo lo aleatorio (candidatos, ofertas, errores) sale de un `RandomNumberGenerator` con semilla guardada en la partida. Así una prueba sin ventana da siempre el mismo resultado y cargar una partida no cambia lo que iba a pasar.
- **Guardado:** cada sistema nuevo implementa `export_state()` e `import_state()`, y su importación tolera claves ausentes, para que las partidas de la fase 1 sigan cargando.
- **Personajes:** cada empleado es una escena como la del CEO, con la misma rutina de llegar, caminar a su puesto, sentarse e irse. La rutina del CEO se generaliza en lugar de copiarse.
- **Horarios:** cada cargo tiene un horario por defecto en `data/staff.json`, que el turno del equipo reemplaza (hito 15). Un turno es una hora de entrada y sus días, con al menos uno de descanso; dura 8 horas más una de almuerzo, que cae en la 4.ª hora de la jornada (a las 12 si se entra a las 8). El CEO no tiene horario: llega solo a las 8 en días hábiles y se queda hasta que el jugador lo manda a casa, así que puede quedarse hasta tarde o volver cuando quiera. Si sigue en la oficina a las 22 se queda dormido y no produce hasta su hora de llegada.
- **Puesto de trabajo:** escritorio + silla + computadora dentro de un Área de trabajo que funciona. El CEO conserva el suyo en la Oficina Ejecutiva.
- **Arte provisional:** los empleados son figuras dibujadas en código, con un color de camisa por especialidad.

### 16.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 10. Vacantes y candidatos | Menú Personal con vacantes: cargo, nivel, sueldo ofrecido y publicidad ($100). En los días siguientes llegan candidatos con nombre, nivel, sueldo pedido y habilidades en rangos; caducan a los pocos días | Al publicar una vacante llegan candidatos en los días siguientes; con publicidad llegan más; un candidato desaparece al caducar |
| 11. Contratación | Contratar a un candidato: exige un puesto de trabajo libre, acepta si el sueldo iguala o supera lo que pide y si no rechaza o contraoferta. Entrevista opcional que ocupa horas del CEO y revela un rasgo y los valores reales | Sin puesto libre no se puede contratar; con puesto, el empleado queda asignado a él y ningún puesto queda con dos empleados |
| 12. Jornada de los empleados | Los empleados llegan a su hora, caminan a su puesto, se sientan, almuerzan y se van, como el CEO. La energía baja trabajando y se recupera fuera. Clic en un empleado abre su ficha (12.4) | Cada empleado llega a su puesto por un camino válido y se va al terminar; la ficha muestra sus barras; con la oficina vacía el tiempo salta a la próxima entrada |
| 13. Nómina y despidos | Los días 15 y 30 se paga la mitad del sueldo mensual de cada empleado. Sin dinero no se paga y baja el ánimo de todos. Despedir cuesta lo ganado hasta ese día y baja el ánimo de los compañeros | El día 15 el saldo baja exactamente la mitad de la suma de sueldos; un despido el día 10 cobra 10/30 del sueldo |
| 14. Ofertas de contratos | Menú Proyectos con la bandeja de ofertas: cliente, tipo, tamaño, plazo, pago, anticipo y penalidad (13.4). Llegan más y mejores con más reputación y con vendedores. Aceptar cobra el anticipo | Los puntos, plazos y pagos de cada oferta caen en los rangos de la tabla 13.4; aceptar un contrato con anticipo suma el 30% al saldo |
| 15. Equipos y turnos | Crear equipos con miembros, un turno (entrada, salida y días, con al menos un día de descanso) y un proyecto asignado. Un equipo trabaja en un proyecto a la vez | Un empleado solo está en un equipo; cambiar el turno de un equipo cambia la hora a la que llegan sus miembros |
| 16. Producción | Cada empleado suma puntos por hora trabajada en su especialidad según nivel, energía y computadora (13.3). Las fases diseño, programación y pruebas avanzan en orden, con solapamiento desde la mitad. Tres barras por proyecto | El CEO solo produce 24 puntos por día; 2 programadores y 1 diseñador Junior producen 48; la programación no empieza antes de la mitad del diseño |
| 17. Errores y pruebas | Al programar se generan errores ocultos, más con empleados cansados o de bajo nivel. QA los encuentra en la fase de pruebas y los programadores los corrigen | Sin QA los errores llegan a la entrega; con QA bajan; con la misma semilla se generan siempre los mismos errores |
| 18. Entrega y reputación | El jugador decide cuándo entregar. Pago con penalidad por atraso (5% por día, máximo 50%) y por errores (2% cada uno, máximo 30%). Cancelar devuelve el anticipo. Reputación de 1 a 5 estrellas visible arriba a la izquierda | Cada resultado de la tabla 7.4 paga y mueve la reputación como dice; un contrato con 3 días de atraso y 2 errores paga el 81% |
| 19. Ánimo y renuncias | El ánimo y el estrés cambian con el trabajo, el sueldo comparado con su nivel, la nómina sin pagar y los despidos. Con ánimo bajo o estrés alto por mucho tiempo, el empleado avisa que renuncia; un aumento lo retiene. A veces alguien pide aumento | Un empleado con ánimo bajo varios días avisa y, si no se le retiene, se va; con un aumento a tiempo se queda |

### 16.4 Orden y dependencias

- **Personal:** el 10, el 11 y el 12 van en cadena; sin empleados no hay nada que producir.
- **Dinero de los empleados:** el 13 va después del 12, porque la nómina y los despidos necesitan empleados contratados.
- **Trabajo:** el 14 puede ir en paralelo con el 12 y el 13. El 15 necesita empleados y contratos; el 16, el 17 y el 18 van en cadena después.
- **Cierre:** el 19 va al final, porque el ánimo depende de la nómina, la carga de trabajo y las entregas.

### 16.5 Riesgos de esta fase

- **Muchos personajes:** con decenas de empleados, recalcular caminos a la vez puede trabar el juego. Conviene repartir los cálculos entre cuadros y probarlo en el hito 12 con 20 empleados.
- **Puestos compartidos:** dos empleados no deben ir al mismo puesto ni sentarse en la misma silla. La asignación de puesto se guarda en el empleado y se valida al construir y vender muebles.
- **Balance:** los valores de la sección 13 son una propuesta. El hito 16 compara la producción real con la tabla 13.8 antes de seguir.
- **Partidas viejas:** cada sistema nuevo debe cargar sin error un guardado de la fase 1.

### 16.6 Fases siguientes

| Fase | Tema | Qué incluye |
| --- | --- | --- |
| 3 | Banco y crecimiento | Préstamos, calificación de crédito, préstamo de emergencia, mora y embargo; compra de terreno; etapas de la empresa, valor de la empresa, objetivos guiados y menú Empresa |
| 4 | Organización | Líderes de equipo, gerentes, ejecutivos y departamentos con el rendimiento del CEO; ascensos por experiencia; horas extra y agenda semanal; recepcionista con visitas, contador y limpieza; competencia por empleados |
| 5 | Productos y eventos | Productos propios con ciclo de vida y sala de servidores; eventos con tarjetas y cuenta atrás; ambiente y decoración con efecto; salir a bolsa |
| 6 | Vida en la oficina | Rasgos con efecto, baños y Sala de descanso, muebles que faltan, candidatos según la empresa, iconos de estado e inversionista |
| 7 | Arte y sonido | Sprites finales generados con la herramienta de arte, animaciones de los personajes, sonido y pulido de la interfaz |

## 17. Plan de desarrollo: fase 3

La fase 3 agrega el banco y el crecimiento de la empresa: pedir préstamos y pagarlos, el riesgo de embargo (la única forma de perder), comprar terreno, y medir el progreso con el valor de la empresa, las etapas y los objetivos guiados. Al terminarla, el juego tiene una forma de perder y una escalera de metas. Se construye en diez hitos, numerados después de los de la fase 2.

### 17.1 Alcance

| Entra en la fase 3 | Queda para fases siguientes |
| --- | --- |
| Menú Banco: saldo, movimientos e ingresos y gastos del mes (8.1) | Contador: mejores tasas y aviso de cuota (fase 4) |
| Calificación de crédito de la A a la E (8.3 y 13.6) | Líderes, gerentes, ejecutivos y departamentos (fase 4) |
| Préstamos: solicitud, cuota mensual, pago anticipado y refinanciación (8.2) | Productos propios y sala de servidores (fase 5) |
| Préstamo de emergencia el día de nómina | Eventos con tarjetas y cuenta atrás (fase 5) |
| Mora, embargo de muebles y fin de la partida (8.4) | Salir a bolsa (fase 5) |
| Compra de terreno junto al local (3.1) | Los desbloqueos de etapa que dependen de esos sistemas |
| Valor de la empresa siempre visible (9.3) | |
| Las cinco etapas y el menú Empresa (9.1 y 12.3) | |
| Objetivos guiados con recompensa (9.4) | |

### 17.2 Decisiones técnicas

- **Sistemas nuevos (autoload):** `Bank` (calificación, préstamos, mora y embargo) y `Company` (valor, etapas y objetivos), después de `Projects` y antes de `SaveManager`. Se comunican con los demás por `EventBus`. Todo cobro o pago sigue pasando por `Economy` con su concepto.
- **Datos fuera del código:** tasas, límites, plazos, mora y reventa en `data/bank.json` (sección 13.6); requisitos y desbloqueos de etapa en `data/stages.json` (9.1); objetivos, sus condiciones y recompensas en `data/objectives.json`; el precio del terreno en `data/construction.json`.
- **Calificación:** se calcula cada día 1 con los ingresos de contratos de los últimos 30 días, el valor de los bienes, los meses de antigüedad y el historial de pagos (cuotas a tiempo y atrasadas). Una empresa nueva empieza en C con un límite fijo de $5,000 hasta tener ingresos; después el límite es el múltiplo de su letra por el ingreso mensual. Cada atraso baja una letra en el momento.
- **Préstamos:** interés simple mensual: total = monto × (1 + tasa × meses) y cuota = total / meses, cobrada el día 1 junto al mantenimiento. La suma de lo que se debe nunca pasa el límite. El pago anticipado cobra el capital que falta más el interés del mes en curso. Refinanciar, una vez por préstamo, alarga el plazo con la tasa un punto más alta. Las etapas ponen un tope extra al monto (préstamos pequeños en Emprendimiento, grandes desde Mediana empresa), provisional en `data/bank.json`.
- **Mora y embargo:** una cuota que no alcanza queda atrasada, cobra el 5% de recargo y se paga sola apenas alcance el saldo, como la nómina debida. Con 2 cuotas atrasadas seguidas el banco avisa y no presta más; con 3, embarga: suma la reventa de los muebles (50% del precio) y, si cubre la deuda, se los lleva empezando por la decoración y dejando los puestos de trabajo para el final; si no la cubre, la partida termina.
- **Fin de la partida:** una pantalla con las estadísticas (días jugados, empleados contratados, contratos entregados, mejor reputación) y un botón al menú principal. Se borra el autoguardado para no volver al momento del embargo; las ranuras manuales quedan.
- **Préstamo de emergencia:** si el día de nómina no alcanza el dinero y el banco todavía presta, el tiempo se pausa y aparece una ventana con el monto (lo que falta para la nómina), la tasa del 12% y la cuota, con Aceptar y Rechazar. Aceptar paga la nómina y crea el préstamo; rechazar deja la deuda de nómina como en la fase 2. El plazo es fijo y provisional (3 meses) y no cuenta para el límite.
- **Terreno:** el local deja de ser un rectángulo: pasa a ser un conjunto de casillas dentro del solar. La compra se elige en Construir (lado, ancho × fondo y posición a lo largo del lado), con vista previa y precio antes de confirmar. El terreno nuevo trae piso básico, el contorno de paredes se corre al nuevo borde y el borde compartido queda abierto. El mantenimiento sube solo porque se cobra por m².
- **Valor de la empresa:** dinero + reventa de los muebles (50%) + terreno comprado al precio pagado − deuda con el banco (capital pendiente de los préstamos, cuotas atrasadas y recargos). Los productos se suman en la fase 5. Se muestra arriba a la izquierda, junto al dinero y la reputación.
- **Etapas:** se revisan cada día y nunca bajan. Las cinco existen desde ya, pero la 4 y la 5 piden productos y ejecutivos, así que no se alcanzan hasta las fases 4 y 5. Un equipo cuenta como completo si tiene al menos un diseñador, un programador y un QA. Los contratos medianos llegan desde Startup o con un vendedor (reemplaza la regla de 2 estrellas); los grandes siguen pidiendo 4 estrellas y Sala de reuniones hasta que la etapa 4 sea alcanzable.
- **Objetivos:** una lista corta (hasta 3 visibles) a la izquierda, plegable, que se pliega sola al abrir Personal, Proyectos o Equipos. Cada objetivo tiene una condición, un texto y una recompensa de dinero, de reputación o de ambas. Al cumplirse avisa, cobra la recompensa con el concepto «Objetivo cumplido» y entra el siguiente de la lista.
- **Menús:** la barra de abajo suma Banco y Empresa. Banco y Empresa ocupan el lado izquierdo como Personal, Proyectos y Equipos: abrir uno cierra los otros.
- **Guardado:** `Bank` y `Company` implementan `export_state()` e `import_state()` tolerantes a claves ausentes, para que las partidas de la fase 2 carguen sin préstamos, en etapa calculada y con los objetivos ya cumplidos marcados sin recompensa.

### 17.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 20. Menú Banco | Menú Banco con el saldo, los movimientos (fecha, concepto y monto) y los ingresos y gastos del mes por concepto | Tras comprar un mueble y cobrar un contrato, ambos movimientos aparecen con su fecha y los totales del mes cuadran con `Economy` |
| 21. Calificación de crédito | Nota de la A a la E con ingresos, bienes, antigüedad e historial; límite de préstamo según la letra (13.6). Se ve en el Banco con lo que la sube y la baja | Una empresa nueva está en C con límite de $5,000; con ingresos y pagos puntuales sube; un atraso la baja una letra |
| 22. Préstamos | Pedir un préstamo eligiendo monto y plazo (3 a 24 meses) con vista previa de tasa, cuota y total; cuota el día 1; pago anticipado; refinanciar una vez | $10,000 a 10 meses en C cuesta $14,500 en cuotas de $1,450 cobradas el día 1; no se puede pedir más que el límite; el pago anticipado ahorra intereses; refinanciar no se puede dos veces |
| 23. Mora y embargo | Cuotas atrasadas con recargo del 5%, aviso a las 2 y embargo a las 3: el banco se lleva muebles (decoración primero) o, si no alcanzan, termina la partida con la pantalla de fin | Una cuota sin pagar cobra el 5% y baja la letra; con 2 el banco no presta; con 3 y muebles suficientes la deuda queda saldada y siguen los puestos de trabajo; sin muebles aparece la pantalla de fin y se borra el autoguardado |
| 24. Préstamo de emergencia | Ventana que pausa el tiempo el día de nómina sin dinero, con monto, tasa del 12%, cuota, Aceptar y Rechazar | El día 15 sin dinero aparece la ventana con el tiempo en pausa; aceptar paga la nómina y crea el préstamo al 12%; rechazar deja la deuda de nómina; con 2 cuotas atrasadas no se ofrece |
| 25. Compra de terreno | Herramienta Terreno en Construir: lado, ancho × fondo y posición, vista previa y precio; el local crece y el contorno se corre | Comprar 4 × 3 al este cuesta $1,800, el local suma 12 m² y el mantenimiento sube $60 al mes; no se puede comprar fuera del solar ni sin tocar el local; los caminos llegan al terreno nuevo |
| 26. Valor de la empresa | Valor calculado (9.3) y visible arriba a la izquierda, con el detalle en el Banco | Comprar un mueble baja el valor la mitad de su precio; pedir un préstamo no cambia el valor; comprar terreno tampoco (se cuenta a lo pagado); cada cuota baja el valor solo en su interés |
| 27. Etapas y menú Empresa | Las cinco etapas con requisitos y desbloqueos (data/stages.json); menú Empresa con la etapa, el progreso hacia la siguiente, la reputación y los ingresos y gastos del mes | Con 5 empleados y 3 contratos entregados la empresa pasa a Startup con un aviso y llegan contratos medianos sin vendedor; despedir después no la baja de etapa |
| 28. Objetivos guiados | Lista plegable de objetivos con recompensa de dinero, reputación o ambas (data/objectives.json) | Al contratar al primer programador el objetivo se marca, cobra su recompensa una sola vez y aparece el siguiente; una partida de la fase 2 carga con sus objetivos ya cumplidos marcados |
| 29. Comprobación de la fase | Simulación sin ventana de varios meses: CEO solo, primer equipo con préstamo y una empresa que deja de pagar. Ajuste de los valores de `data/bank.json` y `data/stages.json` | La simulación cuadra con la tabla 13.8; un préstamo razonable se paga con el primer equipo; dejar de pagar lleva al embargo en el tercer mes; todas las pruebas anteriores siguen pasando |

### 17.4 Orden y dependencias

- **Banco:** el 20, el 21 y el 22 van en cadena; la calificación necesita los movimientos y los préstamos necesitan el límite.
- **Riesgo:** el 23 y el 24 van después del 22, porque necesitan préstamos y cuotas.
- **Terreno:** el 25 es independiente del banco y puede ir en cualquier momento después del 20.
- **Progreso:** el 26 necesita la deuda (22) y el terreno (25); el 27 y el 28 van después del 26, porque el menú Empresa y algunos objetivos usan el valor.
- **Cierre:** el 29 va al final.

### 17.5 Riesgos de esta fase

- **Local no rectangular:** hoy el local es un rectángulo (`lot_rect`). Pasar a un conjunto de casillas toca la construcción, las paredes del contorno, las habitaciones, la cámara y el guardado; conviene hacerlo al empezar el hito 25 con pruebas de las fases 1 y 2 corriendo.
- **Embargo y empleados:** si el banco se lleva un puesto de trabajo ocupado, el empleado queda sin puesto; debe tratarse igual que vender el mueble y no dejar asignaciones colgadas.
- **Ventana que pausa:** la ventana de emergencia no puede quedar abierta mientras el tiempo salta con la oficina vacía ni al cargar una partida.
- **Barra de menús:** con Banco y Empresa son nueve botones; deben caber en 1280 px de ancho.
- **Balance:** los valores de 9.1 y 13.6 son una propuesta. El hito 29 los ajusta antes de cerrar la fase.
- **Partidas viejas:** cada sistema nuevo debe cargar sin error un guardado de la fase 2.

## 18. Plan de desarrollo: fase 4

La fase 4 agrega la organización de la empresa: líderes de equipo, gerentes, ejecutivos y departamentos que reparten el trabajo del CEO; ascensos por experiencia; horas extra, turnos de noche y la agenda semanal; los roles de apoyo (recepcionista, contador y limpieza) y la competencia por los buenos empleados. Al terminarla, crecer obliga a delegar y la empresa puede llegar a Mediana empresa. Se construye en diez hitos, numerados después de los de la fase 3.

### 18.1 Alcance

| Entra en la fase 4 | Queda para fases siguientes |
| --- | --- |
| Ascensos por experiencia: Pasante → Junior → SemiSenior → Senior (5) | Productos propios y sala de servidores que funciona (fase 5) |
| Líderes de equipo y supervisión real (4 y 6) | Eventos con tarjetas y cuenta atrás (fase 5) |
| Gerentes y organigrama (4) | Ambiente y decoración con efecto (fase 5) |
| Departamentos, rendimiento del CEO y ejecutivos (4.1) | Salir a bolsa (fase 5) |
| Horas extra, turno de noche y horario individual (6 y 6.2) | Rasgos con efecto en el trabajo |
| Agenda semanal y plantillas de turno (6 y 12.3) | Arte final y sonido (fase 7) |
| Recepcionista y visitas de clientes (5.1) | |
| Contador y limpieza (5.1) | |
| Competencia por empleados (5.3) | |

### 18.2 Decisiones técnicas

- **Sistemas:** la organización vive en `Staff` (cargos, líderes, gerentes, ejecutivos y departamentos) con sus funciones puras aparte (`Organization`), como `Production` y `Embargo`. Las visitas de clientes van en `Projects`; la suciedad, en `OfficeState`. Todo se comunica por `EventBus` y todo pago pasa por `Economy`.
- **Datos fuera del código:** cargos de apoyo y de dirección, sueldos, umbrales de ascenso, horas extra, turno de noche, suciedad y competencia en `data/staff.json`; los muebles nuevos (mostrador, sofá de espera y zafacón) en `data/furniture.json`; los cambios de etapa en `data/stages.json`.
- **Cargos sin niveles:** recepcionista, contador, limpieza, líder de equipo, gerente y ejecutivo tienen un sueldo fijo de 13.2 y no ascienden por nivel; solo se les sube el sueldo. El ánimo compara su sueldo con ese fijo.
- **Ascensos:** cada empleado cuenta los contratos en que trabajó (sumó puntos) y los días en la empresa; los vendedores cuentan los contratos aceptados mientras estaban. Al cumplir los dos umbrales (3 y 30 para Junior, 8 y 90 para SemiSenior, 15 y 180 para Senior) la ficha ofrece Ascender con un sueldo que el jugador elige (sugerido: el de su nuevo nivel). Ascender cuenta como aumento para el ánimo; dejarlo pasar no castiga hasta que exista el rasgo «ambicioso».
- **Líderes de equipo:** se desbloquean en Startup. Un Senior asciende a líder de un equipo sin líder; cobra $4,200, no suma puntos y ocupa un puesto en el Área de trabajo. Un equipo tiene como mucho un líder y 10 miembros. El líder cuenta como presente solo mientras está en la oficina en el turno del equipo. Desde Startup, un equipo sin líder presente rinde al 75 %; en Emprendimiento rinde al 100 % aunque no tenga líder.
- **Gerentes:** se desbloquean en Pequeña empresa. Se contratan con su vacante, necesitan una Oficina única libre (con escritorio ejecutivo y silla) y dirigen hasta 5 líderes. Los equipos de esos líderes rinden +10 % y su meta de estrés baja 10. Un sexto líder necesita un gerente que lo dirija.
- **Departamentos:** Desarrollo (programadores y QA), Diseño, Ventas (vendedores y recepcionistas) y Administración (contadores y limpieza). Un departamento existe desde que tiene un empleado. Los que no tienen ejecutivo los dirige el CEO, y cada uno rinde según cuántos dirige (100 %, 85 %, 70 % y 55 % con 1 a 4). Ese factor multiplica la producción en Desarrollo y Diseño, la probabilidad de ofertas en Ventas y el efecto de contador y limpieza en Administración.
- **Ejecutivos:** se desbloquean en Mediana empresa, que en esta fase pide solo 40 empleados (el requisito de producto vuelve en la fase 5). Un ejecutivo cuesta $9,000, necesita su Oficina única y dirige un departamento: lo devuelve al 100 % y le suma hasta +10 % según su liderazgo. El ejecutivo de Administración puede hacer las entrevistas en lugar del CEO.
- **Horas extra:** el turno de un equipo o el horario individual suma de 0 a 4 horas extra por día. Se pagan a 1.5 veces la hora normal en la nómina siguiente («Horas extra») y gastan más energía y suben el estrés.
- **Turno de noche:** las horas trabajadas entre las 22 y las 6 cobran un extra del sueldo (provisional 20 %) y bajan la meta de ánimo.
- **Horario individual:** cualquier empleado puede tener un horario propio que reemplaza el de su equipo, con al menos un día de descanso.
- **Agenda:** el menú Equipos pasa a llamarse Horarios: plantillas de turno con nombre, equipos y una agenda semanal que muestra quién trabaja a cada hora y marca los huecos (equipo sin líder, nadie en la recepción).
- **Recepcionista y visitas:** desde Startup, una parte de las ofertas llega como visita de un cliente a la Recepción (con mostrador). Si hay un recepcionista presente, la oferta entra en la bandeja; si no, el cliente espera unas horas (más con sofá de espera) y se va, y la oferta se pierde.
- **Contador:** baja el mantenimiento y la tasa de los préstamos nuevos (provisional −10 % y −1 punto), y avisa tres días antes de cada cuota o nómina que no va a alcanzar.
- **Limpieza:** cada habitación junta suciedad por las horas que la gente pasa en ella (menos con zafacón). Sobre un umbral, la meta de ánimo de quienes trabajan ahí baja. El personal de limpieza la quita en su turno.
- **Competencia:** a veces otra empresa le hace una oferta a un empleado SemiSenior o Senior (más si gana menos que su nivel, menos si es «leal», más si es «ambicioso»). Avisa como la renuncia: se queda con un aumento que iguale la oferta y, si no, se va al terminar el plazo.
- **Guardado:** los datos nuevos se exportan e importan tolerando claves ausentes; una partida de la fase 3 carga sin líderes, sin horas extra y con la oficina limpia.

### 18.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 30. Ascensos | Contratos trabajados y días en la empresa por empleado; en la ficha, el progreso al siguiente nivel y Ascender con el sueldo elegido | Un Pasante con 3 contratos y 30 días puede ascender a Junior: produce 16 puntos por jornada y su sueldo cambia en la nómina; antes de los umbrales no puede |
| 31. Líderes de equipo | Ascender un Senior a líder de un equipo; supervisión real según su presencia; tope de 10 miembros | En Startup, un equipo sin líder presente rinde 75 % y con líder 100 %; en Emprendimiento rinde 100 %; un líder fuera de turno no cuenta |
| 32. Gerentes y organigrama | Vacante de gerente con su Oficina única; asignar hasta 5 líderes; organigrama en Personal | Sin Oficina única libre no se contrata; los equipos de sus líderes rinden 110 % y bajan el estrés; un sexto líder sin gerente no se puede nombrar |
| 33. Departamentos y ejecutivos | Departamentos por cargo, rendimiento del CEO según los que dirige, ejecutivos con su oficina; Mediana empresa con 40 empleados | Con 3 departamentos a cargo del CEO cada uno rinde 70 %; con un ejecutivo en Desarrollo ese vuelve al 100 % más su ventaja y los otros dos suben a 85 % |
| 34. Horas extra y turno de noche | Horas extra en el turno (0–4), pago a 1.5×, turno de noche con recargo, horario individual | Un turno de 2 horas extra cobra 2 × 1.5 horas por día trabajado en la nómina; un turno de 22 a 6 cobra el recargo; el horario individual cambia la hora de llegada de esa persona |
| 35. Agenda semanal | Menú Horarios con plantillas de turno con nombre, equipos y la agenda de la semana con huecos marcados | Cambiar una plantilla cambia el turno de todos sus equipos; la agenda marca la hora en que un equipo no tiene líder presente |
| 36. Recepcionista y visitas | Muebles de recepción, cargo de recepcionista, clientes que llegan, esperan y se van | Con recepcionista presente la visita deja su oferta; sin él, el cliente se va y la oferta se pierde; con sofá espera más |
| 37. Contador y limpieza | Cargo de contador con sus descuentos y avisos; suciedad por habitación, zafacón y personal de limpieza | Con contador el mantenimiento baja 10 % y un préstamo nuevo cuesta 1 punto menos; una habitación sucia baja el ánimo y la limpieza la deja en 0 |
| 38. Competencia por empleados | Ofertas de otras empresas a buenos empleados, con aviso y retención por aumento | Un Senior mal pagado recibe ofertas más seguido que uno bien pagado; con un aumento que iguala se queda; si no, se va en el plazo |
| 39. Comprobación de la fase | Simulación sin ventana de una empresa que crece hasta Mediana empresa con líderes, gerente y un ejecutivo; ajuste de `data/staff.json` y `data/stages.json` | La simulación llega a Mediana empresa sin quebrar con una política simple; dirigir 4 departamentos se nota en los ingresos; todas las pruebas anteriores siguen pasando |

### 18.4 Orden y dependencias

- **Escalera de cargos:** el 30 va primero, porque un líder es un Senior ascendido. El 31, el 32 y el 33 van en cadena: gerentes dirigen líderes y los ejecutivos completan los departamentos.
- **Tiempo:** el 34 y el 35 van después del 31, porque la agenda marca los huecos de líder.
- **Apoyo:** el 36 y el 37 dependen del 33 (Ventas y Administración); pueden ir en cualquier orden entre sí.
- **Cierre:** el 38 usa los aumentos y avisos de la fase 2; el 39 va al final.

### 18.5 Riesgos de esta fase

- **Balance:** el rendimiento de los departamentos y la regla del líder bajan la producción de las empresas que crecen. El hito 39 revisa que el primer equipo de la fase 3 siga pagando su préstamo.
- **Muchos personajes:** Mediana empresa son más de 40 personas caminando; hay que probar el rendimiento con 50 personajes antes del hito 39.
- **Oficinas:** gerentes y ejecutivos necesitan una Oficina única con su escritorio; vender ese mueble o perder la habitación debe dejarlos sin oficina igual que un puesto de trabajo, sin asignaciones colgadas.
- **Barra de menús:** Equipos pasa a Horarios para no sumar un botón.
- **Partidas viejas:** cada sistema nuevo debe cargar sin error un guardado de la fase 3.

## 19. Plan de desarrollo: fase 5

La fase 5 agrega lo que hace a la empresa algo más que un taller de contratos: productos propios que dan ingreso diario desde la sala de servidores, eventos que piden decisiones rápidas, el ambiente de la oficina y las calidades de los muebles, los contratos grandes con su sala de reuniones y el final de la partida: llegar a Corporación y salir a bolsa. Al terminarla se puede jugar una partida completa, de Emprendimiento a la bolsa. Se construye en diez hitos, numerados después de los de la fase 4.

### 19.1 Alcance

| Entra en la fase 5 | Queda para fases siguientes |
| --- | --- |
| Sala de servidores que funciona: racks y aire acondicionado (2.1 y 11.2) | Rasgos con efecto en el trabajo (5) |
| Productos propios: desarrollo, lanzamiento, usuarios, ingreso diario y actualizaciones (7.5 y 13.5) | Baños y sala de descanso con efecto (2.1 y 11.2) |
| Eventos con tarjeta y cuenta atrás, y su lista inicial (10) | Inversionista (14) |
| Ambiente y decoración con efecto (2 y 11.2) | Arte final y sonido (fase 7) |
| Calidades de muebles: computadora media y pro, segundo monitor, silla ergonómica y escritorio amplio (11.1) | |
| Contratos grandes, Sala de reuniones y clientes de élite (7.1 y 9.1) | |
| Corporación y salir a bolsa (9.1 y 9.5) | |

### 19.2 Decisiones técnicas

- **Sistemas:** los productos viven en un sistema propio (`Products`, autoload después de `Projects`) con sus funciones puras aparte (como `Production`); comparten con los contratos el avance por puntos, las fases y los errores. Los eventos van en otro (`Events`) que sortea, muestra y resuelve tarjetas; sus efectos llaman a las funciones públicas de los demás sistemas. Todo se comunica por `EventBus` y todo pago pasa por `Economy`.
- **Datos fuera del código:** productos (tamaños, ingreso, racks, ciclo de vida) en `data/products.json`; eventos (textos, opciones, efectos, condiciones y prevención) en `data/events.json`; muebles nuevos, calidades y ambiente en `data/furniture.json`; contratos grandes y clientes de élite en `data/contracts.json`; requisitos de etapa en `data/stages.json`.
- **Sala de servidores:** funciona con al menos un rack y aire acondicionado. Cada rack ($3,000, $100 al mes de mantenimiento) sostiene una cantidad de productos según su tamaño (13.5). Un producto sin racks suficientes pierde usuarios.
- **Desarrollo de un producto:** el jugador elige tipo y tamaño y se lo da a un equipo (o al CEO) como un contrato sin cliente, sin plazo y sin anticipo. Cuenta para el tope de proyectos en curso. Se puede lanzar cuando está terminado.
- **Lanzamiento y usuarios:** un producto lanzado tiene usuarios que crecen, se estancan y caen. Da ingreso diario («Ingreso de productos») según usuarios y calidad (de la mitad al 150 % de 13.5: más diseño y menos errores, mejor). Los vendedores suben el crecimiento. Los errores que se colaron hacen perder usuarios hasta corregirlos.
- **Actualización:** un proyecto pequeño sobre un producto lanzado que corrige sus errores y lo reaviva (vuelve a crecer).
- **Etapas:** Mediana empresa vuelve a pedir 40 empleados y 1 producto lanzado; Corporación pide 4 ejecutivos y 3 productos activos (lanzados y con usuarios).
- **Valor de la empresa:** suma lo que generan los productos (provisional: 60 días de su ingreso actual).
- **Eventos:** una tarjeta con texto corto y dos o tres opciones. El tiempo sigue corriendo y el jugador tiene 2 minutos reales para elegir, a cualquier velocidad; si no elige, el juego toma una opción al azar. No ocurren en pausa ni en modo construcción. Uno cada pocos días al inicio, más seguidos mientras más grande es la empresa; la mitad buenos y la mitad malos. Cada evento tiene condiciones (por ejemplo, sin contador), y roles o muebles que lo reducen o lo anulan.
- **Ambiente:** cada habitación tiene un ambiente que suben la decoración (plantas, cuadros, reloj, alfombras, lámparas, pecera) y que baja amontonar escritorios. El ambiente cambia la meta de ánimo de quienes trabajan ahí. Los objetos de pared se colocan en un borde con pared, como las puertas.
- **Calidades:** (fase 8: quedan dos niveles, básica y pro; las pantallas extra, hasta 2, solo van en el escritorio largo con computadora pro.) La computadora pro da más velocidad y se instala o mejora sobre el escritorio; cada pantalla extra suma un poco; la silla ergonómica hace que la energía baje más lento. (El escritorio amplio se quitó en la fase 8: el sencillo ya es rectangular.)
- **Contratos grandes:** desde Mediana empresa con 4 estrellas. La Sala de reuniones aparece para construir cuando llega la primera oferta grande y exige mesa de reuniones. Los clientes de élite llegan en Corporación: pagan más y exigen más reputación. Corporación también desbloquea el tamaño máximo del solar.
- **Salir a bolsa:** con Corporación y un valor de más de $5,000,000 aparece la opción. Muestra una pantalla de cierre con estadísticas y la partida sigue en modo libre.
- **Guardado:** los datos nuevos se exportan e importan tolerando claves ausentes; una partida de la fase 4 carga sin productos, sin eventos pendientes y con ambiente neutro.

### 19.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 40. Sala de servidores | Rack de servidores y aire acondicionado; la sala funciona con los dos; capacidad en racks y su mantenimiento | Sin aire acondicionado la sala no funciona; cada rack cobra su mantenimiento el día 1; la capacidad cuenta los racks de la sala |
| 41. Desarrollo de productos | Menú Productos: elegir tipo y tamaño, asignarlo a un equipo; avance por puntos y errores como un contrato | Sin sala de servidores que funcione no se puede empezar; un equipo avanza un producto igual que un contrato y cuenta para el tope |
| 42. Lanzamiento y ciclo de vida | Lanzar, usuarios que crecen, se estancan y caen, ingreso diario por calidad, actualización, errores en producción; etapas con productos; valor con productos | Un producto pequeño de buena calidad llega cerca de $150 al día en su mejor momento; con errores pierde usuarios; una actualización lo reaviva; Mediana empresa pide uno lanzado |
| 43. Eventos | Sistema de eventos: sorteo según frecuencia y condiciones, tarjeta con opciones y cuenta atrás de 2 minutos reales, efectos | No salen en pausa ni en construcción; sin elegir se toma una opción al azar a los 2 minutos a cualquier velocidad; la frecuencia sube con la empresa |
| 44. Lista de eventos | Los eventos de 10.2 con sus efectos, condiciones y prevención (contador, limpieza, líder, baterías de respaldo, archivero) | Con contador la inspección de impuestos no multa; con baterías el apagón no ocurre; sin limpieza aparece la oficina sucia |
| 45. Ambiente y decoración | Decoración de piso y de pared, ambiente por habitación, efecto en la meta de ánimo, penalidad por amontonar | Una habitación con plantas y cuadros sube la meta de ánimo; muchos escritorios juntos la bajan; los objetos de pared van en bordes con pared |
| 46. Calidades de muebles | Computadora media y pro, segundo monitor y silla ergonómica, con mejorar desde el escritorio (el escritorio amplio se quitó en la fase 8) | Una computadora pro rinde más que la básica; con silla ergonómica la energía baja más lento; mejorar cobra la diferencia |
| 47. Contratos grandes y Sala de reuniones | Mesa de reuniones, Sala de reuniones, ofertas grandes desde Mediana empresa, clientes de élite en Corporación | La primera oferta grande habilita la Sala de reuniones; sin sala no se acepta; los de élite solo llegan en Corporación |
| 48. Corporación y salir a bolsa | Requisitos de Corporación, tamaño máximo del solar, opción de salir a bolsa, pantalla de cierre y modo libre | Con 4 ejecutivos y 3 productos activos se llega a Corporación; con valor > $5,000,000 se puede salir a bolsa y la partida sigue |
| 49. Comprobación de la fase | Simulación sin ventana de una empresa que llega a Corporación con productos y sale a bolsa; ajuste de `data/products.json`, `data/events.json` y `data/stages.json` | La simulación llega a la bolsa sin quebrar con una política simple; los productos dan una parte visible de los ingresos; todas las pruebas anteriores siguen pasando |

### 19.4 Orden y dependencias

- **Productos:** el 40, el 41 y el 42 van en cadena y primero, porque Mediana empresa vuelve a pedir un producto lanzado y varios eventos tocan productos.
- **Eventos:** el 43 antes del 44; el 44 usa productos (servidor caído, competidor) y muebles de prevención.
- **Oficina:** el 45 y el 46 pueden ir en cualquier orden; el 45 agrega la colocación en pared que también usan el aire acondicionado y la pizarra.
- **Cierre:** el 47 antes del 48 (Corporación), y el 49 al final.

### 19.5 Riesgos de esta fase

- **Balance:** los productos pueden volver inútiles los contratos o al revés. El hito 49 revisa que los dos importen.
- **Objetos de pared:** el aire acondicionado del hito 40 llega antes que la colocación en pared del 45; mientras tanto ocupa una casilla.
- **Eventos con tiempo real:** la cuenta atrás va en segundos reales; las pruebas sin ventana la adelantan con una función propia en vez de esperar.
- **Tope de proyectos:** productos y contratos comparten el tope de proyectos en curso; hay que mostrarlo claro en Proyectos y Productos.
- **Partidas viejas:** cada sistema nuevo debe cargar sin error un guardado de la fase 4.

## 20. Plan de desarrollo: fase 6

La fase 6 llena de vida la oficina: los rasgos de cada empleado cambian cómo trabaja, los baños y la Sala de descanso pasan a importar, llegan los muebles que faltaban del catálogo, los candidatos dependen de la fama y el ambiente de la empresa, la interfaz avisa con iconos qué le pasa a cada uno y aparece el inversionista. Es la última fase de mecánicas: el pulido pasa a la fase 7 y el arte final y el sonido a la fase 8. Se construye en diez hitos, numerados después de los de la fase 5.

### 20.1 Alcance

| Entra en la fase 6 | Queda para fases siguientes |
| --- | --- |
| Rasgos con efecto en el trabajo, el ánimo y la carrera (5) | Arte final, animaciones y sonido (fase 8) |
| Historial y puntualidad en la ficha (5 y 12.4) | Versión móvil y otros idiomas (14) |
| Baños con capacidad (2.1 y 11.2) | Baños por sexo y necesidades individuales |
| Almuerzo en la oficina y pausas en la Sala de descanso (2.1 y 11.2) | |
| Muebles que faltan: nevera, microondas, mesa de comedor, sofá, dispensador de agua, mesa de ping pong, máquina expendedora, impresora, pizarra y ventanas (11.2) | |
| Candidatos según reputación, sueldo y ambiente (5.2) | |
| Iconos de estado sobre los empleados y avisos con clic (12.2) | |
| Inversionista (14) | |

### 20.2 Decisiones técnicas

- **Rasgos:** cada rasgo es un conjunto de modificadores en `data/staff.json` (`traits`) que leen las funciones que ya existen (producción, errores, energía, metas de ánimo y estrés, renuncia, competencia), sin código propio por rasgo cuando se pueda. Valores provisionales:
  - **Noctámbulo:** +20 % de puntos entre las 22 y las 6, −10 % de día; el turno de noche no le baja el ánimo.
  - **Perfeccionista:** −15 % de puntos y −40 % de errores al programar; QA perfeccionista encuentra un 25 % más.
  - **Adicto al café:** sin una cafetera en una Sala de descanso que funcione rinde −15 %; con ella recupera +2 de energía por hora trabajada. El evento «Se acabó el café» lo usa.
  - **Sociable:** +5 a la meta de ánimo de su equipo (una vez por equipo, aunque haya varios) y −5 % de sus propios puntos.
  - **Impuntual:** cada día de trabajo, 20 % de llegar una hora tarde (no trabaja esa hora) y 2 % de faltar el día.
  - **Mentor:** los Pasantes y Juniors de su equipo rinden +15 % mientras él está presente, y suben de nivel con un contrato menos.
  - **Ambicioso:** además de la competencia, si cumple los requisitos de ascenso y pasan 15 días sin ascenderlo, −15 a su meta de ánimo hasta que se le asciende («ascenso negado», 5.3).
  - **Leal:** además de la competencia, necesita el doble de días seguidos mal para avisar que renuncia.
- **Descubrir rasgos:** la entrevista revela uno (como hoy); los demás se descubren solos después de 15 días en la empresa cada uno, en orden, con aviso. La ficha y Personal muestran solo los conocidos, pero todos tienen efecto desde el primer día.
- **Historial:** cada empleado guarda errores causados (los ocultos que generó al programar), ausencias, llegadas tarde y contratos trabajados. La ficha muestra el historial y la puntualidad (% de días a tiempo).
- **Baños:** capacidad = inodoros de los baños que funcionan; hace falta 1 por cada 10 personas presentes (redondeando hacia arriba, contando al CEO). Si faltan, la meta de ánimo de todos baja 10 y la producción baja 5 % por cada inodoro que falta (hasta −20 %) por las colas. El evento «Baño dañado» quita un inodoro de la capacidad hasta pagar la reparación. Se mantienen los dos baños obligatorios; no se separan por sexo.
- **Almuerzo en la oficina:** una Sala de descanso con nevera, microondas y mesa de comedor sirve almuerzo dentro a tantos como asientos (4 por mesa). Quien almuerza dentro recupera el doble de energía en esa hora y trabaja media hora de ella (rinde la mitad de una hora normal). Los que no caben salen como hoy. El personaje camina a la mesa en vez de irse.
- **Pausas:** quien trabaja con energía bajo 40 toma una pausa de una hora en la Sala de descanso si hay un lugar libre (sofá: 2 lugares). En la pausa no produce y recupera +15 de energía. La cafetera (ya obligatoria) da +3 de energía extra a quien almuerza o descansa ahí.
- **Muebles de ánimo:** dispensador de agua +2 a la meta de ánimo de todos; mesa de ping pong +8, pero cada empleado pierde 3 % de puntos («se distrae»); máquina expendedora +3 y $2 por persona presente al día («Máquina expendedora»). Ninguno se acumula: cuenta uno de cada uno en la Sala de descanso.
- **Impresora:** en un Área de trabajo con un contador, sus efectos (descuento de mantenimiento, tasa y cobro del pago atrasado) valen ×1.25.
- **Pizarra:** objeto de pared en la Sala de reuniones. El evento «La reunión que pudo ser un correo» cuesta la mitad y los contratos grandes y de élite llegan con 10 % más de plazo.
- **Ventanas:** objeto que reemplaza un tramo de pared exterior del local (no del interior). Cada ventana suma ambiente a la habitación que da a ella; no se puede colgar nada en esa cara. Al comprar terreno, las ventanas del borde que se abre se devuelven a su precio de reventa.
- **Candidatos:** cuántos llegan y su nivel de habilidad dependen de la reputación (±1 candidato por estrella respecto de 3), del sueldo ofrecido frente al de su nivel (más alto, mejores habilidades dentro del rango) y del ambiente medio de las Áreas de trabajo. El «Premio de la industria» suma un candidato a cada vacante durante 7 días.
- **Iconos de estado:** sobre cada personaje, como mucho uno a la vez y por prioridad: sin puesto, cansado (energía bajo 30), molesto (ánimo bajo 30 o aviso de renuncia), estresado (estrés desde 70) y sin tarea (su equipo no lleva proyecto). Se calculan al cambiar la hora, no cada cuadro.
- **Avisos con clic:** un aviso puede llevar a quién se refiere (`EventBus.notice` con un destino opcional: empleado, contrato, producto, habitación o menú). Un clic abre su ficha o su menú.
- **Inversionista:** un evento (`data/events.json`) desde Pequeña empresa con valor positivo: ofrece entre el 10 y el 25 % del valor de la empresa en efectivo a cambio de un porcentaje de los ingresos (contratos y productos) durante 12 a 24 meses. Se acepta o se rechaza desde la tarjeta. El pago se cobra el día 1 («Pago al inversionista»), cuenta como gasto en Empresa y Banco, y lo que falta por pagar resta del valor de la empresa (estimado con el ingreso del mes pasado). Uno a la vez.
- **Datos fuera del código:** rasgos en `data/staff.json`; muebles nuevos en `data/furniture.json` y `data/rooms.json`; baños, almuerzo y pausas en una sección nueva de `data/staff.json`; candidatos en `hiring`; inversionista en `data/events.json` y `data/bank.json`.
- **Guardado:** las claves nuevas se importan tolerando su falta; una partida de la fase 5 carga con los rasgos que ya tenía, historial vacío y sin inversionista.

### 20.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 50. Rasgos de producción | Noctámbulo, perfeccionista, sociable y mentor con sus efectos; descubrir rasgos con el tiempo | Un noctámbulo rinde más de noche; un perfeccionista hace menos errores y menos puntos; un mentor acelera a los juniors de su equipo; los rasgos se descubren a los 15 días |
| 51. Rasgos de conducta e historial | Impuntual, adicto al café, ambicioso y leal; historial y puntualidad en la ficha | Un impuntual llega tarde y falta a veces y se ve en su puntualidad; sin cafetera el adicto rinde menos; al ambicioso le baja el ánimo si no se le asciende; el leal tarda más en renunciar |
| 52. Baños con capacidad | Capacidad por inodoros, efecto en ánimo y producción, baño dañado quita capacidad | Con 25 personas y 2 inodoros baja el ánimo y la producción; con 3 no; el evento de baño dañado quita uno hasta repararlo |
| 53. Almuerzo en la oficina | Nevera, microondas y mesa de comedor; almuerzo dentro según asientos | Con la sala armada, quien cabe almuerza dentro, recupera más energía y rinde media hora; los demás salen |
| 54. Sala de descanso y pausas | Sofá, dispensador de agua, mesa de ping pong y máquina expendedora; pausas con energía baja | Un cansado toma una pausa si hay sofá libre y recupera energía; el ping pong sube el ánimo y baja un poco la producción; la máquina da su ingreso diario |
| 55. Impresora, pizarra y ventanas | Impresora para el contador, pizarra en la Sala de reuniones, ventanas en las paredes exteriores | La impresora mejora al contador; con pizarra la reunión inútil cuesta la mitad y los grandes traen más plazo; una ventana sube el ambiente y no se pone en paredes interiores |
| 56. Candidatos según la empresa | Cantidad y calidad de candidatos por reputación, sueldo ofrecido y ambiente; el premio suma candidatos | Con 5 estrellas llegan más candidatos que con 1; ofrecer más sueldo trae mejores habilidades |
| 57. Iconos de estado y avisos | Iconos sobre los empleados por prioridad; avisos con destino que abren ficha o menú | Un empleado cansado muestra su icono y deja de mostrarlo al recuperarse; un clic en el aviso de renuncia abre su ficha |
| 58. Inversionista | Evento del inversionista, pago mensual, efecto en Empresa, Banco y valor | Aceptar da el efectivo y cobra el porcentaje cada día 1 hasta terminar; el valor descuenta lo que falta por pagar; rechazar no cambia nada |
| 59. Comprobación de la fase | Simulación sin ventana con rasgos, baños, descanso e inversionista; ajuste de `data/staff.json`, `data/furniture.json` y `data/events.json` | La empresa de la fase 5 sigue llegando a la bolsa sin quebrar; armar baños y Sala de descanso compensa su costo; los rasgos se notan sin decidir solos la partida; todas las pruebas anteriores siguen pasando |

### 20.4 Orden y dependencias

- **Rasgos:** el 50 antes del 51; el 51 usa la cafetera, que ya existe, y los ascensos de la fase 4.
- **Oficina:** el 52, el 53 y el 54 en ese orden; el 54 agrega los lugares de la Sala de descanso que también usa el almuerzo.
- **Muebles sueltos:** el 55 puede ir en cualquier momento después del 52; las ventanas usan la colocación en pared del hito 45.
- **Interfaz:** el 57 después del 51, porque los iconos usan el estado de los rasgos y las ausencias.
- **Cierre:** el 58 antes del 59, y el 59 al final.

### 20.5 Riesgos de esta fase

- **Balance:** los rasgos multiplican los efectos que ya existen; varios juntos pueden dejar a alguien inútil o demasiado bueno. El hito 59 revisa los extremos.
- **Rendimiento:** iconos, pausas y almuerzo agregan trabajo por hora; las pruebas largas no deben volver a pasar de un minuto.
- **Personajes:** almorzar dentro y tomar pausas cambia adónde caminan; los caminos deben seguir funcionando con la Sala de descanso llena.
- **Ventanas:** cambian la regla de que el contorno del local no se toca; hay que cuidar el terreno nuevo y el embargo.
- **Partidas viejas:** cada sistema nuevo debe cargar sin error un guardado de la fase 5.

## 21. Plan de desarrollo: fase 7

La fase 7 pule el juego para que alguien que nunca lo vio pueda jugarlo de principio a fin sin ayuda: menús completos, opciones que se recuerdan, un tutorial guiado con ayuda en cada menú, interfaz escalable y exportaciones listas para escritorio. El juego sale solo en escritorio (macOS, Windows y Linux): no hay versión para Android ni iOS. No agrega mecánicas ni cambia el balance. El arte final, las animaciones y el sonido quedan para la fase 8. Se construye en ocho hitos, numerados después de los de la fase 6.

### 21.1 Alcance

| Entra en la fase 7 | Queda para fases siguientes |
| --- | --- |
| Ajustes completos que se guardan entre partidas (12.3) | Arte final, animaciones y sonido (fase 8) |
| Menú principal completo: continuar, nueva partida, cargar, ajustes, salir | Versiones para Android e iOS y controles táctiles (no se harán) |
| Menú de pausa y confirmaciones al salir o pisar una partida | Otros idiomas (14) |
| Tutorial guiado de la primera partida y ayuda en cada menú | Logros, estadísticas en línea y nube |
| Interfaz escalable (12.1) | Mecánicas nuevas o cambios de balance |
| Exportación de escritorio (macOS, Windows y Linux) | |

### 21.2 Decisiones técnicas

- **Opciones:** un autoload nuevo `Settings` guarda las opciones del jugador en `user://settings.cfg` (`ConfigFile`), aparte de las partidas: pantalla completa, escala de la interfaz, autoguardado, velocidad inicial del reloj, pausa al abrir Construir y pausa automática al perder el foco. Se aplican al iniciar y al cambiarlas; un valor que falta o no sirve vuelve a su valor por defecto (en `data/settings.json`). Las pruebas usan otro archivo, como con `SaveManager.save_dir`.
- **Ajustes en la partida:** el panel de Ajustes suma Cargar (con el resumen de cada ranura) y la sección Opciones; cargar o salir sin guardar pide confirmación. El sonido aparece en la fase 8.
- **Menú principal:** Continuar carga la partida más reciente (autoguardado o ranura); Nueva partida avisa si va a reemplazar el autoguardado; Ajustes abre las mismas opciones; Salir cierra el juego.
- **Pausa:** el botón Pausa del reloj sigue igual; Esc abre un menú de pausa con Seguir, Guardar, Cargar, Ajustes y Salir al menú, y cierra primero el panel que esté abierto.
- **Tutorial:** una lista de pasos en `data/tutorial.json` (texto, qué resaltar y la condición que lo da por cumplido, leída del estado de los sistemas como los objetivos). Arranca en la primera partida nueva, se puede saltar y retomar desde Ajustes, y se guarda en la partida. Resalta el botón o la zona de la oficina con un marco y una flecha; no bloquea el resto de la interfaz.
- **Ayuda en los menús:** cada panel izquierdo y el modo construcción tienen un botón «?» que muestra un texto corto de `data/help.json`. Los botones sin texto llevan una descripción emergente.
- **Interfaz escalable:** la escala (100, 125 o 150 %) cambia `content_scale_factor`; los paneles se acomodan sin taparse a 1280×720 con 150 %. Todo botón mide al menos 44 px de alto para que el clic sea cómodo; nada depende de pasar el ratón por encima.
- **Exportación:** `export_presets.cfg` con macOS, Windows y Linux; todos excluyen `addons/panku_console/*` y `scripts/debug/*` (ver CLAUDE.md). Una prueba revisa que la versión de lanzamiento arranque sin las herramientas de desarrollo.
- **Datos fuera del código:** opciones por defecto en `data/settings.json`, pasos del tutorial en `data/tutorial.json` y ayudas en `data/help.json`.
- **Guardado:** una partida de la fase 6 carga sin tutorial (como si ya lo hubiera terminado).

### 21.3 Hitos

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 60. Opciones y Ajustes | Autoload `Settings` con `user://settings.cfg`; Ajustes con Cargar, Opciones y confirmaciones | Una opción cambiada se aplica y sigue igual al reiniciar; un archivo roto vuelve a los valores por defecto; cargar desde la partida pide confirmación y carga la ranura |
| 61. Menú principal | Continuar, Nueva partida con aviso, Cargar, Ajustes y Salir | Continuar abre la partida más reciente; sin partidas no aparece; nueva partida avisa si hay autoguardado |
| 62. Menú de pausa | Esc abre la pausa con Seguir, Guardar, Cargar, Ajustes y Salir; cierra primero el panel abierto | Con un panel abierto Esc lo cierra; sin panel abre la pausa y el reloj se detiene; Seguir vuelve a como estaba |
| 63. Tutorial: primeros pasos | Motor de pasos con resaltado y flecha; pasos de cámara, Construir, puestos y la primera contratación | Una partida nueva muestra el primer paso; al cumplir la condición pasa al siguiente; saltarlo lo cierra y se guarda |
| 64. Tutorial: el negocio y ayuda | Pasos de contratos, nómina y Banco; botón «?» en cada menú con su texto | El tutorial llega hasta la primera entrega; cada menú abre su ayuda; una partida vieja carga sin tutorial |
| 65. Interfaz escalable | Escala de 100/125/150 %, botones de 44 px, descripciones emergentes | A 150 % en 1280×720 ningún panel se sale de la pantalla ni tapa la barra; todos los botones miden al menos 44 px |
| 66. Exportación de escritorio | Presets de macOS, Windows y Linux sin herramientas de desarrollo; icono y nombre | La exportación de prueba arranca, llega al menú principal y no carga Panku ni DevTools |
| 67. Comprobación de la fase | Recorrido completo de una partida nueva solo con el ratón siguiendo el tutorial; revisión de tiempos | Se juega del menú a la primera entrega sin teclado; todas las pruebas anteriores siguen pasando y ninguna larga pasa de un minuto |

### 21.4 Orden y dependencias

- **Opciones primero:** el 60 antes del 61 y el 62, que reutilizan el panel de Ajustes y las confirmaciones.
- **Tutorial:** el 63 antes del 64; los dos después del 62 para que el tutorial pueda pausar y retomar.
- **Interfaz:** el 65 antes del 66, para exportar con la escala ya resuelta.
- **Cierre:** el 67 al final.

### 21.5 Riesgos de esta fase

- **Pruebas sin ventana:** la escala, la pantalla completa y el foco no existen en `--headless`; las pruebas comprueban el valor aplicado, no la ventana.
- **Tutorial frágil:** si los pasos dependen de nombres de nodos, cambiar la interfaz lo rompe; cada panel expone sus botones con funciones (`get_…_button`) como hoy.
- **Exportación:** necesita las plantillas de exportación de Godot; si no están, el hito deja el preset y la prueba lo reporta en vez de fallar en silencio.
- **Partidas viejas:** el estado del tutorial se importa tolerando su falta.

### 21.6 Agregados antes de la fase 8

Pedidos aparte de la lista de la fase 7, hechos antes de empezar la fase 8 (arte y sonido). Se numeran después del 67.

- **Mapa y cámara (hito 68):** zoom suave en más niveles, inercia, teclado y borde de la pantalla, girar la vista de a 90° y un mapa con calle, árboles y el límite del solar marcado.
- **Puerta doble de vidrio (hito 69):** la puerta de la Recepción. Es una pieza de borde que solo reemplaza la puerta de entrada de la oficina (el borde entre la casilla de entrada y la calle): ahí se cambia puerta normal por puerta de vidrio y al venderla vuelve a ser una puerta normal (la del contorno no se cobra ni se devuelve, como la pared con la ventana). Deja pasar como cualquier puerta y cuenta como puerta para las habitaciones. Cuesta $900, se vende a la mitad y suma 6 puntos de ambiente a la habitación a la que da, normalmente la Recepción (como un adorno o una ventana). Se dibuja con marco oscuro y dos hojas de vidrio. No cuenta como bien para el banco. Herramienta «Puerta de vidrio» en la sección Estructura de Construir. La empresa de prueba (`starting_company`) la trae puesta como ejemplo.
- **Personas en la oficina (sin número de hito):** caminan a una casilla por segundo a 1x (el doble solo si tienen prisa: quien llega después de su hora y el candidato al que llaman a la entrevista) y nunca hay dos en la misma casilla: quien encuentra ocupado el paso espera, busca otro camino y, si dos quedan de frente en un pasillo, pasan tras unos segundos. Al empezar la jornada cada empleado entra entre las 7:30 y las 8:10 (de 30 minutos antes a 10 después de su hora), fijo por persona y día: la mayoría llega antes, uno de cada diez llega unos minutos tarde y los impuntuales la mitad de las veces (y nunca más de 10 minutos antes). Quien llega antes espera de pie en la Sala de descanso o, si no hay, da vueltas por la oficina, y a su hora va a su puesto. Al terminar la jornada (no al salir a almorzar) cada uno se va entre la hora en punto y 20 minutos después. Solo cambia lo que se ve: la producción y las tardanzas de una hora del rasgo impuntual siguen contando por hora. El CEO, que es el jugador, abre la oficina: llega siempre puntual a las 7:30 (30 minutos antes de su hora) y va a su escritorio, así nadie entra antes que él; rinde desde las 8. Con la oficina vacía el reloj salta hasta el primero que entra.
- **Construir por secciones (sin número de hito):** el panel de construcción tenía todas las herramientas a la vez y tapaba casi todo el mapa, también el terreno que se quería comprar. Ahora arriba se elige la sección (Estructura, Muebles, Habitaciones o Terreno, con la ayuda y Salir) y solo se ven sus herramientas; los muebles van además por categoría (Trabajo, Servicios, Descanso y Decoración), con Girar y Mejorar siempre a mano. Terreno muestra cómo elegirlo y Comprar. El tutorial resalta la sección o la categoría que hay que abrir antes de la herramienta.
- **Guía de sprites a 128 px (sin número de hito):** las reglas para generar el arte final de la fase 8 pixel por pixel (escala ×2, lienzo de 128×128 con el rombo del piso abajo, pisos que empalman con 4 variantes, luz, muebles con 4 rotaciones, paredes altas y bajas, personajes) están en `docs/sprites_128.md`. Es solo la guía: el juego todavía dibuja todo con código.
- **Vista fija y paredes bajas (sin número de hito):** se quitó girar la vista (botón ↻, Q y E): la oficina se ve siempre desde la misma esquina. Como en los juegos de construir casas, las paredes del fondo (las del contorno que dan al exterior por detrás) se ven a su alto, y todas las demás, las del frente y las interiores, se dibujan bajitas para ver lo que pasa adentro. Lo colgado en una pared baja se ve chico y pegado abajo.
- **Suelo con más detalle (sin número de hito):** el pasto y los pisos se veían pixelados de cerca porque cada casilla era una imagen de 64×32 ampliada. Ahora se pintan con 4 veces más detalle y se suavizan al dibujarse, sin cambiar el tamaño de la casilla: la cerámica tiene losas con junta y bisel, la madera tablones con veta, la alfombra cuadros, el pasto manchas y briznas, y el camino, la acera y la calle grava, baldosas y asfalto. Los muebles y personajes siguen en pixel art.
- **Cuartos de casilla para muebles chicos (sin número de hito):** para decorar con más libertad sin achicar la casilla (que obligaría a rehacer precios, habitaciones, caminos y guardados), se siguió la idea de Timberborn: construir en casillas enteras y dejar que algunas piezas compartan casilla. La casilla sigue siendo de 1 m², pero la planta pequeña, el zafacón, el dispensador de agua y la lámpara de pie ocupan solo un cuarto: caben hasta 4 en una casilla, en el cuarto que marca el ratón, y nunca junto a un mueble grande en la misma casilla. La casilla con muebles chicos sigue tapando el paso (una persona por casilla). Vender y girar eligen el mueble del cuarto bajo el ratón. Las partidas viejas ponen los suyos en el primer cuarto.
- **Losas más chicas y terreno arrastrando (sin número de hito):** cada casilla de 1 m² se dibuja como 2×2 losas (losas de 16 px de alto en vez de 32), solo el dibujo: la lógica, los precios por m² y las habitaciones no cambian. Comprar terreno ya no se hace con lado, ancho, fondo y posición: en la sección Terreno se arrastra un rectángulo en el mapa, se ve qué casillas entran y el precio ($150/m² más la cerámica a mitad de precio, como antes) y se pulsa Comprar. Entra la parte del rectángulo que está dentro del solar, no es del local ni es la calle de la entrada y toca el local; lo demás se recorta. Se quitaron las restricciones de antes: el terreno ya no tiene que ir pegado a un lado completo, puede tocar varias habitaciones y no se rechaza por cuadros colgados (esa pared queda cerrada). Cada pedazo nuevo se abre solo hacia un espacio del local (el pasillo antes que una habitación), así dos habitaciones nunca se juntan; solo se rechaza si una habitación se perdería.
- **Turno de limpieza (sin número de hito):** el personal de limpieza trabaja de lunes a viernes de 7 a 15 y almuerza a las 11. Entra siempre a las 7:20, se sienta en su armario y a las 7:30 empieza a trapear; la primera hora solo limpia esa media hora. A las 15:00 se va en punto. Tiene sus propios rasgos: Meticuloso (limpia 25 % más), Despistado (20 % menos), Madrugador (llega y empieza 20 minutos antes), Alegre (+2 a la meta de ánimo de toda la empresa, una vez aunque haya varios), Impuntual, Leal y Adicto al café; los demás cargos no los tienen. No entra en equipos ni, por eso, en proyectos.
- **Entrevistas citadas (sin número de hito):** las oficinas (Ejecutiva y única) funcionan con dos sillas, la de quien trabaja ahí y una de visita. «Entrevistar» ya no empieza al momento: cita al candidato para el día siguiente de quien entrevista, a su hora de entrada (ver 5, Entrevista). El candidato llega antes, espera en la Recepción y a la hora lo llaman: camina a la oficina y la media hora de entrevista empieza cuando se sienta en la silla de visita.

| Hito | Qué se construye | Cómo se comprueba |
| --- | --- | --- |
| 68. Mapa y cámara | Zoom de 0.25 a 4 con animación, inercia, WASD y borde, girar la vista, terreno con calle y árboles | La casilla bajo el ratón no se mueve al hacer zoom; girar cuatro veces vuelve al principio y cada casilla sigue en su lugar; el mapa se rehace al comprar terreno |
| 69. Puerta doble de vidrio | Pieza de borde que reemplaza la puerta de entrada, con su herramienta y su dibujo | Solo se pone en la entrada; cobra $900 y al venderla devuelve $450 y queda la puerta normal; deja pasar al CEO; suma 6 puntos al ambiente de la Recepción; se guarda y se carga |
