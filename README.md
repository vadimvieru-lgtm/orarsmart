# OrarSmart

Program pentru calculator (Windows) și aplicație pentru telefon. Ecrane: Orar, Notificări, Panou administrator, Setări.

## Pe calculator (Windows)

1. Extrage arhiva (clic dreapta → Extract all).
2. Dublu clic pe `START-AICI-Creeaza-OrarSmart-exe.bat` (internet necesar; prima dată 3–6 minute, a doua oară sub 2 minute).
3. Se deschide `OrarSmart.exe`, iar pe Desktop apare scurtătura „OrarSmart".

Programul e în `dist\OrarSmart-win32-x64\`. Pentru a-l da altcuiva, arhivează tot folderul.

## Pe telefon (Android, fișier APK)

1. Creează un cont gratuit pe github.com și un depozit nou („New repository", numele `orarsmart`, Public).
2. Apasă „uploading an existing file" și trage înăuntru tot conținutul unei **copii proaspete** extrase din arhivă (fără folderele `node_modules`, `dist`, `.tools`). Apoi „Commit changes".
3. Deschide fila **Actions**. „Build Android APK" pornește singur (5–10 minute). Dacă nu, apasă „Run workflow".
4. Când apare bifa verde, deschide rularea, jos la **Artifacts** descarcă `OrarSmart-apk`, extrage zip-ul și ai `app-debug.apk`.
5. Trimite APK-ul pe telefon, deschide-l și permite „Instalare din surse necunoscute" când te întreabă. Apasă Instalează.

iPhone: nu se poate instala un program fără un Mac și un cont Apple Developer plătit. Pe iPhone rămâne varianta „Adaugă pe ecranul principal" dintr-un link.

## Ca să vezi panoul de administrator

Setări → Mod → Administrator → apare fila „Admin".

## De știut

- Datele sunt salvate local pe fiecare dispozitiv (nu pe un server). O înlocuire făcută pe calculator nu apare pe telefon. Pentru asta e nevoie de un server.
- Dacă schimbi ceva în `src\index.html`, rulează din nou fișierul `.bat` ca să refaci programul.
