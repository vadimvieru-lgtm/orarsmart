/* OrarSmart — acces la baza de date (Supabase), fără dependențe externe.
 *
 * Se încarcă în pagină după config.js (două taguri script, în această ordine:
 * întâi config.js, apoi db.js), iar apoi se folosește ca  OrarDB.loadTimetable(1)  etc.
 *
 * Toate funcțiile întorc Promise și aruncă Error cu mesaj în română,
 * gata de afișat utilizatorului (ex: „Sala este deja ocupată la această oră.").
 */
(function () {
  "use strict";

  const cfg = window.ORARSMART_CONFIG || {};
  const URL_ = String(cfg.SUPABASE_URL || "").replace(/\/+$/, "");
  const KEY = cfg.SUPABASE_ANON_KEY || "";
  const SESSION_KEY = "orarsmart-session";

  const configured = () => /^https:\/\/.+/.test(URL_) && !/XXXX/.test(URL_) && KEY && !/PUNE-AICI/.test(KEY);

  /* ---------- mesaje de eroare prietenoase ---------- */
  const RULES = [
    [/lessons_class_slot_key/, 'Clasa are deja o lecție la această oră. Pentru lecții pe grupe completează câmpul „Grupa".'],
    [/lessons_room_slot_key/, "Sala este deja ocupată la această oră."],
    [/lesson_teachers_teacher_slot_key/, "Unul dintre profesori are deja o lecție la această oră."],
    [/substitutions_once_key/, "Pentru această lecție există deja o înlocuire în ziua aleasă."],
    [/teachers_last_name_first_name_key/, "Există deja un profesor cu acest nume."],
    [/subjects_(code|name)_key/, "Există deja o materie cu acest cod sau nume."],
    [/rooms_name_key/, "Există deja o sală cu acest nume."],
    [/classes_grade_letter_key/, "Această clasă există deja."],
    [/bell_slots_pkey/, "Această oră de apel există deja."],
    [/update or delete on table/, "Nu se poate șterge: elementul este folosit în orar sau în alte înregistrări."],
    [/row-level security|permission denied/, "Nu ai dreptul să faci această modificare. Intră cu un cont de administrator."],
    [/Invalid login credentials/i, "Email sau parolă greșită."],
    [/Email not confirmed/i, "Contul nu a fost confirmat prin email."],
    [/JWT expired|invalid JWT/i, "Sesiunea a expirat. Intră din nou în cont."]
  ];
  function friendly(raw) {
    const text = [raw && raw.message, raw && raw.details, raw && raw.msg, raw && raw.error_description, typeof raw === "string" ? raw : ""]
      .filter(Boolean).join(" ");
    for (const [re, msg] of RULES) if (re.test(text)) return msg;
    return (raw && (raw.message || raw.msg || raw.error_description)) || "A apărut o eroare. Încearcă din nou.";
  }
  const fail = raw => { const e = new Error(friendly(raw)); e.raw = raw; throw e; };

  /* ---------- sesiune (cont de administrator) ---------- */
  let session = null;
  try { session = JSON.parse(localStorage.getItem(SESSION_KEY) || "null"); } catch (e) { session = null; }
  const saveSession = s => {
    session = s;
    try { s ? localStorage.setItem(SESSION_KEY, JSON.stringify(s)) : localStorage.removeItem(SESSION_KEY); } catch (e) { /* ignorăm */ }
  };

  async function authCall(path, body, token) {
    let res;
    try {
      res = await fetch(URL_ + "/auth/v1/" + path, {
        method: "POST",
        headers: Object.assign({ apikey: KEY, "Content-Type": "application/json" }, token ? { Authorization: "Bearer " + token } : {}),
        body: JSON.stringify(body || {})
      });
    } catch (e) { fail("Nu există conexiune la internet."); }
    const data = await res.json().catch(() => ({}));
    if (!res.ok) fail(data);
    return data;
  }
  const toSession = d => ({
    access_token: d.access_token, refresh_token: d.refresh_token,
    expires_at: d.expires_at || Math.floor(Date.now() / 1000) + (d.expires_in || 3600),
    user: { id: d.user && d.user.id, email: d.user && d.user.email }
  });

  async function signIn(email, password) {
    saveSession(toSession(await authCall("token?grant_type=password", { email, password })));
    return session.user;
  }
  async function signOut() {
    const t = session && session.access_token;
    saveSession(null);
    if (t) { try { await authCall("logout", {}, t); } catch (e) { /* ieșim oricum */ } }
  }
  async function token() {                 // reîmprospătează automat sesiunea
    if (!session) return null;
    if (session.expires_at - 60 > Date.now() / 1000) return session.access_token;
    try { saveSession(toSession(await authCall("token?grant_type=refresh_token", { refresh_token: session.refresh_token }))); }
    catch (e) { saveSession(null); return null; }
    return session.access_token;
  }

  /* ---------- apel REST ---------- */
  async function rest(path, opt) {
    opt = opt || {};
    if (!configured()) fail("Aplicația nu e conectată la baza de date. Completează fișierul config.js.");
    const t = await token();
    const headers = { apikey: KEY, "Content-Type": "application/json" };
    if (t) headers.Authorization = "Bearer " + t;          // fără sesiune: acces public (doar citire)
    if (opt.prefer) headers.Prefer = opt.prefer;
    let res;
    try {
      res = await fetch(URL_ + "/rest/v1/" + path, {
        method: opt.method || "GET", headers,
        body: opt.body === undefined ? undefined : JSON.stringify(opt.body)
      });
    } catch (e) { fail("Nu există conexiune la internet."); }
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) fail(data || { message: res.statusText });
    return data;
  }
  const qs = o => Object.entries(o || {}).map(([k, v]) => k + "=" + encodeURIComponent(v).replace(/%2C/g, ",").replace(/%28/g, "(").replace(/%29/g, ")")).join("&");

  const select = (table, params) => rest(table + "?" + qs(Object.assign({ select: "*" }, params)));
  const insert = async (table, row) => (await rest(table, { method: "POST", body: row, prefer: "return=representation" }))[0];
  async function update(table, id, patch, pk) {
    const r = await rest(`${table}?${pk || "id"}=eq.${encodeURIComponent(id)}`, { method: "PATCH", body: patch, prefer: "return=representation" });
    if (!r.length) fail("permission denied");                // 0 rânduri = fără drept (RLS) sau inexistent
    return r[0];
  }
  async function remove(table, id, pk) {
    const r = await rest(`${table}?${pk || "id"}=eq.${encodeURIComponent(id)}`, { method: "DELETE", prefer: "return=representation" });
    if (!r.length) fail("permission denied");
  }
  const rpc = (fn, args) => rest("rpc/" + fn, { method: "POST", body: args || {} });

  /* ---------- date calendaristice ---------- */
  const pad = n => String(n).padStart(2, "0");
  const isoDate = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());   // data locală, nu UTC
  const isoDow = d => (d.getDay() + 6) % 7 + 1;                                                  // 1 = luni ... 7 = duminică

  /* ---------- funcții pentru aplicație ---------- */
  const api = {
    configured, friendly, isoDate, isoDow,

    // cont
    signIn, signOut,
    user: () => (session ? session.user : null),
    signedIn: () => !!session,
    async profile() {                                        // profilul contului curent (rol: elev / profesor / admin)
      if (!session) return null;
      return (await select("profiles", { id: "eq." + session.user.id }))[0] || null;
    },
    async isAdmin() { const p = await this.profile(); return !!p && p.role === "admin"; },

    // citire (public)
    async loadReference() {
      const [subjects, teachers, rooms, classes, bells] = await Promise.all([
        select("subjects", { order: "name" }),
        select("teachers", { select: "*,teacher_subjects(subject_id)", order: "last_name" }),
        select("rooms", { order: "name" }),
        select("classes", { order: "grade,letter" }),
        select("bell_slots", { order: "period" })
      ]);
      teachers.forEach(t => { t.subject_ids = (t.teacher_subjects || []).map(x => x.subject_id); delete t.teacher_subjects; });
      return { subjects, teachers, rooms, classes, bells };
    },
    loadTimetable: classId => select("v_timetable", { class_id: "eq." + classId, order: "day_of_week,period,group_name" }),
    classDay: (classId, date) => rpc("class_day", { p_class_id: classId, p_date: date }),
    freeTeachers: (date, period, subjectId) => rpc("free_teachers", { p_date: date, p_period: period, p_subject_id: subjectId || null }),
    notifications: (classId, limit) => select("notifications", {
      or: "(class_id.is.null,class_id.eq." + classId + ")", order: "created_at.desc", limit: limit || 50 }),
    substitutionsOn: date => select("substitutions", { lesson_date: "eq." + date }),

    // orar (admin)
    saveLesson: l => rpc("save_lesson", {
      p_id: l.id || null, p_class_id: l.classId, p_subject_id: l.subjectId, p_day: l.day, p_period: l.period,
      p_room_id: l.roomId || null, p_group: l.group || "", p_teacher_ids: l.teacherIds || []
    }),
    deleteLesson: id => remove("lessons", id),

    // înlocuiri (admin) — notificarea către elevi se creează automat în baza de date
    addSubstitution: s => insert("substitutions", {
      lesson_id: s.lessonId, lesson_date: s.date, absent_teacher_id: s.absentTeacherId,
      substitute_teacher_id: s.substituteTeacherId, room_id: s.roomId || null, reason: s.reason || "Alt motiv" }),
    cancelSubstitution: id => remove("substitutions", id),

    // anunțuri (admin)
    announce: (classId, body) => insert("notifications", { class_id: classId || null, kind: "anunt", body }),

    // generic (admin): materii, profesori, săli, clase, ore de apel, conturi
    select, insert, update, remove,
    async setTeacherSubjects(teacherId, subjectIds) {
      const have = (await select("teacher_subjects", { teacher_id: "eq." + teacherId })).map(r => r.subject_id);
      const add = subjectIds.filter(s => !have.includes(s)), del = have.filter(s => !subjectIds.includes(s));
      if (add.length) await rest("teacher_subjects", { method: "POST", body: add.map(s => ({ teacher_id: teacherId, subject_id: s })), prefer: "resolution=ignore-duplicates" });
      if (del.length) await rest(`teacher_subjects?teacher_id=eq.${teacherId}&subject_id=in.(${del.join(",")})`, { method: "DELETE" });
    },

    // actualizare periodică (simplu și sigur și în aplicația de telefon)
    poll(fn, ms) { fn(); const h = setInterval(fn, ms || 30000); return () => clearInterval(h); }
  };

  window.OrarDB = api;
})();
