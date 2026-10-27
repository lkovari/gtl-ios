# GPS Track Logger — App Store feltöltés fizetős fejlesztői fiókkal

Ez a lista attól a ponttól indul, amikor az Apple Developer Program tagságod már **jóváhagyott és aktív** (a fizetés önmagában kevés: a tagság e-mailje megérkezett, a [developer.apple.com/account](https://developer.apple.com/account) oldal belépés után a programot aktívnak mutatja).

A lépések ehhez a projekthez szólnak: `gtl.xcodeproj`, scheme `gtl`, csak iPhone, iOS 17, angol és magyar.

Hivatalos felületek:

- Fejlesztői fiók: [developer.apple.com/account](https://developer.apple.com/account)
- Áruház: [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
- Irányelvek: [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- Connect súgó: [developer.apple.com/help/app-store-connect](https://developer.apple.com/help/app-store-connect/)

A review szempontjai és a már javított pontok: [gtl-ios-review-hu.md](gtl-ios-review-hu.md). A képernyőképek helye: [README-hu.md](README-hu.md) „App Store képek” szakasza.

## Az app rögzített adatai

Ezeket a Connectben és az Xcode-ban ugyanígy kell megadni. A bundle azonosító az első verzió után nem cserélhető.

| Mező | Érték |
| --- | --- |
| Xcode-projekt | `gtl.xcodeproj` |
| Scheme | `gtl` (a teszt scheme-eket ne archiváld) |
| Áruházi név, angol | GPS Track Logger |
| Kezdőképernyő, angol | GPS Track Logger |
| Kezdőképernyő, magyar | GTL GPS útvonal napló |
| Bundle azonosító | `com.lkovari.mobile.apps.gtl` |
| Verzió (`MARKETING_VERSION`) | 1.0.1 |
| Build (`CURRENT_PROJECT_VERSION`) | 33, ha ez a szám még soha nem ment fel. Új binárisnál a build szám nő, az 1.0.1 maradhat. |
| Csapat a projektben | `2885GLR3V7`, automatikus aláírás |
| Minimum rendszer | iOS 17.0 |
| Készülék | csak iPhone, álló tájolás |
| Kategória a binárisban | Navigation (`public.app-category.navigation`) |
| Titkosítás | `ITSAppUsesNonExemptEncryption` = hamis (HTTPS, mentes) |
| Háttérmód | csak `location` |
| Követés, fiók, hirdetés | nincs |
| Támogatási e-mail az appban | `laszlo.kovary@gmail.com` |
| Adatvédelmi és támogatási URL | `https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html` |
| A lap forrása | `docs/gtl-ios-private-policy.html` |

A projektfájlban a csapat `2885GLR3V7`. Ha a fizetős tagság **ugyanahhoz az Apple ID-hoz** tartozik, ez a csapat marad. Ha a fizetős fiók másik csapat (másik Apple ID, vagy szervezet), az Xcode Signing & Capabilities alatt azt a csapatot kell választani, és a bundle azonosítót annak a csapatnak kell birtokolnia.

## Sorrend egy mondatban

Szerződések, élő adatvédelmi lap, csapat az Xcode-ban, App ID, archive, feltöltés, Connect-rekord, adatvédelem és korhatár, szövegek, képernyőképek, build hozzárendelése, review-jegyzet, beküldés.

A metaadatot töltheted, amíg a build felkerül. Beküldeni csak akkor lehet, ha a build feldolgozása kész, és minden kötelező mező zöld.

---

## 1. Tagság, Apple ID, kétlépcsős azonosítás

1. Nyisd meg a [developer.apple.com/account](https://developer.apple.com/account) oldalt azzal az Apple ID-val, amelyik a program tagja.
2. Ellenőrizd, hogy a Membership oldal állapota Active, a lejárat egy év múlva van, és a szereped Account Holder vagy Admin. Archive-hoz és az első alkalmazás létrehozásához Account Holder vagy Admin kell. Developer szerep binárist tölthet fel, az alkalmazásrekordot gyakran nem hozhatja létre.
3. Az Apple ID-n a kétlépcsős azonosítás legyen bekapcsolva. Enélkül az Xcode és a Connect kiírja, és nem enged tovább.
4. Jegyezd fel a Team ID-t a Membership oldalon. Ha ez `2885GLR3V7`, a projekt csapata egyezik. Ha más, a 4. lépésben azt választod.

Egyéni tagságnál az áruházban a fejlesztő neve a tagságon lévő személynév. Szervezeti tagságnál a cégnév. Ezt alkalmazásonként nem írod be: a fiók adja. Az első alkalmazás előtt nézd meg, ez a név mehet-e a listaoldalra.

## 2. Szerződések az App Store Connectben

1. Lépj be: [appstoreconnect.apple.com](https://appstoreconnect.apple.com).
2. Nyisd meg a Business részt (Üzlet), azon belül az Agreements, Tax, and Banking (Szerződések, adók és banki adatok) oldalt.
3. Fogadd el a függőben lévő Free Apps és, ha kéri, a Paid Apps szerződést. A gomb az Account Holdernek aktív.
4. Ez az alkalmazás ingyenes, alkalmazáson belüli vásárlás nélkül. Ingyenes alkalmazáshoz bankszámla és adóűrlap nem kell. Bankszámla és adó csak akkor kell, ha az ár nem Free, vagy később vásárlást teszel az appba.
5. Frissítsd az oldalt. A szerződés állapota Active legyen. Függő szerződésnél a beküldés gomb a verzió oldalon nem végez.

Ugyanitt, ha a fiók új, néha külön Account Holder adatot kér (cím, telefon). Töltsd ki, mielőtt az első appot létrehozod.

## 3. Az adatvédelmi lap legyen elérhető

A review a Support URL-t és a Privacy Policy URL-t megnyitja. A binárisban a link már ez:

`https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html`

A forrás a repóban: `docs/gtl-ios-private-policy.html`.

1. Másold ezt a fájlt a KLHome oldalra, arra az útvonalra, amit a fenti cím kér, a feltöltés előtt, minden nyilatkozat-változás után (legutóbb 2026. október 3., a „használat közben” zárolt rögzítés és a letöltési tükör miatt). A régi `gtl-privacy-policy.html` az Android alkalmazást írja le. Az iOS cím másik fájl. A `private-policy` fájlnév marad, mert a cím bele van égetve a binárisba; átirányítás nem kell, mert a cím nem változik.
2. Várj, amíg a GitHub Pages kiadja a lapot.
3. Nyisd meg a címet inkognitóban, telefonos hálózaton is.
4. A lapnak iOS szöveget kell mutatnia: MapKit, a nyomvonal SQLite-ban a telefonon, a mentés viszi az adatbázist, a letöltött térkép kimarad a mentésből, az útvonal és a cím kérése koordinátát küld az Apple-nek, az OSM-fájl a Hochschule Esslingen tükréről jön (`ftp-stud.hs-esslingen.de`), az OSM és a Turistautak letöltésénél a kiszolgáló látja az IP-címet és a kért fájlt, a hely csak „Az app használata közben” engedéllyel, Mindig kérés nélkül, nincs Google Fonts, nincs fiók, nincs hirdetés, nincs követés. A kapcsolati cím: `laszlo.kovary@gmail.com`.
5. A lapnak angolul és magyarul is meg kell nyílnia (a lap saját nyelvváltója).
6. A címet ezután írd be a Connect Support URL és Privacy Policy URL mezőjébe. Mindkét mező ugyanaz a cím. A Bitbucket-gyökér támogatásnak nem elég.

Ha a cím 404, vagy a szöveg még Android (Google Térkép, Maps SDK, Room), a beküldéssel várj. Az 5.1.1 ezt a lapot veti össze a binárissal.

## 4. Az Apple ID az Xcode-ban

1. Xcode → Settings → Accounts.
2. Add a bal alsó pluszszal azt az Apple ID-t, amelyik a fizetős csapat tagja. A kétlépcsős kód kell.
3. A csapat sora mellett a szerep Admin vagy Account Holder legyen, a program Apple Developer Program.
4. Nyisd meg a `gtl.xcodeproj` fájlt.
5. A bal oldali projektnavigátorban a `gtl` projekt, majd a `gtl` target (az alkalmazás, nem a `gtlTests` és nem a `gtlUITests`).
6. Signing & Capabilities, minden konfigurációra (Debug és Release):
   - Automatically manage signing bekapcsolva.
   - Team: a fizetős csapat. Ha a Team ID `2885GLR3V7`, ez a sor egyezik a projektfájllal.
   - Bundle Identifier: `com.lkovari.mobile.apps.gtl`.
7. A Signing hibasornak üresnek kell lennie. Az első alkalommal az Xcode kéri, hogy hozzon létre fejlesztői tanúsítványt. Fogadd el.
8. Background Modes alatt a Location updates legyen bekapcsolva. Ez a `gtl/Info.plist` `UIBackgroundModes` / `location` sora. Más háttérmód (audio, fetch, remote notification) ne legyen bekapcsolva.
9. Külön entitlement a helyhez nem kell. Push, Associated Domains, iCloud, App Groups ennél az appnál nincs.

Futtasd a `gtl` scheme-et egy saját iPhone-on (iOS 17 vagy újabb), a kábelen vagy vezeték nélkül, Development aláírással. A szimulátor a képernyőket megmutatja. Zárolt képernyős nyomvonal, barométer és használható iránytű csak fizikai iPhone-on ellenőrizhető. Ezt a review előtt egyszer végig kell vinni, mert a review jegyzet ezt ígéri.

## 5. App ID a fejlesztői portálon

Automatikus aláírásnál az Xcode az első sikeres, csapathoz kötött buildnél regisztrálja az azonosítót. Kézzel is megcsinálhatod, és a Connect rekord előtt így biztosan létezik.

1. [developer.apple.com/account](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → Identifiers.
2. Plusz → App IDs → App.
3. Description: `GPS Track Logger`.
4. Bundle ID, Explicit: `com.lkovari.mobile.apps.gtl`.
5. Capability: hagyd üresen, ami a listában extra jogosultság. A helyháttér a plistből jön, nem egy portál-capability.
6. Register.

Ha az azonosító már létezik ennél a csapatnál, ne hozz létre másikat. Wildcard (`com.lkovari.*`) App Store feltöltéshez nem jó. Explicit azonosító kell.

## 6. Verzió és build szám

A felhasználó a verziót látja: `1.0.1`. Az Apple a build számot használja arra, hogy két binárist megkülönböztessen. Egy verzió alatt minden feltöltött build száma egyedi és növekvő.

1. Xcode → `gtl` target → General:
   - Version: `1.0.1`
   - Build: `33`, ha a 33 még nincs az App Store Connecten ennél a bundle-nél.
2. Ha a 33-at már feltöltötted (akár elutasították, akár feldolgozás alatt áll), a Build legyen `34`, aztán `35`, és így tovább. A Version marad `1.0.1`, amíg a felhasználónak szánt számot nem akarod növelni.
3. A két szám a `project.pbxproj` `MARKETING_VERSION` és `CURRENT_PROJECT_VERSION` mezője, Debug és Release ágon egyszerre.

A névjegy képernyője a verziót a bundle `CFBundleShortVersionString` mezőjéből olvassa, így a névjegy és a General Version mező mindig ugyanazt a számot mutatja.

## 7. Feltöltés előtti ellenőrzés ezen a fán

Ezek a review és a képfeltöltés kapui. A kód review-ja a másik fájlban van; itt csak az van, ami a beküldés napján eldől.

1. A 3. lépés URL-je él, és iOS szöveget mutat.
2. Saját iPhone-on: Elfogadom után a napló megnyílik. Az Elutasítom a nyilatkozaton marad, rögzítés nélkül.
3. Hely „Az app használata közben”, valódi iPhone, iOS 17 vagy újabb, tiszta telepítés (az appot előbb töröld): Indítás, zárolás, 10–15 perc mozgás, feloldás. A nyomvonal folytonos. A kék jelző zárolt képernyőn nem látszik; feloldás után a kezdőképernyőn vagy egy másik appban az óra körül kék háttérként vagy kapszulaként látszik, és a Leállítás után eltűnik. Engedély: Beállítások → Adatvédelem és biztonság → Helymeghatározás → az app → „Az app használata közben”, „Pontos hely” bekapcsolva. Mindig engedélyt az app nem kér. **Nincs még elvégezve.**
4. Ugyanez a Home-ra küldött appal, néhány percig. **Nincs még elvégezve.**
5. Kényszerített bezárás (appváltó) rögzítés közben: a rögzítés leáll, és magától nem folytatódik. **Nincs még elvégezve.**
6. Csökkentett pontosság: a rögzítés a pontos hely nélkül nem indul, és figyelmeztetés jön Beállítások gombbal. Magyar rendszeren az ideiglenes pontos hely ablaka a `PreciseRoute` magyar mondatát mutatja („A használható nyomvonalhoz pontos hely kell.”). **Nincs még elvégezve.**
7. Megtagadott hely: a Térkép fülön az Indítás és a helyzetgomb figyelmeztetést ad, a Beállítások megnyitása gomb a rendszer Beállításaiba visz. A GPS fül is elmondja.
8. Első Indítás új telepítésen: az engedély megadása után a rögzítés második koppintás nélkül elindul.
9. Az `UIRequiredDeviceCapabilities` (`gps`, `location-services`) miatt csak Wi-Fi-s iPadre az app nem telepíthető; mobilhálózatos iPadre igen. iPad szimulátoron és lehetőleg valódi, mobilhálózatos iPaden (kompatibilitási mód): nyilatkozat, a négy fül, minden menüpont, a letöltőlista kontinens-csoportjai, megosztás üresen és egy útvonallal, Indítás és Leállítás. Csak Wi-Fi-s iPaden az Indítás utáni gyenge GPS a Térkép fülön is látszik („A GPS minősége túl alacsony”). **Nincs még elvégezve.**
10. Online Apple térképen az Apple logó és a Legal link látszik, a nyitott sebességskála nem takarja. Szimulátorban ellenőrizve (2026. október 3.); valódi iPhone-on még egyszer nézd meg.
11. Hálózati katalógus-teszt a tükörrel: `GTL_NETWORK_TESTS=1` mellett a `gtlTests/MapCatalogNetworkTests` mind a 37 címre 200-at ad, és mindegyik a plafon alatt van.
12. Külső TestFlight-kör legalább egy másik tesztelővel. **Nincs még elvégezve.**
13. Adatvédelmi nyilatkozat link: az első képernyőn, a Beállításokban és a Súgóban. A cím a 3. lépés URL-je.
14. Névjegy: OSM `© OpenStreetMap contributors` mondat, Turistautak link, MapLibre copyright, támogatás e-mail, Hibanapló gomb, a készülék típusa és rendszerverziója.
15. Offline OSM sarok: `© OpenStreetMap contributors`. Turistautak sarok: `© Turistautak.hu`. Online módban nincs saroksáv.
16. A `docs/images/app-store/iphone-6.9-inch/` nyolc képe a futó app felvétele. Feltöltés előtt mindegyiket vesd össze a feltöltött builddel; ami eltér, azt készítsd újra (lásd a 15. lépést). A `06-saved-tracks.png` olvasható használati nevet mutat, és a lista a kódban is ezt írja.
17. Az ikon a buildből jön. Alfa csatorna és előre lekerekített sarok nélkül, 1024×1024. A `docs/images/app-store/app-icon/app-icon-1024.png` élesebb változat; ha cseréled, a `gtl/Assets.xcassets/AppIcon.appiconset/AppIcon.png` helyére kerül, archive előtt.

Release fordítás a gépen, aláírással, a feltöltés előtt:

```sh
xcodebuild -project gtl.xcodeproj -scheme gtl \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  build
```

A scheme tesztjei a szimulátoron, a szokásos parancs a [README-hu.md](README-hu.md) elején van. A teszt nem helyettesíti az archive-ot.

## 8. Archive

Az archive Release konfiguráció, áruházi aláírásra készül. Szimulátorra archive nem készül.

1. A scheme a `gtl`. Product → Scheme → `gtl`.
2. A céleszköz: Any iOS Device (arm64). Konkrét iPhone kiválasztva a Product → Archive menü szürke, vagy fejlesztői buildet csinál.
3. Product → Archive.
4. Az első archive-nál az Xcode létrehozza az Apple Distribution tanúsítványt és az App Store provisioning profile-t. A kulcskarika kérheti a bejelentkezést és a „Always Allow” választ a codesignhoz. Fogadd el.
5. Ha „No signing certificate” vagy „No profiles for com.lkovari.mobile.apps.gtl” jön: Signing & Capabilities, a fizetős csapat, Automatically manage signing, majd Xcode → Settings → Accounts → a csapat → Manage Certificates → plusz → Apple Distribution. Utána az archive újra.
6. Kész archive után megnyílik az Organizer (Window → Organizer). A sor: GPS Track Logger, verzió 1.0.1, build 33 (vagy amit megemeltél), dátum.

Validate App, még feltöltés előtt:

1. Az Organizerben az archive → Validate App.
2. App Store Connect distribution.
3. Upload symbols: bekapcsolva. Az appnak nincs külön bitkód-kapcsolója, amit kézzel kellene állítani; az Xcode alapja maradjon.
4. Automatically manage signing, a fizetős csapat.
5. A vége legyen succeeded. A figyelmeztetéseket olvasd el. Hiányzó privacy manifest (ITMS-91053, ITMS-91061), hiányzó ikon, vagy aláírási hiba itt megáll. Ezeket javítsd, a build számot emeld, és archiválj újra. Ugyanaz a build szám másodszor nem tölthető fel.

## 9. Feltöltés az Organizerből

1. Ugyanaz az archive → Distribute App.
2. Custom helyett az App Store Connect útvonal.
3. Upload (Export csak akkor, ha Transporterrel akarod felvinni; lásd lent).
4. A szimbólumok menjenek fel, az aláírás automatikus, a csapat a fizetős csapat.
5. Upload. A végén a siker azt jelenti, hogy a csomag az Apple-hez elindult. A feldolgozás ezután még 5–30 perc, néha tovább.

App Store Connect → a létrejött app (a 10. lépés) → TestFlight. A build először Processing, aztán egy sárga figyelmeztetés, ha hiányzik az export-megfelelőség, majd kész. Amíg Processing, a verzió oldal build-választója üres.

Ha a binárisban az `ITSAppUsesNonExemptEncryption` hamis, az export kérdés gyakran elmarad. Ha a TestFlight mégis kéri:

- Az app használ titkosítást? A HTTPS igen.
- Mentes a dokumentációs kivétel alól? Igen. Csak a rendszer HTTPS-e, saját titkosító algoritmus nincs.
- A franciaországi külön nyilatkozat ehhez a mentes HTTPS-hez nem kell.

Ezt a választ a build mellett mentsd. A következő build ugyanezt örökli, amíg a plist kulcs hamis marad.

### Feltöltés Transporterrel

Ha az Organizer upload elakad:

1. Az Organizer → Distribute App → Export, method App Store Connect. A gép kap egy `.ipa` fájlt.
2. A Transporter a Mac App Store-ból jön. Ugyanazzal az Apple ID-val jelentkezel be.
3. Húzd be az `.ipa` fájlt, Deliver.
4. A feldolgozás ugyanúgy a TestFlight listában jelenik meg.

Parancssori archive, ha az Organizer helyett ezt használod. A cél `generic/platform=iOS`, a konfiguráció Release:

```sh
xcodebuild -project gtl.xcodeproj -scheme gtl \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/gtl.xcarchive" \
  archive
```

Az export egy `ExportOptions.plist` fájllal megy, `method` = `app-store-connect`, `teamID` = a fizetős csapat azonosítója, `uploadSymbols` = igaz, `signingStyle` = `automatic`. Utána `xcodebuild -exportArchive`. Az `.ipa` a Transporterbe kerül. Az Organizer ugyanezt a tanúsítványt használja, kevesebb plisttel.

## 10. Az alkalmazásrekord létrehozása

Ezt a bundle regisztrációja után csináld. A build felkerülhet előtte is: a Connect a bundle azonosító alapján később ide köti. Áttekinthetőbb, ha a rekord már létezik, amikor a build Processingből kilép.

1. App Store Connect → Apps → plusz → New App.
2. Platforms: iOS. A macOS, visionOS, tvOS jelölő üres.
3. Name: `GPS Track Logger`. Ez az áruházi név, legfeljebb 30 karakter, és foglalt névre a mentés hibát ad. 2026. október 3-án a pontos „GPS Track Logger” név a nyilvános App Store-keresésben nem szerepelt; közeli, de más nevek: „GPS Tracks & Logger - MyGPSLog” (id 6736848229) és „iRoutesShare -GPS Track Logger” (id 6756664144). Egy rejtett vagy foglalt rekordot a keresés nem mutat, ezért a Connect válasza dönt. Tartalék, ha a Connect foglaltnak jelzi: `GTL GPS Track Logger` (20 karakter). Ilyenkor csak az áruházi név változik; a kezdőképernyő neve (`CFBundleDisplayName`), a nyilatkozat és a képfeliratok csak akkor követik, ha a név tényleg cserélődik.
4. Primary language: English (U.S.). A forrásszövegek angolok. A magyar lokalizációt a következő lépésben adod hozzá. A hiányzó fordítás az elsődleges nyelvre esik vissza.
5. Bundle ID: a legördülőből `com.lkovari.mobile.apps.gtl`. Ha nincs a listában, az 5. lépés App ID-ja még nem ezen a csapaton van, vagy a rekordot túl korán nyitottad. Az azonosító a létrehozás után nem módosítható.
6. SKU: belső azonosító, a felhasználó nem látja, később nem módosítható. Használd: `gtl-ios`.
7. User Access: Full Access, ha egyedül vagy a fiókban.
8. Create.

## 11. App Information, ár, elérhetőség

Az App Information (nem a verzió oldal) mezői ritkán változnak.

1. Bal oldalon App Information.
2. Subtitle itt még üres lehet; a felirat a verzió lokalizációjánál is kitölthető. Lásd a 14. lépés szövegeit.
3. Category, Primary: Navigation. Secondary: Travel, ha a felület másodlagos kategóriát kér. A bináris `LSApplicationCategoryType` értéke navigation, azzal egyezzen az elsődleges.
4. Content Rights: az app harmadik fél térképadatát jeleníti meg (Apple MapKit, OpenStreetMap ODbL, Turistautak.hu a saját feltételeivel, MapLibre BSD). A jelölő azt mondja, hogy rendelkezel a megjelenítés jogával. Az OSM hozzárendelés a térkép sarkában és a névjegyben van, a Turistautak hivatkozás és a MapLibre copyright a névjegyben van.
5. Age Rating: a 13. lépés. License Agreement: az Apple szokásos EULA-ja elég, saját szöveg nem kell.
6. Pricing and Availability.
   - Price: Free. Ingyenes appnál ársávot nem választasz.
   - Elérhetőség: minden ország, vagy szűkítsd, ha csak bizonyos piacra akarod. Magyarország egyedül is választható; az angol lokalizáció ettől még megmarad.
   - Pre-order nem kell az első kiadáshoz.
7. Save.

## 12. Adatvédelem a Connectben

Az App Privacy űrlap és a `gtl/PrivacyInfo.xcprivacy` ugyanazt mondja. A manifest `NSPrivacyCollectedDataTypes` tömbje üres: az Apple meghatározásában „gyűjtés” az, ami elhagyja a készüléket és a fejlesztőhöz vagy partneréhez kerül. A nyomvonal a telefonon marad, a MapKit-kéréseket az Apple szolgálja ki, a fejlesztő nem fér hozzájuk.

1. Bal oldalon App Privacy → Get Started, vagy Edit, ha már van válasz.
2. Adatkapcsolás követéshez (tracking): Nem. Nincs ATT-párbeszéd, nincs reklám-SDK, a manifest `NSPrivacyTracking` értéke hamis.
3. Gyűjtötök adatot ebből az alkalmazásból: **Nem** (Data Not Collected). Precise Location sort ne jelölj. A manifest üres gyűjtött-adat tömbje ezzel egyezik.
4. Publish / Save. A termékoldalon a címke: Data Not Collected.

A nyilatkozat lapja részletesebb, mint a címke: a naplózott nyomvonal a telefonon marad, a mentés az adatbázist viszi, a letöltött térképet nem, a MapKit keresés, útvonal és cím az Apple-nek küldi a kéréshez kellő koordinátát vagy térképablakot. A címkének a manifesttel kell egyeznie. A lapnak a futó alkalmazással kell egyeznie.

## 13. Korhatár

A kérdőív az App Information → Age Rating alatt van. Az Apple a kérdéseket néha átnevezi; a tartalom szerint válaszolj. Ennek az appnak a várható eredménye 4+.

Minden gyakoriság None / None of the above / Infrequent sem, ahol a skála erőszak, szexualitás, trágárság, horror, szerencsejáték, verseny, alkohol, dohány, kábítószer.

Külön válaszok, ahogy a varázsló hozza őket:

- Korlátlan webes tartalom: Nem. A nyilatkozat link és a Turistautak link Safari nézetet nyithat, ez nem beépített böngésző.
- Felhasználók által létrehozott megosztott tartalom: Nem. A GPX és a KMZ a saját telefonon és a rendszer megosztójában marad, nyilvános közösségi tér nincs.
- Üzenetküldés, hirdetés, loot box, szerencsejáték: Nem.
- Made for Kids / Gyerekek kategória: Nem. A gyerek kategória külön szabály, és egy helymeghatározó appot oda tenni nem szabad.

Mentsd a kérdőívet. Az eredmény 4+ legyen. Ha a varázsló magasabb korhatárt ad, nézd meg, melyik kérdés kapott gyakoriságot, és állítsd None-ra, ha a tartalom tényleg üres.

## 14. Verzióoldal: szövegek angolul és magyarul

Bal oldalon az iOS App verzió, állapot Prepare for Submission. Felül a nyelv. Először az English (U.S.) lokalizáció, aztán plusz → Hungarian.

A promóciós szöveg review nélkül cserélhető később. A leírás, a felirat, a kulcsszavak és a képernyőképek a verzióval együtt mennek review-ra.

Karakterhatárok: név 30, felirat 30, promóciós szöveg 170, kulcsszavak 100 (a vessző is számít), leírás 4000.

### English (U.S.)

Name:

```text
GPS Track Logger
```

Subtitle:

```text
GPS routes on your iPhone
```

Promotional text:

```text
Record a route on this iPhone. The track stays on the phone. Share it as GPX or KMZ.
```

Description:

```text
GPS Track Logger records a route on your iPhone and keeps the accepted points in a database on the phone.

Log a walk, run, hike, ride, drive, flight, or boat trip. The line is colored by speed. Saved routes open on the map or leave the phone as GPX 1.1 and KMZ, through the share sheet or the Files app.

Online maps are Apple Maps: standard, satellite, and hybrid. Place search, a route to a point you tap, and an address lookup send Apple the coordinate or the map area needed for that request. The logged track is not uploaded to the developer, and nothing stored on the phone is shared with a third party.

Offline maps use one downloaded region at a time, OpenStreetMap or Turistautak.hu. The file stays on the phone. OpenStreetMap is credited on the map. Turistautak.hu and MapLibre are credited in About.

The compass shows magnetic and true heading. When the iPhone has a barometer, barometric altitude is stored with the route.

Location is used only While Using the App; the app never asks for Always. After you tap Start, recording continues while the screen is locked or another app is open, with the blue location indicator, until you tap Stop. Precise Location is required to start a recording.

There is no account, no advertising, and no tracking.

Continued use of GPS running in the background can dramatically decrease battery life.
```

Keywords (100 karakteren belül, szóköz a vessző után nincs):

```text
gps,track,gpx,kmz,hike,bike,run,compass,offline,logger,route,walk,altitude
```

Support URL:

```text
https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html
```

Marketing URL: üresen hagyható.

Privacy Policy URL: ugyanaz, mint a Support URL.

Copyright: az év és a tagságon szereplő jogtulajdonos neve, például `2026` és a fiók egyéni vagy céges neve. A szöveg egyezzen a névjegy copyright sorával.

### Hungarian

A verzió oldal tetején a nyelv plusz gombja → Hungarian.

Name:

```text
GTL GPS útvonal napló
```

Subtitle:

```text
GPS-útvonal a telefonon
```

Promotional text:

```text
Rögzíts útvonalat ezen az iPhone-on. A nyomvonal a telefonon marad. Megosztás GPX-ben vagy KMZ-ben.
```

Description:

```text
A GPS Track Logger útvonalat rögzít az iPhone-on, és az elfogadott pontokat a telefon adatbázisában tartja.

Gyaloglás, futás, túra, kerékpár, autó, motor, repülő vagy hajó. A vonal színe a sebesség. A mentett útvonal megnyílik a térképen, vagy GPX 1.1 és KMZ formában kimegy a megosztón és a Fájlok appon.

Az online térkép az Apple térképe: standard, műhold és hibrid. A helykeresés, a koppintott pontig kért útvonal és a címlekérdezés az Apple-nek küldi az ehhez szükséges koordinátát vagy térképablakot. A naplózott nyomvonal nem kerül a fejlesztő szerverére, és a telefonon tárolt adat nem kerül harmadik félhez.

Az offline térkép egy letöltött régió: OpenStreetMap vagy Turistautak.hu. A fájl a telefonon marad. Az OpenStreetMap hozzárendelése a térképen van. A Turistautak.hu és a MapLibre a névjegyben van.

Az iránytű mágneses és valódi északot mutat. Ha az iPhone-ban van barométer, a barometrikus magasság az útvonallal együtt tárolódik.

Az app csak „Az app használata közben” helyengedélyt kér, Mindig engedélyt nem. Az Indítás után a rögzítés zárolt képernyőn és másik app mellett is folytatódik, a kék helyjelzővel, amíg a Leállítást meg nem nyomod. A rögzítéshez pontos hely kell.

Nincs fiók, nincs hirdetés, és nincs követés.

A háttérben folyamatosan futó GPS jelentősen csökkentheti az akkumulátor üzemidejét.
```

Keywords:

```text
gps,útvonal,nyomvonal,gpx,kmz,túra,kerékpár,futás,iránytű,térkép,magasság
```

Support URL és Privacy Policy URL: ugyanaz az angol mezőkön megadott cím. A Connect a támogatás és a nyilatkozat címét lokalizációnként kéri; mindkét nyelven ugyanaz az URL megy, mert a lap mindkét nyelvet tudja.

A What’s New az első verziónál gyakran nem jelenik meg. Ha a felület mégis kéri, egy mondat elég: első App Store kiadás.

## 15. Képernyőképek

iPad-készlet nem kell. A target csak iPhone (`TARGETED_DEVICE_FAMILY = 1`).

A kötelező sor a 6,9 hüvelykes kijelző. A fájlok 1320×2868 PNG-k, RGB, alfa nélkül, állók. Ha ez a sor megvan, a 6,5 hüvelykes és a kisebb iPhone-méretek az Apple skálázásával készülnek. Külön fájl nem kötelező. App előnézeti videó nem kell.

A képek helye: `docs/images/app-store/iphone-6.9-inch/`. Mind a nyolc a futó app felvétele, angol felülettel, készülékkeretben, angol felirattal.

| Sorrend | Fájl | Mit mutat |
| --- | --- | --- |
| 1 | `docs/images/app-store/iphone-6.9-inch/01-map.png` | Térkép, sebesség szerint színezett nyomvonal, jelmagyarázat |
| 2 | `…/02-route.png` | Útvonal: sebesség számlap, az út adatai, magassági profil |
| 3 | `…/03-gps.png` | GPS: koordináták, pontosság, magasság, a fix kora |
| 4 | `…/04-compass.png` | MAG / TRUE és a számlap |
| 5 | `…/05-offline-maps.png` | Offline térképek: Turistautak.hu és az OSM-országlista |
| 6 | `…/06-saved-tracks.png` | Mentett útvonalak miniatűrrel és adatokkal |
| 7 | `…/07-settings.png` | Beállítások |
| 8 | `…/08-about.png` | Névjegy |

Feltöltés:

1. A verzió oldalon a nyelv English (U.S.).
2. Previews and Screenshots → iPhone, 6.9" Display.
3. Húzd be a nyolc képet 01-től 08-ig.
4. Válts Hungarian nyelvre. Amíg nincs magyar felületű készlet, ugyanez a nyolc kép megy, ugyanabban a sorrendben (az Apple elfogadja, a felirat angol marad). Ha elkészül a magyar sorozat, kerüljön egy `hu/` almappába, és az menjen fel.
5. **A mostani nyolc kép már nem a végleges felület** (2026. október 3.): a főgomb magyarul Indítás / Leállítás, az offline térképek listája kontinensek szerint csoportosít „EU” előtag nélkül, a Mindig-lap és a cím alatti zárolási sor megszűnt, a mentett útvonalaknál új Rögzített pontok gomb van, a Névjegyben Hibanapló gomb és a készülék típusa látszik. A `05-offline-maps.png` 2026. október 3-án újra elkészült (kontinens-csoportok, „EU” nélkül). A `06-saved-tracks.png` is újra elkészült (2026. október 3.): nyitott alsó menüvel, benne a Recorded points gombbal. A többi hat angol kép a mostani felületet mutatja (a `08-about.png`-n az Alkalmazás adatai kártya csukva van, ezért a változott készüléksor nem látszik). A magyar készletnél a főgomb Indítás.
6. A kép a futó appot mutassa (irányelv 2.3.3). Feltöltés előtt minden képet vess össze a feltöltött builddel. Ha egy képernyő megváltozott, készíts új képet egy 6,9 hüvelykes iPhone-ról vagy szimulátorról, 1320×2868, alfa nélkül. A `05-offline-maps.png` a C1 javítás utáni felület (a sorok alatt a fájlméret).

Az ikont külön mezőbe nem töltöd. A 1024-es ikon az archive-ban van.

## 16. Build hozzárendelése a verzióhoz

1. Várj, amíg a TestFlight oldalon a build Processingből átmegy, és az export válasz megvan.
2. A verzió oldalon a Build szakasz plusz gombja.
3. Válaszd az 1.0.1 (33) sort, vagy a megemelt build számot.
4. Ha a lista üres: a bundle azonosító a rekordon és a binárisban tér el, a feldolgozás még fut, vagy az export kérdés a TestFlight oldalon nyitva van.
5. A verzió oldal Game Center, alkalmazáson belüli vásárlás és hirdetés jelölői üresek. Sign-in information: nincs bejelentkezés.

Included Assets és az App Clip üres. Routing coverage file nem kell, mert az app nem ad útvonalat más alkalmazásoknak; a MapKit útvonalat kér, nem szolgáltat.

## 17. App Review információ

A verzió oldal alján, App Review Information. Ez a reviewernek szól, az áruházban nem jelenik meg. Angolul írd, a review csapat angolul dolgozik.

Contact:

- Vezetéknév és utónév: a tagságon lévő név.
- Telefon: olyan szám, amin a review napjaiban fel tudnak hívni.
- E-mail: `laszlo.kovary@gmail.com`, mert ez van az app névjegyében és a nyilatkozatban.

Sign-in required: kikapcsolva. Felhasználónév és jelszó üres.

Notes (illeszd be, és a telefonszámot ne ide írd, az a kapcsolat mezőben van):

```text
GPS Track Logger is an iPhone-only app (portrait, iOS 17+). There is no account and no demo login.

First launch shows a short disclaimer. Accept opens the tracker. Refuse stays on that screen and does not record. The privacy policy link on that screen is:
https://lkovari.github.io/KLHome/assets/bigfiles/gtl-ios-private-policy.html
The same link is in Settings and in Help. Support email in About: laszlo.kovary@gmail.com

Location permission:
- The app asks only for While Using the App. There is no Always prompt.
- Recording starts only from the foreground with Start. After Start, recording continues while the screen is locked or the app is in the background, and the blue location indicator stays visible until Stop.
- Precise Location is required. Reduced accuracy does not start a recording.
- Force quitting the app stops the recording; it does not restart on its own.
- If location is denied or Precise Location is off, Start and the location button show an alert on any tab with Open Settings. The GPS tab explains it as well.

Diagnostics: About → Error log shows the on-device error log. Saved tracks → select one track → Recorded points shows that track's stored points as a table.

The logged route, acceleration, and lean angle stay in SQLite on the phone. An iPhone backup includes that database. Downloaded map files are excluded from backup. The track is not uploaded to the developer, and no stored data is shared with any third party; it leaves the phone only through a GPX or KMZ export the user starts.

Apple Maps (standard, satellite, hybrid), place search, a route to a tapped point, and address lookup send Apple the coordinate or map area needed for that request.

Offline maps are optional. OpenStreetMap regions (from the Hochschule Esslingen HTTPS mirror of download.mapsforge.org) and one Turistautak.hu file can be downloaded; the server sees the IP address and the requested file. On a mobile network the app asks before the download and shows the size. The corner credit is “© OpenStreetMap contributors” or “© Turistautak.hu”. About lists MapLibre Native (BSD) as well.

Background mode is Location only, and only while a recording started with Start is running (While Using the App, CLBackgroundActivitySession).

No ads, no tracking, no App Tracking Transparency prompt. Encryption is HTTPS only (exempt).
```

Ha a review egy valós készüléken a zárolt rögzítést nézi, a jegyzet és a bináris ugyanazt csinálja. A szimulátoros review a háttér-helyet gyengén mutatja; a jegyzet ezért leírja, hogy „app használata közben” engedéllyel a Start után zárolva is rögzít.

## 18. Beküldés

1. A verzió oldalon minden kötelező mező töltve: leírás, kulcsszavak, support URL, nyilatkozat URL, copyright, egy 6,9 hüvelykes képsor nyelvenként, build, korhatár, adatvédelmi címke, kapcsolattartó.
2. A lap tetején Add for Review, majd Submit to App Review. A felület felsorolja, ami még piros. Azt pótold, és küldd újra.
3. Version Release:
   - Manually release this version: a jóváhagyás után te nyomod meg a kiadást. Első kiadásnál ez a nyugodt választás.
   - Automatically release: a jóváhagyás pillanatában kikerül az áruházba.
4. A beküldés után az állapot Waiting for Review. Export question, ha még nyitva maradt, a beküldés előtt a build sorában is megválaszolható.

Az első alkalmazás egy új fiókon gyakran tovább tart, mint egy rutinfrissítés. A Waiting for Review után In Review, aztán Accepted vagy Rejected. A levél az Apple ID címére megy, és a Connect Resolution Center is mutatja.

## 19. Amíg a review tart

A beküldött build szövegén és képein már nem változtatsz anélkül, hogy a verziót visszavonnád. A promóciós szöveg kivétel, az review nélkül cserélhető, amíg a verzió él.

Ha a binárisban hibát találsz:

1. Vond vissza a verziót, ha a felület engedi (Waiting for Review alatt általában igen; In Review alatt már a reviewerhez került).
2. Emeld a build számot.
3. Archiválj, töltsd fel, válaszd az új buildet, és küldd be újra. Az 1.0.1 verziószám maradhat.

A review közben a 3. lépés URL-jét ne törd el, és a lap szövegét ne cseréld vissza az Android nyilatkozatra.

## 20. Elutasítás

A Resolution Center üzenete Guideline számmal jön. Válaszolj a szálon angolul, röviden, a konkrét képernyőre.

Tipikus okok ennél az appnál, és mi a válasz útja:

| Jel | Hol látszik | Teendő |
| --- | --- | --- |
| ITMS-91053 vagy ITMS-91061 | Feltöltés, a build nem is review | A privacy manifest és a MapLibre saját manifestje. Új archive, magasabb build szám. |
| 5.1.1 félrevezető adatkezelés | Review | A lap, a kérdőív és az első képernyő szövege ugyanazt mondja. A lap URL-je él. |
| 2.5.4 háttér-hely | Review | „Az app használata közben” engedéllyel, a Start után zárolva is rögzít, a kék jelző a Stopig látszik. Mindig kérés nincs. |
| 2.1 a gomb nem csinál semmit | Review | Megtagadott helynél bármelyik fülön figyelmeztetés Beállítások gombbal. Csökkentett pontosságnál a pontos hely kérése. |
| 5.2.1 térképjog | Review | OSM sarok `© OpenStreetMap contributors`, Turistautak sarok és névjegy, MapLibre a névjegyben. |
| 2.3.3 a kép nem a futó app | Review | Új 6,9 hüvelykes kép a futó felületről. A nyers enum-ot mutató mentett-útvonal kép maradjon kint. |
| Üres vagy halott Support URL | Beküldés vagy review | A 3. lépés címe, böngészőből megnyitva. |

Szöveges válasz elég, ha a bináris már helyes, és a reviewer nem találta a lépést. Bináris változás mindig új build szám.

A részletes review-lista: [gtl-ios-review-hu.md](gtl-ios-review-hu.md).

## 21. Jóváhagyás és kiadás

1. Az állapot Pending Developer Release, ha kézi kiadást választottál. Nyisd meg a verziót, Release this version.
2. Automaticnál a jóváhagyás után az állapot Ready for Sale, országonként pár óra, amíg a kereső is mutatja.
3. A termékoldalon ellenőrizd: név, felirat, a 6,9 hüvelykes képek, a 4+ korhatár, az adatvédelmi címke (Data Not Collected), a support link, az ingyenes ár, az iPhone és az iOS 17.0.
4. Telepítsd az áruházból egy olyan iPhone-ra, amin a fejlesztői build nincs fent, vagy töröld előtte a fejlesztői példányt. A bundle azonosító ugyanaz, a két példány nem él egymás mellett.
5. Az áruházi példányon: nyilatkozat, helyengedély, egy rövid rögzítés, leállítás, mentett útvonal, a nyilatkozat linkje.

Phased release a frissítésekre van. Az első kiadás minden elérhető országban megjelenik, amit az ár lépésben bejelöltél.

## 22. Következő frissítés

1. Version: új `MARKETING_VERSION`, ha a felhasználó új számot lát (1.0.2). Build: az előző buildnál nagyobb szám akkor is, ha a verzió nő.
2. Archive, feltöltés, ugyanaz a bundle.
3. A Connecten az iOS App mellett plusz verzió, vagy a jóváhagyott verzió mellé New Version.
4. What’s New mindkét nyelven. A képernyőkép csak akkor cserélendő, ha a felület változott.
5. Új build kiválasztása, beküldés.

A bundle azonosító, az SKU és az elsődleges nyelv a rekord élete alatt marad. Új alkalmazásrekord csak másik bundle azonosítóval hozható létre; az a felhasználónál másik app.

## Rövid ellenőrzőlista a beküldés gomb előtt

- [ ] A tagság Active, a szerződés Active, az Account Holder adatok megvannak.
- [ ] A nyilatkozat URL-je böngészőből iOS szöveget mutat, angolul és magyarul.
- [ ] Xcode csapat: a fizetős csapat. Bundle: `com.lkovari.mobile.apps.gtl`. Automatikus aláírás.
- [ ] Archive a `gtl` scheme-ről, Any iOS Device, Release. Validate App succeeded.
- [ ] A build a TestFlight listában kész, az export válasz megvan.
- [ ] Ár: Free. Kategória: Navigation. Korhatár: 4+. Gyerek kategória nincs.
- [ ] Adatvédelem: követés nincs; Data Not Collected; a manifest gyűjtött-adat tömbje üres.
- [ ] A `docs/gtl-ios-private-policy.html` friss változata kint van a KLHome ugyanezen címén. A harmadik félről szóló mondat miatt újra ki kell tenni (a 2026. október 3. 09:00-s változatban még nincs benne).
- [ ] App Store Connect → Pricing and Availability: az „iPhone and iPad Apps on Apple Silicon Macs” és a visionOS elérhetőség kikapcsolva.
- [ ] A 7. lépés eszköztesztjei (zárolt séta, Home, force quit, PreciseRoute magyarul, iPad) elvégezve.
- [ ] Angol és magyar név, felirat, leírás, kulcsszavak, support URL, privacy URL, copyright.
- [ ] 6,9 hüvelykes képek mindkét nyelven, a futó felületről. A 04-es kép csak olvasható útvonalnévvel.
- [ ] A verzióhoz a friss build van választva.
- [ ] Review jegyzet angolul, telefon és `laszlo.kovary@gmail.com` a kapcsolattartónál, bejelentkezés nélkül.
- [ ] Kézi vagy automatikus kiadás ki van választva.
