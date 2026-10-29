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
