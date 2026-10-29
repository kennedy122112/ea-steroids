#!/usr/bin/env node
/**
 * prisma-a-spec: convierte un schema.prisma en specs de ea-cli (diagramas de clases).
 *
 *   node prisma-a-spec.mjs <dominios.json> <carpeta-salida>
 *
 * dominios.json:
 * {
 *   "schema": "ruta/a/schema.prisma",            // relativa al propio dominios.json
 *   "parent": "Model/Proyecto",                  // paquete donde cuelga el modelo de datos
 *   "paquete": "06 Modelo de datos (Prisma)",    // paquete raíz que se crea
 *   "prefijo": "06",                             // prefijo de los archivos de salida
 *   "dominios": [
 *     { "paquete": "06.1 Organización", "esquemas": ["org", "auth"] },
 *     { "paquete": "06.5 Motor", "modelos": ["RegistroContable", "AsientoContable"] }
 *   ],
 *   "enumeraciones": "06.9 Enumeraciones",       // opcional: paquete con los enum
 *   "agruparDesde": 4                            // N o más relaciones entre las mismas dos clases → una sola
 * }
 *
 * Un modelo va al dominio que lo nombre en "modelos"; si ninguno, al que tenga su @@schema en
 * "esquemas". Un modelo sin dominio es un error: la vista tiene que cubrir todo el schema.
 * Cada relación se dibuja en el dominio de la clase que tiene la clave foránea; la otra clase,
 * si es de otro dominio, entra como "ref" opcional (por eso build se corre dos veces).
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';

const [, , rutaConfig, salida] = process.argv;
if (!rutaConfig || !salida) {
  console.error('Uso: node prisma-a-spec.mjs <dominios.json> <carpeta-salida>');
  process.exit(1);
}
const cfg = JSON.parse(readFileSync(rutaConfig, 'utf8'));
const texto = readFileSync(resolve(dirname(rutaConfig), cfg.schema), 'utf8');

const ESCALARES = new Set(['String', 'Int', 'BigInt', 'Float', 'Decimal', 'Boolean', 'DateTime', 'Json', 'Bytes']);

/** Devuelve el contenido entre paréntesis balanceados que empieza en s[i] === '('. */
function entreParentesis(s, i) {
  let prof = 0, enTexto = false;
  for (let j = i; j < s.length; j++) {
    const ch = s[j];
    if (ch === '"' && s[j - 1] !== '\\') enTexto = !enTexto;
    if (enTexto) continue;
    if (ch === '(') prof++;
    else if (ch === ')' && --prof === 0) return s.slice(i + 1, j);
  }
  return s.slice(i + 1);
}
function atributo(resto, nombre) {
  const i = resto.indexOf('@' + nombre + '(');
  return i < 0 ? null : entreParentesis(resto, i + nombre.length + 1);
}
function sinComentario(linea) {
  let enTexto = false;
  for (let j = 0; j < linea.length - 1; j++) {
    if (linea[j] === '"' && linea[j - 1] !== '\\') enTexto = !enTexto;
    if (!enTexto && linea[j] === '/' && linea[j + 1] === '/') return linea.slice(0, j);
  }
  return linea;
}

