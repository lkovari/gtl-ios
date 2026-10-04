# GTL iOS fejlesztési roadmap

Állapot: termékterv az 1.0.1 (33-as build) után, 2026. október 4. Forrás: az Android GTL (2.0.19) roadmapje, erre az iOS-appra szűrve.

Ez nem kódspecifikáció. Azt rögzíti, mit érdemes legközelebb megépíteni, milyen sorrendben és miért. Egy hullám megvalósítása előtt külön brief és tesztlista kell.

Effort: egy, a kódbázist ismerő fejlesztő naptári napja.

Kapcsolódó: [README-hu.md](README-hu.md), [gtl-ios-decline-fix-plan-hu.md](gtl-ios-decline-fix-plan-hu.md), [gtl-ios-possible-decline-hu.md](gtl-ios-possible-decline-hu.md).

## Kiválasztási szabály

Egy tétel csak akkor van a listán, ha **a mai működés elrontása vagy blokkolása nélkül** hozzáadható. Konkrétan minden tételnek érintetlenül kell hagynia ezeket:

- **Rögzítési szerződés.** Indítás csak előtérből, „Az app használata közben” engedéllyel és Pontos hellyel; rögzítés közben `CLBackgroundActivitySession`; kék jelző a Leállításig. Nincs Mindig kérés, nincs háttérből indítás.
- **Adatvédelem.** A nyomvonal a telefonon marad. A tárolt adatból semmi nem megy a fejlesztőhöz vagy harmadik félhez. Az áruházi címke Data Not Collected marad.
- **Tárolt adat.** A meglévő útvonalak továbbra is megnyílnak és exportálhatók. Adatbázis-változás csak bővítés lehet (új oszlop vagy tábla alapértékkel), a `gps_events` átírása soha.
- **Áruházi helyzet.** Nincs új engedély, háttérmód vagy rejtett funkció, ami újranyitná az 1.0.1-nél megválaszolt review-kérdéseket.

Ebből semmi ne menjen ki az 1.0.1 jóváhagyása előtt. Minden hullám külön frissítés.

## Ami iOS-en már megvan (az Android-listából)

Ezek az iOS-appban készen vannak, lent nem szerepelnek újra:

- Térkép HUD nagy sebességgel, pontossággal, naplózáskor úttal, eltelt idővel és REC-cel
- Használat szerinti sebességsávokkal színezett nyomvonal, jelmagyarázattal (nyitva vagy összecsukott pöttyökkel)
- **Kapuzott, menetirányú követés** (az Android 3. tétele): 1 m/s felett course, alatta iránytű, 5 fokos lépcső, kb. 52 fokos dőlés, a kétujjas döntés megmarad, az észak-tárcsa visszaállít; a Teljes útvonal a képen nézet északra áll
- Mentett-útvonal kártyák kis rajzzal, távval, idővel, átlag- és csúcssebességgel
- GPX 1.1 és KMZ abszolút GPS-magassággal és Start / Pause / Stop jelölőkkel
- Magasságprofil szaggatott barometrikus vonallal, QNH, GPS-magasság választás
- OSM (Mapsforge, MapLibre-rel rajzolva) és Turistautak offline térkép, fájlellenőrzéssel
- Apple térkép standard, műhold és hibrid nézetben, valós domborzattal
- Rendszer szerinti világos és sötét téma az app felületén; az Apple térkép magától követi a sötét módot

## Ami iOS-en nem alkalmazható vagy elvetett

