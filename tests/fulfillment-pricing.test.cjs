const {test}=require('node:test');
const assert=require('node:assert/strict');
const {deliveryDistanceTenths,deliveryCharge}=require('../dist/modules/fulfillment/pricing.js');
test('distance and charges round as stated',()=>{
 assert.equal(deliveryDistanceTenths(18.52,73.85,18.52,73.85),0);
 assert.equal(deliveryCharge(30,5,42),51);
 assert.equal(deliveryCharge(0,0.05,1),0.01);
 assert.equal(deliveryCharge(0,0.04,1),0);
 assert.ok(deliveryDistanceTenths(18.52,73.85,18.53,73.85)>=11);
});
