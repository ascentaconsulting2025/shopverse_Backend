/** Resolve inherited mappings without losing the ancestors needed for navigation. */
export function resolveCatalog(rows: any[], roots: string[], type: 'product' | 'service', businessActive: boolean) {
 const byId = new Map(rows.map(row => [row.id, row]));
 const mapped = new Set(roots);
 const parents = new Set(rows.map(row => row.parent_id).filter(Boolean));
 const allowed = new Set<string>();
 for (const row of rows) {
  if (!businessActive || !row.available || row.catalog_kind !== type) continue;
  let node = row; let inherited = false; let valid = true;
  const seen = new Set<string>();
  while (node) {
   if (seen.has(node.id) || node.catalog_kind !== type || !node.available) { valid = false; break; }
   seen.add(node.id); inherited ||= mapped.has(node.id);
   if (!node.parent_id) break;
   node = byId.get(node.parent_id);
   if (!node) valid = false;
  }
  if (valid && inherited) allowed.add(row.id);
 }
 const visible = new Set(allowed);
 for (const id of allowed) {
  let node = byId.get(id); const seen = new Set<string>();
  while (node?.parent_id && !seen.has(node.parent_id)) {
   seen.add(node.parent_id); visible.add(node.parent_id); node = byId.get(node.parent_id);
  }
 }
 return rows.filter(row => visible.has(row.id)).map(row => ({...row, type,
  allowed: allowed.has(row.id), selectable: allowed.has(row.id) && !parents.has(row.id),
 }));
}

/** Public browsing describes published records; it must not reuse permissions for NEW listings. */
export function publicCategoryProjection(rows: any[], products: any[], services: any[]) {
 const byId=new Map(rows.map(row=>[row.id,row]));
 return ([['product',products],['service',services]] as const).flatMap(([type,items])=>{
  const visible=new Set<string>();
  for(const item of items) {
   if(item.is_published===false) continue;
   let node=byId.get(item.folder_category_id);const seen=new Set<string>();
   while(node && node.available && !seen.has(node.id)) {
    seen.add(node.id);visible.add(node.id);node=byId.get(node.parent_id);
   }
  }
  return rows.filter(row=>visible.has(row.id)).map(row=>({...row,type}));
 });
}
