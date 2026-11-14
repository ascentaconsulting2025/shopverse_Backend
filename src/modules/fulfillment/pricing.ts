/** Straight-line distance rounded up to a tenth of a kilometre. */
export function deliveryDistanceTenths(lat1:number,lon1:number,lat2:number,lon2:number):number {
 const radians=(n:number)=>n*Math.PI/180, dLat=radians(lat2-lat1),dLon=radians(lon2-lon1);
 const a=Math.sin(dLat/2)**2+Math.cos(radians(lat1))*Math.cos(radians(lat2))*Math.sin(dLon/2)**2;
 return Math.ceil(6371*2*Math.asin(Math.sqrt(Math.min(1,a)))*10);
}
/** Values are rupees with at most two decimals; arithmetic uses paise. */
export function deliveryCharge(base:number,perKm:number,distanceTenths:number):number {
 const basePaise=Math.round(base*100), ratePaise=Math.round(perKm*100);
 return (basePaise+Math.floor((distanceTenths*ratePaise+5)/10))/100;
}
