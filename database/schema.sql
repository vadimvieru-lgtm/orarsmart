-- =====================================================================
--  OrarSmart — schema bazei de date (PostgreSQL / Supabase)
--
--  Cum se folosește:
--    Supabase → SQL Editor → New query → lipești tot fișierul → Run.
--    Rulează-l O SINGURĂ DATĂ, pe un proiect nou.
--  După aceea (opțional) rulează și database/seed.sql pentru date demo.
--
--  Ce conține:
--    1. Datele de bază:  materii, profesori, săli, clase, orele de apel
--    2. Orarul:          lecții + profesorii fiecărei lecții
--    3. Înlocuiri:       profesor absent → înlocuitor, cu notificări automate
--    4. Conturi:         roluri elev / profesor / admin
--    5. Securitate:      toți CITESC orarul, doar adminii îl MODIFICĂ
--    6. Funcții:         orarul unei zile, profesori liberi, salvare lecție
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. DATE DE BAZĂ
-- ---------------------------------------------------------------------

create table public.subjects (               -- materii
  id    bigint generated always as identity primary key,
  code  text not null unique check (code ~ '^[a-z0-9_]+$'),   -- ex: mat, info, fiz
  name  text not null unique,                                  -- ex: Matematică
  color text not null default '#4338CA' check (color ~ '^#[0-9A-Fa-f]{6}$')
);

create table public.teachers (               -- profesori
  id           bigint generated always as identity primary key,
  last_name    text not null,
  first_name   text not null default '',
  display_name text,                          -- cum apare în aplicație; implicit „Prof. Nume"
  active       boolean not null default true, -- false = nu mai apare ca înlocuitor
  unique (last_name, first_name)
);

create function public.teachers_set_display_name() returns trigger
language plpgsql as $$
begin
  if coalesce(btrim(new.display_name), '') = '' then
    new.display_name := 'Prof. ' || new.last_name;
  end if;
  return new;
end $$;

create trigger teachers_display_name
  before insert or update on public.teachers
  for each row execute function public.teachers_set_display_name();

create table public.teacher_subjects (       -- ce materii predă fiecare profesor
  teacher_id bigint not null references public.teachers(id) on delete cascade,
  subject_id bigint not null references public.subjects(id) on delete cascade,
  primary key (teacher_id, subject_id)
);

create table public.rooms (                  -- săli
  id       bigint generated always as identity primary key,
  name     text not null unique,              -- ex: Sala 14, Laborator 3
  capacity integer check (capacity > 0)
);

create table public.classes (                -- clase
  id                  bigint generated always as identity primary key,
  grade               smallint not null check (grade between 1 and 12),
  letter              text not null check (char_length(letter) between 1 and 3),
  homeroom_teacher_id bigint references public.teachers(id) on delete set null,  -- diriginte
  short_name          text generated always as (grade::text || letter) stored,   -- 10B
  display_name        text generated always as ('Clasa a ' || grade::text || '-a ' || letter) stored,
  unique (grade, letter)
);

create table public.bell_slots (             -- orele de apel (câte ore pe zi, de la ce oră la ce oră)
  period    smallint primary key check (period between 1 and 12),
  starts_at time not null,
  ends_at   time not null,
  check (ends_at > starts_at)
);
comment on table public.bell_slots is
  'Dacă școala lucrează în două schimburi, numerotați orele schimbului 2 de la 7 în sus (7, 8, 9...). '
  'Așa nicio regulă de mai jos nu se încurcă între schimburi.';


-- ---------------------------------------------------------------------
-- 2. ORARUL
--    O lecție = o clasă, într-o zi, la o oră, cu o materie, într-o sală.
--    Profesorii unei lecții sunt în tabelul lesson_teachers (pot fi mai mulți).
--    Pentru clase împărțite pe grupe: câte o lecție pe grupă (group_name).
-- ---------------------------------------------------------------------

