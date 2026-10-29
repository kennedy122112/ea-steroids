---
name: ea-read
description: Lee un modelo de Sparx Enterprise Architect para explicarlo, auditarlo, documentarlo o exportarlo a XMI, incluidos los procesos BPMN 2.0 (pools, carriles, tareas, compuertas, eventos y flujos). Úsala cuando el usuario diga "qué hay en mi modelo de EA", "revisa/audita la arquitectura en Enterprise Architect", "lee/explica/documenta este proceso BPMN de EA", "documenta este paquete", "exporta a XMI", "compara EA con el código", o "genera la documentación del modelo".
---

# Leer y auditar Enterprise Architect

Requiere conexión activa (`ea-connect`). **ea-cli** está definido en `ea-setup`.

## Leer
- Estructura: `ea-cli tree -Depth 3` (o `-Package <ruta|GUID>`).
- Contenido: `ea-cli read -Package <ruta|GUID> [-Tags]` → elementos (tipo, estereotipo, notas, estado),
  también los anidados (lo que va dentro de un pool, un carril, un componente o un nodo, con `parent`),
  conectores y diagramas del paquete. `-Tags` suma los tagged values con valor (BPMN, ArchiMate y
  otros perfiles guardan ahí sus propiedades). Recorre subpaquetes con `read` sobre cada uno.

## Procesos BPMN 2.0
`ea-cli bpmn -Package <ruta|GUID>` lee el paquete como proceso:
- `pools` con sus carriles (`lanes`).
- `nodes`: cada tarea, subproceso, compuerta, evento y dato con su tipo BPMN (`User`, `Service`,
  `Send`…; `Exclusive`, `Parallel`…; `Start`, `End`, `Intermediate / Timer`…), su pool y su carril.
- `sequenceFlows` con nombre y condición (`conditionExpression`), `messageFlows` entre pools y
  `associations` (datos, anotaciones).
- `steps`: el recorrido numerado desde los eventos de inicio, con a dónde va cada paso y con qué
  condición. `unreachable` lista lo que ningún inicio alcanza: es un hallazgo de auditoría.

Para explicarlo al usuario, cuenta el proceso por pasos y por responsable (carril), con las
decisiones y sus condiciones. Para auditarlo, revisa además: compuertas sin nombre o sin
condiciones en sus salidas, tareas sin tipo, caminos sin evento de fin, nodos inalcanzables,
carriles vacíos y flujos de mensaje dentro del mismo pool.

Un `.bpmn` suelto (exportado de Bizagi u otra herramienta) no se lee aquí: hay que importarlo
primero en EA con su importación de BPMN 2.0 XML (cinta *Publish*) o leerlo con bizagi-steroids.

## Auditar (informe priorizado, sin modificar nada)
Revisa y reporta con ejemplos concretos:
- Elementos **sin conectores** (huérfanos) o que no aparecen en ningún diagrama.
- Elementos **sin notas** o con nombres genéricos/duplicados.
- Requisitos sin realización/traza; componentes sin interfaz.
- Mezcla de idiomas o de convenciones de nombre; estereotipos inconsistentes.
- Si hay código disponible: componentes del modelo que ya no existen en el código y viceversa.
Propón correcciones; aplícalas solo si el usuario lo autoriza (con `ea-model`).

## Documentar
Arma la documentación a partir de `read` (descripción por paquete, tabla de elementos,
relaciones) en el formato que pida el usuario: doc, Word o Markdown.

## Ver un diagrama
`ea-cli image -Package <ruta|GUID> [-Diagram <nombre>] -Path <salida.png>` → PNG del diagrama para revisarlo o incluirlo en documentación.

## Exportar
`ea-cli export -Package <ruta|GUID> -Path <salida.xmi>` → XMI 2.1 con diagramas, importable en
otra instancia de EA u otras herramientas UML.

No le muestres comandos al usuario. Ejecútalos tú y entrega conclusiones en lenguaje sencillo.
