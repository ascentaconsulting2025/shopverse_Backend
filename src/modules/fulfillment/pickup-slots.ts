const dayNames=['sun','mon','tue','wed','thu','fri','sat'];
function dayNumber(value:string):number { return dayNames.indexOf(value.slice(0,3).toLowerCase()); }
function parseDays(value:unknown):Set<number>|null {
 if(typeof value!=='string')return null;
 const text=value.trim().toLowerCase();if(text==='daily'||text==='every day')return new Set([0,1,2,3,4,5,6]);
 const match=text.match(/^(sun(?:day)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?)\s*[-–]\s*(sun(?:day)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?)$/);
 if(match){const days=new Set<number>();let n=dayNumber(match[1]),end=dayNumber(match[2]);for(let i=0;i<7;i++){days.add(n);if(n===end)break;n=(n+1)%7;}return days;}
 const parts=text.split(/\s*,\s*/);if(!parts.length||parts.some(p=>!/^(sun(?:day)?|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?)$/.test(p)))return null;
 return new Set(parts.map(dayNumber));
}
function parseTime(value:string):number|null {
 const m=value.trim().match(/^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$/i);if(!m)return null;
 const hour=Number(m[1]),minutes=Number(m[2]||0);if(hour<1||hour>12||minutes>59)return null;
 return (hour%12+(m[3].toLowerCase()==='pm'?12:0))*60+minutes;
}
const formatters=new Map<string,Intl.DateTimeFormat>();
function partsAt(ms:number,timezone:string):number[] {
 let fmt=formatters.get(timezone);
 if(!fmt){fmt=new Intl.DateTimeFormat('en-GB',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});formatters.set(timezone,fmt);}
 const parts=fmt.formatToParts(new Date(ms));return ['year','month','day','hour','minute'].map(key=>Number(parts.find(p=>p.type===key)?.value));
}
// Reject nonexistent or ambiguous local times rather than guessing at clock changes.
function localToUtc(year:number,month:number,day:number,minutes:number,timezone:string):number|null {
 const wall=Date.UTC(year,month-1,day,0,minutes),target=new Date(wall),desired=[target.getUTCFullYear(),target.getUTCMonth()+1,target.getUTCDate(),target.getUTCHours(),target.getUTCMinutes()];
 let guess=wall;
 for(let n=0;n<3;n++){const p=partsAt(guess,timezone);guess+=wall-Date.UTC(p[0],p[1]-1,p[2],p[3],p[4]);}
 const matches:number[]=[];for(let delta=-180;delta<=180;delta++){const t=guess+delta*60000;if(partsAt(t,timezone).every((x,i)=>x===desired[i]))matches.push(t);}
 return matches.length===1?matches[0]:null;
}
export function pickupSlots(daysText:unknown,timingsText:unknown,timezone:string,date:string,now:Date,leadMinutes:number){
 const days=parseDays(daysText);const times=typeof timingsText==='string'?timingsText.trim().match(/^(.+?)\s*[-–]\s*(.+)$/):null;
 const open=times?parseTime(times[1]):null,close=times?parseTime(times[2]):null;
 if(!days||open===null||close===null||open===close)throw new Error('Store hours are unavailable or ambiguous');
 if(!/^\d{4}-\d{2}-\d{2}$/.test(date))throw new Error('Invalid date');
 const day=new Date(`${date}T00:00:00Z`);if(Number.isNaN(day.valueOf())||day.toISOString().slice(0,10)!==date)throw new Error('Invalid date');
 // Validate timezone before looking for possible UTC instants.
 try{partsAt(now.valueOf(),timezone);}catch{throw new Error('Store timezone is unavailable');}
 const result:{start:string;end:string}[]=[];
 for(const offset of [-1,0]){
  const base=new Date(day.valueOf()+offset*86400000);if(!days.has(base.getUTCDay()))continue;
  const end=close<=open?close+1440:close;
  for(let minute=open;minute+60<=end;minute+=60){
   const localStart=new Date(Date.UTC(base.getUTCFullYear(),base.getUTCMonth(),base.getUTCDate(),0,minute));
   if(localStart.toISOString().slice(0,10)!==date)continue;
   const start=localToUtc(base.getUTCFullYear(),base.getUTCMonth()+1,base.getUTCDate(),minute,timezone);
   const finish=localToUtc(base.getUTCFullYear(),base.getUTCMonth()+1,base.getUTCDate(),minute+60,timezone);
   if(start!==null&&finish!==null&&finish-start===3600000&&start>=now.valueOf()+leadMinutes*60000) result.push({start:new Date(start).toISOString(),end:new Date(finish).toISOString()});
  }
 }
 return result;
}
