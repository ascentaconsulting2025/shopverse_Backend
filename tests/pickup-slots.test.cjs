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
test('uses Marathi days and Devanagari hours when English fields are missing',()=>{
 const now=new Date('2026-11-15T00:00:00Z');
 const expected=pickupSlots('Mon - Sat','10:00 AM - 8:00 PM','Asia/Kolkata','2026-11-16',now,0);
 assert.deepEqual(pickupSlots({en:'',mr:'सोमवार ते शनिवार'},{en:'',mr:'सकाळी १०:०० ते रात्री ८:००'},'Asia/Kolkata','2026-11-16',now,0),expected);
 assert.deepEqual(pickupSlots({mr:'सोम - शनि'},{mr:'१०:०० AM - ८:०० PM'},'Asia/Kolkata','2026-11-16',now,0),expected);
 assert.deepEqual(pickupSlots({en:'Mon - Sat',mr:'दररोज'},{en:'10:00 AM - 8:00 PM',mr:'सकाळी ९ ते रात्री ९'},'Asia/Kolkata','2026-11-16',now,0),expected);
});
