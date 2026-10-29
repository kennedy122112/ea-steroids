#!/usr/bin/env python3
"""prisma_a_spec: convierte un schema.prisma en specs de ea-cli (diagramas de clases).

    python prisma_a_spec.py <dominios.json> <carpeta-salida>

Solo usa la biblioteca estándar (Python 3.8 o superior).

dominios.json:
{
  "schema": "ruta/a/schema.prisma",            // relativa al propio dominios.json
  "parent": "Model/Proyecto",                  // paquete donde cuelga el modelo de datos
  "paquete": "06 Modelo de datos (Prisma)",    // paquete raíz que se crea
  "prefijo": "06",                             // prefijo de los archivos de salida
  "dominios": [
    { "paquete": "06.1 Organización", "esquemas": ["org", "auth"] },
    { "paquete": "06.5 Motor", "modelos": ["RegistroContable", "AsientoContable"] }
  ],
  "enumeraciones": "06.9 Enumeraciones",       // opcional: paquete con los enum
  "agruparDesde": 4                            // N o más relaciones entre las mismas dos clases → una sola
}

Un modelo va al dominio que lo nombre en "modelos"; si ninguno, al que tenga su @@schema en
"esquemas". Un modelo sin dominio es un error: la vista tiene que cubrir todo el schema.
Cada relación se dibuja en el dominio de la clase que tiene la clave foránea; la otra clase,
si es de otro dominio, entra como "ref" opcional (por eso build se corre dos veces).
"""
import json
import re
import sys
import unicodedata
from pathlib import Path


def entre_parentesis(s, i):
    """Contenido entre paréntesis balanceados que empieza en s[i] == '('."""
    prof, en_texto = 0, False
    for j in range(i, len(s)):
        ch = s[j]
        if ch == '"' and (j == 0 or s[j - 1] != '\\'):
            en_texto = not en_texto
        if en_texto:
            continue
        if ch == '(':
            prof += 1
        elif ch == ')':
            prof -= 1
            if prof == 0:
                return s[i + 1:j]
    return s[i + 1:]


def atributo(resto, nombre):
    i = resto.find('@' + nombre + '(')
    return None if i < 0 else entre_parentesis(resto, i + len(nombre) + 1)


def sin_comentario(linea):
    en_texto = False
    for j in range(len(linea) - 1):
        if linea[j] == '"' and (j == 0 or linea[j - 1] != '\\'):
            en_texto = not en_texto
        if not en_texto and linea[j] == '/' and linea[j + 1] == '/':
            return linea[:j]
    return linea


def parsear(texto):
    """Devuelve (modelos, enums): dict nombre → bloque, en el orden del schema."""
    modelos, enums = {}, {}
    lineas = re.split(r'\r?\n', texto)
    doc = []
    i = 0
    while i < len(lineas):
        l = lineas[i].strip()
        if l.startswith('///'):
            doc.append(l[3:].strip())
            i += 1
            continue
        m = re.match(r'^(model|enum)\s+(\w+)\s*\{', l, re.ASCII)
        if not m:
            if l:
                doc = []
            i += 1
            continue
        tipo_bloque = m.group(1)
        bloque = {'nombre': m.group(2), 'doc': ' '.join(doc), 'campos': [], 'esquema': '',
                  'tabla': m.group(2), 'valores': [], 'pk': None}
        doc = []
        doc_campo = []
        i += 1
        while i < len(lineas) and not re.match(r'^\s*\}', lineas[i]):
            raw = lineas[i].strip()
            i += 1
            if raw.startswith('///'):
                doc_campo.append(raw[3:].strip())
                continue
            t = sin_comentario(raw).strip()
            if not t:
                doc_campo = []
                continue
            if t.startswith('@@'):
                sch = re.search(r'@@schema\("(\w+)"\)', t)
                if sch:
                    bloque['esquema'] = sch.group(1)
                mp = re.search(r'@@map\("([^"]+)"\)', t)
                if mp:
                    bloque['tabla'] = mp.group(1)
                pk = re.search(r'@@id\(\s*(?:fields:\s*)?\[([^\]]*)\]', t)
                if pk:
                    bloque['pk'] = [x.strip() for x in pk.group(1).split(',') if x.strip()]
                doc_campo = []
                continue
            if tipo_bloque == 'enum':
                bloque['valores'].append({'nombre': t.split()[0], 'doc': ' '.join(doc_campo)})
                doc_campo = []
                continue
            f = re.match(r'^(\w+)\s+(\w+)(\[\])?(\?)?\s*(.*)$', t, re.ASCII)
            if not f:
                doc_campo = []
                continue
            resto = f.group(5) or ''
            rel = atributo(resto, 'relation')
            rel_nombre, rel_campos = None, []
            if rel is not None:
                n = re.match(r'^\s*"([^"]+)"', rel) or re.search(r'name:\s*"([^"]+)"', rel)
                if n:
                    rel_nombre = n.group(1)
                fc = re.search(r'fields:\s*\[([^\]]*)\]', rel)
                if fc:
                    rel_campos = [x.strip() for x in fc.group(1).split(',') if x.strip()]
            bloque['campos'].append({
                'nombre': f.group(1), 'tipo': f.group(2), 'lista': bool(f.group(3)), 'opcional': bool(f.group(4)),
                'id': bool(re.search(r'@id\b', resto)), 'unico': bool(re.search(r'@unique\b', resto)),
                'defecto': atributo(resto, 'default'), 'rel_nombre': rel_nombre, 'rel_campos': rel_campos,
                'doc': ' '.join(doc_campo),
            })
            doc_campo = []
        (modelos if tipo_bloque == 'model' else enums)[bloque['nombre']] = bloque
        i += 1
    return modelos, enums