| Ötlet | Miért nem |
| --- | --- |
| GNSS skyplot, konstellációlista, SNR | Az iOS-nek nincs nyilvános API-ja a műholdakhoz. Nem építhető meg. |
| Élő megosztás, saját szerver, feltöltés | Szemben az adatvédelmi ígérettel és a Data Not Collected címkével. |
| Utcára pattintás (map matching) | Szemben az app lényegével: a vonal az, amit a chip rögzített. |
| Közösség, kudos, szegmensek | Más termék. |
| Apple Watch app | Hetek munkája, külön target és tesztmátrix. Később, ha egyáltalán. |
| GPX import | Az app logger, nem archívumkezelő. |
| FIT / TCX export | Csak ha valaki Garmin Connecthez kéri. |
| Turn-by-turn navigáció | Vezetés közbeni figyelemelterelés és review-kockázat; az Apple Maps ezt tudja. |
| Hőmérséklet szerint színezett nyomvonal | Az iPhone-ban nincs környezeti hőmérséklet-szenzor. |
| Fekvő, tankra tett HUD | Az app csak álló, `UIRequiresFullScreen` beállítással. A fekvő mód engedélyezése minden képernyőt és a követő kamerát érinti; pont ez az „el ne rontsd” kockázat. Csak külön, elszigetelt teljes képernyős nézetként érdemes újra megnézni, ha a motorosok kérik. |
| Magától induló rögzítés (bekapcsoláskor, geokerítésre, háttérből) | Mindig engedély kell hozzá, és megtöri a rögzítési szerződést. |

---

## Prioritási lista

Érték szerint: elöl, ami minden felvételen látszik; hátul, amit egy túra után egyszer nézel meg. Ahol két tétel közel azonos értékű, az olcsóbb kerül előre a hullámban.

### 1. Álló helyzetben 0 a HUD sebessége

**Állapot: megvalósítva (2026. október 4.).** `StationarySpeedGate` a `gtl/Engine/EngineDisplay.swift`-ben, `RecordedFix.speedAccuracy`, `TrackerModel.displaySpeedMps`; ezt használja a HUD, a jelmagyarázat kiemelése és az Útvonal fül élő sebessége. Tesztek: `gtlTests/ThemeAndSpeedTests.swift`. A Live Activity (3. tétel) ugyanezt az értéket olvassa majd.

Érték: magas — a műszer álló helyzetben is mozgást mutat · Effort: kb. 1 nap · 1. hullám

**Miért.** A HUD a nyers `CLLocation.speed` értéket kerekíti (`model.speedMps` → `Units.hudSpeedNumber`, `gtl/UI/MapViews.swift`). Bent, mozdulatlan telefonnál a Doppler-zaj néhány km/h-t mutat. Egy fix km/h-küszöb a lassú gyaloglást levágná, egy nagyobb benti tüskét átengedne.

**Mit építs.** Egy tiszta engine-függvényt, amit a HUD, az Útvonal fül élő sebessége és a Live Activity (3. tétel) is hív:

- Nincs sebesség (`speed < 0`): „—”.
- Van sebességpontosság (`CLLocation.speedAccuracy >= 0`): ha a sebesség ≤ a pontossága, 0.
- Különben: ha az előző fix óta az elmozdulás ≤ a vízszintes pontosság, 0.
- Hiszterézis: két szignifikáns minta a 0 elhagyásához, kettő a visszatéréshez.

A `RecordedFix` kap egy `speedAccuracy` mezőt (bővítés). A letárolt nyomvonal nem változik; ez csak megjelenítési szabály.

**Miért nem ront el semmit.** Csak a kijelzést érinti; a rögzítési lánc, a szűrők és a tárolt pontok maradnak.

**Teszt.** Engine-teszt minden ágra és a hiszterézisre. Szimulátorban álló helynél 0; szimulált útvonalon megjön a sebesség, 0/5 villogás nélkül.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció. A `speedAccuracy` a meglévő helyengedéllyel érkező `CLLocation` része.

### 2. Sötét offline térkép és téma-választó az appban

