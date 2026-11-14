const {test}=require('node:test');
const assert=require('node:assert/strict');
const {pickupSlots}=require(process.env.SHOPVERSE_TEST_DIST+'/modules/fulfillment/pickup-slots.js');
test('generates complete one-hour windows respecting opening days and lead time',()=>{
 const slots=pickupSlots('Mon - Sat','9:00 AM - 11:30 AM','Asia/Kolkata','2026-11-16',new Date('2026-11-16T03:15:00Z'),30);
 assert.deepEqual(slots,[{start:'2026-11-16T04:30:00.000Z',end:'2026-11-16T05:30:00.000Z'}]);
 assert.deepEqual(pickupSlots('Mon - Sat','9:00 AM - 11:30 AM','Asia/Kolkata','2026-11-15',new Date('2026-11-14T00:00:00Z'),30),[]);
});
test('includes after-midnight windows from the previous opening day',()=>{
 const slots=pickupSlots('Mon','11:00 PM - 2:00 AM','Asia/Kolkata','2026-11-17',new Date('2026-11-16T00:00:00Z'),30);
 assert.deepEqual(slots.map(s=>s.start),['2026-11-16T18:30:00.000Z','2026-11-16T19:30:00.000Z']);
});
test('rejects ambiguous hours and invalid dates or timezones',()=>{
 for(const args of [['Mon - Sat','whenever open','Asia/Kolkata','2026-11-16'],['Mon','9:00 AM - 5:00 PM','Invalid/Zone','2026-11-16'],['Mon','9:00 AM - 5:00 PM','Asia/Kolkata','2026-02-31']])assert.throws(()=>pickupSlots(...args,new Date('2026-11-14T00:00:00Z'),30));
});
