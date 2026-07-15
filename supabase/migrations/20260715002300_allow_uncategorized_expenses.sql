-- Expense categories are optional in the app and local database. Reports
-- already group a null category as "Uncategorized". Align existing remote
-- databases with that contract.

alter table public.expenses
alter column category_name drop not null;
