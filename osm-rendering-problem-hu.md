# Offline OSM rajzolás

> Ez a jegyzet a korábbi állapotot írja le. A keretek, az áttekintő mintavétel, az útkosár fenntartása és a nagyítás számítása azóta megváltozott. A mérések és a mostani állapot a `rendering-fix-hu.md` fájlban, a rövid leírás a README Térképek részében van.

Ez a jegyzet azt írja le, miért volt üres vagy töredékes a nagyított offline térkép, és az egyes kódváltozások miért kerültek be. A felhasználói leírás a `README-hu.md` és a `README-en.md` Térképek részében van.

A rajz OSM és Turistautak Mapsforge fájlra is vonatkozik. Mindkettőt ugyanaz az olvasó dekódolja, és MapLibre Native rajzolja.

## Amit a képernyő mutatott

Három külön hiba ugyanabból a dekódolásból jött.

A térkép közepe körül egy négyzet nem frissült. A szomszédos csempék utcái megvoltak, a középső terület üres vagy a korábbi, durvább rajz maradt.

Nagyításkor a rajz szétesett. Rövid, össze nem érő szürke és rózsaszín szakaszok, közöttük üres téglalapok, a jobb szélen üres rács. Az utca helyett a vonal egy darabja látszott, a házak és a földfelület hiányzott.

Tovább nagyítva a képernyő nagy része krém színű üres volt. Csak egy alsó sávban volt zöld felület, barna ösvény és felirat (Lőrinci temető). A helyzetjelző az üres területen ült. A Miklóstelep felirat megjelent az üresen, mert egy pont vagy egy név megmaradt, az utcák azon a részen nem.

Instrumentsben az All Heap Total Bytes körülbelül 2,4 GiB volt egy negyven másodperces felvételen. Ez az összes foglalás összege, a már felszabadítottakkal együtt. A tartós készlet körülbelül 66 MB volt, amíg a térkép nyitva volt: nagyrészt IOSurface (a GPU felületei) és a MapLibre szálainak vermei. Egy 1 MB körüli MapLibre blokk néhány száz milliszekundum után felszabadult. A Swift sztringek forgalma nagy összesen, kis tartós méret.

## Miért így tárolja a Mapsforge

A fájl nagyítási sávokra, alfájlokra van osztva. Egy alfájl csempéjének azonosítója az alap-nagyítás, az oszlop és a sor. Nem a képernyő aktuális nagyítása. 16–18-as képernyő-nagyításnál gyakran egy 12–14-es alapú csempe nagyobb, mint a telefon. Az egész képernyő egy csempe belsejébe esik.

A csempében a vonalak nagyítási sorokban vannak, az alacsonyabbtól a magasabb felé. Az első sor a durva utaké és a nagy felületeké. Az utca és a ház a képernyő nagyításához tartozó későbbi sorban van. Egy soron belül a vonalak a fájl írásának sorrendjében vannak, nem északról délre. Az első néhány száz vonal ezért egy földrajzi sarokba eshet, a helyzetjelző pedig a csempe másik felén üres marad. Ez az alsó sáv.

A 4 MB-nál nagyobb csempét az olvasó nem töltötte be egészben. A régi út a vonallista elejéből olvasott legfeljebb 4 MB-ot. Egy városi csempén ez pont a durva sor, az utcák a fájl későbbi részén vannak.

Minden vonal elején 2 bájtos alcsempe-bitkép van. A csempe 4×4-es rács, két nagyítási szinttel az alap alatt. A legmagasabb bit az északnyugati cella, utána balról jobbra, fentről lefelé. A partvonal mind a 16 bitet beállítja. A bitképből eldönthető, hogy a vonal egyáltalán metszi-e a nézetet, a koordináták végigolvasása nélkül.

A helyek (POI) a vonalak előtt vannak, szintén fájlsorrendben. Az első néhány tucat hely nem feltétlenül a képernyőn van. Ezért látszott egy településnév ott, ahol utca nem.

A csempe gyorsítótár kulcsa az alap-nagyítás és a csempe oszlopa, sora. Ugyanaz a csempe 14-es és 17-es képernyő-nagyításnál is ugyanaz az azonosító. Ha a 14-es, ritka dekódolást megtartjuk 17-nél, a nagyított kép a durva vonalakat rajzolja újra.