**Állapot: megvalósítva (2026. október 4.), egy eltéréssel a tervtől.** Rendszer / Világos / Sötét helyett a Beállítások → Téma csoportban **Automatikus témaváltás** van (alapból bekapcsolva): a pillanatnyi helyzet szerinti pirkadat és alkonyat között világos, azon kívül sötét, a telefonon számolt polgári szürkület (a nap −6°-on) alapján (`SolarDaylight`). Kikapcsolva kézzel választható a Világos vagy a Sötét. Ismeretlen helyzetnél az automatikus mód az iPhone beállítását követi, ami megtartja a korábbi működést. A sötét offline paletta a `gtl/Maps/OfflineMapPalette.swift`, futás közben alkalmazva; sötét térképen a nyomvonal világos szegélye tartja láthatóan a sebességszíneket. Szimulátorban ellenőrizve: kézi sötét, és automatikus váltás világosról (Andorra, nappal) sötétre (Tokió, éjjel) újraindítás nélkül.

Érték: magas — éjszakai motorozás, márka, az áruházi képek sötétek · Effort: 2–3 nap · 1. hullám

**Miért.** Az app felülete és az Apple térkép már a rendszerrel együtt sötétül. Az offline OSM- és Turistautak-térkép nem: a `gtl/offline-style.json` és a rétegszínek világos stílusúak (háttér `#f3efe4`). Éjjel egy letöltött térkép fehér téglalap, és a világos sebességsávok kiégnek.

**Mit építs.**

- Beállítás: Rendszer / Világos / Sötét (a `SettingsStore`-ban tárolva, a `RootView`-ban `.preferredColorScheme`-mel alkalmazva; az alapérték a Rendszer marad).
- Az offline stílus sötét változata (háttér, felszínborítás, utak, víz, feliratok) OSM-hez és Turistautakhoz, a tényleges színséma szerint választva.
- Kontrasztellenőrzés sötét térképen: HUD, sebességsávok, pontossági kör, pozíciófelhő, S/E jelölő. Sávot csak akkor módosíts, ha eltűnik.

**Ne.** Harmadik, „nagy kontrasztú” paletta.

**Miért nem ront el semmit.** Világos módban a világos stílus marad az alap; a sötét stílus egy második erőforrás, amit a rajzolás pillanatában választ az app.

**Teszt.** Rendszer / Világos / Sötét × Apple térkép / OSM / Turistautak; a HUD, a sebességsávok és a pozíciófelhő mindegyiken olvasható.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció. A témaválasztás a `UserDefaults`-ba kerül, amit a privacy manifest már deklarál (`CA92.1`).

### 3. Live Activity a zárolási képernyőn és a Dynamic Islanden

Érték: közepes–magas — második HUD zsebben vagy a tankon · Effort: 2–3 nap · 1. hullám

**Miért.** Az androidos élő értesítés iOS-megfelelője. Rögzítés közben sebesség, táv és eltelt idő a zárolási képernyőn és a Dynamic Islanden, egy Leállítás gombbal.

**Mit építs.**

- Widget Extension target egy `ActivityAttributes` típussal; `NSSupportsLiveActivities` az app Info.plist-jében.
- Indul a `beginSession`-ben, elfogadott pontoknál frissül, legfeljebb néhány másodpercenként (az ActivityKitnek frissítési kerete van), véget ér a `stopLogging`-ban.
- Leállítás gomb egy App Intenttel, ami ugyanazt a leállítási utat hívja, mint az app gombja.
- A sebesség az 1. tétel kapuzott értéke.

**Miért nem ront el semmit.** Az ActivityKitnek nem kell helyengedély és új háttérmód. A Live Activity csak számokat mutat; rögzítést továbbra is csak az app indíthat. Ha a felhasználó kikapcsolja a Live Activityket, más nem változik.

**Teszt.** Indítás, zárolás, a Live Activity frissül; a benne lévő Leállítás ugyanúgy zárja a munkamenetet, mint az app gombja; kényszerített bezárásnál a Live Activity is véget ér.

**Engedélyek és deklarációk.** Felhasználói engedélyablak nincs, de több deklaráció kell:

