-- Keep the immutable audit timestamp separate from the accounting period.
-- A completed repair cancelled while its original period is still open must
-- restate that original period instead of making today's operating profit
-- appear negative. Cash refunds and cancellation activity remain dated today.

alter table public.repair_financial_events
  add column if not exists effective_at timestamptz;

update public.repair_financial_events
set effective_at = occurred_at
where effective_at is null;

-- Backfill existing reversals, including chained historical data, from their
-- immutable completion snapshot.
update public.repair_financial_events reversal
set effective_at = original.effective_at
from public.repair_financial_events original
where reversal.event_type = 'reversal'
  and reversal.reversal_of_event_id = original.id
  and reversal.effective_at is distinct from original.effective_at;

alter table public.repair_financial_events
  alter column effective_at set default now(),
  alter column effective_at set not null;

create index if not exists repair_financial_events_effective_date_idx
  on public.repair_financial_events(tenant_id, branch_id, effective_at);

create or replace function public.set_repair_financial_effective_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $function$
declare
  v_original_effective_at timestamptz;
begin
  if new.event_type = 'reversal' then
    if new.reversal_of_event_id is null then
      raise exception using errcode = '23514',
        message = 'Repair reversal must reference its original event.';
    end if;

    select original.effective_at
      into v_original_effective_at
    from public.repair_financial_events original
    where original.id = new.reversal_of_event_id;

    if v_original_effective_at is null then
      raise exception using errcode = '23503',
        message = 'Original repair financial event was not found.';
    end if;

    new.effective_at := v_original_effective_at;
  else
    new.effective_at := coalesce(new.effective_at, new.occurred_at, now());
  end if;

  return new;
end
$function$;

drop trigger if exists trg_repair_financial_effective_at
  on public.repair_financial_events;
create trigger trg_repair_financial_effective_at
before insert or update of event_type, reversal_of_event_id, effective_at
on public.repair_financial_events
for each row execute function public.set_repair_financial_effective_at();

revoke all on function public.set_repair_financial_effective_at() from public;

comment on column public.repair_financial_events.effective_at is
  'Accounting-period timestamp. Reversals inherit the original completion effective_at; occurred_at remains the immutable audit timestamp.';
