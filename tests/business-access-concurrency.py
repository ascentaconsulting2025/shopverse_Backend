"""Concurrency checks against the disposable database after business-access-database.sql."""
import os
import re
import subprocess
import time

base = ['psql', '-X', '-h', os.environ.get('TEST_PGHOST', '/tmp'), '-p', os.environ.get('TEST_PGPORT', '55440'), '-d', os.environ.get('TEST_PGDATABASE', 'access_creation_test'), '-v', 'ON_ERROR_STOP=1', '-qAt']
owner = '00000000-0000-4000-8000-000000000001'
manager = '00000000-0000-4000-8000-000000000002'
admin = '00000000-0000-4000-8000-000000000003'
business = '10000000-0000-4000-8000-000000000001'
owned = '10000000-0000-4000-8000-000000000002'

def run(sql):
    return subprocess.run(base + ['-c', sql], capture_output=True, text=True, check=True).stdout.strip()

def caller(user):
    return f"set role authenticated; select set_config('request.jwt.claims','{{\"sub\":\"{user}\",\"session_id\":\"{user}\"}}',false);"

# Both requests race to invite one normalized email, despite different token hashes.
first_sql = f"begin; {caller(owner)} select business_invite('{owned}','race@example.test',repeat('c',64),7); select pg_sleep(1); commit;"
second_sql = f"begin; {caller(owner)} select business_invite('{owned}','race@example.test',repeat('d',64),7); commit;"
first = subprocess.Popen(base + ['-c', first_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
second = subprocess.Popen(base + ['-c', second_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
out1, err1 = first.communicate(timeout=10)
out2, err2 = second.communicate(timeout=10)
assert sorted([first.returncode, second.returncode]) == [0, 1], (out1, err1, out2, err2)
assert run(f"select count(*) from business_invitations where business_id='{owned}' and invited_email='race@example.test' and status='pending'") == '1'

# Retried creation requests serialize and return the same business ID.
request = '30000000-0000-4000-8000-000000000002'
payload1 = '{"owner_id":"' + owner + '","business_name":"Concurrent creation","slug":"concurrent-one"}'
payload2 = '{"owner_id":"' + owner + '","business_name":"Concurrent creation","slug":"concurrent-two"}'
first_sql = f"begin; {caller(owner)} select business_create_with_people('{payload1}','[]','{request}')->>'id'; select pg_sleep(1); commit;"
second_sql = f"begin; {caller(owner)} select business_create_with_people('{payload2}','[]','{request}')->>'id'; commit;"
first = subprocess.Popen(base + ['-c', first_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
second = subprocess.Popen(base + ['-c', second_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
out1, err1 = first.communicate(timeout=10)
out2, err2 = second.communicate(timeout=10)
assert first.returncode == 0 and second.returncode == 0, (out1, err1, out2, err2)
ids1 = [line for line in out1.splitlines() if re.fullmatch(r'[0-9a-f-]{36}', line)]
ids2 = [line for line in out2.splitlines() if re.fullmatch(r'[0-9a-f-]{36}', line)]
assert len(ids1) == len(ids2) == 1 and ids1 == ids2, (out1, out2)
assert run("select count(*) from businesses where business_name='Concurrent creation'") == '1'

# Revocation holds the business lock while the Manager attempts a write.
run(f"{caller(admin)} select business_change_access('{business}','add_manager','{manager}',null,'remove','revoke');")
remove_sql = f"begin; {caller(admin)} select business_change_access('{business}','remove_manager','{manager}',null,'remove','revoke'); select pg_sleep(1); commit;"
write_sql = f"begin; {caller(manager)} insert into products(business_id,name) values('{business}','racing revoked write'); commit;"
first = subprocess.Popen(base + ['-c', remove_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
second = subprocess.Popen(base + ['-c', write_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
out1, err1 = first.communicate(timeout=10)
out2, err2 = second.communicate(timeout=10)
assert first.returncode == 0 and second.returncode != 0, (out1, err1, out2, err2)
assert run("select count(*) from products where name='racing revoked write'") == '0'

# The same guarantee must hold for edits to the business row itself.
run(f"{caller(admin)} select business_change_access('{business}','add_manager','{manager}',null,'remove','revoke');")
remove_sql = f"begin; {caller(admin)} select business_change_access('{business}','remove_manager','{manager}',null,'remove','revoke'); select pg_sleep(1); commit;"
write_sql = f"begin; {caller(manager)} update businesses set business_name='racing revoked edit' where id='{business}'; commit;"
first = subprocess.Popen(base + ['-c', remove_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
second = subprocess.Popen(base + ['-c', write_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
out1, err1 = first.communicate(timeout=10)
out2, err2 = second.communicate(timeout=10)
assert first.returncode == 0 and second.returncode != 0, (out1, err1, out2, err2)
assert run("select count(*) from businesses where business_name='racing revoked edit'") == '0'

# A former Owner cannot delete a business after a concurrent transfer commits.
transfer_sql = f"begin; {caller(admin)} select business_change_access('{owned}','transfer_owner','{manager}','{owner}','remove','revoke'); select pg_sleep(1); commit;"
delete_sql = f"begin; {caller(owner)} delete from businesses where id='{owned}'; commit;"
first = subprocess.Popen(base + ['-c', transfer_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
time.sleep(0.2)
second = subprocess.Popen(base + ['-c', delete_sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
out1, err1 = first.communicate(timeout=10)
out2, err2 = second.communicate(timeout=10)
assert first.returncode == 0, (out1, err1, out2, err2)
assert run(f"select count(*) from businesses where id='{owned}'") == '1'
print('Business access concurrency tests passed.')