- `NSSupportsLiveActivities` = `YES` az app Info.plist-jében. A `NSSupportsLiveActivitiesFrequentUpdates` nem kell, mert néhány másodperces frissítés elég.
- Új Widget Extension target saját bundle ID-val (például `com.lkovari.mobile.apps.gtl.LiveActivity`). Automatikus aláírásnál az Xcode regisztrálja és provisioning profile-t kér hozzá; a fejlesztői portálon új App ID jelenik meg.
- A bővítménynek saját `PrivacyInfo.xcprivacy` kell, ha required reason API-t használ (például `UserDefaults`); ha nem, nem kell.
- App Group nem kell, mert az adat az ActivityKit tartalmában megy át. Push-értesítés (push token alapú frissítés) nem kell, ezért a Push Notifications képesség sem.
- A Leállítás gomb App Intentje (`LiveActivityIntent`) nem kér Info.plist kulcsot.
- App Store Connect: az adatvédelmi címke nem változik. A review-jegyzetbe egy mondat: a Live Activity rögzítés közben a sebességet, a távot és az időt mutatja, Leállítás gombbal.

### 4. Dőlésszalag motoros útvonalakon (kinematikai dőlés)

Érték: magas a motoros alapbeállításhoz · Effort: 3–4 nap · 2. hullám

**Miért.** Minden pont tárol dőlésszöget, de a felület ebből semmit nem mutat. A mostani forrás ráadásul kanyarban félrevezet: a `BikeLeanAngle.fromGravity` a gravitációs vektorból számol, és egyenletes, koordinált kanyarban a látszólagos gravitáció a motor síkjába esik, így a tankon lévő telefon 0° közelit mér.

**Mit építs.**

- Engine: dőlés ≈ atan(v · ω / g), ahol v a sebesség, ω a forduló szögsebessége. Mentett útvonalon ω a tárolt irányszög változásából és az időből jön, így visszamenőleg minden meglévő motoros útvonalra működik, és nem függ attól, hogyan van rögzítve a telefon. Élőben ω a giroszkóp yaw rate-jéből (Core Motion), ha van.
- Kb. 3 m/s alatt és ritka pontoknál nincs szalag (ott az irányszög-zaj dominál).
- Rajzolás Apple térképen és MapLibre-en: szalag a vonal mellett, vagy színezési választó (sebesség / dőlés), bal és jobb külön árnyalattal; jelmagyarázat fokban.
- Mentett kártya: max bal / max jobb.
- Futás/Túránál rejtve, kerékpárnál opcionális.

**Elsőre ne.** A gravitáció alapú dőlés kirajzolása. Kalibrációs varázsló a tartóhoz.

**Miért nem ront el semmit.** Már tárolt adatból számol; a tárolt `leanAngle` oszlop marad, ahogy van.

**Teszt.** Engine: szintetikus körív adott sebességgel → ismert dőlés; egyenes ~0°; álló helyzetben nincs szalag. Valódi szerpentin: a bal/jobb előjel helyes.

**Engedélyek és deklarációk.** Nincs új engedély. Az élő dőléshez a giroszkóp (yaw rate) a `CMMotionManager` device motion adatából jön, amit az app már olvas, és amire a `NSMotionUsageDescription` már megvan. A mostani szöveg („a mozgást … a dőlésszög … rögzítéséhez olvassa”) lefedi; nem kell átírni.

### 5. Üstökösfarok az élő nyomvonalon

Érték: közepes — olcsó, menet közben mozgást ad · Effort: kb. 1 nap · 2. hullám

**Miért.** Naplózáskor az utolsó perc vastagabb és teljes színű, a régebbi vonal halkabb. A meglévő sebességszínezett szakaszokra ül, új adat nem kell.

**Mit építs.** A sebességszakaszok kapnak egy korlépcsőt (2–3 lépcső elég, nem méterenkénti színátmenet). A szélesség és az átlátszóság a lépcsőt követi. Csak élő munkamenetben; mentett útvonalon egyenletes a vonal. Figyelj a polyline-ok számára az Apple térképen és a vonalrétegek számára MapLibre-en; a zárolási szabály (inaktív jelenetnél a térkép nem rajzolódik újra) marad.

