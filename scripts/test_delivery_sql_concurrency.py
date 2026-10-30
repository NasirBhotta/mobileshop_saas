"""Run against the isolated local fixture only; never accepts a remote DSN."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import uuid

PSQL = Path(r'D:\postgres\bin\psql.exe')
COMMAND = [str(PSQL), '-h', '127.0.0.1', '-p', '55439', '-U', 'nizaam_test',
           '-d', 'nizaam_features', '-v', 'ON_ERROR_STOP=1', '-At']

def run(sql):
    result = subprocess.run(COMMAND, input=sql, text=True, capture_output=True, check=True)
    return result.stdout

ticket, product, event_a, event_b = [str(uuid.uuid4()) for _ in range(4)]
tenant = '00000000-0000-0000-0000-000000000010'
branch = '00000000-0000-0000-0000-000000000020'
run(f"""
insert into repair_tickets(id,tenant_id,branch_id,customer_name,device_brand,device_model,fault_description,status,created_by)
values('{ticket}','{tenant}','{branch}','Guest','Phone','Model','Fault','received','00000000-0000-0000-0000-000000000001');
insert into inventory(branch_id,product_id,quantity) values('{branch}','{product}',10);
insert into repair_parts(ticket_id,tenant_id,branch_id,source_type,product_id,name,quantity,unit_cost_snapshot,unit_sale_price,state)
values('{ticket}','{tenant}','{branch}','inventory','{product}','Screen',1,40,100,'planned');
select prepare_repair_ticket_v3('{ticket}',gen_random_uuid(),100);
""")
with ThreadPoolExecutor(max_workers=2) as executor:
    first = executor.submit(run, f"begin; select id from repair_tickets where id='{ticket}' for update; select pg_sleep(1); select deliver_repair_ticket_v3('{ticket}','{event_a}'); commit;")
    second = executor.submit(run, f"select deliver_repair_ticket_v3('{ticket}','{event_b}');")
    first.result()
    second.result()
result = run(f"select quantity from inventory where product_id='{product}'; select count(*) from repair_financial_events where ticket_id='{ticket}';")
assert result.strip().splitlines() == ['9', '1'], result
print('Concurrent deliveries with different event IDs: stock deducted once; one financial event.')
