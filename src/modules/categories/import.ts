import { ApiError } from '../../utils/apiError';
/** Matches the legacy object/array/string hierarchy format, with bounded input. */
export function parseCategoryImport(input: unknown): string[][] {
 const paths:string[][]=[];
 const seen=new Set<string>();
 const add=(name:string,parent:string[])=>{
  const label=name.normalize('NFKC').trim().replace(/\s+/gu,' ');
  if(!label) return null;
  if(label.length>100 || parent.length>=32) throw new ApiError('Category names must be 1–100 characters and hierarchy depth at most 32',400);
  const path=[...parent,label];
  const key=JSON.stringify(path.map(p=>p.toLowerCase()));
  if(!seen.has(key)){ seen.add(key); paths.push(path); }
  if(paths.length>1000) throw new ApiError('Import at most 1000 categories at a time',400);
  return path;
 };
 const walk=(node:unknown,parent:string[],depth=0)=>{
  if(depth>64) throw new ApiError('Category JSON is too deeply nested',400);
  if(typeof node==='string') add(node,parent);
  else if(Array.isArray(node)) node.forEach(value=>walk(value,parent,depth+1));
  else if(node && typeof node==='object') Object.entries(node).forEach(([key,value])=>{const path=add(key,parent);if(path)walk(value,path,depth+1);});
  else if(node!==null) throw new ApiError('Use category objects, arrays, or names in the JSON structure',400);
 };
 walk(input,[]);
 if(!paths.length) throw new ApiError('No category nodes found in JSON',400);
 return paths;
}
