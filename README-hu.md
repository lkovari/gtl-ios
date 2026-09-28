# GPS Track Logger

[English](README-en.md)

A GPS Track Logger útvonalat rögzít az iPhone-on, és a pontokat a készüléken lévő adatbázisban tartja. A mentett útvonalak GPX 1.1 vagy KMZ formában megoszthatók.

Az Xcode-projekt a `gtl.xcodeproj`. A forrás a `gtl/` mappában van. A közös scheme a `gtl`.

## Követelmények

- Xcode az iOS 17 SDK-val vagy újabbal
- iPhone-szimulátor, vagy iOS 17 vagy újabb iPhone
- Swift 6

## Verzió és azonosítók

| | |
| --- | --- |
| Megjelenő név | GPS Track Logger |
| Magyar kezdőképernyő-név | GTL GPS útvonal napló |
| Bundle azonosító | `com.lkovari.mobile.apps.gtl` |
| Verzió | 2.0.15 |
| Build | 33 |
| Készülékek | csak iPhone, álló tájolás |
| Nyelvek | angol és magyar, a rendszer nyelve szerint |
| Megjelenés | világos és sötét, a rendszer szerint |

Az aláírás automatikus, a fejlesztői csapat nincs beállítva, ezért a szimulátor fizetős fiók nélkül is fordul. Az archive és a feltöltés az Apple Developer Program csapatát kéri az Xcode Signing & Capabilities alatt.

## Fordítás, teszt, futtatás

Nyisd meg a `gtl.xcodeproj` fájlt, és futtasd a `gtl` scheme-et egy iPhone-szimulátoron.

Parancssorból, telepített iPhone-szimulátorral:

```sh
xcodebuild -project gtl.xcodeproj -scheme gtl \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -packageAuthorizationProvider netrc \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Ha ez a szimulátornév nincs telepítve, válassz egyet innen:

```sh
xcrun simctl list devices available
```

A unit tesztek a rögzítési szűrőket, a térközt, a simítást, a barometrikus magasságot, az exportot és a térképszámítást fedik. A UI-teszt elindítja az appot, elfogadja a nyilatkozatot, és ellenőrzi, hogy a napló a képernyőn van.

## Felépítés

```mermaid
flowchart TD
  ui[SwiftUI képernyők]
  vm[Tracker modell a MainActoron]
  engine[Tiszta Swift motor]
  loc[Core Location munkamenet]
  motion[Core Motion és magasságmérő]
  db[SQLite útvonaltár]
  mapkit[MapKit online]
  libre[MapLibre offline]
  files[Mapsforge térképfájlok]
  ui --> vm
  vm --> engine
  vm --> loc
  vm --> motion
  vm --> db
  vm --> mapkit
  vm --> libre
  libre --> files
  loc --> engine
  engine --> db
```

A rögzítés addig áll, amíg egy munkamenet el nem indul. A helyzet, a mozgás és a barométer csak nyitott munkamenet alatt fut. Az iránymérés az Iránytű fülhöz, és munkamenet közben a térképen lévő mutatóhoz megy.

```mermaid
sequenceDiagram
  participant Felhasználó
  participant Napló
  participant Helyzet
  participant Motor
  participant Adatbázis
  Felhasználó->>Napló: Indítás
  Napló->>Adatbázis: munkamenet nyitása
  Napló->>Helyzet: legjobb pontosságú frissítések
  Helyzet->>Motor: fix
  Motor->>Motor: pontosság, térköz, opcionális simítás
  Motor->>Adatbázis: elfogadott pont
  Felhasználó->>Napló: Stop
  Napló->>Helyzet: frissítések leállítása
  Napló->>Adatbázis: munkamenet zárása
