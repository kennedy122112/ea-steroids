<#
  Instala (o reinstala) ea-steroids en los agentes de esta PC.
  Las skills viven una sola vez en ~/.ea-steroids/skills y cada agente las ve por un enlace
  (junction), así que editarlas o actualizarlas aquí las cambia en todos.

    powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ea-steroids\install.ps1"
    ... -Uninstall   quita los enlaces (no borra ~/.ea-steroids)
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$h = $env:USERPROFILE

# Carpeta de skills de cada agente. Solo se instala donde el agente ya existe.
$destinos = [ordered]@{
  'Claude Code'           = @{ base = "$h\.claude";              skills = "$h\.claude\skills" }
  'Codex y otros (.agents)' = @{ base = "$h\.agents";            skills = "$h\.agents\skills" }
  'OpenCode'              = @{ base = "$h\.config\opencode";     skills = "$h\.config\opencode\skills" }
  'Antigravity'           = @{ base = "$h\.gemini\antigravity";  skills = "$h\.gemini\antigravity\skills" }
}

# Las skills llaman al puente por ~/.ea-steroids: si el repositorio está en otra carpeta,
# ~/.ea-steroids es un enlace hacia él.
$casa = "$h\.ea-steroids"
$rootReal = (Get-Item $root).FullName
$casaItem = Get-Item $casa -Force -ErrorAction SilentlyContinue
if (-not $Uninstall -and -not ($casaItem -and ($casaItem.FullName -eq $rootReal -or "$($casaItem.Target)" -eq $rootReal))) {
  if ($casaItem -and $casaItem.LinkType -ne 'Junction') { throw "$casa existe y es una carpeta real: muévela o bórrala antes de instalar." }
  if ($casaItem) { [IO.Directory]::Delete($casa) }
  New-Item -ItemType Junction -Path $casa -Target $rootReal | Out-Null
  "~/.ea-steroids             -> $rootReal"
}

$skills = Get-ChildItem "$root\skills" -Directory
foreach ($agente in $destinos.Keys) {
  $d = $destinos[$agente]
  if (-not (Test-Path $d.base)) { "{0,-24} no instalado, se omite" -f $agente; continue }
  if (-not $Uninstall) { New-Item -ItemType Directory -Force $d.skills | Out-Null }
  foreach ($s in $skills) {
    $link = Join-Path $d.skills $s.Name
    $item = Get-Item $link -Force -ErrorAction SilentlyContinue
    if ($item) {
      if ($item.LinkType -ne 'Junction') { "{0,-24} {1}: existe una carpeta real, no se toca" -f $agente, $s.Name; continue }
      [IO.Directory]::Delete($link)   # quita solo el enlace, nunca el contenido
    }
    if (-not $Uninstall) { New-Item -ItemType Junction -Path $link -Target $s.FullName | Out-Null }
  }
  "{0,-24} {1} ({2})" -f $agente, $(if ($Uninstall) { 'enlaces quitados' } else { "$($skills.Count) skills enlazadas" }), $d.skills
}