A menetirány szerinti rendezés és a 64 MB-os bájtkorlát a kamera előtti nagy csempéket hagyta meg, a középsőt pedig eldobhatta, ha az volt a legnagyobb. A középső négyzet ezért maradt üresen, miközben a széle frissült.

## Változások, és miért

### A durva vonalak helyett a képernyő sora

A részletes dekódolás (`queryZoom` 11 fölött, nézet szűrés nélkül) a `ZoomWayBudget` tervet használja. A keret 75 százaléka a képernyő nagyítási sorára megy, a maradék a durvább sorokra, felülről lefelé, és ami még fér, visszamegy a részletes sorra. Áttekintésnél (`queryZoom` legfeljebb 11, vagy 36-nál több csempe) a terv továbbra is az alacsony sortól tölti a keretet, mert ott az egész tájat kell mutatni, nem egy utcát.

A helynévindex ezt az utat használja, nézet nélkül, csempénként nagy kerettel. A keresés így nem csak a most látható utcaneveket kapja.

### A nagy csempe végigolvasása

A 4 MB fölötti csempe részletes nézetben nem a vonallista elején áll meg. Egy 256 KB-os ablakkal végigmegy a kért nagyítási sorokon (`streamPlannedWays`, illetve nézet szerint `streamVisibleWays`). Az áttekintő nagy csempe továbbra is legfeljebb 4 MB-ot olvas az első vonaltól, mintával, mert ott a teljes csempét kell képviselni, nem egy utcát.

### A középső csempe bent marad

A látható csempék a nézet közepe felől vannak sorba rakva. A gyorsítótár a láthatót a menetirány mögötti elé, azon belül a közeli elé sorolja, majd a 24 csempés és 64 MB-os plafonnál vág. A vágás után a képernyő közepéhez legközelebbi csempe akkor is visszakerül, ha a bájtkorlát kidobta. Enélkül a menetirányban előre eső, nagy csempék kitöltötték a keretet, és a középső négyzet nem frissült.

### Újraolvasás, ha a nagyítás vagy a nézet kilép

A gyorsítótár megjegyzi, milyen képernyő-nagyításhoz és milyen területre készült a csempe. Újra kell olvasni, ha nincs ilyen csempe, ha a kért nagyítás nagyobb, vagy ha a csempének a most látható része nincs benne a korábbi lefedésben. Kisebb nagyítás önmagában nem indít új dekódolást, amíg a látható rész a lefedett területen belül van. A lefedés a képernyő, minden irányban a fesztáv 45 százalékával megtoldva. Ezen a ráhagyáson belüli húzás nem indít új olvasást.

A helynévindex és az áttekintés lefedése a csempe saját földrajzi téglalapja, mert ott a vonalak nincsenek a képernyőre szűrve.

### Képernyőre szűrés 11-es nagyítás fölött

Ez a nagyítás üres felső részét javítja. A dekódolás nem az első N vonalat tartja meg a sorból, hanem azokat, amelyek metszik a megtoldott képernyőt.

A szűrés két lépés. Először az alcsempe-bitkép: ha a maszk nem a teljes csempe, és a vonal egy bitje sem esik a nézet celláira, a rekord mérete alapján átugorjuk, koordináta nélkül. Utána a tényleges befoglaló: pont akkor marad, ha a téglalapban van, vonal akkor, ha a befoglalója metszi a nézetet. A bitkép mercator-rács, a befoglaló a már dekódolt koordináta. A bitkép a gyors szűrő, a befoglaló a pontos.

A keret három kosár. Az út, a vasút és a vízfolyás a keret 60 százaléka. A föld, a víz és a park 20 százalék. A ház és minden más a maradék. A durvább sorok az útkosárnak csak a negyedét tölthetik. A háromnegyed a képernyő sorának utcáira van fenntartva. Ha egy durvább sor kosarai megteltek, a sor többi vonala méret alapján kimarad. A képernyő során addig megy az olvasás, amíg mind a három kosár meg nem telik, vagy a sor véget nem ér.

A teljesen dekódolt vonalak száma csempénként `max(keret × 8, 2500)`. A bitkép miatt átugrott vonal ebbe nem számít. A plafon azért van, hogy egy sűrű városi csempe ne olvasson korlát nélkül. Ha az utcák a cellán belül ennél később vannak, azok a vonalak ebből a menetből kimaradnak.