create table public.lessons (
  id          bigint generated always as identity primary key,
  class_id    bigint   not null references public.classes(id)  on delete cascade,
  subject_id  bigint   not null references public.subjects(id) on delete restrict,
  day_of_week smallint not null check (day_of_week between 1 and 6),   -- 1 = luni ... 5 = vineri
  period      smallint not null references public.bell_slots(period) on update cascade on delete restrict,
  room_id     bigint   references public.rooms(id) on delete set null,
  group_name  text     not null default '',                            -- '' = toată clasa
  created_at  timestamptz not null default now(),
  constraint lessons_class_slot_key unique (class_id, day_of_week, period, group_name),
  constraint lessons_room_slot_key  unique (room_id,  day_of_week, period),
  constraint lessons_id_slot_key    unique (id, day_of_week, period)
);
create index lessons_class_idx on public.lessons (class_id, day_of_week, period);

create table public.lesson_teachers (        -- profesorii fiecărei lecții
  lesson_id   bigint   not null,
  teacher_id  bigint   not null references public.teachers(id) on delete restrict,
  day_of_week smallint not null,              -- copiate automat din lecție (vezi trigger);
  period      smallint not null,              -- servesc ca să nu fie un profesor în 2 locuri odată
  primary key (lesson_id, teacher_id),
  constraint lesson_teachers_lesson_fk
    foreign key (lesson_id, day_of_week, period)
    references public.lessons (id, day_of_week, period) on delete cascade on update cascade,
  constraint lesson_teachers_teacher_slot_key unique (teacher_id, day_of_week, period)
);

create function public.lesson_teachers_fill_slot() returns trigger
language plpgsql as $$
begin
  select l.day_of_week, l.period into new.day_of_week, new.period
    from public.lessons l where l.id = new.lesson_id;
  return new;
end $$;

create trigger lesson_teachers_fill
  before insert or update of lesson_id on public.lesson_teachers
  for each row execute function public.lesson_teachers_fill_slot();


-- ---------------------------------------------------------------------
-- 3. ÎNLOCUIRI ȘI NOTIFICĂRI
-- ---------------------------------------------------------------------

create table public.substitutions (          -- o înlocuire într-o anumită dată
  id                    bigint generated always as identity primary key,
  lesson_id             bigint not null,
  lesson_date           date   not null,
  absent_teacher_id     bigint not null,
  substitute_teacher_id bigint not null references public.teachers(id) on delete restrict,
  room_id               bigint references public.rooms(id) on delete set null,  -- null = aceeași sală
  reason                text   not null default 'Alt motiv',
  created_by            uuid   default auth.uid() references auth.users(id) on delete set null,
  created_at            timestamptz not null default now(),
  constraint substitutions_absent_fk
    foreign key (lesson_id, absent_teacher_id)
    references public.lesson_teachers (lesson_id, teacher_id) on delete cascade,
  constraint substitutions_once_key unique (lesson_id, lesson_date, absent_teacher_id),
  constraint substitutions_different_teacher check (absent_teacher_id <> substitute_teacher_id)
);
create index substitutions_date_idx on public.substitutions (lesson_date);