```

## Képernyők

Az első indítás nyilatkozatot mutat. Az elfogadás a készüléken tárolódik. Az elutasítás bezárja az appot.

A naplónak GPS, Útvonal, Térkép és Iránytű füle van. A menü a Beállításokat, az offline térképletöltést, a mentett útvonalakat, a Súgót, a Névjegyet és a Helyzet beállításait nyitja. A Névjegy verziósorára hétszer koppintva megnyílik a hibanapló.

A beállítások: használat (Repülő, Hajó, Autó, Motor, Kerékpár, Futás/Túra), metrikus / angolszász / ICAO mértékegység, megjelenés, rögzítési sűrűség, barométer ha a telefonon van, és a használt térkép rétegkapcsolói.

A mentett útvonalak megoszthatók GPX-ként vagy KMZ-ként, megjeleníthetők a térképen, vagy törölhetők.

## Térképek

Az online térkép MapKit: standard, műhold és hibrid, mindegyik valós domborzattal. Naplózás közben a kamera a haladás irányával dől és fordul. A nyomvonal sebesség szerint színezett. A térkép koppintása gyalogos, kerékpáros vagy autós útvonalat kérhet az Apple-től. A helykeresés az online térképen a MapKit helyi keresését használja.

A kamera, a sebességszín, a KMZ-magasság és a koppintott pontig vezető út a lenti [Térkép funkciók](#térkép-funkciók) részben van.

Offline térkép egyszerre egy letöltött régió:

- OpenStreetMap régiók a `https://download.mapsforge.org/maps/v5/` címről, 2 GB-os plafonnal és 64 MB szabadhely-tartalékkal
- Turistautak.hu csak a `https://turistautak.elte.hu/tuhu/tuhu_mapsforge.zip` címről

A letöltés előbb a fájl tényleges méretét olvassa. Ha a méret nem olvasható, nagyobb a plafonnál, vagy a szabad hely a 64 MB tartalékkal nem elég, a letöltés nem indul. Mobilhálózaton a méret megerősítés után indul. Menet közben a letöltés megáll, ha a leírt bájt átlépné a szabad helyet a tartalékkal, vagy a plafont. A letöltött térképfájl kimarad a készülék mentéséből.

A MapKit ezeket a fájlokat nem rajzolja. Az app a látható csempéket olvassa a Mapsforge fájlból, és MapLibre Native-nel rajzolja (BSD 2-Clause). A dekódolás a fő szálon kívül fut, a kamera mozdulásakor megszakad, és nem tölti be az egész országot a memóriába. A MapLibre csak addig jön létre, amíg offline térkép van használatban. A névjegy a MapLibre copyright sorait is kiírja.

Offline OSM térképnél a sarokfelirat `© OpenStreetMap contributors`. Turistautak térképnél `© Turistautak.hu`, a névjegy a lapra és a jogi nyilatkozatra hivatkozik. Domborzatárnyékolás csak akkor van, ha magasságfájlok ülnek a térkép mellett.

Az offline térkép helykeresése készüléken lévő indexet használ. A keresés 3 karakternél indul, és legfeljebb 5 találatot ad.

## Adatvédelem

A privacy manifest pontos helyet kér az app működéséhez. A required reason API okok: UserDefaults `CA92.1`, fájlidő `C617.1`, lemezhely `E174.1`. Az app nem követ. Az `ITSAppUsesNonExemptEncryption` hamis.

A naplózott nyomvonal, a gyorsulás és a dőlés a telefon SQLite adatbázisában marad. Az iPhone mentése ezt az adatbázist tartalmazza. A letöltött térképfájl a mentésből ki van zárva. A térkép, a keresés, az útvonal és a cím az Apple-nek küldi az ehhez szükséges koordinátát vagy térképablakot. Az OSM- és a Turistautak-letöltésnél a kiszolgáló látja az IP-címet és a kért fájlt. A naplózott track nem kerül a fejlesztő szerverére. Ezt mondja az első képernyő és a Súgó használati bekezdése is.

Az adatvédelmi nyilatkozat: `https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html`. Ugyanez az App Store Connect Support URL. A forrás a `docs/gtl-ios-private-policy.html` fájl; a lapot a feltöltés előtt a KLHome oldalra kell másolni. A névjegyben a `laszlo.kovary@gmail.com` cím is ott van. A link az első képernyőn, a Beállításokban és a Súgóban is elérhető.

Az első képernyő Elutasítom gombja nem lép ki. A rögzítés az Elfogadomig nem indul. When In Use mellett az Indítás előbb elmondja, miért kell a Mindig engedély a zárolt képernyőhöz; a csak az app használata közben ág Always kérés nélkül indul. Csökkentett pontosságnál a rögzítés a Pontos hely nélkül nem indul. Elutasított helyengedélynél a GPS fül a Helyzet beállítások képernyőre visz.

