"""Run with a disposable migrated DB as template, never a production connection.
Requires local PostgreSQL tools and the fixture-only postgres DB on /tmp:55479.
Creates and drops its own temporary clone; no environment credentials used.
"""
import concurrent.futures, pathlib, re, subprocess, uuid
name='logistics_race_'+uuid.uuid4().hex[:12]
args=['-h','/tmp','-p','55479']
def sql(text):
 return subprocess.run(['psql',*args,'-d',name,'-v','ON_ERROR_STOP=1','-At'],input=text,text=True,capture_output=True)
source=(pathlib.Path(__file__).parent/'logistics-lifecycle.sql').read_text()
try:
 subprocess.run(['createdb',*args,'-T','postgres',name],check=True)
 fixture=source.split('do $$')[0]
 cfg=re.search("cfg jsonb:='([^']+)'",source)[1];details=re.search("details jsonb:='([^']+)'",source)[1]
 prepared=sql(fixture+f"select delivery_save_settings('da000000-0000-4000-8000-000000000001','{cfg}');\n"+''.join(f"select delivery_select_order('dd000000-0000-4000-8000-{i:012}','da000000-0000-4000-8000-000000000001',false,'{details}');\n" for i in [1,2,3])+'commit;')
 assert prepared.returncode==0,prepared.stderr
 task=sql("select id from delivery_tasks order by store_order_id").stdout.splitlines()
 def accept(pair):
  taskid,user=pair
  return sql(f"select delivery_accept('{taskid}','da000000-0000-4000-8000-{user:012}');")
 with concurrent.futures.ThreadPoolExecutor() as pool: result=list(pool.map(accept,[(task[0],3),(task[0],4)]))
 assert sum(r.returncode==0 for r in result)==1,[r.stderr for r in result]
 winner=sql(f"select p.user_id from delivery_tasks t join delivery_partner_profiles p on p.id=t.partner_id where t.id='{task[0]}'").stdout.strip()
 sql(f"update delivery_partner_profiles set max_active_orders=2 where user_id='{winner}'")
 with concurrent.futures.ThreadPoolExecutor() as pool: result=list(pool.map(accept,[(task[1],int(winner[-12:])),(task[2],int(winner[-12:]))]))
 assert sum(r.returncode==0 for r in result)==1,[r.stderr for r in result]
 count=sql(f"select count(*) from delivery_assignments a join delivery_partner_profiles p on p.id=a.partner_id where p.user_id='{winner}' and ended_at is null").stdout.strip()
 assert count=='2',count
 print('PASS: concurrent acceptance has one winner; concurrent reservations cannot exceed partner capacity')
finally:
 subprocess.run(['dropdb',*args,'--if-exists',name],check=True)