create table public.notifications (          -- notificările văzute de elevi
  id         bigint generated always as identity primary key,
  class_id   bigint references public.classes(id) on delete cascade,   -- null = pentru toată școala
  kind       text not null default 'anunt' check (kind in ('inlocuire', 'revenire', 'anunt')),
  body       text not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index notifications_idx on public.notifications (class_id, created_at desc);

-- Verifică o înlocuire: data trebuie să cadă în ziua lecției, iar înlocuitorul să fie liber.
create function public.substitutions_validate() returns trigger
language plpgsql as $$
declare
  l record;
begin
  if new.absent_teacher_id = new.substitute_teacher_id then
    raise exception 'Profesorul nu se poate înlocui pe sine.';
  end if;

  select day_of_week, period into l from public.lessons where id = new.lesson_id;

  if extract(isodow from new.lesson_date)::int <> l.day_of_week then
    raise exception 'Data % nu cade în ziua în care are loc lecția.', to_char(new.lesson_date, 'DD.MM.YYYY');
  end if;

  if exists (
    select 1 from public.lesson_teachers lt
     where lt.teacher_id = new.substitute_teacher_id
       and lt.day_of_week = l.day_of_week and lt.period = l.period
       and not exists (                      -- ...decât dacă e și el înlocuit atunci
         select 1 from public.substitutions s
          where s.lesson_id = lt.lesson_id and s.lesson_date = new.lesson_date
            and s.absent_teacher_id = lt.teacher_id and s.id is distinct from new.id)
  ) then
    raise exception 'Profesorul ales are deja o lecție la ora % în această zi.', l.period;
  end if;

  if exists (
    select 1 from public.substitutions s
      join public.lessons l2 on l2.id = s.lesson_id
     where s.substitute_teacher_id = new.substitute_teacher_id
       and s.lesson_date = new.lesson_date and l2.period = l.period
       and s.id is distinct from new.id
  ) then
    raise exception 'Profesorul ales înlocuiește deja la altă lecție la ora %.', l.period;
  end if;

  return new;
end $$;

create trigger substitutions_validate
  before insert or update on public.substitutions
  for each row execute function public.substitutions_validate();

-- Creează automat notificarea când adminul confirmă / anulează o înlocuire.
create function public.substitutions_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r        record;
  zile     text[] := array['Luni','Marți','Miercuri','Joi','Vineri','Sâmbătă','Duminică'];
  luni     text[] := array['ianuarie','februarie','martie','aprilie','mai','iunie','iulie',
                           'august','septembrie','octombrie','noiembrie','decembrie'];
  v_date   date;
  v_row    public.substitutions;
  v_prefix text;
begin
  v_row := case when tg_op = 'DELETE' then old else new end;
  v_date := v_row.lesson_date;

  -- La ștergere NU notificăm dacă:
  --  • înlocuirea e într-o zi trecută, sau
  --  • a dispărut în cascadă (profesorul a fost scos din lecție / lecția a fost ștearsă):
  --    în cazul acela legătura profesor–lecție nu mai există.
  if tg_op = 'DELETE' and (
       v_date < current_date
       or not exists (select 1 from public.lesson_teachers lt
                       where lt.lesson_id = old.lesson_id and lt.teacher_id = old.absent_teacher_id)
     ) then
    return old;
  end if;

  select l.class_id, l.period, sj.name as subject, ab.display_name as absent,
         sb.display_name as substitute, coalesce(rm.name, ol.name) as room_name
    into r
    from public.lessons l
    join public.subjects sj on sj.id = l.subject_id
    join public.teachers ab on ab.id = v_row.absent_teacher_id
    join public.teachers sb on sb.id = v_row.substitute_teacher_id
    left join public.rooms ol on ol.id = l.room_id
    left join public.rooms rm on rm.id = v_row.room_id
   where l.id = v_row.lesson_id;

  if not found then return coalesce(new, old); end if;

  v_prefix := zile[extract(isodow from v_date)::int] || ', ' || extract(day from v_date)::int
              || ' ' || luni[extract(month from v_date)::int] || ' · Ora ' || r.period
              || ', ' || r.subject || ': ';

  if tg_op = 'DELETE' then
    insert into public.notifications (class_id, kind, body)
    values (r.class_id, 'revenire', v_prefix || 'revine la orarul inițial (' || r.absent || ').');
    return old;
  end if;

  insert into public.notifications (class_id, kind, body)
  values (r.class_id, 'inlocuire',
          v_prefix || r.substitute || ' în loc de ' || r.absent
          || case when v_row.room_id is not null then ', ' || r.room_name else '' end || '.');
  return new;
end $$;

create trigger substitutions_notify
  after insert or update or delete on public.substitutions
  for each row execute function public.substitutions_notify();


-- ---------------------------------------------------------------------
-- 4. CONTURI ȘI ROLURI
--    Conturile le gestionează Supabase Auth (email + parolă).
--    Fiecare cont nou primește automat un profil cu rolul „elev".
--    Primul administrator se face manual (vezi database/README.md).
-- ---------------------------------------------------------------------

create table public.profiles (
  id                    uuid primary key references auth.users(id) on delete cascade,
  email                 text,                       -- copiat la înregistrare, ca adminul să recunoască conturile
  full_name             text,
  role                  text not null default 'elev' check (role in ('elev', 'profesor', 'admin')),
  class_id              bigint references public.classes(id)  on delete set null,
  teacher_id            bigint references public.teachers(id) on delete set null,
  notifications_seen_at timestamptz not null default now(),
  created_at            timestamptz not null default now()
);

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Un utilizator își poate schimba numele și clasa, dar NU rolul sau legătura cu un profesor.
create function public.profiles_protect() returns trigger
language plpgsql as $$
begin
  if (new.role, new.teacher_id, new.id) is distinct from (old.role, old.teacher_id, old.id)
     and auth.uid() is not null and not public.is_admin() then
    raise exception 'Doar un administrator poate schimba rolul unui cont.' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger profiles_protect
  before update on public.profiles
  for each row execute function public.profiles_protect();


-- ---------------------------------------------------------------------
-- 5. SECURITATE (Row Level Security)
--    • Orarul, profesorii, înlocuirile, notificările: le poate CITI oricine
--      (elevii nu trebuie să-și facă cont ca să vadă orarul).
--      Dacă vrei orar doar pentru cei logați, în bucla de mai jos schimbă
--      „to anon, authenticated" în „to authenticated".
--    • Orice MODIFICARE (adăugare, editare, ștergere): doar admin.
--    • Profilurile: fiecare vede doar profilul lui; adminii le văd pe toate.
-- ---------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['subjects','teachers','teacher_subjects','rooms','classes',
                           'bell_slots','lessons','lesson_teachers','substitutions','notifications']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy public_read on public.%I for select to anon, authenticated using (true)', t);
    execute format('create policy admin_write on public.%I for all to authenticated
                      using (public.is_admin()) with check (public.is_admin())', t);
    execute format('grant select on public.%I to anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

alter table public.profiles enable row level security;
create policy own_read    on public.profiles for select to authenticated using (id = auth.uid());
create policy own_update  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());
create policy admin_all   on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select, update on public.profiles to authenticated;
grant delete on public.profiles to authenticated;   -- doar adminii (politica admin_all)

grant usage on schema public to anon, authenticated;


-- ---------------------------------------------------------------------
-- 6. VEDERI ȘI FUNCȚII PENTRU APLICAȚIE
-- ---------------------------------------------------------------------

-- Orarul complet, o linie pe lecție, cu profesorii într-o listă JSON.
create view public.v_timetable with (security_invoker = true) as
select l.id as lesson_id, l.class_id, c.short_name as class_name,
       l.day_of_week, l.period, b.starts_at, b.ends_at,
       s.id as subject_id, s.code as subject_code, s.name as subject_name, s.color,
       l.group_name, r.id as room_id, r.name as room_name,
       coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.display_name)
                          order by t.display_name) filter (where t.id is not null),
                '[]'::jsonb) as teachers
  from public.lessons l
  join public.classes   c on c.id = l.class_id
  join public.subjects  s on s.id = l.subject_id
  join public.bell_slots b on b.period = l.period
  left join public.rooms r on r.id = l.room_id
  left join public.lesson_teachers lt on lt.lesson_id = l.id
  left join public.teachers t on t.id = lt.teacher_id
 group by l.id, c.id, s.id, b.period, r.id;

