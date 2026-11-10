# maia-session-service — analiza wykonalności

Stan: projekt, bez implementacji (2026-11-10, Maia 0.2.0, gałąź main `7ec37dd`).

## W skrócie

- **Wykonalne, i warto.** Nowa usługa w Rust, `maia-session-service`, staje się głównym procesem
  sesji: uruchamia kompozytor, usługi KDE, usługi Maia i `appMaiaServer`, pilnuje ich, a jako jedyna
  rozmawia z `systemd-logind` (wylogowanie, restart, wyłączenie, uśpienie).
- **Największy zysk:** awaria `appMaiaServer` (powłoki) przestaje kończyć sesję. Usługa uruchamia
  powłokę od nowa, a otwarte programy zostają, tak jak po awarii `plasmashell` w Plasmie.
- **Tak samo robi Plasma 6:** jej menedżer sesji (`plasma_session`) uruchamia `kwin_wayland_wrapper`
  jako swój proces potomny (`plasma-workspace/startkde/plasma-session/startup.cpp:162`).
- **Bash zostaje tylko w fazie 1** (zmienne środowiska, skrypty dystrybucji, `dbus-run-session`),
  potem `exec maia-session-service`. Faza 2 skryptu znika.
- **API:** kontrakt `session.capnp` (Cap'n Proto, jak pozostałe usługi) i moduł QML `Maia.Session`,
  który zastępuje `MSessionManager` z `Maia.Backend`.
- **Trzy etapy.** Etap 1 sam w sobie daje najwięcej i niczego nie psuje we frontendach.

---

## 1. Jak jest dziś

```
SDDM
 └─ run_maia_kwin.sh  (faza 1: środowisko)
     └─ exec kwin_wayland_wrapper --xwayland --exit-with-session=run_maia_kwin.sh
         └─ kwin_wayland
             └─ run_maia_kwin.sh  (faza 2, bash)
                 ├─ systemctl --user start plasma-kwallet-pam, -polkit-agent, -powerdevil, -kaccess
                 ├─ maia-windows-service &
                 ├─ maia-network-service &
                 ├─ maia-appearance-service &          (tylko KWin)
                 └─ appMaiaServer  ← skrypt czeka na niego
```

Pod Wayfire to samo, tylko fazę 2 uruchamia `[autostart]` z `wayfire.ini`, a na końcu skrypt zabija
Wayfire po PID-zie (`MAIA_COMPOSITOR_PID`).

Wylogowanie, restart, wyłączenie i uśpienie obsługuje dziś `appMaiaServer`: usługa D-Bus
`org.maia.SessionService` (`Maia/BackendLib/server/SessionService.cpp`), wołana przez
`MSessionManager` (`Maia/BackendLib/MSessionManager.cpp`). Wylogowanie polega na tym, że
`appMaiaServer` się kończy, a za nim skrypt i kompozytor.

### Co z tego wynika

1. **Awaria powłoki kończy sesję.** Skrypt czeka na `appMaiaServer`; gdy ten padnie, skrypt się kończy,
   KWin też (`--exit-with-session`), a z nim wszystkie otwarte programy.
2. **Awaria usługi Maia nie jest naprawiana.** Padnie `maia-network-service`, to Wi-Fi w powłoce nie
   działa do końca sesji (moduł QML łączy się co sekundę, ale nie ma z czym).
3. **Proces GUI decyduje o sesji.** Zamykanie sesji siedzi w procesie, który rysuje powłokę i ładuje
   frontendy: najbardziej narażonym na błędy.
4. **Wayfire kończy się przez `kill` na PID-zie rodzica.** Działa, ale to obejście.
5. **Bash nie nadaje się do pilnowania procesów:** kolejność, gotowość, restarty i limity czasu
   w bashu są kruche i trudne do testowania.
6. **`--exit-with-session` a awaria KWina:** proces sesji jest dzieckiem samego `kwin_wayland`, nie
   wrappera (`kwin/src/main_wayland.cpp:196`). Po awarii wrapper uruchamia nowy KWin z tymi samymi
   argumentami, który uruchomiłby fazę 2 drugi raz, obok starej. Plasma tej drogi nie używa.

---

## 2. Jak będzie

```
SDDM
 └─ run_maia_kwin.sh / run_maia_wayfire.sh   (bash, tylko faza 1)
     └─ exec maia-session-service --compositor kwin|wayfire
         ├─ 1. kompozytor
         │      KWin:    kwin_wayland_wrapper --xwayland <pomocnik gotowości>
         │      Wayfire: wayfire -c ~/.config/maia/<v>/wayfire.ini
         ├─ 2. kglobalacceld                      (tylko Wayfire)
         ├─ 3. usługi KDE: systemctl --user start plasma-kwallet-pam, -polkit-agent, -powerdevil, -kaccess
         ├─ 4. maia-windows-service, maia-network-service, maia-appearance-service
         └─ 5. appMaiaServer                      (po awarii uruchamiany od nowa)
```

`maia-session-service` jest liderem sesji: SDDM czeka na niego, a gdy on się kończy, kończy się sesja.

### Co usługa robi, a czego nie

Robi:

- uruchamia procesy sesji w ustalonej kolejności i czeka na ich gotowość;
- pilnuje ich i uruchamia ponownie po awarii, z limitem;
- kończy sesję w ustalonej kolejności, z limitem czasu na każdy krok;
- rozmawia z logind: wyłączenie, restart, uśpienie, hibernacja, możliwości (`Can*`), blokady
  (`Inhibit`), sygnały `PrepareForSleep`, `Lock`, `Unlock`;
- wystawia kontrakt `session.capnp`;
- zbiera wyjście procesów potomnych do logu sesji.

Nie robi:

- **żadnego GUI.** Okno „Czy na pewno wylogować?” pokazuje powłoka, potem woła `logout()`;
- **niczego, co nie dotyczy życia sesji.** Sieć, okna i wygląd zostają w swoich usługach;
- **ustawień środowiska z fazy 1.** Wczytywanie `plasma-workspace/env/*.sh` dystrybucji wymaga basha.

Im mniej robi, tym trudniej ją wywrócić. To ważne, bo jej awaria kończy sesję (punkt 9).

---

## 3. Start sesji krok po kroku

1. **Faza 1 (bash, bez zmian):** `dbus-run-session`, zmienne `XDG_*`, `QT_QPA_PLATFORM`,
   `XDG_CONFIG_DIRS`, katalog `~/.config/maia/<v>/`. Pod Wayfire: pierwsza kopia `wayfire.ini`
   z szablonu. Na końcu `exec maia-session-service --compositor kwin` (albo `wayfire`).
2. **Gniazdo usługi:** `$XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock` (punkt 7). Usługa zakłada je
   przed kompozytorem, więc może od razu odpowiadać na pytania o stan sesji.
3. **Kompozytor:** uruchomienie i czekanie na gotowość (limit np. 20 s; po przekroczeniu sesja kończy
   się z wpisem w logu, a SDDM wraca do ekranu logowania).
4. **Środowisko:** `WAYLAND_DISPLAY`, `DISPLAY`, `XAUTHORITY` od kompozytora trafiają do środowiska
   procesów potomnych i do aktywacji D-Bus i systemd (dziś robi to
   `dbus-update-activation-environment --systemd` w fazie 2). Do tego `MAIA_SESSION_SOCKET`
   i `MAIA_COMPOSITOR`.
5. **kglobalacceld** (tylko Wayfire; KWin ma go wbudowanego), potem **usługi KDE** przez
   `systemctl --user start --no-block`, jak dziś, z tym samym zapasowym startem z autostartu.
6. **Usługi Maia**, każda od razu po poprzedniej. Nie trzeba czekać na ich gotowość: moduły QML łączą
   się same, gdy gniazdo się pojawi.
7. **`appMaiaServer -platform wayland`**, z `MAIA_LOG_FILE` i `MAIA_LOG_PORT` jak dziś.

### Gotowość kompozytora: pomocnik

Problem: usługi i powłoka potrzebują `WAYLAND_DISPLAY` i `DISPLAY`, a nazwy gniazd wybiera kompozytor.
Wrapper KWina wybiera wolną nazwę sam (`wl_socket_create`), Wayfire też (`choose_socket`, bez opcji
wyboru; `wayfire/src/main.cpp`, v0.10.0).

Rozwiązanie, jednakowe dla obu kompozytorów: kompozytor uruchamia mały proces pomocniczy, który
dziedziczy jego środowisko, przekazuje je głównej usłudze przez jej gniazdo i od razu się kończy:

```
maia-session-service --compositor-ready
```

- **KWin:** jako „aplikacja do uruchomienia” (argument pozycyjny `kwin_wayland`, który wrapper
  przekazuje dalej):
  `kwin_wayland_wrapper --xwayland "maia-session-service --compositor-ready"`. W odróżnieniu od
  `--exit-with-session` jego zakończenie nie kończy KWina. Po awarii KWina wrapper uruchamia nowy
  KWin, a ten znów uruchamia pomocnika: usługa dostaje przy okazji wiadomość „KWin wstał ponownie”
  (zmienne są te same, bo wrapper trzyma gniazda).
- **Wayfire:** przez `[autostart]`. Szablon ma już wpis `maia = "$MAIA_SESSION_SCRIPT"`. Wystarczy,
  że usługa ustawi `MAIA_SESSION_SCRIPT="<prefix>/libexec/maia-session-service --compositor-ready"`,
  i istniejące pliki `~/.config/maia/0.2.0/wayfire.ini` działają bez zmian, łącznie z Twoim.

Dodatkowo, dla KWina: wrapper rejestruje nazwę D-Bus `org.kde.KWinWrapper`, gdy wyeksportował
zmienne (`kwin/src/helpers/wayland_wrapper/kwin_wrapper.cpp`). To drugi, niezależny sygnał
gotowości, przydatny w logu.

---

## 4. Pilnowanie procesów

### Zasady dla każdego procesu

| Proces | Po awarii | Gdy nie da się go utrzymać |
|---|---|---|
| kompozytor (KWin) | restartuje go wrapper, na tych samych gniazdach | wrapper kończy się po 10 awariach: koniec sesji |
| kompozytor (Wayfire) | koniec sesji (wszystkie okna i tak zginęły) | — |
| `appMaiaServer` | restart po 1 s, 2 s, 4 s… | 5 awarii w 2 minuty: koniec sesji z wpisem w logu |
| usługi Maia | restart po 1 s, 2 s, 4 s… (maks. 30 s) | dalsze próby co 30 s; sesja trwa bez tej usługi |
| `kglobalacceld` | restart jak usługa Maia | jak usługa Maia |
| usługi KDE (systemd) | pilnuje ich systemd | — |

Po awarii KWina programy Qt wracają same (`QT_WAYLAND_RECONNECT=1`), a GTK, Chrome i programy X11
giną. Tego nie da się naprawić po stronie Maia: to cecha protokołu Wayland.

Pod Wayfire można później spróbować więcej: uruchomić Wayfire i powłokę od nowa zamiast wracać do SDDM.
Programy i tak by zginęły, więc zysk jest mały; na początek wystarczy czysty koniec sesji.

### Mechanika w Linuksie

- **`PR_SET_PDEATHSIG`** (przez `pre_exec` w `std::process::Command`): każde dziecko dostaje `SIGTERM`,
  gdy usługa sesji umrze. Nic nie zostaje osierocone, a SDDM wraca do ekranu logowania.
- **`PR_SET_CHILD_SUBREAPER`:** procesy osierocone w sesji (np. programy uruchamiane przez
  `maia-windows-service` w osobnej grupie procesów, `launch.rs`) trafiają pod usługę sesji, a nie pod
  `systemd --user`. Usługa musi je odbierać (`waitpid` w pętli po `SIGCHLD`), żeby nie zostawały
  zombie, i może je zakończyć przy wylogowaniu.
- **Sygnały:** `SIGTERM` i `SIGHUP` od SDDM albo systemd (np. `systemctl poweroff` z terminala) uruchamiają
  szybki koniec sesji (punkt 5) z krótkimi limitami. `SIGINT` w testach tak samo.
- **Wyjście procesów** (`stdout`, `stderr`) czytane przez usługę i zapisywane do logu sesji z nazwą
  procesu na początku linii: `[maia-network-service] …`. Dziś wszystko leci do jednego logu bez
  oznaczeń.

### Zgodność w etapie 1: wyjście `appMaiaServer`

Dziś „wyloguj” znaczy: `appMaiaServer` kończy się z kodem 0. Dopóki frontendy nie przejdą na
`Maia.Session` (etap 2), usługa sesji czyta wyjście powłoki tak:

- **kod 0:** prośba o wylogowanie, czyli koniec sesji, jak dziś;
- **awaria albo kod różny od 0:** restart według tabeli.

Od etapu 2 wylogowanie idzie przez `logout()`, a kod 0 bez prośby traktujemy jak awarię.

---

## 5. Koniec sesji

### Wylogowanie

1. Usługa przechodzi w stan `ending` (`action = logout`) i powiadamia słuchaczy: powłoka może pokazać
   „Wylogowywanie…”.
2. Czeka na zwolnienie blokad (`inhibit`, etap 3), maks. kilka sekund.
3. *(Etap 3)* Prosi programy o zamknięcie przez `maia-windows-service` (`WindowControl.close` dla każdego
   okna), czeka maks. ok. 10 s. Program z niezapisanym dokumentem może to przerwać.
4. Kończy `appMaiaServer` (`SIGTERM`, po 5 s `SIGKILL`).
5. Kończy usługi Maia i `kglobalacceld`, zatrzymuje usługi KDE (`systemctl --user stop`).
6. Kończy kompozytor (`SIGTERM`, po 5 s `SIGKILL`). Tak samo dla KWina i Wayfire: to jego dziecko.
7. Sama się kończy. `dbus-run-session` się kończy, SDDM pokazuje ekran logowania.

### Restart, wyłączenie

Kroki 1–4 jak wyżej, potem `PowerOff` albo `Reboot` w logind, **zanim** znikną kompozytor i agent
polkit. Powód: gdy zalogowany jest inny użytkownik, logind odpowiada `challenge` i polkit pyta
o hasło administratora. Okno z hasłem pokazuje `plasma-polkit-agent`, a do tego potrzebny jest
działający kompozytor. Tak samo robi Plasma (`plasma-shutdown` po wylogowaniu, przy działającym KWinie).

Jeśli logind odmówi (np. użytkownik anulował hasło), sesja nie jest już do uratowania, bo powłoka
została zamknięta w kroku 4. Rozwiązanie: przed krokiem 1 sprawdzić `CanPowerOff`/`CanReboot`, a gdy
jest `challenge`, najpierw zapytać o uprawnienie, a dopiero potem zamykać. To samo robi Plasma:
możliwość sprawdza z góry.

### Uśpienie, hibernacja

Bez zamykania czegokolwiek: wywołanie w logind. Przed uśpieniem logind wysyła `PrepareForSleep(true)`,
po przebudzeniu `PrepareForSleep(false)`. Usługa trzyma blokadę typu `delay`, przekazuje sygnał powłoce
i zwalnia blokadę, gdy powłoka gotowa (np. zablokowała ekran, gdy będzie ekran blokady) albo po
limicie czasu.

---

## 6. logind

Usługa jako jedyny proces Maia rozmawia z `org.freedesktop.login1` (D-Bus systemowy, `zbus`, jak
`maia-network-service` z NetworkManagerem).

| Co | Po co |
|---|---|
| `Manager.PowerOff`, `Reboot`, `Suspend`, `Hibernate`, `HybridSleep`, `SuspendThenHibernate` (z `interactive = true`) | koniec sesji, uśpienie |
| `Manager.CanPowerOff`, `CanReboot`, `CanSuspend`, `CanHibernate`… (`yes`, `no`, `challenge`, `na`) | które przyciski pokazać i czy będzie pytanie o hasło |
| `Manager.Inhibit(what, who, why, mode)` | blokady `delay` przed uśpieniem i wyłączeniem |
| sygnały `Manager.PrepareForSleep`, `PrepareForShutdown` | „za chwilę uśpienie”, „za chwilę wyłączenie” (także spoza Maia) |
| `Manager.GetSession($XDG_SESSION_ID)`, sygnały `Session.Lock`, `Unlock` | `loginctl lock-session` i blokada po uśpieniu, dla przyszłego ekranu blokady |
| `Session.SetLockedHint`, `SetIdleHint` | później, z ekranem blokady i bezczynnością |

**Atrapa logind do testów** (`MAIA_SESSION_BACKEND=fake`, jak `MAIA_NETWORK_BACKEND=fake`): zapisuje
wywołania do logu i udaje odpowiedzi (`CanPowerOff = yes`, a na życzenie `challenge` albo odmowę).
Zastępuje dzisiejsze `MAIA_NESTED_SESSION=1` z `SessionService`. Sesja zagnieżdżona zawsze używa
atrapy, więc test nigdy nie wyłączy prawdziwego komputera.

---

## 7. Kontrakt: `session.capnp`

Zasady jak w `network.capnp`: `watch()` wysyła najpierw cały stan (`snapshot`), potem tylko zmiany,
dopóki klient trzyma `Subscription`; wyniki, które użytkownik ma zobaczyć, to wartości (`Result`),
a nie wyjątki; teksty dla ludzi nie są częścią kontraktu.

**Gniazdo:** `$XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock`. Inne usługi mają w nazwie
`$WAYLAND_DISPLAY`, ale ta zakłada gniazdo przed kompozytorem, więc nazwy ekranu jeszcze nie zna.
`XDG_SESSION_ID` ustawia `pam_systemd` przy logowaniu. Pełną ścieżkę dostaje każdy proces sesji
w `MAIA_SESSION_SOCKET`, także programy aktywowane przez D-Bus (środowisko aktywacji). Brak
`XDG_SESSION_ID` (testy): `session-<pid usługi>.sock`.

**Dostęp:** gniazdo leży w `XDG_RUNTIME_DIR` (tylko właściciel), a usługa sprawdza `SO_PEERCRED`
(ten sam użytkownik). Tak samo jak dziś z D-Bus: każdy proces użytkownika może go wylogować.

```capnp
@0x………………;   # nowy identyfikator: capnp id

# Contract of the Maia session service (maia.session, version 1).
#
# maia-session-service starts the session (the compositor, KDE's and Maia's services, the shell),
# keeps it running and ends it; it is the only process of Maia that talks to systemd-logind.
# Socket: $MAIA_SESSION_SOCKET ($XDG_RUNTIME_DIR/maia/session-$XDG_SESSION_ID.sock).

enum ErrorCode {
  none @0;
  notAllowed @1;          # logind or polkit refused, or the user cancelled the authentication
  notSupported @2;        # e.g. hibernation without swap
  busy @3;                # the session is already ending
  inhibited @4;           # an inhibition holds it up; see Result.message
  failed @5;              # anything else; Result.message has the detail (for logs)
}

struct Result {
  error @0 :ErrorCode;
  message @1 :Text;
}

enum Ability {
  no @0;                  # not possible (logind "no" or "na")
  yes @1;
  challenge @2;           # possible after the administrator's password (polkit)
}

struct Capabilities {
  logout @0 :Bool;
  powerOff @1 :Ability;
  reboot @2 :Ability;
  suspend @3 :Ability;
  hibernate @4 :Ability;
  hybridSleep @5 :Ability;
  suspendThenHibernate @6 :Ability;
}

enum State {
  starting @0;            # before the shell runs
  running @1;
  ending @2;              # logout, reboot or power off is under way (Ending says which)
  sleeping @3;            # between PrepareForSleep(true) and PrepareForSleep(false)
}

enum EndAction {
  logout @0;
  reboot @1;
  powerOff @2;
}

struct Ending {
  action @0 :EndAction;
  initiator @1 :Initiator;
  enum Initiator {
    user @0;              # logout(), reboot(), powerOff() of this contract
    system @1;            # SIGTERM, or logind's PrepareForShutdown from outside the session
  }
}

enum ChildKind {
  compositor @0;
  shell @1;               # appMaiaServer
  maiaService @2;
  kdeService @3;
  helper @4;              # kglobalacceld, …
}

enum ChildState {
  waiting @0;             # not started yet
  running @1;
  restarting @2;          # crashed, waiting for its next start
  failed @3;              # given up (see the restart limits)
  stopped @4;             # ended on purpose
}

struct Child {
  name @0 :Text;          # "maia-network-service", "appMaiaServer", "kwin_wayland_wrapper"
  kind @1 :ChildKind;
  state @2 :ChildState;
  pid @3 :UInt32;         # 0 when not running
  restarts @4 :UInt32;    # since the session started
  lastExit @5 :Text;      # "exit code 1", "signal 11 (SIGSEGV)", for logs and a debug page
}

struct Info {
  serviceVersion @0 :Text;
  maiaVersion @1 :Text;   # "0.2.0"
  compositor @2 :Text;    # "kwin", "wayfire"
  sessionId @3 :Text;     # logind's session id
  backend @4 :Text;       # "logind", "fake"
}

interface SessionListener {
  snapshot @0 (state :State, ending :Ending, capabilities :Capabilities, children :List(Child));
  stateChanged @1 (state :State, ending :Ending);
  capabilitiesChanged @2 (capabilities :Capabilities);
  childChanged @3 (child :Child);
  # logind's Lock and Unlock of this session (loginctl lock-session, …), for the lock screen
  lockRequested @4 ();
  unlockRequested @5 ();
}

interface Subscription {}

# Held as long as it is needed; dropping it (or the client disconnecting) ends the inhibition
interface Inhibition {}

enum InhibitWhat {
  ending @0;              # logout, reboot, power off wait (at most a few seconds)
  sleep @1;               # suspend and hibernation wait (logind delay lock)
}

interface SessionService {
  info @0 () -> (info :Info);
  watch @1 (listener :SessionListener) -> (subscription :Subscription);
  control @2 () -> (control :SessionControl);
}

interface SessionControl {
  logout @0 () -> (result :Result);
  reboot @1 () -> (result :Result);
  powerOff @2 () -> (result :Result);
  suspend @3 () -> (result :Result);
  hibernate @4 () -> (result :Result);
  hybridSleep @5 () -> (result :Result);
  suspendThenHibernate @6 () -> (result :Result);

  # "Wait, I am saving": the shell, Maia Settings or an app holds the session up a little
  inhibit @7 (what :List(InhibitWhat), who :Text, why :Text) -> (result :Result, inhibition :Inhibition);

  # By hand, e.g. from a debug page of Maia Settings: start a child again (the shell too)
  restartChild @8 (name :Text) -> (result :Result);
}
```

Odpowiedzi metod kończących sesję przychodzą od razu po przyjęciu prośby. To, co dzieje się dalej
(`ending`, kolejne procesy zatrzymane), przychodzi przez słuchacza, jak w `network.capnp`.

Celowo **poza** pierwszą wersją: anulowanie rozpoczętego wylogowania, zapis i przywracanie sesji
(które programy były otwarte), przełączanie użytkownika, bezczynność i wygaszacz.

---

## 8. Moduł QML: `Maia.Session`

`Maia/services/session/qml/`, C++, tak samo zbudowany jak `Maia.Network`: połączenie Cap'n Proto
w osobnym wątku, ponowne łączenie co sekundę, gniazdo z `MAIA_SESSION_SOCKET`.

| Typ | Co daje |
|---|---|
| `Session` (singleton) | `connected`, `state`, `endingAction`; `canLogout`, `canSuspend`, `canReboot`, `canPowerOff`, `canHibernate`, `powerOffNeedsAuthorization`…; `logout()`, `reboot()`, `powerOff()`, `suspend()`, `hibernate()`; sygnały `endingStarted(action)`, `lockRequested()`, `unlockRequested()`, `prepareForSleep(sleeping)` |
| `SessionInhibitor` | deklaratywny, jak `SecretPrompt`: `active: true`, `what`, `reason`. Np. Maia Settings przy zapisie |
| `SessionChildrenModel` | lista procesów sesji ze stanem i liczbą restartów: na stronę diagnostyczną Maia Settings |

Singleton, bo `MSessionManager` też nim jest. Przejście frontendu to w większości zmiana nazw:

```qml
// dziś                                       // po zmianie
import Maia.Backend as Maia                   import Maia.Session
Maia.MSessionManager.canSuspend               Session.canSuspend
Maia.MSessionManager.poweroff()               Session.powerOff()
```

Miejsca do zmiany (dziś): `Lumen/shell/Main.qml`, `Lumen/shell/state/Shell.qml`,
`Maia/shell/session/SessionScreen.qml`, `Ubuntu 24.04/shell/controlboard/ControlBoardContent.qml`,
`XPLuna/shell/session/LogoutContent.qml`, `TurnOffContent.qml`, `XPLuna/shell/experiments/mask/WindowOverlay.qml`.
Potem `MSessionManager` i `SessionService` znikają z `Maia.Backend` i `appMaiaServer`.

---

## 9. Ryzyka

| Ryzyko | Co z nim zrobić |
|---|---|
| **Awaria usługi sesji kończy sesję.** To jedyny taki proces. | Mało kodu, żadnego GUI, żadnych wtyczek; testy kolejności i limitów; `panic = "abort"` z wpisem w logu; `PDEATHSIG`, żeby nic nie wisiało. Ten sam rachunek ma dziś bash w fazie 2 i `appMaiaServer`, tylko gorzej. |
| **Zawieszony proces blokuje wylogowanie.** | Limit czasu na każdy krok, potem `SIGKILL`. |
| **Gotowość kompozytora.** Pomocnik nie wystartuje (np. stary `wayfire.ini` bez wpisu `[autostart]`). | Limit 20 s, czytelny wpis w logu (dziś skrypt ostrzega tak samo), koniec sesji zamiast czarnego ekranu. |
| **Wyłączenie z hasłem administratora** (inny użytkownik zalogowany). | Sprawdzenie `Can*` przed zamykaniem; `PowerOff` przy działającym kompozytorze i agencie polkit (punkt 5). |
| **Wyłączenie spoza Maia** (`systemctl poweroff`, przycisk zasilania przez powerdevil). | `PrepareForShutdown` i `SIGTERM` uruchamiają szybki koniec z krótkimi limitami. |
| **Restart powłoki zostawia stan.** Okna proxy (`MProxyWindow`) i ich gniazda po starej powłoce. | Procesy klienckie i tak kończą się z serwerem (gniazdo znika); `ProxyWindowLocalServer` już usuwa stare gniazdo przy starcie (`QLocalServer::removeServer`). Do sprawdzenia w teście. |
| **Pętla awarii powłoki** (zły frontend zapisany w `maiarc`). | Limit 5 awarii w 2 minuty. Później: po 3 awariach z rzędu start z domyślnym frontendem. |
| **Sesja zagnieżdżona a prawdziwy systemd użytkownika.** | Zagnieżdżona ma własną magistralę sesyjną, więc wysyłka zmiennych do systemd trafia w próżnię. Dodatkowo tryb testowy usługi pomija `systemctl --user` (jak dziś `MAIA_SESSION_TEST=1`). |

---

## 10. Testy

- **Jednostkowe (Rust):** opis sesji i kolejność startu; zasady restartu z udawanym zegarem (1 s, 2 s,
  4 s…, limit 5 w 2 min); kolejność kroków przy wylogowaniu, restarcie i wyłączeniu; tłumaczenie
  odpowiedzi logind (`yes`, `no`, `challenge`, `na`) na `Ability`.
- **Integracyjne** (`service/tests/`, jak w innych usługach): usługa z atrapą logind i atrapami procesów
  (małe programy testowe, które się kończą, wywracają albo czekają na `SIGTERM`); atrapa kompozytora,
  która uruchamia pomocnika gotowości. Sprawdzamy: kolejność startu, restart po awarii, wyłączenie
  z `challenge`, wylogowanie w limicie czasu mimo zawieszonego procesu, brak zombie, brak sierot po
  zabiciu usługi.
- **Bezgłowy Wayfire** (jak dziś testy sesji z `MAIA_SESSION_TEST=1`): prawdziwy kompozytor, pomocnik
  z `[autostart]`, prawdziwe usługi Maia.
- **Sesja zagnieżdżona:** `run_maia_nested_wayland.sh` uruchamia `maia-session-service --nested`
  (`kwin_wayland` w oknie zamiast wrappera, atrapa logind, własna magistrala D-Bus). Ręczny test:
  zabić `appMaiaServer` i patrzeć, jak wraca, a otwarte okna zostają.

---

## 11. Co się zmienia w repozytorium

| Miejsce | Zmiana |
|---|---|
| `Maia/services/session/` (nowe) | `contract/session.capnp`, `service/` (Rust), `qml/` (`Maia.Session`), `README.md`, `docs/`; w CMake jak `windows`: `maia_add_cargo_executable` → `<prefix>/libexec/` |
| `Maia/DeployFiles/session/run_maia_*.sh.in` | koniec fazy 1: `exec maia-session-service --compositor …`; faza 2 znika |
| `Maia/DeployFiles/session/maia-session-common.sh.in` | zostaje `maia_session_prepare`; `maia_session_run` i funkcje uruchamiania usług przechodzą do Rusta |
| `Maia/DeployFiles/etc/maia/wayfire.ini` | bez zmian (`$MAIA_SESSION_SCRIPT` wskazuje pomocnika) |
| `Maia/DeployFiles/run_maia_nested_wayland.sh` | uruchamia `maia-session-service --nested` |
| `Maia/BackendLib/` | etap 2: znikają `server/SessionService.*` i `MSessionManager.*` |
| frontendy (7 plików, punkt 8) | etap 2: `import Maia.Session` |
| `doc/diagrams/project_map.py` | nowy proces na mapie, nowy start sesji |

Pliki `.desktop` sesji, logi w katalogu domowym (`~/maia_<v>_kwin_session.log`, `…_server.log`)
i katalog konfiguracji `~/.config/maia/<v>/` zostają bez zmian.

---

## 12. Etapy

Rozmiar dla porównania: `maia-windows-service` to ok. 1800 linii Rust i tyle samo C++ w module QML.

**Etap 1: usługa sesji zamiast fazy 2.** Średni: ok. 1500 linii Rust i testy.
- start i pilnowanie procesów, pomocnik gotowości, eksport środowiska, logi z nazwami procesów;
- restart `appMaiaServer` i usług Maia; koniec sesji (wylogowanie przez wyjście powłoki z kodem 0,
  `SIGTERM` z zewnątrz);
- skrypty sesji i sesja zagnieżdżona.

Frontendy bez zmian. Od razu: awaria powłoki nie kończy sesji.

**Etap 2: kontrakt i moduł QML.** Średni: kontrakt, ok. 800 linii C++ modułu, logind w Rust.
- `session.capnp`, logind (możliwości, wyłączenie, restart, uśpienie), atrapa logind;
- `Maia.Session`; frontendy przechodzą; `SessionService` i `MSessionManager` znikają.

**Etap 3: dopracowanie.** Każda rzecz osobno, mała lub średnia.
- blokady (`inhibit`), `PrepareForSleep`, `Lock`/`Unlock` dla przyszłego ekranu blokady;
- zamykanie programów przy wylogowaniu przez `maia-windows-service`;
- strona diagnostyczna w Maia Settings (`SessionChildrenModel`), restart procesu z ręki;
- zapasowy frontend po pętli awarii powłoki.

---

## 13. Decyzje do podjęcia

1. **Gdy padnie Wayfire:** koniec sesji (propozycja na start) czy próba uruchomienia Wayfire i powłoki
   od nowa?
2. **Limity restartu powłoki:** 5 awarii w 2 minuty, a potem koniec sesji?
3. **Opis sesji (lista procesów):** w kodzie usługi (prościej) czy w pliku `<prefix>/etc/maia/session.toml`
   (nowa usługa = nowy wpis, bez kompilowania)?
4. **Zamykanie programów przy wylogowaniu** (etap 3): czy w ogóle, i ile czekać?
5. **Zgodność wstecz:** czy w etapie 2 zostawić przez jakiś czas `org.maia.SessionService` w D-Bus jako
   przekaźnik do nowej usługi (np. dla własnych skryptów), czy usunąć od razu?