**Teszt.** Naplózáskor a legújabb rész kiemelt; a mentett útvonal változatlan; zárolva nincs plusz újrarajzolás.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció.

### 6. Repülés az útvonal mentén Google Earth-ben (KMZ gx:Tour)

Érték: közepes — erős látvány, olcsó, a KMZ-közönségnek · Effort: 1–2 nap · 3. hullám

**Miért.** A KMZ már a tárolt GPS-magasságon adja át a vonalat. Egy `gx:Tour` végigrepíti rajta a Google Earth kameráját. Egy „flyover” látványának nagy része, a költsége töredékéért.

**Mit építs.** A KMZ-exportálóban (`gtl/Engine/EngineExport.swift`): `gx:Tour` / `gx:Playlist` `gx:FlyTo` lépésekkel a ritkított pályán (irány a pályából, fix dőlés, távolság a sebesség szerint). Opcionális kapcsoló a megosztásnál. Engine-teszt a generált KML-re.

**Miért nem ront el semmit.** Egy plusz elem a fájlban; a `gx:Tour`-t nem ismerő nézegetők átugorják, a meglévő vonal és jelölők nem változnak.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció. A fájl a meglévő megosztólapon megy ki, ugyanúgy, mint ma a KMZ.

### 7. Mentett útvonalak: név és tárolt statisztika

Érték: közepes · Effort: 1–2 nap · 3. hullám

**Mit építs.**

- Opcionális név munkamenetenként. Üresen a dátum marad, mint ma. A KMZ/GPX fájlnév és a `<name>` ezt használja, a tiltott karakterek cseréjével.
- A `track_sessions` kap `name`, `avg_speed`, `max_speed` oszlopot (és a 4. tétel után `max_lean_left` / `max_lean_right`-ot), Leállításkor számolva. A lista ezeket olvassa; az értékek nélküli régi munkamenetek továbbra is a pontokból számolnak.
- Adatbázis-verziózás: az első migráció bevezeti a `PRAGMA user_version`-t, és `ALTER TABLE … ADD COLUMN`-nal, alapértékkel ad hozzá oszlopot. Táblaátírás nincs.

**Miért nem ront el semmit.** Az oszlopok bővítések alapértékkel; minden meglévő munkamenet ugyanúgy megnyílik és exportálható.

**Teszt.** Frissítés egy útvonalakat tartalmazó 1.0.1-es adatbázisról; mind megnyílik, exportálható, mutatja a statisztikát; egy átnevezett útvonal a nevén exportálódik.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció. Az adatbázis a telefonon marad; az adatvédelmi címke és a privacy manifest nem változik.

### 8. Képeslap megosztás

Érték: közepes — közösségi látvány szerver nélkül · Effort: 2–3 nap · 3. hullám

**Miért.** Sötét kártya izzó, sebességszínezett vonallal, távval, idővel, magasságcsíkkal és GTL-pecséttel, PNG-ként a megosztólapon. Nincs feltöltés.

**Mit építs.** A vonal sötét vásznon, térképcsempe nélkül (a mentett-útvonal kis rajzának kódja nagyrészt újrahasznosítható), SwiftUI `ImageRenderer`-rel képpé alakítva, a meglévő megosztólapon át.

**Miért nem ront el semmit.** Új exportlehetőség a GPX és a KMZ mellett; a telefont csak akkor hagyja el, ha a felhasználó megosztja, ugyanúgy, mint ma a GPX.

**Engedélyek és deklarációk.** **Új Info.plist kulcs kell: `NSPhotoLibraryAddUsageDescription`.** A megosztólapon megjelenik a „Kép mentése” sor, és ha a kulcs hiányzik, erre koppintva az app összeomlik. Angol és magyar szöveg az `InfoPlist.xcstrings`-be, például: „GTL saves the track postcard to your photo library when you choose Save Image.” / „A GTL a Kép mentése választásakor a fotókönyvtáradba menti az útvonal-képeslapot.” Ez csak hozzáadási engedély, olvasni nem enged. Az adatvédelmi címke nem változik, mert a kép nem kerül a fejlesztőhöz. Az adatvédelmi nyilatkozatba egy mondat: a képeslap csak a felhasználó kérésére kerül a Fotókba vagy a megosztás céljához.