// ── Parseo ────────────────────────────────────────────────────────────────
const modelos = new Map();
const enums = new Map();
{
  const lineas = texto.split(/\r?\n/);
  let doc = [];
  for (let i = 0; i < lineas.length; i++) {
    const l = lineas[i].trim();
    if (l.startsWith('///')) { doc.push(l.slice(3).trim()); continue; }
    const m = l.match(/^(model|enum)\s+(\w+)\s*\{/);
    if (!m) { if (l) doc = []; continue; }
    const bloque = { nombre: m[2], doc: doc.join(' '), campos: [], esquema: '', tabla: m[2], valores: [] };
    doc = [];
    let docCampo = [];
    for (i++; i < lineas.length && !/^\s*\}/.test(lineas[i]); i++) {
      const raw = lineas[i].trim();
      if (raw.startsWith('///')) { docCampo.push(raw.slice(3).trim()); continue; }
      const t = sinComentario(raw).trim();
      if (!t) { docCampo = []; continue; }
      if (t.startsWith('@@')) {
        const sch = t.match(/@@schema\("(\w+)"\)/); if (sch) bloque.esquema = sch[1];
        const map = t.match(/@@map\("([^"]+)"\)/); if (map) bloque.tabla = map[1];
        const pk = t.match(/@@id\(\s*(?:fields:\s*)?\[([^\]]*)\]/);
        if (pk) bloque.pk = pk[1].split(',').map((x) => x.trim()).filter(Boolean);
        docCampo = [];
        continue;
      }
      if (m[1] === 'enum') { bloque.valores.push({ nombre: t.split(/\s+/)[0], doc: docCampo.join(' ') }); docCampo = []; continue; }
      const f = t.match(/^(\w+)\s+(\w+)(\[\])?(\?)?\s*(.*)$/);
      if (!f) { docCampo = []; continue; }
      const resto = f[5] || '';
      const rel = atributo(resto, 'relation');
      let relNombre = null, relCampos = [];
      if (rel !== null) {
        const n = rel.match(/^\s*"([^"]+)"/) || rel.match(/name:\s*"([^"]+)"/);
        if (n) relNombre = n[1];
        const fc = rel.match(/fields:\s*\[([^\]]*)\]/);
        if (fc) relCampos = fc[1].split(',').map((x) => x.trim()).filter(Boolean);
      }
      bloque.campos.push({
        nombre: f[1], tipo: f[2], lista: !!f[3], opcional: !!f[4],
        id: /@id\b/.test(resto), unico: /@unique\b/.test(resto),
        defecto: atributo(resto, 'default'), relNombre, relCampos, doc: docCampo.join(' '),
      });
      docCampo = [];
    }
    (m[1] === 'model' ? modelos : enums).set(bloque.nombre, bloque);
  }
}

// ── Dominios ──────────────────────────────────────────────────────────────
const raiz = `${cfg.parent}/${cfg.paquete}`;
const dominioDe = new Map();
for (const d of cfg.dominios) for (const nombre of d.modelos ?? []) {
  if (!modelos.has(nombre)) throw new Error(`El dominio «${d.paquete}» nombra «${nombre}», que no está en el schema.`);
  dominioDe.set(nombre, d);
}
for (const [nombre, mo] of modelos) {
  if (dominioDe.has(nombre)) continue;
  const d = cfg.dominios.find((x) => (x.esquemas ?? []).includes(mo.esquema));
  if (!d) throw new Error(`«${nombre}» (@@schema ${mo.esquema || '—'}) no cae en ningún dominio.`);
  dominioDe.set(nombre, d);
}

// ── Relaciones: una por campo con fields: [...] (el lado de la clave foránea) ─
function contraparte(origen, campo) {
  const destino = modelos.get(campo.tipo);
  const candidatas = destino.campos.filter((c) => c.tipo === origen.nombre && c.relCampos.length === 0
    && (origen.nombre !== destino.nombre || c.nombre !== campo.nombre));
  if (campo.relNombre) return candidatas.find((c) => c.relNombre === campo.relNombre) ?? null;
  return candidatas.find((c) => !c.relNombre) ?? candidatas[0] ?? null;
}
const relaciones = [];
for (const mo of modelos.values()) for (const c of mo.campos) {
  if (!modelos.has(c.tipo) || c.relCampos.length === 0) continue;
  const back = contraparte(mo, c);
  relaciones.push({
    de: mo.nombre, a: c.tipo,
    rolA: c.nombre, cardA: c.opcional ? '0..1' : '1',
    rolDe: back?.nombre ?? '', cardDe: back ? (back.lista ? '0..*' : '0..1') : '0..*',
    campos: c.relCampos,
  });
}