grant select on public.v_timetable to anon, authenticated;

-- Orarul unei clase într-o zi anume, ținând cont de înlocuiri.
create function public.class_day(p_class_id bigint, p_date date)
returns table (
  lesson_id bigint, period smallint, starts_at time, ends_at time,
  subject_code text, subject_name text, color text, group_name text,
  teachers text, original_teachers text, room text, original_room text,
  substituted boolean, reason text
)
language sql stable set search_path = public as $$
  select l.id, l.period, b.starts_at, b.ends_at, sj.code, sj.name, sj.color, l.group_name,
         (select string_agg(coalesce(st.display_name, t.display_name), ', ' order by t.display_name)
            from lesson_teachers lt
            join teachers t on t.id = lt.teacher_id
            left join substitutions sb on sb.lesson_id = lt.lesson_id
                 and sb.lesson_date = p_date and sb.absent_teacher_id = lt.teacher_id
            left join teachers st on st.id = sb.substitute_teacher_id
           where lt.lesson_id = l.id),
         (select string_agg(t.display_name, ', ' order by t.display_name)
            from lesson_teachers lt join teachers t on t.id = lt.teacher_id
           where lt.lesson_id = l.id),
         coalesce(
           (select rr.name from substitutions sb join rooms rr on rr.id = sb.room_id
             where sb.lesson_id = l.id and sb.lesson_date = p_date limit 1),
           r.name),
         r.name,
         exists (select 1 from substitutions sb where sb.lesson_id = l.id and sb.lesson_date = p_date),
         (select string_agg(distinct sb.reason, '; ') from substitutions sb
           where sb.lesson_id = l.id and sb.lesson_date = p_date)
    from lessons l
    join subjects sj on sj.id = l.subject_id
    join bell_slots b on b.period = l.period
    left join rooms r on r.id = l.room_id
   where l.class_id = p_class_id
     and l.day_of_week = extract(isodow from p_date)::int
   order by l.period, l.group_name;
