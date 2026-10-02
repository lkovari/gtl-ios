# Offline OSM rajzolás: elemzés és javítási terv

Ez a jegyzet a jelenlegi (staged) állapotot elemzi, és sorrendben leírja, mit javítanék. Kódot nem módosítottam. Csak az offline (Mapsforge + MapLibre) útról szól, a MapKit-út nincs benne.

Cél: iPhone 12, 4 GB RAM. Tünetek: a térkép szaggatva vagy egyáltalán nem frissül, naplózás közben elfogy a memória és a napló leáll.

## Állapot

Az alábbi javítások bekerültek a kódba (nincs commitolva). Az egységtesztek átmennek (39, hiba nélkül). A valódi `eu-hungary.map` fájlon, az app saját csővezetékével lejátszva ellenőriztem, hogy nincs tengertéglalap, és hogy minden nagyításon megjönnek az utak. Telefonon és hosszú úton még nincs kipróbálva.

| Javítás | Pont | Hol |
| --- | --- | --- |
| A `natural=sea` és `natural=nosea` téglalap eldobása, az ismeretlen (nem `highway`) vonal nem rajzolódik útként | 13. | `readWay`, `mapPaint`, `layerPaints` |
| A megszakítás a vonal- és POI-cikluson belül is érvényesül (256 elemenként), az indexben és a csempedekódolásban | 5., 1. b | `readTile`, `decodeTile`, a `decode…Ways` függvények |
| A `hiking` jelző egyszer, a fejlécben számolódik | 2. | `MapsforgeHeader.hiking` |
| A változó értékű címkék az azonosítók után olvasódnak | 12. | `readTags` |
| Áttekintés: nincs sorszám szerinti mintavétel, nézetre szűrés és osztály szerinti rangsor, legfeljebb 12 000 alakzat, országhatár külön vonallal | 14. | `decodeOverviewWays`, `overviewRank`, `tileBudgets`, `line-border` réteg |
| A fájlból kért nagyítás a MapLibre nagyítása plusz egy | 4. | `Coordinator.queryZoom` |
| Az útkeretből nincs fenntartva a képernyő sorának, a csempénkénti plafon 4000 / 2500 / 1200 | 3. részben | `WayQuota`, `tileBudgets` |
| A csempeplafon 48, és ha a nézetnek több kell, az olvasó mindig durvább alfájlra vált, így a teljes képernyő le van fedve (korábban a 24 legközelebbi csempe maradt, kereszt alakban) | 14. | `OfflineTileCache.maxTiles`, `chooseSubfile` |
| A futó csempe elkészül és megmarad kameramozdulatnál is, az eltárolt, de nem publikált csempe a következő hívásnál kikerül, publikálás csempénként, legfeljebb 0,4 másodpercenként | 1. a, c, d | `refreshOffline`, `OfflineTileCache.keep` |

A valódi fájlon mért kimenet a javítás után, Pestszentlőrinc fölött, telefon méretű nézettel (az idő Macen, szimulátorban):

| MapLibre zoom | Alfájl, csempe | Alakzat | Idő | Amiből a legtöbb van |
| --- | --- | --- | --- | --- |
| 5 | alap 5, 2 | 8099 | 268 ms | autópálya 4239, autóút 1997, országhatár 837 |
| 7 | alap 5, 1 | 9807 | 209 ms | autópálya, autóút, országhatár |
| 7,6 | alap 10, 40 | 10 208 | 835 ms | főút, földfelület, víz, autópálya |
| 8 | alap 10, 24 | 11 825 | 683 ms | főút, másodrendű, víz, földfelület |
| 9 | alap 10, 9 | 12 051 | 790 ms | főút, földfelület, másodrendű, víz, harmadrendű |
| 11 | alap 10, 1 | 10 788 | 228 ms | földfelület 3919, harmadrendű 2161, másodrendű 1592, főút 1182 |
| 11,6 | alap 14, 40 | 11 645 | 134 ms | lakóutca, gyalogút, földfelület |
| 12 | alap 14, 24 | 7683 | 84 ms | lakóutca 1934, gyalogút 1528, földfelület 1025 |
| 14 | alap 14, 4 | 3153 | 68 ms | ház 1714, lakóutca 322, szervizút 210 |
| 16 | alap 14, 1 | 625 | 15 ms | ház 535, lakóutca 33 |

A táblázat minden sorában a nézet teljes területe le van fedve csempével; ezt a mérés külön ellenőrizte.

Két meglévő egységteszt a régi viselkedést rögzítette (24 csempés plafon, és hogy egy 3 fok széles nézet az alap 10-es alfájlon marad csonkolva). Ezeket az új szabályhoz igazítottam.

Ami nincs megcsinálva: a dekódoló tömörítése (2. pont többi része), az index olcsó, folytatható olvasója (5. pont teljes változata), az overlay szétbontása (6.), a kamera (7.), a feliratréteg (8.), a főszál tehermentesítése (9.), a `MLNComputedShapeSource` (10.), az életciklus (11.).

Ismert kockázat: áttekintő nézetben egy lépés 0,2–0,8 másodperc Macen, telefonon ennek többszöröse lehet, és 12 000 alakzat átadása a MapLibre-nak a főszálon történik. Ha ez akad, a plafont (`overviewFeatureCap`) kell lejjebb venni.

## Rövid összefoglaló

