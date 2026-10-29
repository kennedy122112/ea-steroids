---
name: ea-model
description: Crea modelos y diagramas reales y editables en Sparx Enterprise Architect a partir de lenguaje natural o de un repositorio de código - componentes, clases, despliegue, casos de uso, requisitos, actividades, ArchiMate o BPMN. Úsala cuando el usuario diga "modela en EA", "crea el diagrama de componentes/clases/despliegue en Enterprise Architect", "arma la arquitectura en EA", "pasa este código a EA", "documenta la arquitectura en Sparx".
---

# Modelar en Enterprise Architect

Requiere conexión activa (`ea-connect`). **ea-cli** está definido en `ea-setup`.

## Flujo
1. Entiende qué se pide y elige el tipo de diagrama (tabla abajo). Si viene de código, recorre
   el repositorio primero (módulos, servicios, BD, dependencias) y modela lo que existe, no lo que suponga.
2. Lee el destino: `ea-cli read -Package <ruta>` para reutilizar elementos que ya existan.
3. Escribe un **spec JSON** (UTF-8) y ejecuta `ea-cli build -Spec <archivo.json>`. Los spec son la
   fuente de cada vista (rehacerla es volver a correr `build`): guárdalos junto al `.qea`, en
   `vistas/NN-nombre.json` de la carpeta del modelo, nunca solo en una carpeta temporal.
   Las imágenes, en `imagenes/NN-nombre.png`.
4. Revisa la salida (`elements`, `newConnectors`, `diagram.objects`) y **mira el resultado**:
   `ea-cli image -Package <ruta> [-Diagram <nombre>] -Path <salida.png>` y lee el PNG. Corrige
   solapes, nombres o conectores que falten antes de dar el trabajo por terminado.
5. Cuéntale al usuario qué creó y dónde (paquete y diagrama). EA abre el diagrama solo.

## Spec JSON
```json
{
  "parent": "Modelo/Arquitectura",          // opcional: ruta o GUID; por defecto el paquete seleccionado
  "package": "SIAF-RP - Componentes",        // se crea si no existe; omítelo para escribir en parent
  "elements": [
    { "id": "web", "name": "Portal Web", "type": "Component", "stereotype": "Angular", "notes": "SPA" },
    { "id": "api", "name": "API Presupuesto", "type": "Component" },
    { "id": "db",  "name": "BD Presupuesto", "type": "Class", "stereotype": "database",
      "attributes": ["id_pliego", {"name": "monto", "type": "decimal"}],
      "operations": [{"name": "calcular", "returnType": "decimal"}] }
  ],
  "connectors": [
    { "from": "web", "to": "api", "type": "Dependency", "name": "REST/JSON" },
    { "from": "api", "to": "db",  "type": "Association" }
  ],
  "diagram": { "name": "Vista de componentes", "type": "Component", "layout": "auto", "columns": 3 }
}
```
`id` es solo para enlazar conectores dentro del spec; en EA cuenta el `name`.

**Elementos de otro paquete** (vistas de trazabilidad): `{ "id": "b_req", "ref": "Model/SIAF-RP/03 Backend", "name": "requests" }`
reutiliza el elemento existente (sin crearlo ni modificarlo) para conectarlo y ponerlo en el diagrama.
Así una vista cruza paquetes sin duplicar elementos. EA pinta además los conectores que ya existían
entre esos elementos; para ver solo los del spec, `"diagram": { ..., "hideOtherConnectors": true }`.

## Diagramas de clases

- Atributo completo: `{ "name": "monto", "type": "Decimal", "stereotype": "PK|FK|unique", "lower": "0", "upper": "1", "default": "0", "notes": "…" }`.
  Se actualizan si ya existen.
- Asociación con multiplicidad y roles: `{ "from": "Linea", "to": "Asiento", "type": "Association", "fromCard": "0..*", "toCard": "1", "fromRole": "lineas", "toRole": "asiento" }`.
  Dos asociaciones entre las mismas clases se distinguen por `toRole`.
- Vistas que se referencian entre sí: la clase de otro paquete va como `ref` con `"optional": true` y
  `"compact": true` (solo el nombre). Corre `build` de todas las vistas dos veces: la primera crea las
  clases y la segunda las asociaciones que cruzan paquetes (`skippedConnectors` dice cuántas faltan).
- **Desde Prisma**: `python -I ~/.ea-steroids/bin/prisma_a_spec.py <dominios.json> <carpeta>` genera un spec
  por dominio (clases con sus campos, PK/FK/unique, enum, y cada relación con su multiplicidad); la
  documentación de `dominios.json` está al inicio del script. Un modelo sin dominio es un error.

## Derivar vistas desde un proceso BPMN

