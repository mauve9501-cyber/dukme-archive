-- =====================================================================
--  덕메 아카이브 — Supabase 스키마 / 권한(RLS) / 스토리지
--  SQL Editor 에 붙여넣고 [Run] 한 번. 여러 번 실행해도 안전(idempotent).
--  다른 앱과 한 프로젝트를 공유하므로 모든 객체에 dm_ 접두어를 씁니다.
--  "우리만" 보장: dm_members 에 등록된 이메일만 읽기·쓰기 가능.
--  멤버는 앱 안에서 덕메를 초대(이메일 등록)할 수 있습니다.
-- =====================================================================

-- 0) 멤버 -------------------------------------------------------------
create table if not exists public.dm_members (
  email      text primary key,
  label      text,
  invited_by text,
  created_at timestamptz default now()
);

insert into public.dm_members (email, label) values
  ('mauve9501@gmail.com', '미영')
on conflict (email) do nothing;

create or replace function public.dm_is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.dm_members m
                 where m.email = lower(auth.jwt() ->> 'email'));
$$;

-- 로그인 전, 초대된 이메일인지 확인(모르는 사람에게 메일이 가지 않도록)
create or replace function public.dm_can_login(p_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.dm_members where email = lower(trim(p_email)));
$$;
grant execute on function public.dm_can_login(text) to anon, authenticated;

-- 1) 공연 --------------------------------------------------------------
create table if not exists public.dm_concerts (
  id          uuid primary key default gen_random_uuid(),
  no          int,
  title_en    text,
  title_kr    text,
  date        date,
  venue       text,
  city        text,
  seat        text,
  run_time    text,
  setlist     text[] default '{}',
  memo        text,
  cover_hue   text default 'dusk',
  cover_path  text,
  created_at  timestamptz default now(),
  created_by  text default lower(auth.jwt() ->> 'email')
);
alter table public.dm_concerts add column if not exists memo text;
alter table public.dm_concerts add column if not exists cover_path text;

-- 2) 사진 --------------------------------------------------------------
create table if not exists public.dm_photos (
  id           uuid primary key default gen_random_uuid(),
  concert_id   uuid references public.dm_concerts(id) on delete cascade,
  storage_path text not null,
  caption      text,
  starred      boolean default false,
  taken_by     text,
  width        int,
  height       int,
  sort         int default 0,
  created_at   timestamptz default now(),
  uploaded_by  text default lower(auth.jwt() ->> 'email')
);

-- 3) 코멘트 ------------------------------------------------------------
create table if not exists public.dm_comments (
  id           uuid primary key default gen_random_uuid(),
  photo_id     uuid references public.dm_photos(id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 1000),
  author_email text default lower(auth.jwt() ->> 'email'),
  created_at   timestamptz default now()
);

create index if not exists dm_idx_photos_concert on public.dm_photos(concert_id);
create index if not exists dm_idx_comments_photo on public.dm_comments(photo_id);

-- 4) RLS ---------------------------------------------------------------
alter table public.dm_members  enable row level security;
alter table public.dm_concerts enable row level security;
alter table public.dm_photos   enable row level security;
alter table public.dm_comments enable row level security;

drop policy if exists "dm members read"   on public.dm_members;
drop policy if exists "dm members invite" on public.dm_members;
drop policy if exists "dm members update" on public.dm_members;
drop policy if exists "dm members remove" on public.dm_members;
create policy "dm members read"   on public.dm_members for select using (public.dm_is_member());
create policy "dm members invite" on public.dm_members for insert with check (public.dm_is_member() and email = lower(email));
create policy "dm members update" on public.dm_members for update using (public.dm_is_member()) with check (email = lower(email));
-- 자기 자신은 지울 수 없음(마지막 멤버가 잠겨버리는 사고 방지)
create policy "dm members remove" on public.dm_members for delete
  using (public.dm_is_member() and email <> lower(auth.jwt() ->> 'email'));

drop policy if exists "dm all concerts" on public.dm_concerts;
drop policy if exists "dm all photos"   on public.dm_photos;
create policy "dm all concerts" on public.dm_concerts for all using (public.dm_is_member()) with check (public.dm_is_member());
create policy "dm all photos"   on public.dm_photos   for all using (public.dm_is_member()) with check (public.dm_is_member());

-- 코멘트: 읽기·쓰기는 멤버, 삭제는 본인 것만
drop policy if exists "dm read comments"   on public.dm_comments;
drop policy if exists "dm write comments"  on public.dm_comments;
drop policy if exists "dm delete comments" on public.dm_comments;
create policy "dm read comments"   on public.dm_comments for select using (public.dm_is_member());
create policy "dm write comments"  on public.dm_comments for insert
  with check (public.dm_is_member() and author_email = lower(auth.jwt() ->> 'email'));
create policy "dm delete comments" on public.dm_comments for delete
  using (public.dm_is_member() and author_email = lower(auth.jwt() ->> 'email'));

-- 5) 스토리지 (비공개 버킷) --------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('dukme-photos', 'dukme-photos', false, 20971520,
        array['image/webp','image/jpeg','image/png','image/gif','image/heic','image/heif'])
on conflict (id) do update set public = false,
  file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "dm read photos"   on storage.objects;
drop policy if exists "dm write photos"  on storage.objects;
drop policy if exists "dm update photos" on storage.objects;
drop policy if exists "dm delete photos" on storage.objects;
create policy "dm read photos"   on storage.objects for select using (bucket_id = 'dukme-photos' and public.dm_is_member());
create policy "dm write photos"  on storage.objects for insert with check (bucket_id = 'dukme-photos' and public.dm_is_member());
create policy "dm update photos" on storage.objects for update using (bucket_id = 'dukme-photos' and public.dm_is_member());
create policy "dm delete photos" on storage.objects for delete using (bucket_id = 'dukme-photos' and public.dm_is_member());

-- 6) 실시간 코멘트 --------------------------------------------------------
do $$ begin
  alter publication supabase_realtime add table public.dm_comments;
exception when duplicate_object then null; when undefined_object then null; end $$;

-- 7) keepalive 용 공개 핑 (데이터 노출 없음) ------------------------------
create or replace function public.dm_ping() returns text language sql stable as $$ select 'ok' $$;
grant execute on function public.dm_ping() to anon;
