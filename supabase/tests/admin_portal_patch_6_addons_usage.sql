-- Run after all migrations against a disposable/local database.
begin;

insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
 raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
values
 ('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-000000000601','authenticated','authenticated','admin-p6@example.invalid','',now(),'{}','{}',now(),now(),'','','',''),
 ('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-000000000602','authenticated','authenticated','user-p6@example.invalid','',now(),'{}','{}',now(),now(),'','','','');
insert into public.platform_admins(user_id) values('00000000-0000-4000-8000-000000000601');
insert into public.tenants(id,shop_name,business_type,branch_count,plan,status,setup_complete)
values('00000000-0000-4000-8000-000000000603','Patch 6 Shop','retail',1,'starter','active',true);

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000601',true);

do $test$ declare addon uuid; assignment uuid; begin
 addon := public.platform_save_addon(null,'extra_history','Extra history',null,100,'monthly',null,'expenses.history_days',30,true);
 assignment := public.platform_assign_tenant_addon('00000000-0000-4000-8000-000000000603',addon,2,now(),now()+interval '30 days','active','test');
 if (select quantity from public.platform_list_tenant_addons('00000000-0000-4000-8000-000000000603')) <> 2 then raise exception 'Assignment quantity failed'; end if;
 perform public.platform_remove_tenant_addon(assignment,'test removal');
 if (select status from public.platform_list_tenant_addons('00000000-0000-4000-8000-000000000603')) <> 'removed' then raise exception 'Removal failed'; end if;
 if exists (
  select 1 from public.tenant_addons
  where id=assignment and expires_at <= starts_at
 ) then raise exception 'Immediate removal produced an invalid expiry'; end if;
 perform public.platform_deactivate_addon(addon,'test deactivation');
end $test$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000602',true);
do $test$ begin
 begin perform public.platform_list_addons(); raise exception 'Non-admin unexpectedly listed add-ons';
 exception when insufficient_privilege then if sqlstate <> '42501' then raise; end if; end;
end $test$;

reset role;
do $test$ begin
 if (select count(*) from public.entitlement_audit_logs where action in ('addon.created','addon.assigned','addon.removed','addon.deactivated')) <> 4 then
  raise exception 'Every add-on mutation must be audited'; end if;
end $test$;
rollback;
