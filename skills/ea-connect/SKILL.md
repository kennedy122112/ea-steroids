---
name: ea-connect
description: Conecta el agente con Sparx Enterprise Architect abierto en esta PC (API COM, sin MCP) y fija el paquete de trabajo. Úsala cuando el usuario diga "conecta con EA", "conecta con Enterprise Architect", "trabaja en mi modelo de EA", cuando un comando ea-cli falle por conexión, o antes de cualquier tarea de modelado en EA.
---

# Conectar con Enterprise Architect

Si es la primera vez o ea-cli no existe, sigue antes `ea-setup` (allí se define **ea-cli**).

## 1. Estado
`ea-cli status` → debe devolver `ok: true` y `modelLoaded: true`. Si no, ver `ea-setup`.

## 2. Ubicarse en el modelo
`ea-cli tree -Depth 2` muestra modelos raíz y paquetes con su GUID.
- Si el usuario nombra un paquete, úsalo como ruta `Modelo/Paquete/Sub` o por GUID.
- Si no lo nombra, ea-cli usa **el paquete seleccionado en el Project Browser** de EA, y si no hay
  ninguno, el primer modelo raíz. Dile al usuario dónde vas a escribir antes de crear nada.

## 3. Reglas de trabajo
- **Antes de modificar**, lee el paquete (`ea-cli read -Package ...`) para no duplicar elementos.
- `build` es idempotente por nombre: reejecutarlo no duplica elementos, conectores ni objetos del diagrama.
- No borres elementos ni paquetes sin confirmación explícita del usuario (no hay papelera en EA).
- Si el repositorio es compartido (SQL Server / Pro Cloud) o tiene control de versiones/bloqueos,
  avisa antes de escribir; un paquete bloqueado hace fallar `Update()`.

No le muestres comandos al usuario. Ejecútalos tú e informa en lenguaje sencillo.
