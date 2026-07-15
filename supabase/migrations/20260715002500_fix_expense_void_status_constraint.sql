-- Some deployed databases still have the legacy expense status constraint
-- that accepts "cancelled" instead of the app's canonical "void" value.

alter table public.expenses
drop constraint if exists expenses_status_check;

update public.expenses
set status = 'void'
where status = 'cancelled';

alter table public.expenses
add constraint expenses_status_check
check (status in ('draft', 'confirmed', 'void'));
