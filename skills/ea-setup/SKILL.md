---
name: ea-setup
description: Primer arranque de ea-steroids. Comprueba que esta PC puede controlar Sparx Enterprise Architect por su API COM (EA instalado, versión, 32/64 bits, puente ea-cli) y deja abierto un repositorio. Úsala la primera vez, cuando el usuario diga "configura Enterprise Architect", "prepara EA", "set up EA", "no conecta con EA", o cuando ea-cli falle.
---

# Preparar Enterprise Architect (ea-steroids)

ea-steroids controla **Sparx Enterprise Architect** en local mediante su API COM
(`EA.App` / `EA.Repository`). No usa MCP, ni API key, ni nube. El puente es un script
PowerShell sin dependencias, el mismo para cualquier agente (Claude Code, Codex, OpenCode,
Antigravity…):

`~/.ea-steroids/bin/ea-cli.ps1`

En el resto de las skills de EA, **ea-cli** significa:
`powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ea-steroids\bin\ea-cli.ps1" <comando> ...`
(desde bash/Git Bash: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.ea-steroids/bin/ea-cli.ps1" <comando> ...`).
Toda salida es JSON por stdout.

## 1. ¿Está instalado EA?
Busca `EA.exe` recursivamente en `C:\Program Files\Sparx Systems` y `C:\Program Files (x86)\Sparx Systems`
(la carpeta puede ser `EA`, `EA Trial`, etc.) y lee su versión (`(Get-Item EA.exe).VersionInfo.ProductVersion`).
Probado con **EA 17.2 Trial, 64 bits**. La versión Trial pone marca de agua en las imágenes exportadas.
- No está → dile al usuario que lo instale (trial de 30 días en sparxsystems.com; recomendado 16.x o 17.x) y espera.
- Carpeta `Program Files (x86)` = EA de **32 bits**. ea-cli se relanza solo en PowerShell de 32 bits
  cuando hace falta, no tienes que hacer nada.

## 2. ¿Responde por COM?
Ejecuta `ea-cli status`.
- `running: false` → EA no está abierto. Pide al usuario que lo abra, o abre/crea un repositorio tú (paso 3).
- `modelLoaded: false` → EA abierto sin proyecto. Paso 3.
- `ok: true, modelLoaded: true` → listo; informa el archivo y los modelos raíz.

## 3. Abrir o crear un repositorio
- Existente: `ea-cli open -Path "C:\ruta\modelo.qea"`
- Nuevo: `ea-cli open -Path "C:\ruta\modelo.qea" -Create`
  (`.qea` es el formato SQLite de EA 16+; en EA 15 o anterior usa `.eapx`).
Pregunta al usuario dónde guardarlo si no lo dijo; no lo crees en carpetas temporales.

## Problemas frecuentes
- **"no está abierto" con EA visible**: EA se abrió como administrador y el agente no (o al revés). Que lo abra sin "Ejecutar como administrador".
- **Ventana de licencia / "Add-In" bloqueando**: EA espera respuesta del usuario; pídele que la cierre.
- **Repositorio en servidor (SQL Server, Cloud, Pro Cloud)**: `status` muestra la cadena de conexión; funciona igual mientras el usuario lo tenga abierto en EA.
- **`reachable: false`** (EA abierto pero inalcanzable): el agente corre en un sandbox. Pasa con
  **Codex** en su modo por defecto (comprobado). Vuelve a ejecutar ea-cli pidiendo permiso para salir
  del sandbox (escalado / acceso completo) en vez de buscar otra vía; si no puedes pedirlo, dile al
  usuario que active el acceso completo para esta tarea.

No le muestres comandos al usuario. Ejecútalos tú y cuéntale el resultado en lenguaje sencillo.