### 9. Kanyargaléria

Érték: közepes motorosoknak · Effort: 2–3 nap · 3. hullám

**Miért.** „Bal 38°, 72 km/h”: a mentett útvonal legerősebb kanyarjai az irányszög-változásból és a dőlésből; koppintásra a térkép oda ugrik. A 4. tétel után érdemes, mert ugyanazt a számítást használja.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció.

### 10. Kézi szünet és körök

Érték: közepes · Effort: 2–3 nap · 4. hullám

**Miért.** A szünet ma sebességküszöb. Benzinkútnál nem lehet szüneteltetni Leállítás nélkül, ami új munkamenetet indít.

**Mit építs.** Szünet / Folytatás naplózás közben; szünetben nincs MOVE pont; a Folytatás nem nyit új munkamenetet. A KMZ a meglévő szünet ikont használja; a GPX új `trkseg`-et kap a szünetnél. A körök utána.

**Vigyázat.** A háttér-munkamenetnek szünet alatt is élnie kell, különben a folytatáshoz új előtérbeli indítás kellene. A `CLBackgroundActivitySession` és a helyfrissítés fusson tovább szünet alatt is, csak a pontok maradjanak el; zárolt telefonon tesztelendő.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció. A háttérmód marad a meglévő `location`; a szünet alatt is ugyanaz a munkamenet fut.

### 11. Visszajátszás a térképen

Érték: közepes — erős videó, de egy túra után egyszer nézed meg · Effort: 5–8 nap · 4. hullám

**Miért.** A mentett útvonal kirajzolódik, a helyjelölő végigmegy rajta, a HUD az adott pont számait mutatja. Jó áruházi előnézeti videóhoz.

**Drága, mert:** csúszka, tempó (1× / 10× / 60×), jelölő és kamera mindkét térképmotoron. A 6. tétel a látvány nagy részét olcsóbban adja; ezt csak akkor érdemes megépíteni, ha a felhasználók appon belül kérik. Csak mentett útvonalon fut, rögzítés közben soha.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció.

### 12. Indítás és Leállítás a Vezérlőközpontból és Parancsokból

Érték: alacsony–közepes · Effort: kb. 1 nap · Hullám: bármikor

**Miért.** Az androidos Quick Settings csempe iOS-megfelelője. Indítás kesztyűben a Vezérlőközpontból (iOS 18-tól vezérlőelem) vagy Parancsból / Siri-mondattal (App Intents, iOS 17).

**A szerződést megtartó szabály.** Az Indítás intent megnyitja az appot (`openAppWhenRun`), és előtérben a megszokott Indítás utat futtatja, így a „használat közben” és a Pontos hely ellenőrzése, valamint a figyelmeztetések változatlanul érvényesek. A Leállítás futhat az app megnyitása nélkül.

**Engedélyek és deklarációk.** Felhasználói engedélyablak nincs.

- App Intents és App Shortcuts (Parancsok, Siri-mondat): nem kell Siri-képesség és Info.plist kulcs; a SiriKit-féle régi intentekhez kellene, ezekhez nem.
- A Vezérlőközpont-elem (iOS 18 `ControlWidget`) widget extensionben él. Ha a 3. tétel bővítménye már megvan, abba kerül; ha nincs, új target és bundle ID kell, mint ott.
- App Store Connect: nincs teendő.

### 13. Két útvonal egy térképen

Érték: alacsony — archívumhasználat · Effort: 2–3 nap · Később

**Miért.** Két kijelölt mentett útvonal egy térképen, eltérő színnel. Csak olvasó nézet; az élő térkép nem változik.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció.

### 14. Magasság-szobor

Érték: alacsony · Effort: 3–5 nap · Később

