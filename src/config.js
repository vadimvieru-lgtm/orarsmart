// Conectarea la baza de date (Supabase).
// Completează cele două valori din: Supabase → Project Settings → API.
//
//  • SUPABASE_URL      — „Project URL"
//  • SUPABASE_ANON_KEY — cheia „anon" / „public" / „publishable"
//
// Cheia aceasta e PUBLICĂ prin natura ei (apare în orice aplicație). Securitatea
// o asigură regulile din database/schema.sql. NU pune aici niciodată cheia
// „service_role" / „secret".
window.ORARSMART_CONFIG = {
  SUPABASE_URL: "https://XXXXXXXX.supabase.co",
  SUPABASE_ANON_KEY: "PUNE-AICI-CHEIA-ANON"
};
