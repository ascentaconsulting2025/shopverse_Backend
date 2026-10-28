import { ApiError } from '../../utils/apiError';
export const normalizeName = (name: string) => name.normalize('NFKC').trim().replace(/\s+/gu, ' ').toLocaleLowerCase();
export function categoryBusinesses(rows: any[], mappings: any[]) {
 const byId = new Map(rows.map(row => [row.id, row]));
 return rows.map(row => {
  const ancestors = new Set<string>(); let node = row;
  while (node && !ancestors.has(node.id)) { ancestors.add(node.id); node = byId.get(node.parent_id); }
  return {...row, direct_business_category_ids: mappings.filter(m=>m.catalog_category_id===row.id).map(m=>m.business_category_id), business_category_ids: [...new Set([...mappings.filter(m => ancestors.has(m.catalog_category_id)).map(m => m.business_category_id),...rows.filter(c=>c.id!==row.id&&c.catalog_kind==='business'&&ancestors.has(c.id)).map(c=>c.id)])]};
 });
}
export function validateWrite(rows: any[], fields: any, id?: string, business?: string, allowSimilar=false) {
 const current = rows.find(c => c.id === id);
 if (id && !current) throw new ApiError('Category not found',404);
 const next = {...current,...fields};
 const kind = next.catalog_kind || 'legacy';
 const parentOwners=rows.find(c=>c.id===next.parent_id)?.business_category_ids||[];
 if(!business && !id && next.parent_id && parentOwners.length){
  if(parentOwners.length>1)throw new ApiError('This parent is shared. Select an exclusive business branch before adding a child.',409);
  business=parentOwners[0];
 }
 if(current && fields.parent_id!==undefined && fields.parent_id!==current.parent_id){
  const before=[...(current.business_category_ids||[])].sort();
  const after=[...new Set([...(current.direct_business_category_ids||[]),...parentOwners])].sort();
  if(JSON.stringify(before)!==JSON.stringify(after))throw new ApiError('Moving this category would change its business assignments. Update mappings explicitly before changing its parent.',409);
 }

 if (business && !rows.some(c => c.id===business && c.catalog_kind==='business')) throw new ApiError('Business category not found',404);
 if (business && !['product','service'].includes(kind)) throw new ApiError('Business context requires a Product or Service category',400);
 let parent = rows.find(c=>c.id===next.parent_id);
 if(next.parent_id && (!parent || (kind!=='legacy' && parent.catalog_kind!==kind))) throw new ApiError('Select a parent of the same category type',400);
 const seen = new Set(id?[id]:[]);
 while(parent){if(seen.has(parent.id))throw new ApiError('A category cannot be placed beneath itself or its descendants',400);seen.add(parent.id);parent=rows.find(c=>c.id===parent.parent_id);}
 if(business && next.parent_id){
  const owners=rows.find(c=>c.id===next.parent_id)?.business_category_ids || [];
  if(!owners.includes(business))throw new ApiError('Parent is not assigned to the selected business',400);
  if(owners.some((owner:string)=>owner!==business))throw new ApiError('This parent is shared by multiple businesses. A business-specific child cannot safely be added here.',409);
 }
 if(business && current && (!(current.business_category_ids||[]).includes(business) || current.business_category_ids.length>1))throw new ApiError('This category cannot be edited exclusively in the selected business',409);
 if(id && !['name','name_mr','parent_id','catalog_kind'].some(key=>key in fields))return;
 const owners=business?[business]:(next.business_category_ids||[]);
 const siblings=rows.filter(c=>c.id!==id && (c.catalog_kind||'legacy')===kind && (c.parent_id||null)===(next.parent_id||null) && (next.parent_id || kind==='business' || (!owners.length ? !(c.business_category_ids||[]).length : (c.business_category_ids||[]).some((owner:string)=>owners.includes(owner)))));
 const path=(row:any)=>{const names=[];const visited=new Set();while(row&&!visited.has(row.id)){visited.add(row.id);names.unshift(row.name);row=rows.find(c=>c.id===row.parent_id);}return names.join(' > ');};
 const exact=siblings.find(c=>normalizeName(c.name)===normalizeName(next.name) || (next.name_mr && c.name_mr && normalizeName(c.name_mr)===normalizeName(next.name_mr)));
 if(exact)throw new ApiError(`Category Already Exists: ${path(exact)}. Use the existing category or choose a different name.`,409);
 const comparable=(s:string)=>normalizeName(s).replace(/\s/g,'').replace(/jewellery/g,'jewelry').replace(/s$/,'');
 const similar=siblings.find(c=>comparable(c.name)===comparable(next.name));
 if(similar&&!allowSimilar)throw new ApiError(`Similar category: ${path(similar)}. Review it before choosing Create Anyway.`,409);
}