**Miért ilyen hátul.** Az Apple térkép már mutat valós domborzatot, a KMZ abszolút magasságot ad át a Google Earth-nek, és a 6. tétel repülést is hozzáad. Appon belüli 2,5D rajz csak hegyi és repülős használatnál ad hozzá valamit.

**Engedélyek és deklarációk.** Nincs új engedély és deklaráció.

---

## Kiadási hullámok

A verziószámok javaslatok.

### 1. hullám — „éjjel is látod, zsebben is olvasod” (1.1, kb. 5–7 nap)

| # | Tétel | Effort |
| --- | --- | --- |
| 1 | Álló helyzetben 0 a HUD-on (kész) | kb. 1 nap |
| 2 | Sötét offline térkép + Automatikus (pirkadat/alkonyat) / Világos / Sötét (kész) | 2–3 nap |
| 3 | Live Activity | 2–3 nap |
| — | Új képernyőkép: sötét HUD-os térkép naplózás közben | 0,5 nap |

Kész, ha: sötét módban az offline térkép sötét (OSM és Turistautak); álló benti fixnél a HUD 0 km/h; a Live Activity ugyanazt a számot mutatja, mint a HUD; az áruházban van sötét HUD-os kép.

### 2. hullám — „a térkép veled megy” (1.2, kb. 4–5 nap)

| # | Tétel | Effort |
| --- | --- | --- |
| 4 | Dőlésszalag (kinematikai) | 3–4 nap |
| 5 | Üstökösfarok | kb. 1 nap |

Kész, ha: egy mentett szerpentinen látszik a bal/jobb dőlés, a régi útvonalakon is; naplózáskor az utolsó perc kiemelt; zárolva nincs plusz rajzolás.

### 3. hullám — „az archívum mesél” (1.3, kb. 6–10 nap)

| # | Tétel | Effort |
| --- | --- | --- |
| 6 | KMZ gx:Tour | 1–2 nap |
| 7 | Útvonalnév + tárolt statisztika | 1–2 nap |
| 8 | Képeslap PNG | 2–3 nap |
| 9 | Kanyargaléria | 2–3 nap |

### 4. hullám — mélyítés (később, darabolva)

| # | Tétel | Effort |
| --- | --- | --- |
| 10 | Kézi szünet / körök | 2–3 nap |
| 11 | Visszajátszás a térképen | 5–8 nap |
| 12 | Vezérlőközpont / Parancsok | kb. 1 nap |
| 13 | Két útvonal egy térképen | 2–3 nap |
| 14 | Magasság-szobor | 3–5 nap |

## Összesítő tábla

| Rang | Funkció | Érték | Effort | Hullám |
| --- | --- | --- | --- | --- |
| 1 | Álló helyzetben 0 a HUD-on (kész) | magas | ~1 nap | 1 |
| 2 | Sötét offline térkép + téma-választó (kész) | magas | 2–3 nap | 1 |
| 3 | Live Activity | közepes–magas | 2–3 nap | 1 |
| 4 | Dőlésszalag (kinematikai) | magas (motor) | 3–4 nap | 2 |
| 5 | Üstökösfarok | közepes | ~1 nap | 2 |
| 6 | KMZ gx:Tour | közepes | 1–2 nap | 3 |
| 7 | Útvonalnév + tárolt statisztika | közepes | 1–2 nap | 3 |
| 8 | Képeslap megosztás | közepes | 2–3 nap | 3 |
| 9 | Kanyargaléria | közepes (motor) | 2–3 nap | 3 |
| 10 | Kézi szünet / körök | közepes | 2–3 nap | 4 |
| 11 | Visszajátszás a térképen | közepes | 5–8 nap | 4 |
| 12 | Vezérlőközpont / Parancsok | alacsony–közepes | ~1 nap | bármikor |
| 13 | Két útvonal egy térképen | alacsony | 2–3 nap | később |
| 14 | Magasság-szobor | alacsony | 3–5 nap | később |