A helyeknél, ha van nézet, az olvasó nem az első N ponton áll meg. Továbbmegy, legfeljebb a helykeret ötvenszereséig, és a nézetbe eső pontokat tartja meg. Nézet nélkül, ahogy a helynévindex csinálja, az első N pont marad.

### Keretek

A részletes nézet összesen legfeljebb 4800 vonal. Ebből csempénként legfeljebb 2000, ha egy vagy két csempe fedi a nézetet, 900 hat csempéig, és 400 afölött. Az áttekintés összesen legfeljebb 2400, csempénként kisebb részesedéssel. A helykeret áttekintésnél 6, részletes nézetnél 28.

A 2000-es csempekeret a nagyított, egy csempés nézethez kell. A korábbi 320–600 vonal a fájl elejéről kevés volt egy egész képernyőhöz, és ráadásul nem is a képernyő vonalai voltak. A 4800-as összesen és a csempénkénti plafon a MapLibre-nak átadott geometriát fogja. A 64 MB-os csempegyorsítótár ettől függetlenül megmaradt.

### Rajzolás a MapLibre-ban

A kész vonalak egy GeoJSON forrásba kerülnek. A forrás csak akkor számít frissítettnek, ha a stílus betöltése után a forrás már létezik. Korábban a korszak akkor is előrelépett, ha a forrás még nem volt meg, és a későbbi szinkron a már „kész” korszak miatt nem rajzolt.

A forrás alakja a helyén cserélődik. Nincs előtte üresre állítás. Az üresre állítás versenyben maradt az új alakzattal, és a térkép üresen maradt.

A nyomvonal, a helyzetjelző és a cél külön forrás. Az csak akkor épül újra, ha a vonal, az útvonal, a sebességsávok, a farok, a helyzet vagy a cél tényleg változott. A térkép minden kameraképénél újraépíteni ezeket felesleges foglalás volt.

A csempék egyenként dekódolódnak, 220 ms várakozás után, hogy egy húzás ne indítson dekódolást minden képkockán. Ha közben új kameraérkezés jön, a félbemaradt munka nem publikál. A sikeres menet a végén egyszer adja át a vonalakat a térképnek.

### Amit kipróbáltunk, és kivettünk

A 2,4 GiB-os Instruments-számra ezek mentek be, majd ki, mert a tartós készletet nem vitték le, a térképet viszont üresre rajzolták:

- a MapLibre csempegyorstárának kikapcsolása
- a csempe-előtöltés kikapcsolása
- szinkron GeoJSON-frissítés
- nulla egyszerűsítési tűrés és 256-os csempepuffer
- a forrás legnagyobb nagyításának 16-ra fogása
- a forrás alakjának kiürítése az új alakzat előtt

A tartós memória a nyitott térkép GPU-felülete és a MapLibre szálai. Azt a térkép bezárása engedi el, nem egy szigorúbb tesszellálás. Az összesen számláló felszabadított foglalást is mutat, azt nem kell 2 GB-os szivárgásként kezelni.

## Ami most a kódban van

- `gtl/Maps/MapsforgeReader.swift`: nagyítási keret, nézetre szűrés, alcsempe-bitkép, útvonal-kosarak, nagy csempe ablakos olvasása, csempénkénti plafon.
- `gtl/Maps/OfflineTileCache.swift`: 24 csempe, 64 MB, középső csempe megtartása, újraolvasás nagyobb nagyításnál vagy ha a látható rész kilép a lefedésből.
- `gtl/UI/TrackerModel.swift`: a képernyő a szűrés középpontja, a menetirány csak a kért csempék terét toldja meg, egy csempe egyszerre, egy publikálás a végén. Részletes keret 4800, áttekintés 2400.
- `gtl/UI/MapViews.swift`: a GeoJSON forrás a helyén cserélődik, a korszak csak létező forrásnál lép, a nyomvonal-réteg csak valódi változáskor épül újra.

A tesztek a nagyítási keretet, a nézetbe eső utca megtartását, az északnyugati alcsempe bitjét, a középső csempe bent maradását, és azt ellenőrzik, hogy a gyorsítótár nagyobb nagyításnál és a lefedésen kívül újraolvas.
