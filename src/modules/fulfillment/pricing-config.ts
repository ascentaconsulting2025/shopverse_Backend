import { z } from 'zod';
const money=z.number().finite().min(0).max(1000000).refine(v=>Math.abs(v*100-Math.round(v*100))<0.000001,'Maximum two decimal places');
export const configSchema=z.object({
 postcodes:z.array(z.string().regex(/^[1-9]\d{5}$/)).max(10000),maxRadiusKm:z.number().finite().positive().max(500),
 speeds:z.object({standard_4_6h:z.object({enabled:z.boolean(),base:money}).strict(),standard_24h:z.object({enabled:z.boolean(),base:money}).strict(),urgent:z.object({enabled:z.boolean(),base:money}).strict()}).strict(),
 fleetRates:z.array(z.object({fleetId:z.string().uuid(),perKm:money}).strict()).max(100)
}).strict().superRefine((v,ctx)=>{if(new Set(v.postcodes).size!==v.postcodes.length||new Set(v.fleetRates.map(x=>x.fleetId)).size!==v.fleetRates.length)ctx.addIssue({code:'custom',message:'Duplicate postcode or fleet rate'});});
