---
name: ea-read
description: Lee un modelo de Sparx Enterprise Architect para explicarlo, auditarlo, documentarlo o exportarlo a XMI. Úsala cuando el usuario diga "qué hay en mi modelo de EA", "revisa/audita la arquitectura en Enterprise Architect", "documenta este paquete", "exporta a XMI", "compara EA con el código", o "genera la documentación del modelo".
---

# Leer y auditar Enterprise Architect

Requiere conexión activa (`ea-connect`). **ea-cli** está definido en `ea-setup`.

## Leer
- Estructura: `ea-cli tree -Depth 3` (o `-Package <ruta|GUID>`).
- Contenido: `ea-cli read -Package <ruta|GUID>` → elementos (tipo, estereotipo, notas, estado),
  conectores y diagramas del paquete. Recorre subpaquetes con `read` sobre cada uno.

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
