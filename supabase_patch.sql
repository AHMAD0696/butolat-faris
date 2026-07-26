-- =====================================================================
--  تحديث إضافي — شغّله مرة واحدة في SQL Editor بعد السكيمة الأساسية
--  يضيف: التسجيل الذاتي (fa_signup) وتحديث بيانات المستخدم بدون تغيير الرمز
--  (fa_update_profile)، ويثبّت مسار pgcrypto للدوال التي تستخدم التجزئة.
-- =====================================================================

-- تثبيت مسار البحث لدوال التجزئة (crypt/gen_salt في سكيمة extensions)
alter function fa_login(text,text)                                     set search_path = public, extensions;
alter function fa_bootstrap(text,text,text)                            set search_path = public, extensions;
alter function fa_upsert_user(uuid,text,text,text,text,text,text,text,text) set search_path = public, extensions;

-- تسجيل ذاتي: أي شخص ينشئ حساب لاعب/ولي أمر/مدرب/إداري أكاديمية (باسم فريد)
create or replace function fa_signup(
  p_id text, p_name text, p_username text, p_pin text,
  p_role text, p_team text, p_phone text, p_coach_id text
) returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (select 1 from fa_users where username = p_username) then
    raise exception 'username taken';
  end if;
  if p_role not in ('player','viewer','coach','admin-team') then
    raise exception 'role not allowed';
  end if;
  insert into fa_users (id, name, username, pin_hash, role, team, phone, coach_id)
    values (p_id, p_name, p_username, crypt(p_pin, gen_salt('bf')), p_role,
            coalesce(p_team,''), coalesce(p_phone,''), p_coach_id);
  return true;
end; $$;

-- تحديث اسم/جوال/فريق مستخدم دون المساس بالرمز السري (admin أو admin-team)
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
