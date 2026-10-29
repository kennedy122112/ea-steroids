<#
  ea-cli.ps1 - puente local entre el agente y Sparx Enterprise Architect (API COM).
  Sin MCP, sin nube. Requiere EA instalado en esta PC.

  Uso:
    ea-cli.ps1 status                       # ¿EA abierto? ¿qué modelo?
    ea-cli.ps1 open   -Path <archivo.qea>   # abre (o crea con -Create) un repositorio
    ea-cli.ps1 tree   [-Package <guid|ruta>] [-Depth 3]
    ea-cli.ps1 read   -Package <guid|ruta>  # elementos, conectores y diagramas en JSON
    ea-cli.ps1 build  -Spec <spec.json>     # crea paquete + elementos + conectores + diagrama
    ea-cli.ps1 export -Package <guid|ruta> -Path <salida.xmi>
    ea-cli.ps1 image  -Package <guid|ruta> [-Diagram <nombre>] -Path <salida.png>
    ea-cli.ps1 eval   -Script <archivo.ps1> # ejecuta código con $repo disponible

  Las rutas de paquete son "Modelo/Paquete/Subpaquete". Toda salida es JSON por stdout.
#>
param(
  [Parameter(Position = 0)][string]$Command = 'status',
  [string]$Path,
  [string]$Package,
  [string]$Spec,
  [string]$Script,
  [string]$Diagram,
  [int]$Depth = 3,
  [switch]$Create
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Out-Json($obj) { ConvertTo-Json -InputObject $obj -Depth 12 }
function Fail($msg) { Out-Json @{ ok = $false; error = $msg }; exit 1 }

# EA puede ser de 32 bits: su COM solo se ve desde PowerShell de 32 bits. Si falla por
# "clase no registrada" en un proceso de 64 bits, se relanza en SysWOW64.
function Invoke-In32IfNeeded($err) {
  # 80040154 = clase no registrada; 800401F3 = ProgID inválido (EA de 32 bits solo se registra en WOW6432Node)
  $classNotReg = ($err.Exception.HResult -in -2147221164, -2147221005) -or ($err.ToString() -match '80040154|800401F3|no registrad|not registered|Invalid class string|Cadena de clase')
  if ($classNotReg -and [Environment]::Is64BitProcess) {
    $ps32 = "$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe"
    & $ps32 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @script:ForwardArgs
    exit $LASTEXITCODE
  }
}
$script:ForwardArgs = @($Command)
foreach ($k in $PSBoundParameters.Keys) {
  if ($k -eq 'Command') { continue }
  $v = $PSBoundParameters[$k]
  if ($v -is [switch]) { if ($v) { $script:ForwardArgs += "-$k" } } else { $script:ForwardArgs += "-$k"; $script:ForwardArgs += "$v" }
}

function Get-RunningRepo {
  try {
    $app = [System.Runtime.InteropServices.Marshal]::GetActiveObject('EA.App')
    return $app.Repository
  } catch {
    Invoke-In32IfNeeded $_
    return $null
  }
}

function Get-Repo {
  $repo = Get-RunningRepo
  if (-not $repo) { Fail 'Enterprise Architect no está abierto. Ábrelo con un modelo (o usa: ea-cli open -Path <archivo.qea>).' }
  try { $null = $repo.ConnectionString } catch { Fail 'EA está abierto pero sin un modelo cargado.' }
  if (-not $repo.ConnectionString) { Fail 'EA está abierto pero sin un modelo cargado.' }
  return $repo
}

function Resolve-Package($repo, $ref, [switch]$Soft) {
  # -Soft: devuelve $null en vez de terminar cuando la ruta no existe.
  if ($Soft) {
    if ($ref -match '^\{[0-9A-Fa-f-]{36}\}$') { try { return $repo.GetPackageByGuid($ref) } catch { return $null } }
    $parts = $ref -split '/'
    $cur = $null
    foreach ($m in $repo.Models) { if ($m.Name -eq $parts[0]) { $cur = $m; break } }
    for ($i = 1; $cur -and $i -lt $parts.Count; $i++) {
      $next = $null
      foreach ($p in $cur.Packages) { if ($p.Name -eq $parts[$i]) { $next = $p; break } }
      $cur = $next
    }
    return $cur
  }
  if (-not $ref) {
    $sel = $null
    try { $sel = $repo.GetTreeSelectedPackage() } catch {}
    if ($sel) { return $sel }
    return $repo.Models.GetAt(0)
  }
  if ($ref -match '^\{[0-9A-Fa-f-]{36}\}$') { return $repo.GetPackageByGuid($ref) }
  $parts = $ref -split '/'
  $cur = $null
  foreach ($m in $repo.Models) { if ($m.Name -eq $parts[0]) { $cur = $m; break } }
  if (-not $cur) { Fail "No existe el modelo raíz '$($parts[0])'." }
  for ($i = 1; $i -lt $parts.Count; $i++) {
    $next = $null
    foreach ($p in $cur.Packages) { if ($p.Name -eq $parts[$i]) { $next = $p; break } }
    if (-not $next) { Fail "No existe el paquete '$($parts[$i])' dentro de '$($cur.Name)'." }
    $cur = $next
  }
  return $cur
}

function Get-PackagePath($repo, $pkg) {
  $names = @($pkg.Name); $p = $pkg
  while ($p.ParentID -ne 0) { $p = $repo.GetPackageByID($p.ParentID); $names = @($p.Name) + $names }
  return ($names -join '/')
}

function Get-Tree($pkg, $d) {
  $node = [ordered]@{ name = $pkg.Name; guid = $pkg.PackageGUID; elements = $pkg.Elements.Count; diagrams = $pkg.Diagrams.Count }
  if ($d -gt 0 -and $pkg.Packages.Count -gt 0) {
    $node.packages = @(foreach ($c in $pkg.Packages) { Get-Tree $c ($d - 1) })
  }
  return $node
}

# Busca un hijo por nombre en una colección; si no existe lo crea (idempotente).
function Get-OrAdd($collection, $name, $type) {
  foreach ($x in $collection) { if ($x.Name -eq $name) { return $x } }
  $n = $collection.AddNew($name, $type)
  $n.Update() | Out-Null
  $collection.Refresh()
  return $n
}

switch ($Command) {

  'status' {
    $repo = Get-RunningRepo
    if (-not $repo) {
      # Si el proceso existe pero COM no llega, el agente corre aislado (sandbox) o con otro nivel de permisos.
      if (Get-Process EA -ErrorAction SilentlyContinue) {
        Out-Json @{ ok = $false; running = $true; reachable = $false; error = 'EA está abierto pero no se puede alcanzar por COM: el agente corre en un sandbox o con distinto nivel de permisos. Vuelve a ejecutar ea-cli con permiso para salir del sandbox (acceso completo).' }
      } else {
        Out-Json @{ ok = $false; running = $false; error = 'EA no está abierto.' }
      }
      exit 0
    }
    $conn = $null; try { $conn = $repo.ConnectionString } catch {}
    Out-Json ([ordered]@{
      ok = $true; running = $true; modelLoaded = [bool]$conn
      connection = $conn
      version = $(try { $repo.LibraryVersion } catch { $null })
      roots = @(if ($conn) { foreach ($m in $repo.Models) { $m.Name } })
      bits = $(if ([Environment]::Is64BitProcess) { 64 } else { 32 })
    })
  }

  'open' {
    if (-not $Path) { Fail 'Falta -Path.' }
    $full = [System.IO.Path]::GetFullPath($Path)
    $repo = Get-RunningRepo
    $owned = $false
    if (-not $repo) {
      try { $repo = New-Object -ComObject EA.Repository } catch { Invoke-In32IfNeeded $_; Fail "No se pudo iniciar EA por COM: $_" }
      $owned = $true
    }
    if (-not (Test-Path $full)) {
      if (-not $Create) { Fail "No existe '$full'. Usa -Create para crear un repositorio nuevo." }
      if (-not $repo.CreateModel(0, $full, 0)) { Fail "EA no pudo crear '$full'." }
    }
    if (-not $repo.OpenFile($full)) { Fail "EA no pudo abrir '$full'." }
    if ($owned) { try { $repo.ShowWindow(1) } catch {} }
    Out-Json @{ ok = $true; opened = $full; roots = @(foreach ($m in $repo.Models) { $m.Name }) }
  }

  'tree' {
    $repo = Get-Repo
    if ($Package) { $pkg = Resolve-Package $repo $Package; Out-Json (Get-Tree $pkg $Depth) }
    else { Out-Json @(foreach ($m in $repo.Models) { Get-Tree $m $Depth }) }
  }

  'read' {
    $repo = Get-Repo
    $pkg = Resolve-Package $repo $Package
    $byId = @{}
    $elements = @(foreach ($e in $pkg.Elements) {
      $byId[$e.ElementID] = $e.Name
      [ordered]@{ id = $e.ElementID; guid = $e.ElementGUID; name = $e.Name; type = $e.Type; stereotype = $e.StereotypeEx; notes = $e.Notes; status = $e.Status; author = $e.Author }
    })
    $connectors = @(foreach ($e in $pkg.Elements) {
      foreach ($c in $e.Connectors) {
        if ($c.ClientID -ne $e.ElementID) { continue }   # cada conector una sola vez
        $sup = $byId[$c.SupplierID]; if (-not $sup) { $sup = $repo.GetElementByID($c.SupplierID).Name }
        [ordered]@{ from = $e.Name; to = $sup; type = $c.Type; name = $c.Name; stereotype = $c.Stereotype }
      }
    })
    $diagrams = @(foreach ($d in $pkg.Diagrams) { [ordered]@{ id = $d.DiagramID; name = $d.Name; type = $d.Type; objects = $d.DiagramObjects.Count } })
    Out-Json ([ordered]@{ ok = $true; package = (Get-PackagePath $repo $pkg); guid = $pkg.PackageGUID; elements = $elements; connectors = $connectors; diagrams = $diagrams; subpackages = @(foreach ($p in $pkg.Packages) { $p.Name }) })
  }

  'build' {
    if (-not $Spec) { Fail 'Falta -Spec <archivo.json>.' }
    $s = Get-Content -Raw -Encoding UTF8 $Spec | ConvertFrom-Json
    $repo = Get-Repo
    $parent = Resolve-Package $repo $s.parent
    $pkg = if ($s.package) { Get-OrAdd $parent.Packages $s.package '' } else { $parent }
    $parent.Packages.Refresh()

    # Elementos (idempotente por nombre dentro del paquete)
    $map = @{}
    $omitidos = @{}
    foreach ($e in $s.elements) {
      $key = if ($e.id) { $e.id } else { $e.name }
      # "ref": elemento que ya vive en otro paquete; se reutiliza (conectores y diagrama), no se crea ni se modifica.
      # Con "optional": true, si todavía no existe se omite junto con sus conectores (útil para construir
      # varias vistas que se referencian entre sí: se corre build dos veces).
      if ($e.ref) {
        $found = $null
        $rp = $null
        $rp = if ($e.optional) { Resolve-Package $repo $e.ref -Soft } else { Resolve-Package $repo $e.ref }
        if ($rp) { foreach ($x in $rp.Elements) { if ($x.Name -eq $e.name) { $found = $x; break } } }
        if (-not $found) {
          if ($e.optional) { $omitidos[$key] = $true; continue }
          Fail "No existe '$($e.name)' en el paquete '$($e.ref)'."
        }
        $map[$key] = $found
        continue
      }
      $type = if ($e.type) { $e.type } else { 'Class' }
      $el = $null
      foreach ($x in $pkg.Elements) { if ($x.Name -eq $e.name) { $el = $x; break } }
      if (-not $el) { $el = $pkg.Elements.AddNew($e.name, $type) }
      if ($e.stereotype) { $el.StereotypeEx = $e.stereotype }
      if ($e.notes) { $el.Notes = $e.notes }
      if ($e.status) { $el.Status = $e.status }
      $el.Update() | Out-Null
      # Atributos: "nombre" o { name, type, stereotype, notes, lower, upper, default }. Se actualizan si ya existen.
      $pos = 0
      foreach ($a in @($e.attributes)) {
        if (-not $a) { continue }
        $an = if ($a -is [string]) { $a } else { $a.name }
        $at = if ($a -is [string]) { '' } else { [string]$a.type }
        $attr = Get-OrAdd $el.Attributes $an $at
        if ($a -isnot [string]) {
          $attr.Type = $at
          if ($null -ne $a.stereotype) { $attr.Stereotype = [string]$a.stereotype }
          if ($null -ne $a.notes) { $attr.Notes = [string]$a.notes }
          if ($null -ne $a.lower) { $attr.LowerBound = [string]$a.lower }
          if ($null -ne $a.upper) { $attr.UpperBound = [string]$a.upper }
          if ($null -ne $a.default) { $attr.Default = [string]$a.default }
        }
        $attr.Pos = $pos; $pos++
        $attr.Update() | Out-Null
      }
      foreach ($o in @($e.operations)) {
        if (-not $o) { continue }
        $on = if ($o -is [string]) { $o } else { $o.name }
        $ot = if ($o -is [string]) { '' } else { $o.returnType }
        $op = Get-OrAdd $el.Methods $on $ot
      }
      $map[$key] = $el
    }
    $pkg.Elements.Refresh()

    # Conectores (no duplica si ya existe uno igual)
    $nConn = 0
    $specConn = @{}
    $nOmit = 0
    foreach ($c in $s.connectors) {
      if ($omitidos[$c.from] -or $omitidos[$c.to]) { $nOmit++; continue }
      $from = $map[$c.from]; $to = $map[$c.to]
      if (-not $from -or -not $to) { Fail "Conector '$($c.from)' -> '$($c.to)': elemento no definido en elements." }
      $ctype = if ($c.type) { $c.type } else { 'Association' }
      $toRole = [string]$c.toRole
      # Mismo conector = mismo destino, tipo, nombre y rol del destino (dos asociaciones entre las mismas
      # clases se distinguen por el rol).
      $con = $null
      foreach ($x in $from.Connectors) {
        if ($x.ClientID -eq $from.ElementID -and $x.SupplierID -eq $to.ElementID -and $x.Type -eq $ctype -and $x.Name -eq [string]$c.name -and [string]$x.SupplierEnd.Role -eq $toRole) { $con = $x; break }
      }
      if (-not $con) {
        $con = $from.Connectors.AddNew([string]$c.name, $ctype)
        $con.SupplierID = $to.ElementID
        $nConn++
      }
      if ($c.stereotype) { $con.StereotypeEx = $c.stereotype }
      if ($null -ne $c.notes) { $con.Notes = [string]$c.notes }
      if ($c.direction) { $con.Direction = [string]$c.direction }
      $con.Update() | Out-Null
      # Extremos: multiplicidad ("1", "0..1", "0..*", "1..*") y rol.
      $ends = @(@($con.ClientEnd, $c.fromCard, $c.fromRole), @($con.SupplierEnd, $c.toCard, $c.toRole))
      foreach ($en in $ends) {
        $cambia = $false
        if ($null -ne $en[1]) { $en[0].Cardinality = [string]$en[1]; $cambia = $true }
        if ($null -ne $en[2]) { $en[0].Role = [string]$en[2]; $cambia = $true }
        if ($cambia) { $en[0].Update() | Out-Null }
      }
      $specConn[$con.ConnectorID] = $true
      $from.Connectors.Refresh()
    }

    # Diagrama
    $diagInfo = $null
    if ($s.diagram) {
      $dtype = if ($s.diagram.type) { $s.diagram.type } else { 'Logical' }
      $diag = Get-OrAdd $pkg.Diagrams $s.diagram.name $dtype
      $onDiagram = @{}
      foreach ($o in $diag.DiagramObjects) { $onDiagram[$o.ElementID] = $o }
      $cols = if ($s.diagram.columns) { [int]$s.diagram.columns } else { [Math]::Max(1, [Math]::Ceiling([Math]::Sqrt($map.Count))) }
      # layout "grid": cada elemento va en su celda "row"/"col" (o en orden si no la tiene) y se
      # recolocan también los que ya estaban en el diagrama.
      $grid = $s.diagram.layout -eq 'grid'
      $w = if ($s.diagram.cellWidth) { [int]$s.diagram.cellWidth } else { 150 }
      $h = if ($s.diagram.cellHeight) { [int]$s.diagram.cellHeight } else { 70 }
      $gx = if ($s.diagram.gapX) { [int]$s.diagram.gapX } else { 70 }
      $gy = if ($s.diagram.gapY) { [int]$s.diagram.gapY } else { 90 }
      $i = 0
      foreach ($e in $s.elements) {
        $key = if ($e.id) { $e.id } else { $e.name }
        $el = $map[$key]
        if (-not $el) { continue }   # ref opcional que todavía no existe
        $col = if ($grid -and $null -ne $e.col) { [int]$e.col } else { $i % $cols }
        $row = if ($grid -and $null -ne $e.row) { [int]$e.row } else { [Math]::Floor($i / $cols) }
        $i++
        $l = [int](40 + $col * ($w + $gx)); $t = [int](40 + $row * ($h + $gy))
        $obj = $onDiagram[$el.ElementID]
        if ($obj) {
          if ($grid) { $obj.Left = $l; $obj.Right = $l + $w; $obj.Top = - $t; $obj.Bottom = - ($t + $h) }
          elseif (-not $e.compact) { continue }
        } else {
          $obj = $diag.DiagramObjects.AddNew("l=$l;r=$($l + $w);t=-$t;b=-$($t + $h);", '')
          $obj.ElementID = $el.ElementID
        }
        # "compact": en este diagrama solo se ve el nombre (sin atributos ni operaciones); útil para
        # las clases de otros paquetes, que ya se ven completas en su propia vista.
        if ($e.compact) {
          foreach ($k in 'AttPub', 'AttPri', 'AttPro', 'AttPkg', 'OpPub', 'OpPri', 'OpPro', 'OpPkg') { $obj.SetStyleEx($k, '0') }
          $obj.Right = $obj.Left + 190; $obj.Bottom = $obj.Top - 60
        }
        $obj.Update() | Out-Null
      }
      if ($grid) {
        # Los quiebres que dejó un layout anterior ya no sirven en las posiciones nuevas.
        foreach ($lk in $diag.DiagramLinks) { if ($lk.Path) { $lk.Path = ''; $lk.Update() | Out-Null } }
      }
      $diag.DiagramObjects.Refresh()
      $diag.Update() | Out-Null
      # hideOtherConnectors: EA pinta todo conector entre elementos del diagrama; con esta opción
      # solo se ven los del spec (útil en vistas que reutilizan elementos con "ref").
      # El layout automático vuelve a mostrar los enlaces ocultos: se ocultan antes (para que no
      # cuenten al acomodar) y otra vez después.
      $ocultarOtros = {
        $d = $repo.GetDiagramByID($diag.DiagramID)
        $ids = @{}; foreach ($o in $d.DiagramObjects) { $ids[$o.ElementID] = $true }
        $links = @{}; foreach ($lk in $d.DiagramLinks) { $links[$lk.ConnectorID] = $lk }
        foreach ($el in $map.Values) {
          foreach ($x in $el.Connectors) {
            if ($specConn[$x.ConnectorID] -or -not ($ids[$x.ClientID] -and $ids[$x.SupplierID])) { continue }
            $lk = $links[$x.ConnectorID]
            if (-not $lk) { $lk = $d.DiagramLinks.AddNew('', ''); $lk.ConnectorID = $x.ConnectorID; $links[$x.ConnectorID] = $lk }
            $lk.IsHidden = $true
            $lk.Update() | Out-Null
          }
        }
      }
      if ($s.diagram.hideOtherConnectors) { & $ocultarOtros }
      if ($s.diagram.layout -eq 'auto') {
        # 0x00000004 lsCycleRemoveDFS | 0x00010000 lsLayeringOptimalLinkLength | 0x40000000 lsInitializeDFSOut
        try { $repo.GetProjectInterface().LayoutDiagramEx($diag.DiagramGUID, 0x40010004, 4, 40, 40, $false) | Out-Null } catch {}
        if ($s.diagram.hideOtherConnectors) { & $ocultarOtros }
      }
      $repo.ReloadDiagram($diag.DiagramID)
      if ($s.diagram.open -ne $false) { try { $repo.OpenDiagram($diag.DiagramID) } catch {} }
      $diagInfo = [ordered]@{ id = $diag.DiagramID; name = $diag.Name; type = $diag.Type; objects = $diag.DiagramObjects.Count }
    }
    try { $repo.RefreshModelView($pkg.PackageID) } catch {}
    Out-Json ([ordered]@{ ok = $true; package = (Get-PackagePath $repo $pkg); guid = $pkg.PackageGUID; elements = $map.Count; newConnectors = $nConn; skippedConnectors = $nOmit; skippedRefs = $omitidos.Count; diagram = $diagInfo })
  }

  'export' {
    if (-not $Path) { Fail 'Falta -Path <salida.xmi>.' }
    $repo = Get-Repo
    $pkg = Resolve-Package $repo $Package
    $full = [System.IO.Path]::GetFullPath($Path)
    # xmiType 12 = XMI 2.1 (UML 2.x); diagramas incluidos, sin imágenes.
    $tmp = Join-Path $env:TEMP ("ea-xmi-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.xmi')
    $res = $repo.GetProjectInterface().ExportPackageXMI($pkg.PackageGUID, 12, 1, -1, 1, 0, $tmp)
    if (Test-Path $tmp) { Move-Item -Force $tmp $full }
    Out-Json @{ ok = (Test-Path $full); path = $full; message = $res }
  }

  'image' {
    # Exporta un diagrama a PNG para revisarlo visualmente. -Package = paquete, -Diagram = nombre (o el primero).
    if (-not $Path) { Fail 'Falta -Path <salida.png>.' }
    $repo = Get-Repo
    $pkg = Resolve-Package $repo $Package
    $diag = $null
    foreach ($d in $pkg.Diagrams) { if (-not $Diagram -or $d.Name -eq $Diagram) { $diag = $d; break } }
    if (-not $diag) { Fail "No hay diagrama '$Diagram' en '$($pkg.Name)'." }
    $full = [System.IO.Path]::GetFullPath($Path)
    # EA no escribe en rutas largas (>~200 caracteres): exporta a un temporal corto y mueve.
    $tmp = Join-Path $env:TEMP ("ea-img-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + [IO.Path]::GetExtension($full))
    $repo.GetProjectInterface().PutDiagramImageToFile($diag.DiagramGUID, $tmp, 1) | Out-Null
    if (Test-Path $tmp) { Move-Item -Force $tmp $full }
    Out-Json @{ ok = (Test-Path $full); path = $full; diagram = $diag.Name }
  }

  'eval' {
    if (-not $Script) { Fail 'Falta -Script <archivo.ps1>.' }
    $repo = Get-Repo
    . (Resolve-Path $Script)
  }

  default { Fail "Comando desconocido '$Command'. Usa: status, open, tree, read, build, export, image, eval." }
}
