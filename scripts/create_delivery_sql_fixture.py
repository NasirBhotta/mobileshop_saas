"""Generate an isolated test schema, never a production migration."""
from pathlib import Path
import re
src=Path('lib/core/local/local_database.dart').read_text(encoding='utf-8')
tables={}
# Match the Dart triple-quoted statement boundary, not nested SQL parentheses.
for m in re.finditer(r"CREATE TABLE IF NOT EXISTS (\w+)\s*\((.*?)\)\s*\n\s*'''",src,re.S):
    name,body=m.groups()
    lines=[]
    for line in body.splitlines():
        line=line.strip()
        if not line: continue
        cm=re.match(r'(\w+) (TEXT|REAL|INTEGER)(.*)',line)
        if cm:
            col,typ,tail=cm.groups()
            if typ=='TEXT':
                if col=='id' or (col.endswith('_id') and col not in ['reference_id','source_event_key']):typ='uuid'
                elif col.endswith('_at'):typ='timestamptz'
                else:typ='text'
            elif typ=='REAL':typ='numeric'
            else:typ='integer'
            if col in ['is_active','is_warranty_repair']:typ='boolean';tail=tail.replace('DEFAULT 1','DEFAULT true').replace('DEFAULT 0','DEFAULT false')
            tail=tail.replace('NOT NULL','')
            if col=='id':tail=tail.replace('PRIMARY KEY','PRIMARY KEY DEFAULT gen_random_uuid()')
            if col in ['created_at','updated_at','occurred_at','effective_at','received_at','refunded_at','transaction_at'] and 'DEFAULT' not in tail:tail=tail.rstrip(',')+' DEFAULT now()'+(',' if line.endswith(',') else '')
            line=f'{col} {typ}{tail}'
        lines.append(line)
    tables[name]='CREATE TABLE public.'+name+'(\n'+ '\n'.join(lines)+'\n);'
needed=['users','tenants','branches','customers','products','inventory','repair_tickets','repair_parts','repair_financial_events','repair_status_logs','repair_payments','repair_payment_refunds','suppliers','supplier_ledger_entries','accounts','account_transactions','sales','sale_items','sale_payments','customer_settlements']
missing=set(needed)-tables.keys()
if missing:raise Exception(missing)
prefix='''-- Isolated fixture with permission stubs, not a full Supabase/RLS environment.
do $$begin if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end$$;
do $$begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if; end$$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$select '00000000-0000-0000-0000-000000000001'::uuid$$;
create function public.current_user_tenant_id() returns uuid language sql stable as $$select coalesce(nullif(current_setting('test.tenant',true),''),'00000000-0000-0000-0000-000000000010')::uuid$$;
create function public.current_user_has_branch_permission(uuid,uuid,text) returns boolean language sql stable as $$select $1 = public.current_user_tenant_id() and $2 = '00000000-0000-0000-0000-000000000020'::uuid and coalesce(current_setting('test.denied',true),'') <> 'yes'$$;
'''
sql=prefix+'\n'.join(tables[n] for n in needed)
sql+='''
alter table public.repair_payment_refunds add column tenant_id uuid, add column branch_id uuid;
grant usage on schema public,auth to authenticated;
grant select,update,insert on all tables in schema public to authenticated;
'''
Path('build/nizaam_sql_fixture.sql').write_text(sql,encoding='utf-8')
