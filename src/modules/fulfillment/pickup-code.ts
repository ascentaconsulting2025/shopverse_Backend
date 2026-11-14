import { createHmac } from 'crypto';
export function pickupCode(secret:string,orderId:string,nonce:string):string {
 const digest=createHmac('sha256',secret).update(`pickup-code:${orderId}:${nonce}`).digest();
 return String(digest.readUIntBE(0,6)%1000000).padStart(6,'0');
}
export function pickupCodeHash(secret:string,orderId:string,code:string):string {
 return createHmac('sha256',secret).update(`pickup-verify:${orderId}:${code}`).digest('hex');
}