Cuando el usuario pida casos de uso, modelo de datos u otras vistas "a partir del BPMN" (o "del
proceso"), lee primero el proceso con `ea-cli bpmn -Package <ruta>` y arma cada vista con `build`:

| Del BPMN | Pasa a |
|---|---|
| Carril (lane) | **Actor** (un rol de la organización) |
| Pool externo / caja negra | **Actor** externo (otro sistema u organización) |
| Tarea de usuario o manual | **Caso de uso** del actor de su carril (nómbralo con verbo + objeto: «Registrar solicitud de compra») |
| Tarea de servicio, de envío o de script | Caso de uso **del sistema**: va como «extend» (si depende de una decisión, con la condición entre corchetes) o «include» del caso de uso que lo dispara |
| Compuerta | Parte del caso de uso de la tarea que decide; sus salidas son los «extend» con su condición |
| Flujo de mensaje | Asociación del caso de uso con el actor externo |
| Lo que se registra, revisa o envía (solicitud, orden…) | **Clase** del modelo de datos; sus estados salen del recorrido (enumeración) |
| Variables de las condiciones (`aprobada == true`) | **Atributos** de esa clase |
| Carriles | Roles: enumeración y una clase de persona (Empleado, Usuario…) |
| Temporizadores | Atributos de fecha o plazo (y notas en el caso de uso) |

Reglas:
- En las **notas** de cada elemento derivado escribe su origen («Origen BPMN: tarea de usuario
  «Registrar solicitud»») y marca como **Supuesto** todo lo que el BPMN no dice (atributos de
  negocio, tipos de dato, cardinalidades dudosas). Cuéntale al usuario cuáles son los supuestos.
- Crea además una vista de **trazabilidad**: cada caso de uso y cada clase con un `Dependency`
  estereotipo `trace` hacia su tarea o compuerta de origen (los elementos del BPMN entran como
  `ref`; `ref` encuentra también los que están dentro de carriles).
- Usa `layout: "grid"` y `hideOtherConnectors: true` en las tres vistas.
- Ejemplo completo: `examples/derivados-compra/` (casos de uso, modelo de datos y trazabilidad
  derivados del proceso de compra).

## Tipos útiles
| Diagrama (`diagram.type`) | Elementos (`type`) | Conectores (`type`) |
|---|---|---|
| `Component` | Component, Interface, Artifact | Dependency, Realisation, Assembly |
| `Logical` (clases) | Class, Interface, Enumeration | Association, Aggregation, Generalization, Dependency |
| `Deployment` | Node, Device, ExecutionEnvironment, Artifact | Association, Deployment, CommunicationPath |
| `Use Case` | Actor, UseCase, Boundary | UseCase, Association, Include (stereotype "include") |
| `Activity` | Activity, Action, Decision (inicio/fin: `StateNode`, ajustar `Subtype` 100/101 vía `eval`) | ControlFlow, ObjectFlow |
| `Custom` (requisitos) | Requirement | Realisation, Dependency (stereotype "trace") |
| ArchiMate 3 | `ArchiMate3::ApplicationComponent`, `ArchiMate3::Node`, `ArchiMate3::BusinessProcess`… como `stereotype` sobre type `Component`/`Activity` | stereotypes `ArchiMate3::Serving`, `ArchiMate3::Flow` |

Base de datos: Class con stereotype `table` (o `database` para el contenedor).
Si un tipo no se renderiza como esperas, léelo de vuelta con `read` y ajusta; no inventes tipos.

## Diseño del diagrama
- `layout: "auto"` usa el layout automático de EA; sin él, ea-cli coloca en rejilla (`columns`).
- `layout: "grid"` + `"row"`/`"col"` en cada elemento: posición exacta por celda, y recoloca también
  lo que ya estaba en el diagrama (borra los quiebres viejos de los conectores). Ajustes opcionales
  en `diagram`: `cellWidth` (150), `cellHeight` (70), `gapX` (70), `gapY` (90).
  **Es lo mejor para vistas de más de ~12 elementos**: el auto-layout de EA las deja en una franja
  muy ancha y con cruces. Diseña por capas (lo que se usa arriba, lo que usa abajo; en trazabilidad,
  el consumidor en la fila del medio), pon cerca lo que se conecta y evita que una línea recta pase
  por la celda de otro elemento. Revisa el PNG y mueve celdas hasta que no haya cajas tapadas.
- Más de ~15 elementos → divide en varios diagramas/paquetes por capa o dominio.
- Nombres en el idioma del usuario; notas cortas con la responsabilidad del elemento.

## Cambios avanzados
Para lo que `build` no cubre (mover objetos, colores, etiquetas, tagged values, borrar con
permiso del usuario), escribe un `.ps1` con la API COM de EA usando `$repo` y ejecútalo con
`ea-cli eval -Script <archivo.ps1>`. Tras cada `AddNew` llama `Update()` y luego `Refresh()` a la colección.

No le muestres comandos ni JSON al usuario salvo que lo pida.
