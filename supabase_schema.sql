-- =====================================================================
--  بطولات فارس — سكيمة Supabase (نظام دخول مبسّط بأرقام سرية مجزّأة)
--  شغّل هذا الملف كاملاً مرة واحدة في: Supabase ▸ SQL Editor ▸ New query
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1) جدول المستخدمين — بيانات الدخول لا تُقرأ أبداً من المتصفح
--    (لا توجد سياسة SELECT للعامة، فقط الدوال أدناه تقدر تلمسه)
-- ---------------------------------------------------------------------
create table if not exists fa_users (
  id            text primary key,
  name          text not null,
  username      text unique not null,
  pin_hash      text not null,          -- الرمز السري مجزّأ bcrypt (غير قابل للعكس)
  role          text not null,          -- admin | organizer | admin-team | coach | player | viewer
  team          text default '',
  phone         text default '',
  coach_id      text,
  session_token uuid
);
alter table fa_users enable row level security;
-- عمداً: لا سياسات على fa_users => لا أحد يقرأه مباشرة. الوصول فقط عبر دوال SECURITY DEFINER.

-- ---------------------------------------------------------------------
-- 2) حالة التطبيق — كائن JSON واحد فيه (البطولات، الفرق، اللاعبين،
--    الفئات، النتائج، الإعدادات، سجل النشاط...). قراءة عامة، كتابة عبر دالة.
-- ---------------------------------------------------------------------
create table if not exists fa_state (
  id         int primary key default 1,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now(),
  constraint fa_state_single_row check (id = 1)
);
alter table fa_state enable row level security;
create policy fa_state_public_read on fa_state for select using (true);
insert into fa_state (id, data) values (1, '{}'::jsonb) on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3) تسجيل الدخول: يتحقق من الهاش، يولّد توكن جلسة، ويرجّع المستخدم بدون الهاش
-- ---------------------------------------------------------------------
create or replace function fa_login(p_username text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare u fa_users; tok uuid;
begin
  select * into u from fa_users where username = p_username;
  if not found then return null; end if;
  if u.pin_hash <> crypt(p_pin, u.pin_hash) then return null; end if;
  tok := gen_random_uuid();
  update fa_users set session_token = tok where id = u.id;
  return jsonb_build_object(
    'id', u.id, 'name', u.name, 'username', u.username, 'role', u.role,
    'team', coalesce(u.team,''), 'phone', coalesce(u.phone,''),
    'coachId', u.coach_id, 'token', tok
  );
end; $$;

-- ---------------------------------------------------------------------
-- 4) حفظ حالة التطبيق: فقط توكن صالح بصلاحية كتابة يقدر يحفظ
-- ---------------------------------------------------------------------
create or replace function fa_save_state(p_token uuid, p_data jsonb)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare a fa_users;
begin
  select * into a from fa_users where session_token = p_token;
  if not found then raise exception 'unauthorized'; end if;
  if a.role not in ('admin','organizer','admin-team','coach') then raise exception 'forbidden'; end if;
  update fa_state set data = p_data, updated_at = now() where id = 1;
  return true;
end; $$;

-- ---------------------------------------------------------------------
-- 5) إنشاء/تعديل مستخدم (يُستخدم عند إنشاء حساب إداري أو مدرب)
--    فقط admin أو admin-team
-- ---------------------------------------------------------------------
create or replace function fa_upsert_user(
  p_token uuid, p_id text, p_name text, p_username text, p_pin text,
  p_role text, p_team text, p_phone text, p_coach_id text
) returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare a fa_users;
begin
  select * into a from fa_users where session_token = p_token;
  if not found or a.role not in ('admin','admin-team') then raise exception 'forbidden'; end if;
  insert into fa_users (id, name, username, pin_hash, role, team, phone, coach_id)
    values (p_id, p_name, p_username, crypt(p_pin, gen_salt('bf')), p_role,
            coalesce(p_team,''), coalesce(p_phone,''), p_coach_id)
  on conflict (id) do update set
    name = excluded.name, username = excluded.username, role = excluded.role,
    team = excluded.team, phone = excluded.phone, coach_id = excluded.coach_id;
  return true;
end; $$;