$$;

-- Profesorii liberi la o oră dintr-o dată (cei care predau materia respectivă primii).
create function public.free_teachers(p_date date, p_period smallint, p_subject_id bigint default null)
returns table (teacher_id bigint, display_name text, teaches_subject boolean)
language sql stable set search_path = public as $$
  select t.id, t.display_name,
         exists (select 1 from teacher_subjects ts
                  where ts.teacher_id = t.id and ts.subject_id = p_subject_id)
    from teachers t
   where t.active
     -- nu are lecție la ora aceea
     and not exists (select 1 from lesson_teachers lt
                      where lt.teacher_id = t.id
                        and lt.day_of_week = extract(isodow from p_date)::int
                        and lt.period = p_period)
     -- nu înlocuiește deja în altă parte la ora aceea
     and not exists (select 1 from substitutions s join lessons l on l.id = s.lesson_id
                      where s.substitute_teacher_id = t.id and s.lesson_date = p_date
                        and l.period = p_period)
     -- nu este absent în ziua aceea
     and not exists (select 1 from substitutions s
                      where s.absent_teacher_id = t.id and s.lesson_date = p_date)
   order by 3 desc, 2;
$$;

-- Adaugă sau modifică o lecție împreună cu TOȚI profesorii ei, într-un singur pas.
-- p_id null = lecție nouă; p_id completat = modifică lecția existentă.
create function public.save_lesson(
  p_class_id bigint, p_subject_id bigint, p_day smallint, p_period smallint,
  p_room_id bigint default null, p_group text default '',
  p_teacher_ids bigint[] default '{}', p_id bigint default null
) returns bigint
language plpgsql set search_path = public as $$
declare
  v_id bigint;
  v_teachers bigint[] := coalesce(p_teacher_ids, '{}');
begin
  if not public.is_admin() then
    raise exception 'Doar administratorii pot modifica orarul.' using errcode = '42501';
  end if;

  if p_id is null then
    insert into lessons (class_id, subject_id, day_of_week, period, room_id, group_name)
    values (p_class_id, p_subject_id, p_day, p_period, p_room_id, coalesce(p_group, ''))
    returning id into v_id;
  else
    update lessons
       set class_id = p_class_id, subject_id = p_subject_id, day_of_week = p_day,
           period = p_period, room_id = p_room_id, group_name = coalesce(p_group, '')
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'Lecția % nu există.', p_id;
    end if;
  end if;

  delete from lesson_teachers where lesson_id = v_id and teacher_id <> all (v_teachers);

  insert into lesson_teachers (lesson_id, teacher_id)
  select v_id, x from (select distinct unnest(v_teachers) as x) u
  on conflict (lesson_id, teacher_id) do nothing;

  return v_id;
end $$;

grant execute on function public.class_day(bigint, date)                    to anon, authenticated;
grant execute on function public.free_teachers(date, smallint, bigint)      to anon, authenticated;
grant execute on function public.save_lesson(bigint, bigint, smallint, smallint, bigint, text, bigint[], bigint)
  to authenticated;


-- ---------------------------------------------------------------------
-- 7. ACTUALIZĂRI ÎN TIMP REAL (doar Supabase)
--    Elevii văd înlocuirile imediat, fără să redeschidă aplicația.
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime
      add table public.substitutions, public.notifications, public.lessons, public.lesson_teachers;
  end if;
end $$;
