# Korrekt globális hibakezelés iOS-en

Egy iOS-appban nincs olyan hook, ami a folyamat halálának pillanatában minden hibát és minden leállást felír. A Swift `Error` nem kivétel. Az Objective-C kivételhook nem látja a memóriahibát. A jelzéskezelő nem fut le, ha a kerneltől `SIGKILL` jön. A korrekt napló ezért három réteg, és a leállás részlete a következő induláskor kerül fájlba.

Mindkét külső eszköz ingyenes, fiók és szerver nélkül is elég egy helyi fájlhoz:

- a rendszer MetricKitje, iOS 27-től a `MetricManager` API,
- a [PLCrashReporter](https://github.com/microsoft/plcrashreporter), MIT licenc.

## Mit melyik réteg lát

| Esemény | Pillanatnyi hook a folyamatban | Következő induláskor |
| --- | --- | --- |
| Elkapott Swift `Error` | saját napló a `catch` ágon | már a fájlban van |
| `fatalError`, `precondition`, kényszerített nil | PLCrashReporter (`SIGTRAP` / `SIGABRT`) | MetricKit crash, szimbolizált lánc |
| Elkapás nélküli Objective-C kivétel | PLCrashReporter | MetricKit crash |
| `EXC_BAD_ACCESS`, hibás utasítás | PLCrashReporter | MetricKit crash |
| Watchdog, `0x8badf00d` | nem fut le kód | MetricKit crash vagy hang, plusz kilépésszámláló |
| A saját memórialimit túllépése | nem fut le kód | iOS 27: `MemoryExceptionDiagnostic`, hívási lánccal |
| A rendszer memórianyomás miatt kilövi az appot, a limit alatt | nem fut le kód | kilépésszámláló, hívási lánc nélkül |
| Felhasználó kilövi az appváltóból | nem hiba | normál kilépésként számlálódik |
| Debugger alatt | a crash reporter szándékosan csendes | a debugger saját naplója |

A „minden leállás” tehát ezt jelenti: ami a folyamatból látható, azt a PLCrashReporter írja lemezre még a halál előtt; amit csak a rendszer lát, azt a MetricKit adja vissza a következő aktív futásban. A kettő együtt fedi a gyakorlati eseteket. Egy saját `NSSetUncaughtExceptionHandler` egymagában nem.

## 1. Nem fatális hibák

A Swiftnek nincs globális kivételkezelője. A `throw` csak addig megy, amíg egy `catch` vagy egy `Task` el nem kapja. Amit senki nem kap el, az a tasknál csendben eltűnhet, vagy a futásidejű ellenőrzésnél `fatalError` lesz, és az már a crash réteg.

A nem fatális napló egy közönséges fájl, a szokásos nyelvi eszközökkel:

- egy sor: idő, hely, a hiba szövege,
- méretplafon és egy elforgatott előző fájl,
- írás sorosan, hogy két szál ne tépje szét a fájlt,
- titkot, tokent, pontos felhasználói tartalmat nem ír bele.

Ezt a `catch` ágak és a saját hibaágak hívják. A crash handlerhez nincs köze, és a jelzéskezelőből tilos hívni.

## 2. Folyamaton belüli crash: PLCrashReporter

Saját `sigaction` handlert nem érdemes írni. A kezelőben csak async-signal-safe hívás szabad: `write` egy előre megnyitott fájlleíróra, `async_safe` másolás, és utána a jelzés továbbengedése. Nem szabad Swiftet, Objective-C-t, `malloc`-ot, zárolást, `os.Logger`-t vagy Foundation fájl-API-t használni. A halott folyamat heapje és zárai ekkor már hibásak lehetnek. Egy saját handler könnyen beragad, vagy üres fájlt hagy. A PLCrashReporter ezt a részt készen, MIT licenc alatt adja.

Mit fog el: `SIGABRT`, `SIGBUS`, `SIGFPE`, `SIGILL`, `SIGSEGV`, `SIGTRAP`, és az elkapás nélküli Objective-C kivételt. A Mach-kivétel port a BSD-jelzésnél több összeomlást lát. A `SIGABRT` egy része továbbra is BSD-jelzés marad, mert a Mach-os `SIGABRT` elkapása beragaszthatja a folyamatot. A könyvtár ezt így választja szét, ha a Mach mód be van kapcsolva.

Mit nem fog el, és ez nem a könyvtár hibája: `SIGKILL`. A watchdog, a jetsam és a memórialimit kívülről öli a folyamatot. Ilyenkor a handlernek nincs ideje lefutni. Ugyanezért egy iOS-app nem futtathat külső folyamatot, ami a saját Mach-portját figyelné.

Ismert lyuk: az Apple libc néhány `abort` útja a `SIGABRT` előtt leveszi a jelzéskezelőt. Ezeket a PLCrashReporter BSD-útja nem látja. A MetricKit crash diagnosztikája igen, mert azt a rendszer írja, a folyamaton kívül.

Telepítés a folyamat elején, mielőtt más könyvtár handlert rakna, és a példány a folyamat végéig éljen:

```swift
import CrashReporter

enum CrashCapture {
    private static let reporter: PLCrashReporter = {
        let config = PLCrashReporterConfig(
            signalHandlerType: .mach,
            symbolicationStrategy: .none
        )
        return PLCrashReporter(configuration: config)
    }()

    static func start() {
        reporter.enable()
    }

    static func takePendingReport() -> Data? {
        guard reporter.hasPendingCrashReport() else { return nil }
        let data = reporter.loadPendingCrashReportData()
        reporter.purgePendingCrashReport()
        return data
    }
}
```

A `enable()` hibáját a nem fatális naplóba kell írni. Ha a telepítés nem sikerül, a MetricKit ettől még működik.

A report bináris protobuf. Szöveggé a könyvtár `crashReport(with:)` és a szöveges formázója alakítja, már a következő induláskor, normál kódból. Kiadott binárisban a szimbólumok nincsenek benne, ezért a fájl címeket tartalmaz. A szimbolizálás a buildhez tartozó dSYM-mel történik, a bináris UUID alapján, az `atos` vagy a `symbolicatecrash` eszközzel. A dSYM-et a buildből meg kell tartani, különben a lánc olvashatatlan marad.

A jelzéskezelőből nem szabad saját callbackben Swiftet futtatni. A könyvtár megengedi, de a dokumentációja szerint nem ajánlott. A biztos pont a következő indulás: van-e várakozó report, kiírni a diagnosztikai fájlba, majd törölni a várakozót.

Debugger alatt a reporter nem ír reportot. Ez szándékos, hogy a lldb lássa a crash-t.

Az `NSSetUncaughtExceptionHandler` a PLCrashReporteré. Utána saját handlert tenni felülírja. Ha a nem fatális naplóba is kell az Objective-C kivétel szövege, a könyvtár handlerét kell meghívni a saját sor után, nem kicserélni.

## 3. Folyamaton kívüli leállás: MetricKit

A MetricKit a rendszer keretrendszere, külön könyvtár és küldés nélkül. A diagnosztikát nem a haldokló folyamat írja. A rendszer rögzíti, és amikor az app legközelebb aktív, azonnal átadja. iOS 15 óta a diagnosztika nem a napi metrikacsomagban vár. iOS 27-ben a belépő a `MetricManager`. A régi `MXMetricManager` feliratkozó API megmarad a régebbi rendszeren; az új képességek, köztük a memórialimit hívási lánca, csak a `MetricManager`-en jönnek.

A figyelést az induláskor kell elindítani, és a managert életben kell tartani. Ha későn indul, a jelentés elveszhet.

```swift
import Foundation
import MetricKit

final class SystemDiagnostics: Sendable {
    private let manager = MetricManager()
    private let log: DiagnosticLog

    init(log: DiagnosticLog) {
        self.log = log
        Task.detached { [manager, log] in
            for await report in manager.diagnosticReports {
                let data = try JSONEncoder().encode(report)
                log.append(kind: "metrickit", payload: data)
                switch report.result {
                case .crash(let crash):
                    log.noteCrash(
                        reason: crash.terminationReason,
                        category: crash.terminationCategory,
                        tree: crash.callStackTree
                    )
                case .memoryException(let memory):
                    log.noteMemoryLimit(memory)
                case .hang(let hang):
                    log.noteHang(hang)
                default:
                    break
                }
            }
        }
    }
}
```

A `DiagnosticReport` `Codable`. Egy JSON-sor a helyi fájlban elég. A `result` esetei: crash, hang, CPU-kivétel, lemezírás-kivétel, indulás, és memóriakivétel.

A crash diagnosztika szimbolizált hívási láncot, befejezési okot és iOS 27-től befejezési kategóriát ad. A kategória összeköti a napi kilépésszámlálót az egyes esettel: ha az abnormális kilépés nő, megvan hozzá a konkrét lánc.

A `MemoryExceptionDiagnostic` akkor készül, ha az app vagy egy extension a saját memórialimitje miatt áll le. Ez hívási láncot ad, nem csak egy számot. A rendszer memórianyomása, amikor az app a saját limitje alatt is kihal, nem ez a diagnosztika. Annak továbbra is a kilépésszámláló a nyoma.

A napi `metricReports` a trend: csúcsmemória, kilépésfajták, hangidő. Ez nem helyettesíti az egyes crash fájlját. A streamet ugyanígy, induláskor kell figyelni.

iOS 26 és régebbi rendszeren a feliratkozó a `MXMetricManager.shared`. A `MXDiagnosticPayload` adja a crash és a hang reportot. A `MXMetricPayload.applicationExitMetrics` előtér- és háttérszámlálói külön számolják a normál kilépést, az abnormális kilépést, a watchdogot, a CPU-limitot, a memórialimitot, a memórianyomást, a zárolt fájllal felfüggesztett kilövést, a hibás memóriahozzáférést és a háttérfeladat időtúllépését. Hívási lánc a memórialimithez ezen a régebbi API-n nincs.

## Indulás sorrendje

A sorrend számít. Először a crash reporter, utána a MetricKit, és csak ezután a többi keretrendszer.

1. A folyamat elején, az első saját kódnál: `CrashCapture.start()`.
2. Ha van várakozó PLCrashReporter-report, szöveggé alakítani és a diagnosztikai fájl végére írni, majd törölni.
3. Elindítani a `SystemDiagnostics` figyelőt. A MetricKit a már megtörtént leállást ezen a futáson adja át.
4. A nem fatális napló ettől fogva a `catch` ágakból írhat.

Az `applicationWillTerminate` nem fut le crashre, watchdogra és memóriakilövésre. Arra nem lehet naplót építeni.

A két forrás ugyanarról a halálról kétszer is írhat: a PLCrashReporter a folyamaton belül, a MetricKit a rendszer reportjából. A fájlban mindkettő maradhat. Az idő és a bináris UUID mellett a jelzés vagy a befejezési ok mutatja, hogy egy esetről van szó. Törölni a MetricKit-példányt nem kell, a PLCrashReporter várakozó fájlját igen, különben minden indulás újra kiírja.

## A diagnosztikai fájl

Egy fájl az Application Support alatt, a nem fatális sorokkal egy helyen, de külön névvel. A crash payload nagy lehet, ezért:

- plafon, például néhány megabájt, utána a legrégebbi report esik ki,
- a JSON és a PLCrashReporter szövege egy-egy blokk, időbélyeggel és forrással (`swift`, `plcrash`, `metrickit`),
- írás a következő indulás normál kódjából, soha nem a jelzéskezelőből.

Ha a felhasználó a készüléken nézi, a Fájlok megosztása vagy egy képernyő a fájl szövegét mutatja. Küldeni csak akkor kell, ha kell egy szerver. A MetricKit és a PLCrashReporter egyikéhez sem tartozik kötelező háttérszolgáltatás.

## Szimbólumok

Kiadott buildnél a címek magukban nem olvashatók. Minden archivált build dSYM-jét meg kell tartani, a bináris UUID-jával együtt. A PLCrashReporter reportját ezzel kell szimbolizálni. A MetricKit iOS 27-es crash lánca a rendszer szerint már szimbolizált, ezt a fájlba így kell beírni, külön `atos` nélkül.

A bitkód és a újra-optimalizált App Store build UUID-je eltérhet a helyi archívumétól. Az App Store Connectból letöltött dSYM a mérvadó, ha a bináris onnan jött.

## Amit szándékosan nem ígér a napló

- A felhasználó appváltós kilövése nem hiba. Számlálója van, stackje nincs, és nem is kell.
- A rendszerszintű memórianyomás miatti kilövésnek iOS 27-en sincs garantált hívási lánca. A limit túllépésének van.
- Egyetlen leállás sem marad ki száz százalékban a MetricKitből, ha a készülék a következő indulás előtt elveszti a diagnosztikát, vagy a figyelő későn indult. Ezért kell a PLCrashReporter a folyamatban látható crashre: az ő fájlja már a halál előtt a lemezen van.
- Más folyamat, a widget és az extension külön célpont. Mindegyik a saját indulásánál telepíti ugyanazt a két réteget, ha azok is futhatnak.

## Rövid döntés

Nem fatális hiba: saját sor a `catch`-ben. Összeomlás, amit a folyamat még láthat: PLCrashReporter, Mach módban, report a következő induláskor. Watchdog, memórialimit, és minden más, amit a rendszer a folyamaton kívül ír: MetricKit `MetricManager.diagnosticReports`, iOS 27-en a `memoryException` ággal együtt. Saját jelzéskezelőt és egyedül hagyott `NSSetUncaughtExceptionHandler`-t nem használunk.
