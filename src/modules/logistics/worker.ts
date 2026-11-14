import { supabaseAdmin } from '../../config/supabaseClient';
// Deadlines and ownership live in Postgres; multiple server replicas are safe.
export function startDeliveryWorker() {
 if(process.env.LOGISTICS_WORKER_ENABLED!=='true') return;
 let running=false;
 const tick=async()=>{if(running)return;running=true;try{const queued=await supabaseAdmin.rpc('process_delivery_order_allocation');if(queued.error)console.error('Delivery request queue failed',queued.error.code);const {error}=await supabaseAdmin.rpc('process_delivery_jobs');if(error)console.error('Delivery allocation tick failed',error.code);}catch{console.error('Delivery allocation service unavailable');}finally{running=false;}};
 void tick();const timer=setInterval(()=>void tick(),15000);timer.unref();
}