const tipoTexto = (c) => `${c.tipo}${c.lista ? '[]' : ''}`;
function clase(mo) {
  const fks = new Set(mo.campos.flatMap((c) => c.relCampos));
  const notas = [mo.doc, `Tabla: ${mo.esquema ? mo.esquema + '.' : ''}${mo.tabla}`].filter(Boolean).join('\n');
  return {
    id: mo.nombre, name: mo.nombre, type: 'Class', notes: notas,
    attributes: mo.campos.filter((c) => !modelos.has(c.tipo)).map((c) => ({
      name: c.nombre,
      type: tipoTexto(c),
      stereotype: c.id || (mo.pk ?? []).includes(c.nombre) ? 'PK' : fks.has(c.nombre) ? 'FK' : c.unico ? 'unique' : '',
      lower: c.opcional ? '0' : '1',
      upper: c.lista ? '*' : '1',
      default: c.defecto ?? '',
      notes: c.doc,
    })),
  };
}

// ── Salida ────────────────────────────────────────────────────────────────
mkdirSync(salida, { recursive: true });
const escribir = (archivo, spec) => writeFileSync(join(salida, archivo), JSON.stringify(spec, null, 2) + '\n', 'utf8');
const slug = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const agruparDesde = cfg.agruparDesde ?? 4;

escribir(`${cfg.prefijo}-00-raiz.json`, { parent: cfg.parent, package: cfg.paquete, elements: [], connectors: [] });

const resumen = [];
cfg.dominios.forEach((d, n) => {
  const propios = [...modelos.values()].filter((mo) => dominioDe.get(mo.nombre) === d);
  const elementos = propios.map(clase);
  const externos = new Map();
  const conectores = [];
  const rels = relaciones.filter((r) => dominioDe.get(r.de) === d);
  const porPar = new Map();
  for (const r of rels) { const k = `${r.de}>${r.a}`; porPar.set(k, [...(porPar.get(k) ?? []), r]); }
  for (const grupo of porPar.values()) {
    const r0 = grupo[0];
    if (dominioDe.get(r0.a) !== d && !externos.has(r0.a)) {
      externos.set(r0.a, { id: r0.a, ref: `${raiz}/${dominioDe.get(r0.a).paquete}`, name: r0.a, optional: true, compact: true });
    }
    if (grupo.length >= agruparDesde) {
      conectores.push({
        from: r0.de, to: r0.a, type: 'Association', name: `${grupo.length} referencias`,
        fromCard: '0..*', toCard: '0..1', toRole: '',
        notes: grupo.map((r) => `${r.rolA} (${r.campos.join(', ')}) ${r.cardA}`).join('\n'),
      });
    } else {
      for (const r of grupo) conectores.push({
        from: r.de, to: r.a, type: 'Association',
        fromCard: r.cardDe, toCard: r.cardA, fromRole: r.rolDe, toRole: r.rolA,
        notes: `FK: ${r.campos.join(', ')}`,
      });
    }
  }
  const archivo = `${cfg.prefijo}-${String(n + 1).padStart(2, '0')}-${slug(d.paquete.replace(/^[\d.]+\s*/, ''))}.json`;
  escribir(archivo, {
    parent: raiz, package: d.paquete,
    elements: [...elementos, ...externos.values()],
    connectors: conectores,
    // Solo las relaciones de este dominio: las internas de las clases de otros dominios ya están en su vista.
    diagram: { name: d.diagrama ?? d.paquete.replace(/^[\d.]+\s*/, ''), type: 'Logical', layout: 'auto', hideOtherConnectors: true },
  });
  resumen.push(`${archivo}: ${elementos.length} clases, ${externos.size} de otros dominios, ${conectores.length} asociaciones`);
});

if (cfg.enumeraciones) {
  const lista = [...enums.values()];
  escribir(`${cfg.prefijo}-${String(cfg.dominios.length + 1).padStart(2, '0')}-enumeraciones.json`, {
    parent: raiz, package: cfg.enumeraciones,
    elements: lista.map((e) => ({
      id: e.nombre, name: e.nombre, type: 'Enumeration', notes: e.doc,
      attributes: e.valores.map((v) => ({ name: v.nombre, type: '', notes: v.doc })),
    })),
    connectors: [],
    diagram: { name: 'Enumeraciones', type: 'Logical', layout: 'grid', columns: 5, cellWidth: 220, cellHeight: 160 },
  });
  resumen.push(`enumeraciones: ${lista.length}`);
}
console.log(JSON.stringify({ ok: true, modelos: modelos.size, enums: enums.size, relaciones: relaciones.length, archivos: resumen }, null, 2));
