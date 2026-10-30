-- Execute only against scripts/create_delivery_sql_fixture.py's isolated schema.
-- Permission helpers are test doubles; production RLS needs separate staging checks.
begin;
insert into branches(id,tenant_id,name) values
 ('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000010','Test');
insert into customers(id,tenant_id,branch_id,full_name) values
 ('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000020','Test customer');
insert into inventory(branch_id,product_id,quantity) values
 ('00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000040',10);
insert into repair_tickets(id,tenant_id,branch_id,customer_id,customer_name,device_brand,device_model,fault_description,status,created_by,ticket_no)
select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000020',
 '00000000-0000-0000-0000-000000000030','Test customer','Phone','Model','Screen','received',
 '00000000-0000-0000-0000-000000000001','REP-'||n from generate_series(100,104) n;
insert into repair_parts(ticket_id,tenant_id,branch_id,source_type,product_id,name,quantity,unit_cost_snapshot,unit_sale_price,state)
select id,tenant_id,branch_id,'inventory','00000000-0000-0000-0000-000000000040','Screen',1,40,100,'planned'
from repair_tickets;

do $test$
declare t uuid := '00000000-0000-0000-0000-000000000100'; v jsonb;
begin
  perform prepare_repair_ticket_v3(t,gen_random_uuid(),100,0,0,10,0);
  perform prepare_repair_ticket_v3(t,gen_random_uuid(),100,0,0,10,0);
  assert (select quantity=10 from inventory), 'completion deducted stock';
  assert not exists(select 1 from repair_financial_events), 'completion posted finance';
  perform deliver_repair_ticket_v3(t,gen_random_uuid());
  perform deliver_repair_ticket_v3(t,gen_random_uuid());
  assert (select quantity=9 from inventory), 'delivery duplicate stock';
  assert (select count(*)=1 from repair_financial_events), 'duplicate financial posting';
  assert (select gross_profit=50 from repair_financial_events), 'wrong profit';
  assert (select status='delivered' and completed_at is not null and finalized_at is not null from repair_tickets where id=t);

  t := '00000000-0000-0000-0000-000000000101';
  perform prepare_repair_ticket_v3(t,gen_random_uuid(),100);
  perform cancel_repair_ticket_v3(t,gen_random_uuid(),null,null,null);
  assert (select quantity=9 from inventory), 'unposted cancellation restocked';
  assert not exists(select 1 from repair_financial_events where ticket_id=t), 'unposted cancellation reversed profit';

  t := '00000000-0000-0000-0000-000000000102';
  -- A historical posted completion must not be reposted at handover.
  update repair_tickets set status='completed',finalized_at=now(),customer_charge=100 where id=t;
  insert into repair_financial_events(tenant_id,branch_id,ticket_id,event_type,source_event_key,revenue_amount,inventory_cost,direct_parts_cost,commission_cost,other_direct_cost,gross_profit)
    values('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000020',t,'completion','legacy',100,40,0,0,0,60);
  perform deliver_repair_ticket_v3(t,gen_random_uuid());
  assert (select quantity=9 from inventory), 'legacy delivery reposted stock';
  assert (select count(*)=1 from repair_financial_events where ticket_id=t), 'legacy delivery reposted profit';

  t := '00000000-0000-0000-0000-000000000103';
  perform prepare_repair_ticket_v3(t,gen_random_uuid(),100);
  update inventory set quantity=0;
  begin
    perform deliver_repair_ticket_v3(t,gen_random_uuid());
    raise exception 'expected insufficient-stock failure';
  exception when raise_exception then
    if sqlerrm <> 'Insufficient repair-part stock.' then raise; end if;
  end;
  assert (select status='completed' from repair_tickets where id=t), 'failed delivery changed status';
  assert not exists(select 1 from repair_financial_events where ticket_id=t), 'failed delivery posted profit';
  update inventory set quantity=9;

  perform set_config('test.tenant','00000000-0000-0000-0000-000000000099',true);
  begin
    perform deliver_repair_ticket_v3(t,gen_random_uuid());
    raise exception 'expected tenant denial';
  exception when raise_exception then
    if sqlerrm <> 'Not allowed.' then raise; end if;
  end;
  perform set_config('test.tenant','00000000-0000-0000-0000-000000000010',true);
end $test$;

-- Direct status writes cannot bypass deferred accounting, or reset its mode.
set local role authenticated;
do $test$
begin
  begin
    update repair_tickets set status='delivered' where id='00000000-0000-0000-0000-000000000103';
    raise exception 'expected direct delivery denial';
  exception when raise_exception then
    if sqlerrm <> 'Use the repair financial workflow.' then raise; end if;
  end;
end $test$;
reset role;

insert into sales(id,branch_id,customer_id,user_id,status,subtotal,discount_amount,tax_amount,total,created_at)
select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,
 '00000000-0000-0000-0000-000000000020','00000000-0000-0000-0000-000000000030',
 '00000000-0000-0000-0000-000000000001','completed',100,0,0,100,'2026-10-10T12:00:00Z'
from generate_series(200,226) n;
insert into sale_payments(sale_id,method,amount) select id,'cash',60 from sales;
insert into sale_payments(sale_id,method,amount) select id,'credit',40 from sales;
insert into sale_items(sale_id,product_name,quantity,unit_price) select id,'Cable',2,50 from sales;
insert into customer_settlements(customer_id,branch_id,user_id,amount,method,created_at)
values('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000020',
 '00000000-0000-0000-0000-000000000001',50,'cash','2026-10-11T12:00:00Z');

do $test$
declare v jsonb;
begin
 v := customer_activity_v1('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000020','2026-10-01','2026-10-20',0,25);
 assert jsonb_array_length(v->'entries')=25, 'page size';
 assert (v->>'count')::integer=27, 'total incorrectly capped at page size';
 assert (v->>'visits')::integer=27, 'payments counted as visits';
 assert (v->>'purchase_amount')::numeric=2700, 'amount aggregate';
 assert (v->>'payments')::numeric=1670, 'credit double-counted as cash';
 update customers set full_name='Changed name' where id='00000000-0000-0000-0000-000000000030';
 update sales set notes='ordinary edit';
 v := customer_activity_v1('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000020','2026-10-01','2026-10-20',25,25);
 assert jsonb_array_length(v->'entries')=2;
 assert (v->>'visits')::integer=27;
 assert (v->>'purchase_amount')::numeric=2700;
 perform set_config('test.denied','yes',true);
 begin
   perform customer_activity_v1('00000000-0000-0000-0000-000000000030','00000000-0000-0000-0000-000000000020');
   raise exception 'expected history permission denial';
 exception when insufficient_privilege then null;
 end;
end $test$;
rollback;
\echo 'Delivery and customer activity SQL assertions passed.'