A cél-szövegek angolul és magyarul:

- Helyzet az app használata közben
- Helyzet mindig és használat közben
- Mozgás
- Ideiglenes pontos hely a nyomvonalhoz (`PreciseRoute`)

Az egyetlen háttérmód a Helyzet. A zárolt képernyő viselkedése a [Rögzítés zárolt képernyőn](#rögzítés-zárolt-képernyőn) részben van.

## Ami a korábbi viselkedéshez képest változott

Ezek a változások az App Store review miatt kerültek be. A rögzítés, a térkép, a mentett útvonal és az export megmaradt. Néhány művelet, ami régen azonnal lefutott, most egy ellenőrzésen vagy egy választáson megy át. Ahol a feltétel megvan, a művelet ugyanúgy folytatódik.

### Elutasítom

Régen az első képernyő Elutasítom gombja `exit(0)` hívással megszakította az alkalmazás folyamatát. Az iOS-en a felületen nincs Kilépés: a folyamatot a rendszer zárja be. A review ezt kész, használható app és tervezés alatt szokta visszaküldeni.

Most a gomb a nyilatkozat képernyőn hagy. Megjelenik a mondat, hogy a rögzítés addig nem indul, amíg a felhasználó el nem fogadja. Az Elfogadom továbbra is a `disclaimer` UserDefaults kulcsot írja, és utána a nyomkövető nyílik meg.

### Nyitó szöveg és a Súgó

Régen az első képernyő és a Súgó használati bekezdése azt mondta, hogy a helyzet nem megy szerverre, illetve hogy semmi nem kerül fel. A Térkép súgó közben már leírta, hogy az útvonal és a cím kérése koordinátát küld az Apple-nek. A három szöveg ellentmondott egymásnak. Az irányelv szerint a felhasználót nem lehet félrevezetni arról, hogy az adata elhagyja-e a készüléket.

Most mindkét hely külön mondja a kettőt. A naplózott track nem kerül a fejlesztő szerverére. A térkép, a keresés, az útvonal és a cím az Apple-nek küldi az ehhez szükséges koordinátát. A Térkép súgó mondatai változatlanok, azok voltak a minta.

### Adatvédelmi link

Régen a link csak a Súgó egy alapból összecsukott során volt, és a felirata a hosztnév volt. A reviewer az első képernyőt és a Beállításokat nézi. Az irányelv a nyilatkozatot az appban könnyen elérhető helyre kéri.

Most ugyanaz az URL van az első képernyőn, a Beállításokban és a Súgóban. A felirat mindhárom helyen „Adatvédelmi nyilatkozat” vagy „Privacy policy”. A cím: `https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html`. A lap forrása a `docs/gtl-ios-private-policy.html`. Feltöltés előtt ezt a fájlt a KLHome oldalra kell másolni, különben a reviewer a régi Androidos szöveget olvassa. Az App Store Connect Support URL mezője ugyanez a lap legyen.

A lap iOS adatfolyamot ír: a nyomvonal, a gyorsulás és a dőlés a telefon SQLite adatbázisában marad; a mentés a track adatbázist viszi, a letöltött térképfájlt nem; a MapKit, a keresés, az útvonal és a cím koordinátát vagy térképablakot küld az Apple-nek; az OSM- és a Turistautak-letöltésnél a kiszolgáló látja az IP-címet és a kért fájlt; háttérhely csak naplózás közben és Always engedéllyel; nincs fiók, hirdetés, követés.

### Privacy manifest

A manifest régen csak a UserDefaults okot deklarálta (`CA92.1`). A helyindex a térképfájl módosítási idejét olvassa, a letöltés előtt a kód a szabad lemezhelyet kéri le. Ezek kötelező ok-API-k. Hiányzó deklarációnál a feltöltés ITMS-91053 levéllel megáll, a build nem kerül review-ra.

A manifestben maradt a pontos hely, app-funkció, nem kapcsolt, nem követésre. Mellé került a fájlidő `C617.1` és a lemezhely `E174.1`. Ez a felhasználói lépéseket nem változtatja. A feloldott MapLibre 6.31.0 keretrendszer saját `PrivacyInfo.xcprivacy` fájllal érkezik, ezért külön manifestet nem kellett beleírni.

### Mindig engedély

Régen, ha a hely csak az app használata közben volt engedélyezve, az Indítás azonnal a rendszerszintű Always párbeszédet nyitotta, és ugyanabban a lépésben elindította a munkamenetet. A felhasználó a párbeszéd előtt nem látott saját mondatot arról, hogy a zárolt képernyős rögzítéshez kell a Mindig.

Most az Indítás egy saját lapot mutat. A lap azt írja, hogy zárolt képernyőn a rögzítéshez a Helyzet legyen Mindig, a kék jelző a Stopig látszik, és a Stop leállítja a háttérfrissítést. A Mindig engedélyezése ezután hívja a rendszer Always kérdését, és elindítja a munkamenetet. A csak az app használata közben ág Always kérés nélkül indítja a képernyőn lévő rögzítést. Ha a felhasználó később Always-t ad, ugyanaz a munkamenet bekapcsolja a háttérfrissítést és a kék jelzőt. Always engedélynél az Indítás továbbra is azonnal rögzít, magyarázó lap nélkül, mert a rendszerkérdés már nem esedékes.

### Csökkentett pontosság

Régen a felhasználó a rendszer párbeszédben választhatott hozzávetőleges helyet. A rögzítés így is elindult, és a track használhatatlan pontokból állt.

Most, ha a pontosság csökkentett, a naplózás előtt a rendszer ideiglenes teljes pontosságot kér. Az indok kulcsa `PreciseRoute`: a használható nyomvonalhoz pontos hely kell, angolul és magyarul. Ha a felhasználó nem adja meg, a munkamenet nem indul. A GPS fül kiírja, hogy a Beállításokban a Pontos hely kell, és van gomb a Helyzet beállítások képernyőre.

### Elutasított hely

Régen denied vagy restricted állapotban az Indítás egy láthatatlan állapotmezőbe írt, és a GPS fül „Várakozás a GPS-re” szöveget mutatott. A gomb halottnak látszott.

Most a GPS fül kiírja, hogy a helyzet ki van kapcsolva, és egy gomb a már meglévő Helyzet beállítások képernyőre visz. Onnan a rendszer Beállításai nyílnak. A láthatatlan angol állapot ezekre az ágakra nem íródik.

### Offline térkép letöltése

Régen a szabadhely-ellenőrzés 0 bájtos hosszal futott. 64 MB-nál több szabad helynél a letöltés elindult, a tényleges fájlméret nélkül. A háttérletöltés mobilhálózaton is mehetett, megerősítés és kiírt méret nélkül. Menet közben a megszakítás a 2 GB-os OSM vagy az 500 MB-os Turistautak plafonnál volt, nem a még szabad helynél. Két saját hiba csak angolul jelent meg.

Most a letöltés előtt egy HEAD kérés olvassa a `Content-Length` értéket. A Magyarország OSM fájl és a Turistautak zip ezt a választ megadja. Ha a hossz nem olvasható, a fájl nagyobb a plafonnál, vagy a szabad hely a 64 MB tartalékkal nem elég, a letöltés nem indul, magyar és angol hibaüzenettel. Mobilhálózaton egy megerősítés kell, a régió nevével és a várható mérettel. Megerősítés után a mobiladat engedélyezett marad. Wi-Fin a megerősítés kimarad, és a letöltés elindul, ha a méret és a hely rendben van. Menet közben a letöltés megáll, ha a leírt bájt átlépi a kezdéskor számolt keretet, vagy a szabad hely a tartalék alá esik. A `URLSession` saját hibája továbbra is a rendszer nyelvén jön.

### Mentés

Régen a track adatbázis és a térképfájlok is az Application Supportban voltak, és az iPhone mentése, az iCloudot is beleértve, mindkettőt vihette. A nyilatkozatnak és a binárisnak ugyanazt kell mondania a pontos hely sorsáról.

A track adatbázis továbbra is a mentésben van. A nyilatkozat ezt kimondja. Az Exports mappa a Fájlok appban marad, azt a felhasználó szándékosan menti ki. A `maps` könyvtár és a letöltött térképfájl `isExcludedFromBackup` jelzőt kap, mert egy országfájl több száz megabájt, és nem való a mentésbe.

### Térkép-felirat és névjegy

Régen az offline OSM sarokfelirat `© OpenStreetMap` volt. Az ODbL a produced workön a `© OpenStreetMap contributors` formát kéri, azon a képernyőn, ahol a térképadat látszik. Most ez a felirat van a sarokban, amíg letöltött OSM fájl van használatban. A névjegy ODbL mondata megmaradt.

A Turistautak sarokfelirat továbbra is `© Turistautak.hu`. A névjegy hozzáteszi, hogy a feltételek egyértelmű hivatkozást kérnek a lapra, ahol az adat látszik, és a fájl a saját használatra kerül a telefonra. Van link a `https://turistautak.hu` címre és a jogi nyilatkozatra. A letöltés bent maradt, mert a feltétel a saját használatra mentést engedi, ha a hivatkozás látszik.

A névjegy kapott egy MapLibre sort: MapLibre Native, BSD 2-Clause, és a 6.31.0 csomag copyright mondatai (MapLibre contributors, MapTiler.com, Mapbox). A bináris terjesztés ezt a szöveget kéri. Új a Támogatás sor: a nyilatkozat linkje és a `laszlo.kovary@gmail.com` cím. A Bitbucket tároló sora megmaradt, az nem a támogatás. Az App Store Connect Support URL a nyilatkozat lapja, nem a tároló gyökere.

### Ami nem változott

Az Elfogadom után a nyomkövető ugyanúgy nyílik. Always engedéllyel a zárolt képernyős rögzítés és a kék jelző a Stopig megmarad. Az app használata közben a zárolás továbbra is megállítja az új pontokat. Az online MapKit, a helykeresés, a koppintott útvonal, a cím, a mentett útvonalak, a GPX és a KMZ export a helyén van. A track adatbázis a telefonon marad, és a mentés viszi.

## Valódi iPhone

A szimulátor megmutatja a képernyőket és egy szimulált GPS-helyzetet. Ezekhez fizikai iPhone kell:

- Folyamatos nyomvonal zárolt képernyőn
- Barometrikus magasság
- Használható iránytűállás

## Ami az iPhone-on nincs

- Környezeti hőmérséklet. A hőmérséklet sora azt írja, hogy nincs érzékelő, és a hőmérséklet nem tárolódik.
- Külön domborzati raszter alaptérkép. A valós domborzat a MapKit terepe, nem domborzatárnyékoló kép. Az offline térkép lapos marad.

## Térkép funkciók

Ezek a jegyzetek a domborzatos kamerát, a menetirányú követést, a sebességszínt, a KMZ magasságot és a koppintott pontig vezető útvonalat írják le. Ugyanezek a lépések a Súgóban is ott vannak, a telefon nyelvén.

### 3D domborzat és dönthető kamera

Az Apple térkép standard, műhold és hibrid stílusa valós domborzatot használ. API-kulcs nem kell. Rögzítés közben a kamera kb. 52 fokos dőléssel indul, a 45–60 fokos tartományban. Két ujjal dönthető a térkép, és a következő követés ezt a dőlést tartja meg, 0 és 65 fok között. A műhold és a hibrid így navigációs appnak látszik.

Az észak-tárcsa koppintása visszaállítja az 52 fokot, és újra bekapcsolja a menetirányt.

A teljes track a képen felülnézet marad, észak felé, hogy a vonal beférjen.

A letöltött OSM vagy Turistautak térkép dönthető és követi az irányt. Nincs domborzat-hálója, a talaj lapos marad. Domborzatárnyékolás csak akkor van, ha magasságfájlok ülnek a térkép mellett.

### Menetirányú követés

Rögzítés közben a kamera a haladási iránnyal fordul, és a pozíció nyila is vele. 1 m/s-tól a GPS course az irány. Alatta az iránytű földrajzi iránya. Gyenge iránytűnél az utolsó jó irány marad, a térkép nem pörög. Menetirányú kameránál a nyíl a képernyő teteje felé mutat.

Az észak-tárcsa elfordul, így az N továbbra is északra mutat.

### Sebesség szerint színezett nyomvonal

Minden tárolt pontnak van sebessége. A vonal legfeljebb hat színt használ, lassútól gyorsig: kék `#3D5AFE`, türkiz `#1F8A80`, sárga `#F2C14E`, narancs `#E07A3D`, kármin `#C13B2E`, mélyvörös `#7A1530`. A térkép pöttyei az aktuális használat skálája. Csak akkor látszanak, ha színes vonal van a térképen. A lista kiírja a sávokat a választott mértékegységben, és a Beállításokban nyitva marad. Ha ez ki van kapcsolva, a pöttyök maradnak: koppintásra jönnek a sávok, újabb koppintásra eltűnnek. A HUD sebességszáma az aktuális sáv színét kapja. A határ alatti sebesség az alacsonyabb sáv. A sávok a használathoz vannak kötve, ezért egy új maximum nem festi újra a már megrajzolt vonalat.

Futás:

- kék 3,6 km/h alatt
- türkiz 3,6–5,8 km/h
- sárga 5,8–7,9 km/h
- narancs 7,9–10,8 km/h
- kármin 10,8–14,4 km/h
- mélyvörös 14,4 km/h fölött

Túra és gyaloglás:

- kék 3,6 km/h alatt
- türkiz 3,6–5,8 km/h
- sárga 5,8–7,9 km/h
- narancs 7,9–10,8 km/h
- kármin 10,8 km/h fölött

Kerékpár:

- kék 10,8 km/h alatt
- türkiz 10,8–21,6 km/h
- sárga 21,6–28,8 km/h
- narancs 28,8–39,6 km/h
- kármin 39,6–50 km/h
- mélyvörös 50 km/h fölött

Autó és motor:

- kék 28,8 km/h alatt
- türkiz 28,8–50,4 km/h
- sárga 50,4–79,2 km/h
- narancs 79,2–118,8 km/h
- kármin 118,8–130 km/h
- mélyvörös 130 km/h fölött

Repülő:

- kék 100 km/h alatt
- türkiz 100–200 km/h
- sárga 200–350 km/h
- narancs 350–500 km/h
- kármin 500–600 km/h
- mélyvörös 600 km/h fölött

Hajó:

- kék 7,2 km/h alatt
- türkiz 7,2–18 km/h
- sárga 18–28,8 km/h
- narancs 28,8–43,2 km/h
- kármin 43,2 km/h fölött

A hiányzó sebesség a leglassabb szín. A mentett útvonal ugyanezeket a színeket kapja. Az egyszerűsítés csak a rajzolt vonalat ritkítja; a megtartott pontok sebessége megmarad. A tárolt útvonal és a GPX vagy KMZ fájl továbbra is minden elfogadott pontot tartalmaz.

### KMZ valódi magassággal

A GPX a GPS-magasságot már az `ele` mezőbe írja. A KMZ most a vizuális felét is megcsinálja: ha bármely pontnak van véges GPS-magassága, a vonal és a Google Earth track `altitudeMode` absolute, és a koordinátában ez a magasság van. A magasság nélküli pont 0. Az indulás, szünet és megállás ikon a talajon marad.

Ha egyáltalán nincs magasság, a vonal a talajra simul.

A KMZ-t a Google Earthben megnyitva a vonal kiemelkedik a terepből. Repülésnél és hegyi túránál ez a látványos nézet. A Google Earth az absolute magasságot a WGS84 ellipszoidtól méri. A telefon tengerszinthez képesti magasságot tárol, ezért a vonal néhány tíz méterrel a rajzolt terep fölött vagy alatt ülhet. A fájl nincs átváltva.

Megosztás a Mentett útvonalakból. A fájl a Fájlok appban van: A(z) iPhone-omon → GPS Track Logger → Exports.

### Útvonal a koppintott pontig

Koppints a térképre, majd az Útvonalra. A MapKit gyalog, kerékpárral vagy autóval rajzol utat a saját fixtől addig a pontig. A túra és a futás gyalog, a kerékpár kerékpárral, az autó és a motor autóval megy. A repülőnek és a hajónak nincs illő úthálózata, ezért a kártya Gyalog, Kerékpár és Autó sort ad.

A kéréshez hálózat kell. A két koordinátát elküldi az Apple-nek. A naplózott track továbbra is csak a telefonon van. Fix nélkül a kártya azt írja: Nincs GPS. Út nélkül: Nincs útvonal.

Az út kék szaggatott vonal, külön a sebesség szerint színezett tracktől és a légvonalas Távolságtól. Az útvonal chipje törli. Új útvonal kérés megszakítja a még futó kérést.

### Rögzítés zárolt képernyőn

Az Indítás az előtérben rögzít, amint a hely engedélyezett. Zárolt képernyőn a nyomvonal csak akkor megy tovább, ha a Helyzet Mindig. A kék jelző a Stopig látszik. Ha a Mindig ugyanazon az Indításon jön meg, a háttérrögzítés azonnal bekapcsol. Az app használata közben a zárolás megállítja az új pontokat, és a cím alatt egy sor ezt kiírja. Beállítások → Rögzítés → Képernyő bekapcsolva naplózás közben csak a kijelzőt tartja ébren. Nem helyettesíti a Mindig engedélyt.

### App Store képek

Az App Store-nak nincs Google Play-s feature graphic helye (1024×500). Ennél az iPhone-alkalmazásnál a kötelező kép a 6,9 hüvelykes képernyőkép-sor. Az ikon a buildből jön, külön nem töltődik fel. iPad-készlet nem kell: a target csak iPhone (`TARGETED_DEVICE_FAMILY = 1`). Ha a 6,9 hüvelykes sor megvan, a 6,5 hüvelykes és a kisebb méretek az Apple skálázásával mennek, külön fájl nem kötelező.

A review jegyzet, sorokkal és javítással: [gtl-ios-review-hu.md](gtl-ios-review-hu.md).

#### Hova kerülnek

| Fájl | Méret | App Store Connect |
| --- | --- | --- |
| `docs/images/app-store/iphone-6.9-inch/en/01-map.png` … `04-saved-tracks.png` | 1320×2868 PNG, RGB, alfa nélkül | Az app iOS verziója → Screenshots → 6.9" Display, angol lokalizáció. Sorrend: 01, 02, 03, 04. |
| `docs/images/app-store/iphone-6.9-inch/hu/` ugyanaz a négy név | 1320×2868 PNG, RGB, alfa nélkül | Ugyanaz a 6.9" hely, magyar lokalizáció. |
| `docs/images/app-store/app-icon/app-icon-1024.png` | 1024×1024 PNG, RGB, alfa nélkül, sarok nélkül | Nem külön mező. Az ikont a feltöltött build adja. Csere: a fájl menjen a `gtl/Assets.xcassets/AppIcon.appiconset/AppIcon.png` helyére. |

Egy lokalizációhoz 1–10 képernyőkép kell. Itt négy van, állóban, mert az app csak álló tájolást enged.

#### Mit mutat a négy kép

1. `01-map.png` — Térkép, naplózás, sebesség szerint színezett vonal, HUD, észak-tárcsa.
2. `02-route.png` — Útvonal összesítő és magassági vonal.
3. `03-compass.png` — MAG / TRUE és a számlap.
4. `04-saved-tracks.png` — Mentett útvonalak, Térképen, GPX, KMZ, Törlés.

Az angol és a magyar sor ugyanazt a négy képernyőt mondja, a felirat a nyelv. A kezdőképernyő neve magyarul „GTL GPS útvonal napló”; a képen a fejléc a kóddal együtt „GPS Track Logger”. A Start és a Stop a jelenlegi gomb felirata, mindkét nyelven.

Ezek összeállított képek, a 6,9 hüvelykes méretre. A 2.3.3 szerint a feltöltött kép a futó appot mutassa. Feltöltés előtt ugyanaz a négy képernyő jöjjön egy 6,9 hüvelykes iPhone-ról vagy szimulátorról (1320×2868), ha a futó felület eltér. A mentett útvonal képe olvasható nevet mutat (Kerékpár, Túra, Autó). A lista a kódban még a tárolt nyers típust írja; amíg ez így van, a `04-saved-tracks.png` ne menjen fel.