Ha csak kettő fér bele: **sötét offline térkép** és **Live Activity**. Az első éjjel látszik, a második minden felvételen, amikor a telefon nincs a kezedben.
Ha a motoros közönségre lősz, a harmadik: **dőlésszalag** kinematikai dőléssel.

## Engedélyek és deklarációk összesítve

Ami új jelölést kíván az Info.plist-ben, a privacy manifestben, a fejlesztői portálon vagy az App Store Connectben. Új háttérmód, Mindig helyengedély, követési engedély (ATT) vagy push-értesítési képesség egyik tételhez sem kell.

| # | Tétel | Felhasználói engedélyablak | Info.plist | Privacy manifest | Új target / bundle ID | App Store Connect |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Álló helyzetben 0 | nincs | — | — | — | — |
| 2 | Sötét térkép + téma | nincs | — | — (a `UserDefaults` már deklarált) | — | — |
| 3 | Live Activity | nincs | `NSSupportsLiveActivities` | a bővítménynek saját, ha required reason API-t használ | igen: Widget Extension | review-jegyzet egy mondata |
| 4 | Dőlésszalag | nincs (a mozgásengedély már megvan) | — | — | — | — |
| 5 | Üstökösfarok | nincs | — | — | — | — |
| 6 | KMZ gx:Tour | nincs | — | — | — | — |
| 7 | Név + statisztika | nincs | — | — | — | — |
| 8 | Képeslap | **igen, a Kép mentésekor: Fotók hozzáadás** | **`NSPhotoLibraryAddUsageDescription`** (EN + HU) | — | — | címke nem változik; nyilatkozat egy mondata |
| 9 | Kanyargaléria | nincs | — | — | — | — |
| 10 | Kézi szünet | nincs | — | — | — | — |
| 11 | Visszajátszás | nincs | — | — | — | — |
| 12 | Vezérlőközpont / Parancsok | nincs | — | — | a Vezérlőközpont-elemhez widget extension (a 3. tételével közös) | — |
| 13 | Két útvonal | nincs | — | — | — | — |
| 14 | Magasság-szobor | nincs | — | — | — | — |

Két tétel jár új jelöléssel: a **3. (Live Activity)** és a **8. (Képeslap)**. A 12. csak akkor, ha a 3. bővítménye még nincs meg.

## Minden hullám végén

- A README-en.md és a README-hu.md funkciólistája.
- Súgó EN/HU minden új vezérlőhöz.
- Az „Engedélyek és deklarációk összesítve” tábla szerinti Info.plist kulcsok, privacy manifestek és targetek megvannak a Release buildben (az `Info.plist`-et a lefordított `.app`-ban ellenőrizd).
- Adatvédelmi nyilatkozat csak akkor, ha az adatfolyam változik (a fenti tételek közül egyiknek sem kellene; a 3. és a 8. tételnél ellenőrizendő).
- Áruházi képek: 1320×2868 PNG, RGB, alfa nélkül, a futó buildből. What's New mindkét nyelven.
- Minden beküldés előtt zárolt séta valódi iPhone-on, mert az 1., 2. és 4. hullám a rögzítést vagy a rögzítés közbeni térképet érinti.

## Nyitott döntések (hullámonként, megvalósítás előtt)

1. hullám:

- ~~Sötét offline stílus~~ eldöntve: második paletta a meglévő rétegekre, futás közben alkalmazva; ugyanaz a paletta szolgálja az OSM-et és a Turistautakat.
- A Live Activity frissítési gyakorisága az ActivityKit keretén belül (például 5 másodperc vagy minden elfogadott pont, amelyik ritkább).

2. hullám:

- Dőlés: szalag a vonal mellett, vagy sebesség / dőlés színezési kapcsoló?
- Élő dőlés: giroszkóp yaw rate, vagy csak az irányszög változása (kb. egy fixszel késik)?

Ezeket a hullám briefjében rögzítsd; a roadmap szándékosan nem fagyasztja be a pixel-elrendezést.