-- ---------------------------------------------------------------------
-- 6) حذف مستخدم — فقط admin أو admin-team
-- ---------------------------------------------------------------------
create or replace function fa_delete_user(p_token uuid, p_id text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare a fa_users;
begin
  select * into a from fa_users where session_token = p_token;
  if not found or a.role not in ('admin','admin-team') then raise exception 'forbidden'; end if;
  delete from fa_users where id = p_id;
  return true;
end; $$;

-- ---------------------------------------------------------------------
-- 7) قائمة المستخدمين (بدون الهاش) — لعرضها في لوحة الإدارة. فقط admin
-- ---------------------------------------------------------------------
create or replace function fa_list_users(p_token uuid)
returns setof jsonb language plpgsql security definer set search_path = public, extensions as $$
declare a fa_users;
begin
  select * into a from fa_users where session_token = p_token;
  if not found or a.role <> 'admin' then raise exception 'forbidden'; end if;
  return query select jsonb_build_object(
    'id', id, 'name', name, 'username', username, 'role', role,
    'team', coalesce(team,''), 'phone', coalesce(phone,''), 'coachId', coach_id
  ) from fa_users;
end; $$;

-- ---------------------------------------------------------------------
-- 8) تهيئة أول حساب لمدير النظام (مرة واحدة فقط، يفشل لو فيه مستخدمون)
--    شغّلها بعد إنشاء الجداول، مثال في نهاية الملف
-- ---------------------------------------------------------------------
create or replace function fa_bootstrap(p_name text, p_username text, p_pin text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from fa_users) then raise exception 'already bootstrapped'; end if;
  insert into fa_users (id, name, username, pin_hash, role, team)
    values ('u1', p_name, p_username, crypt(p_pin, gen_salt('bf')), 'admin', '');
  return true;
end; $$;

-- ---------------------------------------------------------------------
-- منح صلاحية تنفيذ الدوال لعميل الواجهة (anon)
-- ---------------------------------------------------------------------
grant execute on function fa_login(text,text)                                   to anon;
grant execute on function fa_save_state(uuid,jsonb)                             to anon;
grant execute on function fa_upsert_user(uuid,text,text,text,text,text,text,text,text) to anon;
grant execute on function fa_delete_user(uuid,text)                             to anon;
grant execute on function fa_list_users(uuid)                                   to anon;
grant execute on function fa_bootstrap(text,text,text)                          to anon;

-- 9) تسجيل ذاتي (لاعب/ولي أمر/مدرب/إداري أكاديمية) باسم فريد
create or replace function fa_signup(
  p_id text, p_name text, p_username text, p_pin text,
  p_role text, p_team text, p_phone text, p_coach_id text
) returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from fa_users where username = p_username) then raise exception 'username taken'; end if;
  if p_role not in ('player','viewer','coach','admin-team') then raise exception 'role not allowed'; end if;
  insert into fa_users (id, name, username, pin_hash, role, team, phone, coach_id)
    values (p_id, p_name, p_username, crypt(p_pin, gen_salt('bf')), p_role,
            coalesce(p_team,''), coalesce(p_phone,''), p_coach_id);
  return true;
end; $$;

-- 10) تحديث بيانات مستخدم دون تغيير الرمز (admin أو admin-team)
create or replace function fa_update_profile(
  p_token uuid, p_id text, p_name text, p_username text, p_team text, p_phone text
) returns boolean language plpgsql security definer set search_path = public, extensions as $$
declare a fa_users;
begin
  select * into a from fa_users where session_token = p_token;
  if not found or a.role not in ('admin','admin-team') then raise exception 'forbidden'; end if;
  update fa_users set name = p_name, username = p_username,
         team = coalesce(p_team,''), phone = coalesce(p_phone,'') where id = p_id;
  return true;
end; $$;

grant execute on function fa_signup(text,text,text,text,text,text,text,text) to anon;
grant execute on function fa_update_profile(uuid,text,text,text,text,text)    to anon;

-- =====================================================================
--  خطوة أخيرة (مرة واحدة): أنشئ حساب مدير النظام. غيّر الاسم والرمز.
--  شغّل السطر التالي وحده بعد نجاح كل ما سبق:
--
--  select fa_bootstrap('عبدالحميد الوابل', 'عبدالحميد الوابل', '1425');
-- =====================================================================