1. **A „nem frissül” oka a frissítési csővezeték logikája**, nem a dekódoló. Minden kameramozdulat eldobja a futó dekódolást és újraindítja, 220 ms várakozással. Követő kameránál (naplózás) a kamera 0,5–1 másodpercenként mozdul, a sűrű városi csempe dekódolása nagyjából ennyi ideig tart, így a munka soha nem ér célba. Ezen felül van egy eset, amikor a kész csempe a gyorsítótárba kerül, de soha nem publikálódik.
2. **A dekódoló 10–50-szer lassabb és szemetesebb a kelleténél.** Egyetlen sor ([MapsforgeReader.swift:1301](gtl/Maps/MapsforgeReader.swift#L1301)) vonalanként 5,6 KB-os sztringet épít. Ez adja az Instruments 2,41 GiB-jából kb. 1,1 GiB-ot.
3. **A staged javítás téves feltevésre épül.** A magyar fájlban nincs 4 MB-os csempe: a legnagyobb 323 KB, 4681 vonallal. Az utcák nem a „későbbi sorban” vannak, hanem az elsőben (z12). A kosarak és a nézetre szűrés ezért pont az utcákat és a házakat vágják le, és nézetfüggővé teszik a gyorsítótárat, ami több újradekódolást okoz.
4. **A helynévindex a háttérben a teljes fájlt dekódolja** (6,9 millió vonal), és minden megszakításnál nulláról kezdi. A felvételen végig ez futott.
5. **Klasszikus memóriaszivárgást (retain cycle) nem találtam.** A felvétel sem mutat szivárgást: a tartós készlet 66 MiB és lapos.
6. **A napló leállása nem memória volt, hanem a helynévindex processzorhasználata a háttérben.** Az október 1-jei OSM-úton a rögzítés 18:39:46-kor állt meg, a telefon 18:39:47-re jelez háttérbeli processzortúllépést (98%) az index szálán. A folyamat életben maradt, a Stop 19:11:13-kor rendben kiíródott. A MapKit-úton az index nem fut, ott nem volt szünet. Részletek „A telefon analitikai naplói” részben. **A legelső javítás ezért az index (5. pont), a megszakítás vonalcikluson belüli ellenőrzésével együtt.**

## Amit megmértem

A szimulátorban lévő `eu-hungary.map` fájlt (267 MB) egy külön szkripttel olvastam ki, az app kódjától függetlenül.

| | |
| --- | --- |
| Alfájlok | alap 5 (zoom 0–7, 0,5 MB), alap 10 (zoom 8–11, 12,5 MB), alap 14 (zoom 12–21, 254 MB) |
| Legnagyobb csempe | alap 14: 323 KB (Budapest belváros). Alap 10: 804 KB. Alap 5: 541 KB |
| 1 MB fölötti csempe | 0 darab. 4 MB fölötti: 0 darab |
| Alap 14 medián csempe | 579 bájt. 99. percentilis: 53 KB |
| Összes vonal | 6,9 millió (ebből alap 14: 6,5 millió), 590 ezer POI |
| Út-címkék listája | 339 címke, összefűzve 5608 bájt |

Két budapesti z14 csempe tartalma nagyítási soronként:

| Sor | Belváros (4681 vonal) | Pestszentlőrinc (3463 vonal) |
| --- | --- | --- |
| z12 | 994: residential 448, secondary 153, tertiary 88, primary 40, területek 161 | 258: residential 170, secondary 25, területek 43 |
| z13 | 877: footway 746, cycleway 43, épület 61 | 71: footway 67 |
| z14 | 455: service 193, pedestrian 123 | 170: service 89, path 25 |
| z15 | 2111: **épület 1979** | 2958: **épület 2946** |
| z16 | 176: steps 138 | 6 |
| z17 | 68 | 0 |

Következmények:

- Az utcahálózat az **első** sorban van (z12), a gyalogutak z13-ban, a szervizutak z14-ben. A házak z15-ben.
- Egy teljes csempe legfeljebb kb. 4700 vonal és 100–320 KB. Egészben dekódolható, keret és ablakos olvasás nélkül.
- A `decodeLargeTile`, `streamPlannedWays`, `streamVisibleWays` és `WayWindow` ([MapsforgeReader.swift:606-828](gtl/Maps/MapsforgeReader.swift#L606-L828)) ezen a fájlon soha nem fut. Halott kód, kb. 220 sor.
- Az alcsempe-bitkép szerint a belvárosi vonalak 75 százaléka egyetlen cellát érint (3500 a 4681-ből). A bitkép tehát jó szűrő lenne, ha a kérés egy cella volna. A mostani, 45 százalékkal megtoldott nézet viszont a 16 cellából jellemzően 8–12-t lefed, így alig szűr.

## Amit a képernyőfotók mutatnak

**1. kép (Statistics).** A 2,41 GiB a Total Bytes: a 41 másodperc alatt lefoglalt összes bájt, a felszabadítottakkal együtt. Nem csúcs. A Persistent 66 MiB, a grafikon lapos. Ez kb. 58 MB/s és 240 ezer foglalás/s forgalom, nem szivárgás.

- `Swift.__StringStorage`: 1,10 GiB összesen, 521 900 foglalás, tartósan csak 321 KiB. Ez az [MapsforgeReader.swift:1301](gtl/Maps/MapsforgeReader.swift#L1301) sor: `header.wayTags.joined().contains("osmc")`, vonalanként. 1,10 GiB / 5608 bájt ≈ 210 ezer vonal dekódolása 41 másodperc alatt. A szám illik: ez az egy sor a teljes forgalom 46 százaléka.
- `_DictionaryStorage<String, String>`: 162 604 foglalás, 30,8 MiB. A `tags` szótár, vonalanként és POI-nként.
- `Malloc 16/32/48/64/80 Bytes`: összesen kb. 6 millió átmeneti foglalás. A címkekulcsok (`pattern.split("=")`, `String.init`), a nevek és a koordinátatömbök.
- `MLNPolylineFeature`: 2400 tartós, 6783 összesen. A 41 másodperc alatt tehát csak kb. 3 publikálás volt. A forgalmat nem a rajzolás adja.

210 ezer vonal 41 másodperc alatt kb. 45 teljes belvárosi csempének felel meg, miközben a térkép háromszor frissült. A dekódolt vonalak túlnyomó része tehát nem került a képernyőre.

**2. kép (Created & Persistent, méret szerint).** A 22. sor: `Malloc 544 KiB`, Foundation, `-[NSConcreteFileHandle readDataOfLength:]`, 00:02.323-kor, és a felvétel végén még él. Az alap 5-ös csempe 540 910 bájt. A térkép 14-es zoomon indul, az alap 14-es alfájlt olvassa, ekkora csempe ott nincs. Alap 5-ös csempét csak a helynévindex olvas, az kezdi a legkisebb alfájllal ([MapsforgeReader.swift:184](gtl/Maps/MapsforgeReader.swift#L184)). **Az index tehát a 2. másodpercben elindult, és 39 másodperc múlva is ugyanazt a csempét dolgozta fel.** Ez következtetés a méret egyezéséből, nem hívási veremből, mert a verem „Call stack limit reached”.

A többi tartós tétel rendben van: 3 × 8,95 MiB IOSurface (a térkép és a feliratréteg felületei), 13 MapLibre-szál 560 KiB-os verme, IOGPU erőforrások.

**3. kép.** 640 bájtos MapLibre-foglalások ezrei 20 ms alatt, egy szálon, a veremben ugyanaz a cím ötször egymás alatt (`0x1060e4748`). Ez rekurzió: a geojson-vt csempefelosztása. Minden `source.shape = …` után a MapLibre a teljes forrást újraindexeli.

**4. kép (Generations).** A 26,7 másodpercig nőtt 53 MiB-ból 27 MiB IOSurface, 7,7 MiB verem, 6,4 MiB IOAccelerator. Mind az első 2 másodpercben keletkezett. Utána nincs növekedés.

**Ami hiányzik a felvételből:** a VM Tracker sávja üres (Dirty Size, Resident Size), nem volt bekapcsolva az automatikus pillanatkép. Az iOS a `phys_footprint` alapján öl, abban benne van a Metal- és IOSurface-memória is, amit az Allocations csak részben lát. A felvétel 41 másodperc, naplózás nélkül vagy rövid naplózással. A memóriaölést hosszabb, naplózó felvétel mutatná meg.

## Amit a telefon analitikai naplói mutatnak

A rákötött iPhone 12-ről (iOS 27.0, 24A437) lehúztam a gtl-hez tartozó jelentéseket és a jetsam-eseményeket. A naplók szeptember 27-től október 1-ig tartanak.

**Memóriaölésnek nincs nyoma.** Két `JetsamEvent` van, mindkettő szeptember 27-i, és egyikben sem a gtl a kilőtt folyamat (rendszerdémonok és felfüggesztett appok mentek ki). A gtl legnagyobb rögzített memórialábnyoma 475,8 MB (október 1., 9:06), a többi jelentésben 105–200 MB. Az iPhone 12 appkorlátja 2 GB körül van. A jetsam-naplókat az iOS forgatja, tehát egy régebbi ölést ez nem zár ki, de a meglévő adatok szerint a leállás nem memória volt.

**Nyolc `gtl.cpu_resource` jelentés van, öt nap alatt.**

| Időpont | Processzor | Állapot | Lábnyom |
| --- | --- | --- | --- |
| 09-27 21:41 | 97% 92 másodpercig | előtérben | 64 → 38 MB, csúcs 134 MB |
| 09-28 07:51 | 70% 129 másodpercig | előtérben | 111 → 101 MB |
| 09-28 10:22 | 68% 132 másodpercig | előtérben, 11 szál | 127 → 104 MB, csúcs 184 MB |
| 09-28 11:43 | 75% 120 másodpercig | előtérben | 108 → 38 MB, csúcs 160 MB |
| 09-28 13:58 | 93% 97 másodpercig | előtérben | 165 → 200 MB |
| 10-01 09:06 | 73% 124 másodpercig | előtérben, 5 szál | 382 → 120 MB, csúcs 476 MB |
| 10-01 18:38 | 98% 49 másodpercig | **háttérben, a felhasználó tétlen** | 72 → 75 MB |
| 10-01 19:52 | 95% 95 másodpercig | előtérben, 1 szál | 85 → 88 MB |

Mind a nyolcban ugyanaz a kép: egy Swift Concurrency szál, **Utility** prioritáson, hatékonysági magon, a minták 90–100 százalékában. A commitolt kódban (HEAD) egyetlen feladat fut Utility prioritáson: a helynévindex (`Task.detached(priority: .utility)`, `scheduleIndex`). A csempedekódolás `userInitiated`. A jelentések tehát az indexet mutatják. A legutolsó jelentés vermében 19 mintából 14 a Foundationben van, az app egy függvényéből hívva. Ez illik a névhajtogatásra (`MapSearch.fold`), de a vermet nem tudtam pontosan szimbolizálni, mert az akkori build (`94F08B62…`) szimbólumai már nincsenek meg, és a rendszerkönyvtárak szimbólumai sincsenek a gépen. A prioritás egyezése biztos, a függvénynév következtetés.

Amit ez jelent:

- **A leállás oka a meglévő naplók szerint a processzor, nem a memória.** Az 5. pont (index) ettől előrébb kerül, lásd lent.
- A 18:38-as jelentés szerint az index a háttérben, lezárt telefonon is 98 százalékon futott. Ott a korlát szigorúbb (80% 60 másodpercig). A jelentésekben az „Action taken” mindenhol „none”, vagyis ezek figyelmeztetések, a rendszer nem ölte ki az appot. Háttérben, helymeghatározással futó appnál viszont a tartós túllépés ölést is adhat, és annak nincs külön jelentése.
- A commitolt kód az indexet induláskor és naplózás alatt is futtatta. A staged kód ezt már leállítja naplózáskor és háttérben, és `background` prioritásra teszi. Ez jó irány, de az index még mindig a teljes fájlt dekódolja, és megszakítás után nulláról kezd.
- A 476 MB-os csúcs és a 382 → 120 MB-os esés (10-01 09:06) azt mutatja, hogy a lábnyom dekódolás közben több száz megabájttal megugrik, majd visszaesik. Ez átmeneti foglalás (index, 80 000-es csempekeret, autorelease), nem szivárgás.

**Az október 1-jei leállás: a két GPX és a 18:38-as jelentés egy másodpercre egyezik.**

| | Odaút, MapKit | Visszaút, OSM |
| --- | --- | --- |
| Fájl | `GTL 20261001_195333.gpx` | `GTL 20261001_195257.gpx` |
| Idő | 17:21:16 – 17:58:47 | 18:37:58 – 19:11:13 |
| Pontok | 568 | 25 |
| Legnagyobb szünet | 39 másodperc | **23 perc**, utána 8 perc 20 másodperc |
| Rögzített út | 27,3 km | 19,8 km, ebből 19,2 km két egyenes ugrás |

A visszaút pontjai:

- 18:37:58 – 18:39:46: 23 pont, rendes ütemben (1 perc 48 másodperc).
- 18:39:46 után 23 percig semmi. A következő pont 19:02:45-kor van, 16 km-rel arrébb.
- Utána 8 perc 20 másodpercig semmi. Egy pont 19:11:05-kor, majd Stop 19:11:13-kor.

A processzorjelentés ablaka 18:38:58-tól 18:39:47-ig tart: háttérben, tétlen felhasználóval, 98 százalék, a korlát 80 százalék 60 másodpercre. **A túllépés pillanata 18:39:47, az utolsó rendes pont 18:39:46.**

Amit ebből biztosan tudni lehet:

- **A folyamat nem halt meg.** A fájlban van Stop jelölő 19:11:13-kor, és a Stop csak akkor íródik ki, ha a memóriában megvan a munkamenet azonosítója. Nem memóriaölés volt, és nem összeomlás.
- A rögzítés a háttérbeli processzortúllépés másodpercében állt le.
- A 19:02:45-ös és a 19:11:05-ös pont akkor keletkezett, amikor az app rövid időre újra futott.
- A MapKit-úton az index nem indul el (a `scheduleIndex` csak offline térképnél fut), ezért ott nincs túllépés, és nincs szünet. Ez az egyetlen különbség, ami a két út között a háttérben számít.

Ami következtetés: hogy az iOS a túllépés után pontosan mit tett (felfüggesztette az appot, vagy megvonta a háttérbeli futást), azt a jelentés nem írja le, az „Action taken” sora „none”. Az egyezés egy másodpercre pontos, és más magyarázatot nem találtam, de a mechanizmust a rendszer nem dokumentálja a naplóban.

A 9:06-os jelentésnél volt a legnagyobb lábnyom: 382 MB, csúccsal 476 MB. Az appot 21:43-kor újratelepítették, a telefonon lévő `gtl.db` azóta üres, ezért a GPX-fájlokból dolgoztam.

**A staged kód ezt nem zárja le teljesen.** A staged változat naplózáskor és inaktív jelenetnél megszakítja az indexet, de a megszakítás csak két csempe között érvényesül ([MapsforgeReader.swift:493](gtl/Maps/MapsforgeReader.swift#L493)). Az Instruments-felvételen az index 39 másodperc alatt sem végzett az első, alap 5-ös csempével. Ha a telefon ilyen csempe közben kerül háttérbe, a szál a megszakítás után is tovább pörög, és a 60 másodperces háttérkorlátot ugyanúgy átlépheti. A megszakítást a vonalcikluson belül kell ellenőrizni.

**Egy összeomlás van** (09-27 21:57): `0x8BADF00D`, „Failed to terminate gracefully after 5.0s”, háttérben. A hibás szálon Swift-állítás bukott el a `UInt32.bigEndianBytes` gettert hívó `MarkerIcon.png`-ben, a KMZ megosztásból. Ez nem a térképrajzolás. A mostani kód ott `truncatingIfNeeded`-et használ, ami nem tud elbukni, tehát ez valószínűleg már javítva van.

## A staged javítás értékelése

Ami jó, és megtartanám:

- A forrás alakja a helyén cserélődik, nincs üresre állítás ([MapViews.swift:1158-1163](gtl/UI/MapViews.swift#L1158-L1163)).
- Az overlay csak változáskor épül újra (`OverlayStamp`).
- A középső csempe rögzítése.
- A jelenet inaktív állapotában a csempék és a fájl elengedése.

Ami szerintem ront:

- **Az útkosár fordítva van.** A `WayQuota` az útkeret háromnegyedét a képernyő sorának tartja fenn; a durvább sorok összesen `roadCap − queryRoadFloor` utat kaphatnak ([MapsforgeReader.swift:325](gtl/Maps/MapsforgeReader.swift#L325), [:334](gtl/Maps/MapsforgeReader.swift#L334)). 2000-es csempekeretnél ez 1200 − 900 = **300 út** a z12–z14 sorokból. A képernyő sora 16-os zoomnál a z16, amiben 138 lépcső van. A belvárosban a nézetbe eső utak száma kb. 570, tehát a fele kimarad, fájlsorrendben. Ez ugyanaz a töredezett utcakép, kisebb mértékben.
- **A házak kerete 400** (`restCap`, a keret 20 százaléka). Pestszentlőrincen a nézetbe kb. 850 ház esik. A fele hiányzik.
- **A nézetre szűrt csempe nézetfüggő.** Ugyanaz a csempe minden fél képernyőnyi elmozdulás és minden nagyobb forgás után újra dekódolódik (`needsRefresh`, [OfflineTileCache.swift:27-32](gtl/Maps/OfflineTileCache.swift#L27-L32)). Forgásnál a befoglaló téglalap alakja változik (álló telefon, 9:19,5), a szűk oldal 45 százaléka nem elég. Egészben dekódolt csempénél erre nem volna szükség.
- **A 4 MB-os ág és a `decodeCap`** ezen a fájlon nem fut, illetve nem köt (16 000 > 4681).

A jegyzet (`osm-rendering-problem-hu.md`) „Az utca és a ház a képernyő nagyításához tartozó későbbi sorban van” mondata az utcára nem igaz. A régi hiba oka a 320–600-as keret volt egy 3000–4700 vonalas csempén, nem a csempe mérete és nem a sorok rendje.

## Javítási ötletek, a legvalószínűbbtől

A százalék az én becslésem arra, hogy az adott pont önmagában érezhetően javít a leírt tüneteken. Nem mérés. Az 1–4. pont együtt adja a javítás zömét, és egymásra épül.

### 1. A frissítési csővezeték ne dobja el a munkát — 85%

Hely: [TrackerModel.swift:734-801](gtl/UI/TrackerModel.swift#L734-L801).

Négy külön hiba van ugyanabban a függvényben.

**a) Élőzár.** Ha van hiányzó csempe, minden `refreshOffline` hívás megszakítja a futó feladatot, lépteti a generációt, és 220 ms múlva újrakezdi. A dekódolás eredményét a generáció-ellenőrzés eldobja ([:785](gtl/UI/TrackerModel.swift#L785)), a gyorsítótárba sem kerül. Naplózáskor a követő kamera minden fixnél `setCamera`-t hív (8 m elmozdulás vagy 5 fok fordulás), az `regionDidChangeAnimated`-et vált ki, az pedig `refreshOffline`-t. Autóval ez 1 Hz, futásnál 2 Hz. Egy csempének tehát 780, illetve 280 ms-on belül kell elkészülnie, különben soha nem készül el. A felvételből számolt dekódolási sebesség kb. 5000 vonal/s, egy belvárosi csempe kb. 1 másodperc. Sűrű területen, mozgás közben a térkép ezért nem frissül.

**b) A megszakítás nem állítja le a dekódolást.** A `flag.cancelled` csak csempék között van ellenőrizve ([MapsforgeReader.swift:77](gtl/Maps/MapsforgeReader.swift#L77)), a kérés pedig egy csempe. A megszakított `Task.detached` végigfut, az eredménye a szemétbe megy. Több ilyen fut párhuzamosan, mind a processzort és a memóriát eszi.

**c) Elveszett publikálás.** A ciklus csempénként beírja az eredményt a gyorsítótárba, de csak a legvégén publikál ([:798](gtl/UI/TrackerModel.swift#L798)). Ha a feladat két csempe után megszakad, a két csempe a gyorsítótárban van, a térképen nincs. A következő hívás a maradékot dekódolja. Ha addigra semmi nem hiányzik, a `missing.isEmpty` ág `update(decoded: [])`-ot hív, ami `false`-t ad (nem cserélt, a kulcsok nem változtak), tehát **nincs publikálás**. A kész csempék addig nem látszanak, amíg valami más nem vált ki frissítést.

**d) Semmi nem látszik az utolsó csempéig.** Hat csempénél a felhasználó az első öt alatt üres térképet néz.

Mit tennék:

- Egy soros dekódoló (egy `actor` vagy egy soros sor), egyszerre egy csempe. Az új kérés nem szakítja meg a futót, csak lecseréli a várakozó listát (a legfrissebb nyer).
- A kész csempe mindig bekerül a gyorsítótárba, akkor is, ha közben a kamera elmozdult. A csempe a kulcsa szerint érvényes, nem a kérés generációja szerint.
- Publikálás csempénként, vagy legfeljebb 150–200 ms-onként összevonva. Egy „piszkos” jelző a gyorsítótáron, hogy a c) eset ne fordulhasson elő.
- A megszakítás ellenőrzése a vonalcikluson belül, 256 vonalanként.
- A 220 ms-os várakozás csak kézi húzásnál kell. Követő kameránál fölösleges, mert ott a kamera nem áll meg.

Ez a pont a 2. és a 3. nélkül is javít, de azokkal lesz gyors.

### 2. A dekódoló forgalmának levágása — 80%

Hely: [MapsforgeReader.swift:1241-1306](gtl/Maps/MapsforgeReader.swift#L1241-L1306), [:1562-1645](gtl/Maps/MapsforgeReader.swift#L1562-L1645).

- **`hiking` egyszer, a fejlécben.** A `header.wayTags.joined().contains("osmc")` kerüljön a `MapsforgeHeader`-be, számított mezőként, a fejléc beolvasásakor. Ez egy sor, és a foglalt bájtok 46 százalékát megszünteti. Ha csak egy dolgot javítanék elsőre, ez lenne.
- **Címkék előre feldolgozva.** A fejlécben minden címke-azonosítóhoz egyszer tárolni a kulcsot és az értéket. Most vonalanként fut a `pattern.split(separator: "=")` és a `String.init` ([:1259](gtl/Maps/MapsforgeReader.swift#L1259)), címkénként két-három foglalással.
- **Szótár helyett tömör típus.** A `[String: String]` helyett címke-azonosítók tömbje, vagy egy kis struktúra a ténylegesen használt mezőkkel (`highway`, `building`, `waterway`, `natural`, `landuse`, `leisure`, `railway`, `place`, `ref`, `name`, osmc/kct jelzők). A rajzoló és a felirat ezeket olvassa, a teljes szótárat a keresés sem igényli.
- **A festék (`paint`) dekódoláskor.** A `category` és a `mapPaint` egyszer fusson, a háttérszálon, és az eredmény egy bájtos enum legyen. Most a főszálon fut minden publikálásnál, minden vonalra ([MapViews.swift:1315-1345](gtl/UI/MapViews.swift#L1315-L1345)).
- **`ByteCursor` nyers mutatón.** A `Data` indexelése bájtonként határellenőrzéssel és osztályon keresztül lassú. `withUnsafeBytes` és egy `UnsafeRawBufferPointer` fölötti struktúra kell. A VBE-olvasás a belső ciklus.
- **Koordináták tömören.** A `[(latitude: Double, longitude: Double)]` helyett közvetlenül `[CLLocationCoordinate2D]`, `reserveCapacity(nodes)`-szal. Így a főszálon nem kell még egyszer `map`-elni ([MapViews.swift:1328](gtl/UI/MapViews.swift#L1328)).
- **`autoreleasepool` csempénként** a dekódolóban és az indexben. A `FileHandle.read` és a `String(data:encoding:)` autoreleased objektumot adhat, és egy hosszú, felfüggesztés nélküli ciklusban ezek a feladat végéig élnek.
- **A POI-k** ugyanígy: a belvárosi csempében 5324 POI van, a nézetes út ebből akár 1400-at végigolvas szótárral együtt, hogy 28-at megtartson ([:983](gtl/Maps/MapsforgeReader.swift#L983)).

Várható eredmény: egy belvárosi csempe 1 másodperc helyett 20–50 ms. Ettől az 1. pont élőzára magától is ritkább lesz.

### 3. Egész csempe dekódolása, kosarak és nézetszűrés nélkül — 75%

Hely: [MapsforgeReader.swift:302-349](gtl/Maps/MapsforgeReader.swift#L302-L349), [:830-839](gtl/Maps/MapsforgeReader.swift#L830-L839), [OfflineTileCache.swift:27-32](gtl/Maps/OfflineTileCache.swift#L27-L32).

A mérés szerint egy csempe legfeljebb 4700 vonal. Nincs miért válogatni.

- A csempe a kért nagyítási sorig **teljesen** dekódolódik. Nincs `WayQuota`, nincs `perTile` plafon, legfeljebb egy biztonsági felső határ (például 20 000).
- A gyorsítótár kulcsa: csempe-azonosító és a dekódolt legmagasabb sor. A `covered` mező és a nézet szerinti újraolvasás megszűnik. Húzás és forgás nem indít dekódolást, csak új csempe vagy magasabb sor.
- Magasabb sor kérésekor elég a hiányzó sorokat hozzáolvasni (a sorok a fájlban egymás után vannak), nem kell az egészet újra.
- Áttekintésnél (zoom ≤ 11) marad a mintavétel, ott az alap 10-es csempe 800 KB-ig megy.
- A `tileBudgets`, a `ZoomWayBudget` részletes ága, a `decodeVisibleWays`, a `skipIfOutside`, a `subtileMask` és a 4 MB-os út törölhető. A 4 MB-os határ maradhat védelemnek más országfájlokra, de egyszerű „az első 4 MB” olvasással.
- A memóriakeret marad: 24 csempe, 64 MB. A becslő (`estimatedBytes`) a 2. pont tömör típusaival pontosabb lesz.

Ez megszünteti a hiányzó utcákat és házakat, és az újradekódolások nagy részét. Kockázat: 13-as zoom körül, döntött kameránál sok csempe látszik egyszerre, a GeoJSON-forrás 20–40 ezer alakzatot kaphat. Ezt a 4. és a 6. pont kezeli.

### 4. A zoom egy szinttel el van csúszva — 60%

Hely: [MapViews.swift:944](gtl/UI/MapViews.swift#L944), [:1095](gtl/UI/MapViews.swift#L1095), [:1124](gtl/UI/MapViews.swift#L1124).

A MapLibre 512 képpontos csempével számol. A MapLibre `zoomLevel` 14 ugyanazt a léptéket mutatja, mint a hagyományos (256 képpontos) 15-ös zoom. A Mapsforge sorai a 256-os skálához készültek. A kód `Int(mapView.zoomLevel.rounded())`-et ad át `queryZoom`-nak, tehát egy sorral kevesebbet kér, mint amit a lépték indokol.

A térkép 14-es zoomon nyílik. Ott a z15 sor (a házak, Pestszentlőrincen a vonalak 85 százaléka) nincs kérve, pedig a lépték már z15.

Javítás: `queryZoom = Int((zoomLevel + 1).rounded())`, a `zoom <= 11` áttekintő határral együtt eltolva. A feliratrangok (`pointLabelRank`, `lineLabelRank`) a MapLibre zoomját használják, azok maradhatnak.

### 5. A helynévindex ne dekódolja a teljes fájlt a térkép mellett — 90% a napló leállására, 55% a szaggatásra

A telefon naplói és a két GPX után **ez az első teendő** a napló leállása ellen: a nyolc processzorjelentés mind ezt a szálat mutatja, és az október 1-jei leállás másodpercre egybeesik a háttérbeli túllépéssel. A számozást nem írtam át, mert a többi pont hivatkozik rá. A térkép szaggatására és a hiányzó utcákra továbbra is az 1–4. pont a fő javítás.

A legkisebb, azonnali változat, a teljes átírás előtt:

- a megszakítás ellenőrzése a vonalcikluson belül (például 256 vonalanként), hogy a szál a háttérbe kerülés után legfeljebb néhány ezredmásodpercig fusson,
- az index soha ne fusson, ha a jelenet nem aktív vagy naplózás folyik (a staged kód ezt már tartalmazza),
- az alap 5-ös és alap 10-es alfájl kihagyása.

Hely: [MapsforgeReader.swift:486-531](gtl/Maps/MapsforgeReader.swift#L486-L531), [TrackerModel.swift:1391-1459](gtl/UI/TrackerModel.swift#L1391-L1459), [TrackDatabase.swift:289-295](gtl/Data/TrackDatabase.swift#L289-L295).

Most ez történik, amikor a térkép látszik és nincs naplózás:

- Az index minden alfájl minden csempéjét dekódolja `perTile: 80_000`, `poisPerTile: 80_000` kerettel, teljes geometriával és címkeszótárral. Ez 6,9 millió vonal. A mostani dekódolóval kb. 38 GB sztringforgalom és 20 perc fölötti processzoridő.
- Az alap 5-ös alfájllal kezd, ahol két csempében 22 809 nagy, sok pontos vonal van. A felvételen 39 másodperc alatt nem jutott túl az elsőn.
- Minden megszakítás (fülváltás, zárolás, naplózás indítása, vezérlőközpont) `abort()`-ot hív, a `beginReplace` pedig töröl mindent. **A következő indulás nulláról kezd.** A gyakorlatban valószínűleg soha nem ér a végére, és minden térképnyitáskor újra pörög.
- Ugyanazokon a magokon fut, mint a csempedekódolás, és a memória-sávszélességet is viszi. Ez a szaggatás egyik forrása naplózás nélkül.

Mit tennék:

- Külön, olcsó olvasó az indexhez: csak a nevet, a szükséges két-három címkét és az első (vagy középső) pontot olvassa, geometria és szótár nélkül. A név nélküli vonalat a jelzőbájt alapján átugorja. A vonalak nagy része ház, név nélkül.
- Folytatható állapot: az `index_state` tárolja az alfájl, a sor és az oszlop pozícióját, a kötegek külön tranzakcióban mennek. Megszakítás után onnan folytatja.
- Az alap 14-es alfájl elég. Az alap 5 és 10 ugyanazokat a neveket adja durvább geometriával.
- Ne fusson, amíg a csempedekódoló dolgozik, és amíg a kamera mozog. Vagy a letöltés végén fusson le egyszer, folyamatjelzővel, a térképtől függetlenül.
- A `PlaceScan.seen` halmaz 250 ezer kulcsig nő (kb. 15–25 MB). Elég csempénként vagy néhány szomszédos csempére deduplikálni.

A staged kódban az index naplózás alatt áll. A commitolt kódban, amivel a telefon naplói készültek, naplózás alatt és háttérben is futott. A naplózás közbeni leállásra tehát a régi buildben ez a legerősebb jelölt. A staged buildben a naplózás nélküli szaggatást magyarázza.

### 6. Az overlay és a helyzetjelző ne építse újra a teljes nyomvonalat fixenként — 50%

Hely: [MapViews.swift:1164-1178](gtl/UI/MapViews.swift#L1164-L1178), [:1186-1220](gtl/UI/MapViews.swift#L1186-L1220).

Az `OverlayStamp`-ben benne van a szélesség és a hosszúság. Naplózáskor ez minden fixnél változik, tehát minden fixnél:

- a főszálon újraépül az összes sebességszakasz minden pontja `MLNPolylineFeature`-ként (legfeljebb 300 szakasz, a teljes út),
- a MapLibre a teljes overlay-forrást újraindexeli, és minden érintett csempét újrarak.

Ez a nyomvonal hosszával nő. Egy kétórás túrán fixenként több ezer pont megy át a főszálon és a MapLibre munkaszálain, másodpercenként egyszer-kétszer. Ha a munkaszálak le vannak terhelve (lásd 1. pont), a MapLibre felé több frissítés megy, mint amennyit fel tud dolgozni, és minden várakozó frissítés a teljes nyomvonal másolatát tartja. **Ez a jelöltem a naplózás közbeni memórianövekedésre.** Bizonyítva nincs, a mérési terv 2. lépése dönti el.

Mit tennék:

- Három forrás: lezárt szakaszok (csak új szakasznál változik), a nyitott szakasz a farokkal (fixenként, de rövid), és a helyzetjelző a céllal (egy-két pont).
- A helyzetjelzőhöz `MLNPointAnnotation` saját nézettel, vagy egy sima `UIView` a térkép fölött, amit a koordinátából vetítünk. Ehhez nem kell GeoJSON-frissítés.
- A lezárt szakaszok forrása csak akkor frissüljön, ha a `mapLineToken` változott és a lezárt szakaszok száma is.

### 7. Laposabb követő kamera offline térképen — 40%

Hely: [EngineMap.swift:235](gtl/Engine/EngineMap.swift#L235), [MapViews.swift:1222-1275](gtl/UI/MapViews.swift#L1222-L1275).

Az 52 fokos döntés a MapKit domborzatához készült. Offline térképen nincs domborzat, a döntés csak annyit ad, hogy:

- a `visibleCoordinateBounds` a látóhatár felé megnyúlik, a kért terület 3–4-szeres, több Mapsforge-csempe kell,
- a MapLibre a távoli sávra sok alacsonyabb szintű csempét kér, és mindet a geojson-vt állítja elő,
- minden 5 fokos forgás új befoglaló téglalapot ad.

Javaslat: offline módban 0–30 fok az alap, és `map.maximumPitch` 45 körül. A csempekérés a képernyő közepe körüli, távolsággal korlátozott területre menjen, ne a teljes döntött trapéz befoglalójára. A 3. pont után (nincs nézetfüggő gyorsítótár) ez kevésbé fontos, de a MapLibre terhelését akkor is csökkenti.

### 8. A feliratréteg — 35%

Hely: [MapViews.swift:715-756](gtl/UI/MapViews.swift#L715-L756), [:918-926](gtl/UI/MapViews.swift#L918-L926), [:1347-1360](gtl/UI/MapViews.swift#L1347-L1360), [:1426-1529](gtl/UI/MapViews.swift#L1426-L1529).

Az `OfflineLabelView` teljes képernyős, átlátszó nézet, amit a Core Graphics a processzoron rajzol. Mozgás közben 80 ms-onként újrarajzolódik (12 kép/s): 180 horgony vetítése, `NSString.size` mérés, majd legfeljebb 56 körvonalas szöveg egy 1170 × 2532 képpontos (kb. 12 MB) bitképre. Ez a főszálon fut, pont akkor, amikor a térkép mozog. Az egyik 8,95 MiB-os IOSurface ez a réteg. A felirat ráadásul 12 Hz-en lép, a térkép 60-on, ezért a feliratok „úsznak”.

Lehetőségek, az olcsóbbtól:

- Mozgás közben ne rajzoljon újra, csak a réteget tolja (`transform`), és megálláskor rajzoljon. A szövegméreteket horgonyonként egyszer mérje le.
- A horgonyok számítása (`offlineLabelAnchors`) menjen a háttérszálra, a dekódolással együtt. Most minden publikálásnál és minden egész zoomváltásnál a főszálon járja be az összes alakzatot, horgonyonként új `UIFont`-tal.
- A rendes megoldás: `MLNSymbolStyleLayer` szöveggel. Ehhez betűkészlet-glifek kellenek. A stílusban most nincs `glyphs` kulcs. Egy betűtípus két tartománya (0–255, 256–511, az ő és ű miatt) kb. 150 KB, az appba csomagolható. Akkor a MapLibre a GPU-n rajzol, ütközést is kezel, és a feliratok együtt mozognak a térképpel.

### 9. A főszál tehermentesítése publikáláskor — 35%

Hely: [MapViews.swift:1157-1163](gtl/UI/MapViews.swift#L1157-L1163), [:1051-1083](gtl/UI/MapViews.swift#L1051-L1083), [TrackerModel.swift:1363-1366](gtl/UI/TrackerModel.swift#L1363-L1366).

Egy publikálás most a főszálon:

- `tileCache.features()`: rendezés és `flatMap`,
- `mapShapes()`: alakzatonként `layerPaints`, koordinátamásolás, egy-három `MLN…Feature` és egy `NSDictionary`,
- `source.shape = …`: az MLN objektumok átalakítása a MapLibre belső formájára, szintén a főszálon,
- `frameLocalStreets`: vonalanként négy `map` és `min`/`max`, amíg egyszer nem keretez, utána kameraváltás, ami újabb teljes frissítést indít,
- `offlineLabelAnchors`: újabb teljes bejárás.

Mit tennék:

- A `mapShapes()` a háttérszálon fusson. Az `MLNShape` objektumok szálfüggetlenül létrehozhatók, a forráshoz rendelés marad a főszálon.
- Csempénként egyszer készüljenek el az MLN alakzatok, és a gyorsítótár ezeket tartsa. Publikáláskor csak össze kell fűzni.
- A rétegkapcsolók (ház, park, tömegközlekedés) ne az alakzatok újraépítésével hassanak, hanem a stílusréteg `isVisible` tulajdonságával vagy a szűrővel. Akkor a kapcsoló azonnali, és nincs újraindexelés.
- A `frameLocalStreets` törölhető, vagy a fejléc kezdőpontjából számoljon.
- A `MapFeature` tömb ne menjen át a SwiftUI-n (`features: model.offlineFeatures`). A koordinátor közvetlenül a modelltől kérje, token alapján.

### 10. Csempénkénti források, vagy `MLNComputedShapeSource` — 30% most, hosszabb távon a helyes szerkezet

Egy közös GeoJSON-forrásnál minden új csempe a teljes forrás újraindexelését jelenti (3. kép), mind a 21 rétegre.

**a) Köztes lépés:** a forrás mérete maradjon kicsi. A 3. pont után a látható csempék alakzatai kerülnek be, a 24-es plafon helyett a ténylegesen látható csempékkel.

**b) A helyes szerkezet:** `MLNComputedShapeSource`. A fejléc megvan a 6.31.0 csomagban. A MapLibre maga kéri a csempéket z/x/y szerint egy háttérsoron, és maga kezeli a gyorsítótárat, a kidobást, a megszakítást és a részletességi szinteket. A Mapsforge-oldalon:

- a kérés z/x/y csempéjéhez megkeressük az alap 14-es csempét,
- a 16-os szintű kérés **pontosan egy alcsempe-bit**, a bitkép tehát pontos szűrő lesz, nem közelítő,
- a dekódolt alapcsempe egy kis LRU-ban marad (8–12 darab), a 16 cellára előre szétosztva,
- a forrás legnagyobb zoomja 16, afölött a MapLibre túlnagyít.

Ezzel a `refreshOffline`, az `OfflineTileCache`, a generációk, a 220 ms, a menetirány szerinti toldás és a középső csempe rögzítése mind megszűnik, mert a MapLibre elvégzi. A felhasználói kód nagyjából egy `featuresInTile` függvény és egy LRU.

Kockázat: nagyobb átírás, és a `MLNComputedShapeSource` viselkedését (hívási szál, érvénytelenítés fájlváltáskor) ki kell próbálni. Ezért az 1–4. pont után tenném, ha azok nem elegek, vagy ha a kód egyszerűsítése a cél.

### 11. A MapLibre-nézet életciklusa — 25%

Hely: [MapViews.swift:792-851](gtl/UI/MapViews.swift#L792-L851), [TrackerTabs.swift:14-19](gtl/UI/TrackerTabs.swift#L14-L19).

- A fülváltás eldobja a `MapTab`-ot, visszaváltáskor új `MLNMapView` jön létre: 13 szál, három nagy felület, stílusbetöltés, 21 réteg. Nincs `dismantleUIView`. Ha a régi nézet bármiért nem szabadul fel, fülváltásonként kb. 50 MB marad bent. A kódban nem látok erős hivatkozást, ami bent tartaná (a delegált gyenge, a gesztus célpontja nem tart meg, a koordinátor `mapView`-ja `weak`), de ezt mérni kell: tíz fülváltás után az Allocations-ben hány `MLNMapView` él.
- Javaslat: `static func dismantleUIView` hozzáadása, ami leveszi a delegáltat, kiüríti a forrásokat, és eltávolítja a feliratnézetet. Vagy a térkép nézet maradjon életben rejtve, és csak a tartalma ürüljön.
- A vezérlőközpont lehúzása vagy egy értesítés `inactive` állapotot ad. Erre a `releaseBasemap` mindent eldob, visszatéréskor minden újradekódolódik. Elég volna `background`-nál elengedni, `inactive`-nál csak szüneteltetni.
- Memóriafigyelmeztetésre (`UIApplication.didReceiveMemoryWarningNotification`) most semmi nem reagál. Ott érdemes a csempegyorsítótárat a látható csempékre vágni, és az indexet leállítani.

### 13. A rács: a `natural=sea` és `natural=nosea` téglalapok útként rajzolódnak — 95% erre a tünetre

Tünet: nagyítás és kicsinyítés közben a térképen néha szabályos fehér rács látszik, a csempék határán. Országos nézetben nagy téglalapok jelennek meg Magyarország fölött.

Ok, a fájlból kimérve: a Mapsforge-író minden csempébe betesz egy vagy két, a csempét lefedő ötpontos téglalapot.

| Alfájl | Mit tartalmaz | Méret |
| --- | --- | --- |
| alap 14 | minden csempében egy `natural=nosea` és egy `area=yes, natural=sea` | a teljes csempe |
| alap 10 | ugyanez | 0,34–0,35 fok |
| alap 5 | `natural=nosea` téglalapok | 1 fok és 0,5 fok |

Ezek a tengerpart rajzolásához kellenek: a megjelenítő előbb a tengert festi, arra a szárazföldet. A `category(for:)` ([MapsforgeReader.swift:1331-1359](gtl/Maps/MapsforgeReader.swift#L1331-L1359)) egyiket sem ismeri, és a végén minden ismeretlent `"road"`-nak ad vissza. A `mapPaint` ebből `road` festéket csinál, a téglalap tehát fehér útként, szürke szegéllyel rajzolódik a csempe szélére. Ez a rács a második képen, és ezek a téglalapok az első képen.

Azért csak „néha” látszik, mert a téglalap egy a csempe vonalai közül, és a keret, illetve az áttekintő mintavétel hol megtartja, hol kihagyja.

Javítás:

- A `natural=sea` és a `natural=nosea` vonalat a dekódoló dobja el. Magyarországon nincs tenger. Tengerparti fájlnál a `nosea` lehetne háttérkitöltés, de a stílus háttérszíne ezt most is megadja.
- **A `category` alapértéke ne `"road"` legyen.** Út csak az, aminek `highway` címkéje van. Minden más ismeretlen zárt vonal most útként, fehér körvonallal rajzolódik (a második képen a sok apró fehér zárt alakzat nagy része ilyen: parkoló, iskola, sportpálya, `area=yes`). Ezek vagy kapjanak saját kitöltést, vagy ne rajzolódjanak.

Ez néhány sor, és a többi ponttól független.

**Az első képhez (országos nézet):** a „konfetti” a mintavételből jön. Az alap 5-ös alfájl két csempéjében 22 809 vonal van, a `decodeWays` ebből minden nyolcadikat tartja meg a 2400-as keretig ([MapsforgeReader.swift:1183](gtl/Maps/MapsforgeReader.swift#L1183)). Az utak rövid OSM-szakaszokból állnak, ezért a minta össze nem érő darabokat ad. Itt nem sorszám szerint kell válogatni, hanem osztály szerint: autópálya, főút, nagy víz és határ mind, a többi semmi.

### 14. Áttekintő nézet: minden nyolcadik vonal marad meg — 90% a „hiányos, foltos térkép” tünetre 11-es zoom körül

Tünet (október 2., 1:01-es kép): a képernyő közepén egy éles szélű, téglalap alakú terület krémszínű, körülötte zöld. Az utcák mindenhol rövid, össze nem érő darabok.

Ok, a valódi fájlon az app saját csővezetékével lejátszva, ugyanarra a nézetre (Pestszentlőrinc, 47,431 / 19,188):

| Zoom | Alfájl | Vonal a csempében | Út a krémszínű területen | Azt lefedő földfelület |
| --- | --- | --- | --- | --- |
| 11 | alap 10, egy csempe | 20 556-ból 2404 marad | **6** | **0** |
| 12 | alap 14, hat csempe | 289 | 156 | 1 |
| 13 | alap 14 | 273 | 146 | 1 |
| 14 | alap 14 | 373 | 152 | 1 |

A MapLibre zoomja a képen 11-re kerekedik. Ilyenkor az olvasó az áttekintő ágra megy: az alap 10-es csempe 20 556 vonalából sorszám szerint minden nyolcadikat tartja meg ([MapsforgeReader.swift:1183](gtl/Maps/MapsforgeReader.swift#L1183)), típustól függetlenül. A földfelületek a fájlban darabokra vágva vannak; amelyik darab nem esik a mintába, annak a helye éles szélű lyuk. Az utcáknál ugyanez adja a töredékeket. 12-es zoomtól a részletes ág fut, ott a terület megvan.

Ez nem a mostani négy javítás mellékhatása, és nem elavult gyorsítótár: friss dekódolás is ezt adja.

Javítás:

- Az áttekintő ág se sorszám szerint mintázzon. A nézet az alap 10-es csempének kb. 4 százaléka, a nézetre szűrve kb. 800 vonal marad, az mind kirajzolható.
- A 4. pont (zoom +1) ezt a határt egy szinttel lejjebb tolja: a MapLibre 11-es zoomja léptékben a hagyományos 12-es, ott már az alap 14-es alfájl z12-es sora kell.
- Kisebb zoomon (ország, megye) osztály szerinti válogatás: autópálya, főút, nagy víz, erdő, lakott terület.

### 12. Apróbb hibák, amik a képet rontják — 20%

- **A változó értékű címkék rossz helyről olvasódnak.** A Mapsforge-ben előbb jön az összes címke-azonosító, és csak utánuk az értékek (`building:levels=%b`, `height=%f`, `roof:colour=%i` és társaik). A `readWay` és a `readPOI` az értéket rögtön az azonosító után olvassa ([MapsforgeReader.swift:1255-1261](gtl/Maps/MapsforgeReader.swift#L1255-L1261)). Ha a változó címke nem az utolsó, a többi azonosító, a név és a geometria elcsúszik, a vonal hibás vagy kiesik. A kimért csempékben a vonalak 0,4 százaléka érintett (184 a 43 097-ből), szinte mind ház.

- A `subtileMask` üres metszetnél `0xFFFF`-et ad ([MapsforgeReader.swift:1535](gtl/Maps/MapsforgeReader.swift#L1535)), vagyis „minden”. Ha a nézet nem metszi a csempét, a teljes csempe dekódolódik, majd minden vonal kiesik a befoglalón. A 3. pont után tárgytalan.
- Ha a `readTile` `nil`-t ad (olvasási hiba), a csempe nem kerül a gyorsítótárba, és minden kameramozdulat újra megpróbálja. Üres csempeként kellene eltárolni.
- A `chooseSubfile` 24 csempe fölött alacsonyabb alfájlra lép ([MapsforgeReader.swift:860-881](gtl/Maps/MapsforgeReader.swift#L860-L881)). 12–13-as zoomnál, döntött kameránál ez az alap 10-es alfájl, amiben nincs utca. A kép ilyenkor hirtelen durva lesz. A 7. pont (kisebb kért terület) ezt ritkítja.
- A több koordinátablokkos vonal (lyukas sokszög) blokkjai külön vonalként kerülnek ki ([:1286-1298](gtl/Maps/MapsforgeReader.swift#L1286-L1298)). A belső gyűrű kitöltött sokszögként rajzolódik a külső fölé. Udvaros háznál, szigetes tónál hibás. `MLNPolygonFeature` belső gyűrűkkel volna helyes.
- A `plausible` a 0,15 foknál nagyobb vonalat eldobja ([:1276](gtl/Maps/MapsforgeReader.swift#L1276)). Az alap 5-ös és 10-es alfájlban a folyók, határok, autópályák ennél hosszabbak lehetnek.

## Memóriaszivárgás: amit kerestem, és amit találtam

Végignéztem a `TrackerModel`, a `MapViews`, a `MapsforgeReader`, az `OfflineTileCache`, a `LocationSession` és a `PlaceIndex` hivatkozásait.

Nem szivárgás:

- `Coordinator` → `model` erős, visszafelé nincs hivatkozás. A `mapView` `weak`.
- `MLNMapView.delegate` gyenge, a `UITapGestureRecognizer` nem tartja meg a célpontját.
- A `writeChain` minden feladata az előzőt várja, de a lezárás a futás végén elengedi. Lánc csak akkor nő, ha az adatbázis lassabb a fixeknél.
- A `tileCache` korlátos (24 csempe, 64 MB), a `PlaceScan.seen` az index végén felszabadul.
- A `trackPoints`, a `samples` és a `displayTrack` a nyomvonallal nő, de óránként néhány megabájt.

Gyanús, mérendő:

| # | Jelölt | Miért | Hogyan dönthető el |
| --- | --- | --- | --- |
| 1 | MapLibre-torlódás az overlay fixenkénti cseréjétől (6. pont) | Több frissítés megy be, mint amennyi feldolgozódik, mindegyik a teljes nyomvonalat viszi | Naplózó felvétel, Generations 2 percenként: nő-e a MapLibre-hez rendelt Malloc |
| 2 | Párhuzamosan futó, megszakított dekódolások (1. b pont) | Mind végigfut, csempe-adattal és alakzatokkal | Időprofil: hány szál van a `readWay`-ben egyszerre |
| 3 | Autorelease-halmozódás a hosszú dekódoló ciklusban | A feladat nem függesztődik fel, a pool nem ürül | `@autoreleasepool content` sor növekedése a Generations-ben |
| 4 | `MLNMapView` nem szabadul fel fülváltáskor (11. pont) | Nincs `dismantleUIView` | Élő `MLNMapView` példányok száma tíz fülváltás után |
| 5 | Metal-memória döntött kameránál | Sok csempe, sok vertexpuffer | VM Tracker, IOAccelerator sor |

A telefon naplói szerint a leállás nem memória volt, hanem a processzor a gyanús (lásd „A telefon analitikai naplói”). A fenti jelöltek ettől még érvényesek a staged buildre, mert az más kódot futtat, mint amivel a naplók készültek. Egy következő leállás után ugyanott érdemes nézni: Beállítások → Adatvédelem és biztonság → Analitika és fejlesztések → Analitikai adatok. A `JetsamEvent` memória, a `gtl.cpu_resource…ips` processzor, a sima `gtl-…ips` összeomlás.

## Mérési terv, a javítás előtt és után

1. **Dekódolási idő.** `os_signpost` a `readTile` köré, csempe-azonosítóval, vonalszámmal és megtartott alakzatszámmal. Points of Interest sáv az Instrumentsben. Cél: belvárosi csempe 50 ms alatt iPhone 12-n.
2. **Naplózó felvétel, 20 perc.** Xcode-ban GPX-útvonallal szimulált mozgás Budapesten át, OSM térkép, Run/Hike mód. Allocations és VM Tracker, **automatikus pillanatképpel**. Mark Generation 2 percenként. A Dirty Size és az Xcode memóriamérője számít, nem a Total Bytes.
3. **Számlálók a diagnosztikai képernyőre:** indított, befejezett és eldobott dekódolás, publikálások száma, `os_proc_available_memory()` percenként az `ErrorLogStore`-ba. Így a következő leállásnál lesz nyom.
4. **MetricKit** (`MXDiagnosticPayload`): a következő indításkor megmondja, hogy jetsam, processzorlimit vagy összeomlás volt.
5. **Tesztek** a valódi fájl egy kivágott csempéjével: a dekódolt csempe utcaszáma egyezzen a fájl sorainak összegével (belváros z12–z14: 2326 vonal), és 16-os zoomon a házak is meglegyenek.

## Javasolt sorrend

| Lépés | Mit | Méret |
| --- | --- | --- |
| 0 | Mérés bekötése (signpost, számlálók), hogy legyen mihez hasonlítani | fél nap |
| 1 | Index, azonnali változat: megszakítás a vonalcikluson belül, ne fusson háttérben és naplózás alatt (5. pont). Ez a napló leállása elleni javítás | néhány óra |
| 2 | A `hiking` jelző a fejlécbe (2. pont első sora) | egy sor |
| 3 | A frissítési csővezeték: soros dekódoló, nincs eldobás, publikálás csempénként (1. pont) | 1 nap |
| 3b | Index, teljes változat: olcsó olvasó, folytatható állapot (5. pont) | 1 nap |
| 4 | Egész csempe, kosarak és nézetszűrés törlése, gyorsítótár-kulcs csempe + sor (3. pont), zoom +1 (4. pont) | 1 nap, sok törlés |
| 5 | A dekódoló többi része: címketábla, tömör típus, nyers mutató (2. pont) | 1–2 nap |
| 6 | Overlay három forrásra (6. pont), laposabb kamera (7. pont) | 1 nap |
| 7 | Mérés újra. Ha a főszál még akad: 8. és 9. pont | |
| 8 | Ha a szerkezetet egyszerűsíteni kell: `MLNComputedShapeSource` (10. pont) | 2–3 nap |

Az 1. lépés a napló leállását célozza. Ellenőrzés: OSM térképpel, lezárt képernyővel (vagy CarPlay mellett) egy 30 perces út, utána a GPX-ben ne legyen 10 másodpercnél hosszabb szünet, és a telefonon ne keletkezzen új `gtl.cpu_resource` jelentés. A 2–4. lépés után várható, hogy a térkép mozgás közben is frissül, és megjelennek a hiányzó utcák és házak.