def slug(s):
    s = unicodedata.normalize('NFD', s)
    s = ''.join(ch for ch in s if not unicodedata.combining(ch)).lower()
    return re.sub(r'[^a-z0-9]+', '-', s).strip('-')


def main(argv):
    if len(argv) < 3:
        print('Uso: python prisma_a_spec.py <dominios.json> <carpeta-salida>', file=sys.stderr)
        return 1
    ruta_config, salida = Path(argv[1]), Path(argv[2])
    cfg = json.loads(ruta_config.read_text(encoding='utf-8'))
    texto = (ruta_config.parent / cfg['schema']).resolve().read_text(encoding='utf-8')
    modelos, enums = parsear(texto)

    # ── Dominios ──────────────────────────────────────────────────────────
    raiz = f"{cfg['parent']}/{cfg['paquete']}"
    dominio_de = {}
    for d in cfg['dominios']:
        for nombre in d.get('modelos', []):
            if nombre not in modelos:
                raise SystemExit(f"El dominio «{d['paquete']}» nombra «{nombre}», que no está en el schema.")
            dominio_de[nombre] = d
    for nombre, mo in modelos.items():
        if nombre in dominio_de:
            continue
        d = next((x for x in cfg['dominios'] if mo['esquema'] in x.get('esquemas', [])), None)
        if d is None:
            raise SystemExit(f"«{nombre}» (@@schema {mo['esquema'] or '—'}) no cae en ningún dominio.")
        dominio_de[nombre] = d

    # ── Relaciones: una por campo con fields: [...] (el lado de la clave foránea) ─
    def contraparte(origen, campo):
        destino = modelos[campo['tipo']]
        candidatas = [c for c in destino['campos'] if c['tipo'] == origen['nombre'] and not c['rel_campos']
                      and (origen['nombre'] != destino['nombre'] or c['nombre'] != campo['nombre'])]
        if campo['rel_nombre']:
            return next((c for c in candidatas if c['rel_nombre'] == campo['rel_nombre']), None)
        return next((c for c in candidatas if not c['rel_nombre']), candidatas[0] if candidatas else None)

    relaciones = []
    for mo in modelos.values():
        for c in mo['campos']:
            if c['tipo'] not in modelos or not c['rel_campos']:
                continue
            back = contraparte(mo, c)
            relaciones.append({
                'de': mo['nombre'], 'a': c['tipo'],
                'rolA': c['nombre'], 'cardA': '0..1' if c['opcional'] else '1',
                'rolDe': back['nombre'] if back else '',
                'cardDe': ('0..*' if back['lista'] else '0..1') if back else '0..*',
                'campos': c['rel_campos'],
            })

    def clase(mo):
        fks = {f for c in mo['campos'] for f in c['rel_campos']}
        pk = mo['pk'] or []
        notas = '\n'.join(x for x in [mo['doc'], f"Tabla: {mo['esquema'] + '.' if mo['esquema'] else ''}{mo['tabla']}"] if x)
        return {
            'id': mo['nombre'], 'name': mo['nombre'], 'type': 'Class', 'notes': notas,
            'attributes': [{
                'name': c['nombre'],
                'type': c['tipo'] + ('[]' if c['lista'] else ''),
                'stereotype': 'PK' if c['id'] or c['nombre'] in pk else 'FK' if c['nombre'] in fks else 'unique' if c['unico'] else '',
                'lower': '0' if c['opcional'] else '1',
                'upper': '*' if c['lista'] else '1',
                'default': c['defecto'] if c['defecto'] is not None else '',
                'notes': c['doc'],
            } for c in mo['campos'] if c['tipo'] not in modelos],
        }

    # ── Salida ────────────────────────────────────────────────────────────
    salida.mkdir(parents=True, exist_ok=True)

    def escribir(archivo, spec):
        (salida / archivo).write_text(json.dumps(spec, indent=2, ensure_ascii=False) + '\n', encoding='utf-8', newline='\n')

    agrupar_desde = cfg.get('agruparDesde', 4)
    escribir(f"{cfg['prefijo']}-00-raiz.json", {'parent': cfg['parent'], 'package': cfg['paquete'], 'elements': [], 'connectors': []})

    resumen = []
    for n, d in enumerate(cfg['dominios']):
        propios = [mo for mo in modelos.values() if dominio_de[mo['nombre']] is d]
        elementos = [clase(mo) for mo in propios]
        externos = {}
        conectores = []
        por_par = {}
        for r in relaciones:
            if dominio_de[r['de']] is d:
                por_par.setdefault(f"{r['de']}>{r['a']}", []).append(r)
        for grupo in por_par.values():
            r0 = grupo[0]
            if dominio_de[r0['a']] is not d and r0['a'] not in externos:
                externos[r0['a']] = {'id': r0['a'], 'ref': f"{raiz}/{dominio_de[r0['a']]['paquete']}", 'name': r0['a'],
                                     'optional': True, 'compact': True}
            if len(grupo) >= agrupar_desde:
                conectores.append({
                    'from': r0['de'], 'to': r0['a'], 'type': 'Association', 'name': f'{len(grupo)} referencias',
                    'fromCard': '0..*', 'toCard': '0..1', 'toRole': '',
                    'notes': '\n'.join(f"{r['rolA']} ({', '.join(r['campos'])}) {r['cardA']}" for r in grupo),
                })
            else:
                for r in grupo:
                    conectores.append({
                        'from': r['de'], 'to': r['a'], 'type': 'Association',
                        'fromCard': r['cardDe'], 'toCard': r['cardA'], 'fromRole': r['rolDe'], 'toRole': r['rolA'],
                        'notes': f"FK: {', '.join(r['campos'])}",
                    })
        nombre_vista = re.sub(r'^[\d.]+\s*', '', d['paquete'])
        archivo = f"{cfg['prefijo']}-{n + 1:02d}-{slug(nombre_vista)}.json"
        escribir(archivo, {
            'parent': raiz, 'package': d['paquete'],
            'elements': elementos + list(externos.values()),
            'connectors': conectores,
            # Solo las relaciones de este dominio: las internas de las clases de otros dominios ya están en su vista.
            'diagram': {'name': d.get('diagrama', nombre_vista), 'type': 'Logical', 'layout': 'auto', 'hideOtherConnectors': True},
        })
        resumen.append(f'{archivo}: {len(elementos)} clases, {len(externos)} de otros dominios, {len(conectores)} asociaciones')

    if cfg.get('enumeraciones'):
        lista = list(enums.values())
        escribir(f"{cfg['prefijo']}-{len(cfg['dominios']) + 1:02d}-enumeraciones.json", {
            'parent': raiz, 'package': cfg['enumeraciones'],
            'elements': [{
                'id': e['nombre'], 'name': e['nombre'], 'type': 'Enumeration', 'notes': e['doc'],
                'attributes': [{'name': v['nombre'], 'type': '', 'notes': v['doc']} for v in e['valores']],
            } for e in lista],
            'connectors': [],
            'diagram': {'name': 'Enumeraciones', 'type': 'Logical', 'layout': 'grid', 'columns': 5, 'cellWidth': 220, 'cellHeight': 160},
        })
        resumen.append(f'enumeraciones: {len(lista)}')

    print(json.dumps({'ok': True, 'modelos': len(modelos), 'enums': len(enums), 'relaciones': len(relaciones),
                      'archivos': resumen}, indent=2, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
