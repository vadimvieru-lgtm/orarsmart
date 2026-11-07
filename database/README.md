# Baza de date OrarSmart

Până acum datele (lecții, profesori, săli) erau scrise în cod și se salvau doar pe fiecare dispozitiv. Cu baza de date, **adminii introduc orarul o singură dată** și îl văd toți elevii, pe orice telefon sau calculator.

Folosim **Supabase** (bază de date PostgreSQL + conturi de utilizatori, gratuit pentru început). Nu e nevoie de server propriu.

## Ce conține

| Fișier | Rol |
|---|---|
| `database/schema.sql` | Creează toate tabelele, regulile și drepturile de acces |
| `database/seed.sql` | (opțional) Datele demo din aplicația de acum, ca să vezi cum merge |
| `src/config.js` | Aici pui adresa și cheia proiectului tău Supabase |
| `src/db.js` | Codul prin care aplicația vorbește cu baza de date |
| `src/admin.html` | **Panoul adminilor**: lecții, profesori, săli, clase, înlocuiri, conturi |

## Instalare (o singură dată, ~15 minute)

**1. Creează proiectul.** Cont gratuit pe supabase.com → *New project*. Alege o regiune din Europa (ex. Frankfurt) și notează parola bazei de date.

**2. Creează tabelele.** În proiect: *SQL Editor* → *New query* → lipește tot conținutul `database/schema.sql` → *Run*. Rulează-l o singură dată.
Vrei să vezi aplicația cu date? Repetă cu `database/seed.sql`.

**3. Creează primul administrator.**
- *Authentication* → *Users* → *Add user* → email + parolă (bifează „Auto Confirm User").
- Apoi în *SQL Editor* rulează (cu emailul tău):
  ```sql
  update public.profiles set role = 'admin' where email = 'adresa@scoala.md';
  ```

**4. Conectează aplicația.** *Project Settings* → *API*: copiază **Project URL** și cheia **anon / publishable** în `src/config.js`.
Cheia aceasta este publică prin natură. Nu pune niciodată cheia `service_role` / `secret`.

**5. Intră în panou.** Deschide `src/admin.html` în browser și intră cu contul de la pasul 3.

**6. Introdu datele, în ordinea aceasta:**
1. **Ore de apel** (de la ce oră la ce oră e fiecare lecție)
2. **Materii** · 3. **Profesori** (cu materiile predate) · 4. **Săli** · 5. **Clase**
6. **Orar**: alege clasa, apasă **+** pe o oră, alege materia, sala și **toți profesorii** lecției.

Panoul nu te lasă să faci greșeli: dacă un profesor sau o sală sunt deja ocupate la ora aceea, primești un mesaj clar și nu se salvează nimic.

**7. Recomandat:** *Authentication* → *Sign In / Providers* → dezactivează „Allow new users to sign up". Astfel conturi noi creezi doar tu. Elevii nu au nevoie de cont ca să vadă orarul.

## Cine ce poate face

| | Fără cont | Cont elev / profesor | Administrator |
|---|---|---|---|
| Vede orarul, profesorii, înlocuirile, notificările | da | da | da |
| Modifică orarul, înlocuiește, trimite anunțuri | nu | nu | **da** |
| Vede conturile și le schimbă rolul | nu | doar pe al lui | **da** |

Rolul se schimbă din panou (fila **Conturi**) sau în SQL. Un utilizator nu își poate da singur drept de administrator, iar regulile sunt aplicate chiar în baza de date, nu doar în aplicație.

Dacă vrei ca orarul să se vadă **doar celor cu cont**, în `schema.sql` (secțiunea 5) schimbă `to anon, authenticated` în `to authenticated` înainte de a o rula.

## Cum e organizată baza de date

- `subjects`, `teachers`, `teacher_subjects`, `rooms`, `classes`, `bell_slots`: datele de bază
- `lessons` + `lesson_teachers`: orarul. O lecție poate avea **mai mulți profesori**; pentru clase împărțite pe grupe, câte o lecție pe grupă
- `substitutions`: înlocuirile pe o dată anume. La confirmare sau anulare, baza de date creează singură notificarea din `notifications`
- `profiles`: roluri (elev / profesor / admin)
- Funcții gata făcute: `class_day(clasa, data)` (orarul unei zile, cu înlocuiri), `free_teachers(data, ora, materie)` (profesori liberi, cei de la materia respectivă primii), `save_lesson(...)` (lecție + profesori într-un singur pas)

Reguli aplicate automat: o clasă nu are două lecții la aceeași oră (decât pe grupe diferite), o sală nu e rezervată de două ori, un profesor nu e în două locuri odată, iar un înlocuitor trebuie să fie liber.

## Nu e încă făcut: ecranele pentru elevi

`src/index.html` (aplicația pentru elevi) încă folosește datele scrise în cod. Pasul următor este să o conectăm la baza de date cu `db.js`, astfel încât orarul, înlocuirile și notificările să vină de acolo:

```js
const ref = await OrarDB.loadReference();                      // materii, profesori, săli, clase, ore
const zi  = await OrarDB.classDay(clasaId, "2026-11-09");      // orarul unei zile, cu înlocuiri
const nt  = await OrarDB.notifications(clasaId);               // notificările clasei
OrarDB.poll(() => { /* reîncarcă */ }, 30000);                 // actualizare la 30 de secunde
```

## De știut

- Pe planul gratuit Supabase, proiectele rămase mult timp fără activitate pot fi puse pe pauză. Verifică condițiile actuale pe supabase.com/pricing înainte de lansare.
- Fă periodic o copie de siguranță (*Database* → *Backups*).
- `schema.sql` se rulează o singură dată pe un proiect gol. Pentru modificări ulterioare se scriu scripturi separate.
