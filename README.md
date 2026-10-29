# ea-steroids

Skills para que un agente de IA (Claude Code, Codex, OpenCode, Antigravity…) controle
**Sparx Enterprise Architect** en local: crear paquetes, elementos, conectores y diagramas
desde lenguaje natural o desde un repositorio de código, leer y auditar modelos, exportar a
XMI y a PNG. Sin MCP, sin API key y sin nube: habla con EA por su API COM.

Hermano de figma-steroids y bizagi-steroids.

## Requisitos

- Windows con Sparx Enterprise Architect 16 o 17 instalado (probado con 17.2 Trial, 64 bits).
- Windows PowerShell 5.1 (viene con Windows). Nada más.

## Instalar

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

Enlaza las skills (junctions) en cada agente que encuentre y deja `~/.ea-steroids` apuntando a
esta carpeta. Editar una skill aquí la cambia en todos. `-Uninstall` quita los enlaces.

| Agente | Carpeta de skills |
|---|---|
| Claude Code | `~/.claude/skills` |
| Codex (y otros que leen `.agents`) | `~/.agents/skills` |
| OpenCode | `~/.config/opencode/skills` |
| Antigravity | `~/.gemini/antigravity/skills` |

**Codex** corre en un sandbox que no alcanza el EA abierto: necesita acceso completo para
estas tareas (ea-cli responde `reachable: false` y la skill le indica pedirlo).

## Contenido

| Ruta | Qué es |
|---|---|
| `bin/ea-cli.ps1` | Puente COM. Comandos: `status`, `open`, `tree`, `read`, `build`, `export`, `image`, `eval`. Salida JSON |
| `bin/prisma_a_spec.py` | Genera specs de diagramas de clases desde un `schema.prisma` (Python, solo biblioteca estándar): un diagrama por dominio, PK/FK, enum y multiplicidades |
| `skills/ea-setup` | Primer arranque: EA instalado, 32/64 bits, abrir o crear un `.qea` |
| `skills/ea-connect` | Conectar con el EA abierto y elegir el paquete de trabajo |
| `skills/ea-model` | Crear vistas desde un spec JSON (`build`): elementos, conectores, diagrama, `ref` a otros paquetes, layout `auto` o `grid` |
| `skills/ea-read` | Leer, auditar, documentar y exportar (XMI, PNG) |

## Requisito extra

`prisma_a_spec.py` necesita Python 3.8 o superior, sin paquetes extra; el resto, solo PowerShell.

## Notas de la API de EA aprendidas

- EA no escribe archivos en rutas largas (más de ~200 caracteres): `image` y `export` pasan por un temporal corto.
- El auto-layout de EA vuelve a mostrar los enlaces ocultos: `hideOtherConnectors` los oculta antes y después.
- EA de 32 bits solo registra su COM en WOW6432Node: ea-cli se relanza en PowerShell de 32 bits.
- Las posiciones de un `DiagramObject` existente son enteros: un `double` de PowerShell falla con «conversión no válida».
- Ocultar atributos en un diagrama: `DiagramObject.SetStyleEx('AttPub','0')` (y AttPri, AttPro, AttPkg, Op*).
