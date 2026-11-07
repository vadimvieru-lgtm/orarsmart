-- =====================================================================
--  OrarSmart — date DEMO (aceleași date care erau scrise în cod în src/index.html)
--  Rulează după schema.sql, doar ca să vezi aplicația funcționând.
--  Când ești gata să introduci datele reale, șterge-le cu:
--     truncate public.lessons, public.classes, public.teachers, public.subjects,
--              public.rooms, public.bell_slots restart identity cascade;
-- =====================================================================

begin;

insert into public.subjects (code, name, color) values
  ('mat', 'Matematică', '#3B82F6'),
  ('info', 'Informatică', '#0EA5A4'),
  ('fiz', 'Fizică', '#8B5CF6'),
  ('rom', 'Limba română', '#EC4899'),
  ('ist', 'Istorie', '#D97706'),
  ('eng', 'Engleză', '#16A34A');

insert into public.teachers (last_name) values
  ('Cojocaru'),
  ('Rusu'),
  ('Munteanu'),
  ('Ceban'),
  ('Lungu'),
  ('Moraru'),
  ('Țurcan'),
  ('Bejan'),
  ('Gîscă'),
  ('Popa'),
  ('Sandu'),
  ('Vrabie');

insert into public.teacher_subjects (teacher_id, subject_id)
select t.id, s.id from (values
  ('Cojocaru', 'mat'),
  ('Rusu', 'info'),
  ('Munteanu', 'fiz'),
  ('Ceban', 'rom'),
  ('Lungu', 'ist'),
  ('Moraru', 'eng'),
  ('Țurcan', 'fiz'),
  ('Bejan', 'mat'),
  ('Gîscă', 'info'),
  ('Popa', 'rom'),
  ('Sandu', 'eng'),
  ('Vrabie', 'ist')
) v(last_name, code)
join public.teachers t on t.last_name = v.last_name
join public.subjects s on s.code = v.code;

insert into public.rooms (name) values
  ('Sala 5'),
  ('Sala 8'),
  ('Sala 14'),
  ('Sala 22'),
  ('Sala 31'),
  ('Laborator 3');

insert into public.bell_slots (period, starts_at, ends_at) values
  (1, '08:00', '08:45'),
  (2, '08:55', '09:40'),
  (3, '09:50', '10:35'),
  (4, '10:55', '11:40'),
  (5, '11:50', '12:35');

insert into public.classes (grade, letter) values (10, 'B'), (10, 'A');

with v(letter, day_of_week, period, code, teacher, room) as (values
  ('B', 1, 1, 'mat', 'Cojocaru', 'Sala 14'),
  ('B', 1, 2, 'info', 'Rusu', 'Laborator 3'),
  ('B', 1, 3, 'fiz', 'Munteanu', 'Sala 22'),
  ('B', 1, 4, 'rom', 'Ceban', 'Sala 8'),
  ('B', 1, 5, 'eng', 'Moraru', 'Sala 31'),
  ('B', 2, 1, 'rom', 'Ceban', 'Sala 8'),
  ('B', 2, 2, 'mat', 'Cojocaru', 'Sala 14'),
  ('B', 2, 3, 'ist', 'Lungu', 'Sala 5'),
  ('B', 2, 4, 'fiz', 'Munteanu', 'Sala 22'),
  ('B', 2, 5, 'info', 'Rusu', 'Laborator 3'),
  ('B', 3, 1, 'eng', 'Moraru', 'Sala 31'),
  ('B', 3, 2, 'fiz', 'Munteanu', 'Sala 22'),
  ('B', 3, 3, 'mat', 'Cojocaru', 'Sala 14'),
  ('B', 3, 4, 'info', 'Rusu', 'Laborator 3'),
  ('B', 3, 5, 'ist', 'Lungu', 'Sala 5'),
  ('B', 4, 1, 'mat', 'Cojocaru', 'Sala 14'),
  ('B', 4, 2, 'rom', 'Ceban', 'Sala 8'),
  ('B', 4, 3, 'info', 'Rusu', 'Laborator 3'),
  ('B', 4, 4, 'eng', 'Moraru', 'Sala 31'),
  ('B', 4, 5, 'fiz', 'Munteanu', 'Sala 22'),
  ('B', 5, 1, 'ist', 'Lungu', 'Sala 5'),
  ('B', 5, 2, 'mat', 'Cojocaru', 'Sala 14'),
  ('B', 5, 3, 'fiz', 'Munteanu', 'Sala 22'),
  ('B', 5, 4, 'rom', 'Ceban', 'Sala 8'),
  ('A', 1, 4, 'fiz', 'Țurcan', 'Sala 5'),
  ('A', 2, 4, 'fiz', 'Țurcan', 'Sala 5'),
  ('A', 3, 5, 'fiz', 'Țurcan', 'Sala 8'),
  ('A', 1, 3, 'mat', 'Bejan', 'Sala 5'),
  ('A', 4, 2, 'mat', 'Bejan', 'Sala 5'),
  ('A', 2, 5, 'info', 'Gîscă', 'Sala 5'),
  ('A', 3, 1, 'eng', 'Sandu', 'Sala 5'),
  ('A', 1, 1, 'ist', 'Vrabie', 'Sala 5')
), new_lessons as (
  insert into public.lessons (class_id, subject_id, day_of_week, period, room_id)
  select c.id, s.id, v.day_of_week, v.period, r.id
    from v
    join public.classes  c on c.grade = 10 and c.letter = v.letter
    join public.subjects s on s.code = v.code
    join public.rooms    r on r.name = v.room
  returning id, class_id, day_of_week, period
)
insert into public.lesson_teachers (lesson_id, teacher_id)
select nl.id, t.id
  from v
  join public.classes c on c.grade = 10 and c.letter = v.letter
  join new_lessons nl on nl.class_id = c.id and nl.day_of_week = v.day_of_week and nl.period = v.period
  join public.teachers t on t.last_name = v.teacher;

commit;
