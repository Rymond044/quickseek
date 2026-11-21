# quickseek: перенесённые решения и история

Источник: задача 13 исходного трекера dotfiles, состояние на 2026-11-19.
Старые статусы и команды сверять с README, кодом и поздними решениями.

### 13. quickseek — поиск «как Spotlight в macOS» на Quickshell — IN PROGRESS (v0.4 сделан и запушен 2026-11-13, ждёт проверки клавиатурой)
- Идея пользователя: одно окно, где ищется всё сразу. Пишешь `wallpaper` → и папка на диске, и пункт CC «Choose wallpaper»,
  и «Search Google». Работает даже в неправильной раскладке. Анимация раскрытия окна и «вытягивания» по мере появления
  результатов — «прям как в macOS». Обсуждено в формате grill (3 раунда), все решения ниже — **пользователя**, не пересматривать.
- Предыстория: попытка «глобального поиска» в rofi-CC (пункты всех подменю под 9 разделами главного экрана) **отклонена** —
  rofi не умеет прятать строки при пустом запросе, при прокрутке вылезали Wi-Fi-сети и BT-устройства. Правило:
  пункты подменю видны только внутри своего раздела или когда их нашёл поиск. Откачено, в коммит не попало.

#### Проект
- Имя **quickseek** (Quickshell + seek; «Spotlight» — марка Apple). Отдельный git-репо **`~/Apps/quickseek`** (НЕ в dotfiles),
  лицензия **MIT**. Позже — на GitHub, чтобы люди пользовались и контрибьютили; но «не зацикливаться» на этом:
  сначала чтобы работало у пользователя. Пока только `git init`, GitHub-репо не создавать без просьбы.
- Тексты интерфейса и комментарии в репо quickseek — **на английском, комментариев немного** (решение пользователя).
  Сторона dotfiles (`rofi/cc/quickseek.sh` и т. п.) — по правилам dotfiles, на русском.
- Ядро в репо — только общее для всех: окно и анимации, поиск, frecency, исправление раскладки, источники «для всех»
  (приложения, файлы, калькулятор, веб, power, настройки). Всё специфичное для этой машины (CC, MSI EC, iwd) — в dotfiles,
  подключается **плагинами-скриптами**.
- Протокол плагина: внешняя команда отдаёт JSON-список пунктов (подпись, короткий статус, иконка, id, при необходимости —
  «раздел/папка» с вложенными пунктами) и выполняет пункт по id. Язык любой. Формат протокола спроектировать при старте v0.1.
- CC подключается как такой плагин через `binc/cc` (нужен машиночитаемый вывод из тех же `РАЗДЕЛ_rows`, например
  `cc РАЗДЕЛ json`, — один источник правды, rofi-CC продолжает работать). Пользователю «не важно, в каком виде, лишь бы
  функции CC работали». Позже (после ухода с rofi) можно перевести медленные разделы на нативные модули Quickshell
  (в 0.3.2 есть `Quickshell.Bluetooth`, `Services.Pipewire`, `Hyprland`; `Networking` — только NetworkManager, у нас iwd →
  Wi-Fi остаётся через iwd D-Bus).

#### Движок и работа в фоне
- **Quickshell** (rofi — тупик: нет анимаций, нельзя прятать строки до поиска; готовые vicinae/walker/anyrun — чужой вид,
  CC с подменю в их модель не ложится). Главное условие пользователя: **не жрать CPU без причины и не бить по автономности** —
  оптимизировать и замерять.
- **Демон в фоне** (`uwsm app -s b --`, автостарт), окно (PanelWindow) создаётся при открытии (LazyLoader) и уничтожается после
  анимации закрытия. Пока скрыто — **0 % CPU, без таймеров/опроса**, индексы обновлять по событиям (inotify на папки .desktop,
  смена мониторов) или при открытии. Ожидаемая цена — ~100–120 МБ RSS (пустой Quickshell). Замер до/после (pidstat, powertop
  wakeups); если не уложимся — вариант «холодный старт на каждое открытие».
  NB: выбиралка обоев walls сейчас НЕ демон (`qs -c walls -n`, холодный старт) — пользователь думал, что висит; quickseek
  будет первым постоянным процессом Quickshell. Встраивать walls в тот же демон — не обсуждалось.
- Открытие по горячей клавише: Hyprland global shortcut из Quickshell (`GlobalShortcut`, без запуска процесса) и/или
  `qs ipc call` как запасной путь — выбрать при реализации.

#### Окно и вид («как macOS»)
- Монитор с фокусом, по центру, в верхней трети экрана. Ширина ~680 логических px, на вертикальном DP-1 (1080) ужимается.
  Мониторы не хардкодить (scale/transform).
- При открытии — **только строка ввода** (плейсхолдер вида «Search…»), без результатов. Результаты появляются с первыми
  символами, окно «вытягивается» вниз.
- Анимации: открытие — масштаб 0.96 → 1 + прозрачность ~150 мс; при наборе высота плавно «пружинит» под число результатов;
  закрытие — обратная ~100 мс. Реализация: слой фиксированного размера и прозрачный, внутри анимируется скруглённая плашка
  (не ресайзить layer-surface — Hyprland перестраивает слои, см. «ужимание» waybar в задаче 1).
- Результаты: сверху «лучшее совпадение», ниже **группы с заголовками** (Applications, Control center, Folders, Files, Web…).
  Справа серым — **только короткое состояние** (on/off, connected, active…), «без километровых предложений» и пояснений
  (пользователь только что вычистил такие подписи из CC — коммит 31ec204).
- Цвета (порядок поиска палитры): 1) `colors` в settings.json (путь); 2) `~/.cache/quickseek/colors.json` — пишут шаблоны из репо
  `templates/wallust.json.j2` и `templates/matugen.json` (пользователь подключает их в свой wallust/matugen; у нас — шаблон
  в `~/dotfiles/wallust/templates/`); 3) `~/.cache/wal/colors.json` (формат pywal, у многих есть); 4) встроенная палитра.
  Светлый/тёмный вид — по яркости фона палитры (как `{% set light = … %}` в наших шаблонах, задача 11). Файл палитры
  отслеживать — смена обоев перекрашивает на лету.
- Стекло: неймспейс слоя `quickseek` → добавить в белый список `hypr/lua/glass.lua`; вкл/выкл — общий `binc/glass`
  (прозрачность фона только при включённом стекле, как у waybar/rofi/swaync).

#### Источники
- Приложения (.desktop). Окон нет (решение: отдельного источника окон и «перейти к уже открытому» — не надо).
- Control center — включая пункты подменю (сети, BT-устройства, аудиовыходы, мониторы, тумблеры), но они видны только
  внутри раздела или по поиску.
- Файлы и папки (см. ниже).
- Калькулятор/конвертер — `qalc` (libqalculate стоит), только когда запрос похож на выражение, с debounce.
- Power: Lock (`loginctl lock-session`), Suspend, Reboot, Shutdown, Logout (в т. ч. заменит powermenu в будущем).
- Веб: **Google в браузере по умолчанию** (`xdg-open`, сейчас `chromium.desktop`). Строка «Search Google for “…”» есть
  **всегда последней**, а при пустой выдаче — единственная и сразу выбрана. Префиксы: `g …` (сразу Google), `yt …` (YouTube),
  `aw …` (Arch Wiki).
- **Не нужны**: обои как источник (остаются действия CC «Choose/Random wallpaper», поиск по тегам — в walls), окна.
- На будущее (не в v0.1/v0.2): история буфера (clipse), эмодзи, `> команда`, скрипты binc.

#### Поиск и ранжирование
- Fuzzy-совпадение + **frecency** (чаще/недавно выбранное выше) + запоминание «запрос → выбор». Данные —
  `~/.local/state/quickseek/` (не настройки, в dotfiles не кладём).
- Неправильная раскладка: искать и по введённому тексту, и по нему же, переложенному ЙЦУКЕН ↔ QWERTY по позициям клавиш;
  результаты сливать. Раскладку Hyprland **не переключать**, фонетический транслит — **не нужен** (пока только этот вариант).
- Закрепление: Ctrl+P на любом результате; закреплённые — первыми и в пустом виде, и в поиске.

#### Файлы
- Свой индекс `$HOME` (`updatedb` от пользователя → `~/.cache/quickseek/`), не системный plocate (тот раз в сутки — «фуфел»),
  не `fd` на каждый символ (дорого). Пользователь хочет цену «как у plocate», но свежесть.
- Обновление: user-таймер — на зарядке каждые 30 мин, на батарее каждые 2 ч; плюс при открытии окна, если индексу > 2 ч.
  Перед выбором частоты **замерить** стоимость одного `updatedb` по home (если < 1 с CPU — можно чаще).
- Downloads / Desktop / Documents — живой `fd` при каждом открытии окна (свежие файлы).
- Только `$HOME`. Исключения: `.cache`, `.local/share/Steam`, `node_modules`, `.git`, скрытые (кроме запроса, начинающегося с точки).
- Действия: папка → Nautilus, файл → приложение по умолчанию (`xdg-open`), Alt+Enter → показать в папке
  (FileManager1.ShowItems — помнить фикс портала из задачи 9).

#### Навигация
- ↑/↓ или Ctrl+J/K — по результатам; Enter — выполнить; Esc — закрыть.
- Раздел CC = «папка»: Enter или Tab → войти, в строке поиска «чип» `Wi-Fi ›`, поиск уже внутри раздела;
  Backspace на пустой строке — выйти из раздела.
- Alt+Enter — показать в папке; Ctrl+P — закрепить.
- После действий CC, меняющих состояние (тумблер, выбор выхода звука и т. п.), окно **остаётся открытым** и обновляет статус
  (как сейчас rofi-CC). Запуск приложения / открытие файла / веб — закрывают окно.

#### Настройки
- `~/.config/quickseek/settings.json`: правится руками **и** пунктами настроек в самом окне (поиск `quickseek settings`…),
  окно следит за файлом и применяет сразу. Можно положить в dotfiles (stow).
- Пустой экран настраивается: ничего (по умолчанию) / недавние / популярные / закреплённые (возможно, комбинации).

#### Клавиши
- ~~На время разработки — **Super+Alt+Space**~~ (с v0.3 quickseek на Super+Space, rofi-лаунчер на Super+Alt+Space), rofi не трогаем (Super+Space — rofi-лаунчер, Super+Shift+A — rofi-CC,
  Super+Esc — powermenu).
- После v0.2 и недели без rofi: Super+Space → quickseek, Super+Shift+A → quickseek сразу в корне CC, Super+Esc → сразу
  раздел Power. rofi (лаунчер, CC, powermenu) убирается только тогда, waybar-клики перевести туда же.

#### Этапы
- [x] **v0.1** (локальные коммиты: quickseek 97cdf62, dotfiles b2e1866; не запушено): `~/Apps/quickseek` — плоский каталог QML: `shell.qml`
      (GlobalShortcut `quickseek:toggle`, IPC `toggle/open/close/folder KEY/search TEXT`), `Engine` (источники, поиск,
      группы, действия, калькулятор), `Fuzzy.js` (скоринг + ЙЦУКЕН↔QWERTY), `History` (frecency + «запрос → выбор»,
      `~/.local/state/quickseek/history.json`), `Settings` (settings.json + `include`), `Theme` (палитра), `Plugin`,
      `SeekWindow`/`SearchBar`/`Results`; `docs/plugins.md` (протокол), README, LICENSE, `templates/`.
      Протокол: `cmd list` → JSON lines (id, title, status, icon, parent, folder, keywords), `cmd run ID` → пусто (окно
      остаётся, список перечитывается) / `{"type":"close"}` / `{"type":"menu"}`+пункты / `{"type":"prompt"}` (ответ в env
      `QUICKSEEK_INPUT`). Плагин CC — `cc quickseek list|run` (`rofi/cc/quickseek.sh`): те же `РАЗДЕЛ_rows`, а
      `pick/ask/confirm/launch` в этом режиме отвечают протоколом (fd 3); `launch` — через `uwsm app`. В `cc` метаданные
      разделов вынесены в `SEC_NAME/SEC_ICON` (rofi-вывод не изменился, сверено заглушкой rofi).
      Dotfiles: пакет `quickseek/` (settings.json: uwsm launchPrefix, include `~/.cache/glass/quickseek.json`, плагин cc),
      wallust-шаблон `quickseek.json.j2` → `~/.cache/quickseek/colors.json`, `binc/glass` пишет opacity 0.45/{},
      слой `quickseek` в glass.lua, бинд Super+Alt+Space (`hl.dsp.global("quickseek:toggle")`), автостарт `uwsm app -s b`.
      Проверено через IPC и скриншоты: поиск, раскладка (`цфддзфзук`), папки CC, тумблер DND (статус обновился, окно
      осталось), подменю, confirm «No», prompt с паролем (тестовым плагином), калькулятор, префиксы, двойной Enter
      у Shut down. Простой: 0 переключений контекста за 20 с, RSS ~165 МБ; `list` CC ~0,2 с (разделы параллельно).
      **Не проверено:** клавиатура и ощущение анимаций (пользователь), вертикальный DP-1 (был включён только eDP-1),
      вид со стеклом (стекло выключено).
- Грабли Quickshell (записать, чтобы не наступить снова): имена файлов `Window`, `Palette`, `Colors` перекрываются
  типами QtQuick (тихо!); функция `children()` в синглтоне ломает загрузку («children is read-only»); комментарий
  с `{…}` **перед** `pragma Singleton` тихо ломает синглтон (все свойства undefined); `Instantiator` в синглтоне
  не работает — `Variants`; синглтон `Hyprland` держит поток событий Hyprland → ~3 пробуждения/с из-за смены
  заголовков окон, поэтому монитор берётся из `hyprctl monitors -j` при открытии.
- [x] **Вид под Spotlight** (2026-11-05, не закоммичено): шрифт — системный (`fonts.text` пуст → gsettings `font-name`,
      сейчас CaskaydiaMono), поле крупнее и Light; без результатов окно — «пилюля»; тень `RectangularShadow` (`shadow`,
      при стекле `binc/glass` пишет `false`); строки 44 px, «лучшее совпадение» 56 px с иконкой 40; иконки приложений 32;
      глифы CC/power/web — на цветной плашке с градиентом и белым значком (цвет = color1..6 палитры по разделу CC,
      затемняется до яркости ≤ 0.2); выделение — полупрозрачный акцент, текст обычным цветом. Иконки с абсолютным путём
      и пустые — без предупреждений. Фикс: при удалении `colors` из настроек палитра не возвращалась. Проверено
      скриншотами в светлой и (временной) тёмной палитре на eDP-1. Коммиты quickseek 76dd4c0, 866447e, dotfiles 3a0e00c.
      Иконки, которых нет в теме (у Wiremix нет `Icon=`, `network-vpn` у WireGuard GUI), давали шахматку Quickshell —
      теперь `iconPath(name, true)` → при «» плашка с глифом приложения. Поле ввода — обычная насыщенность (Light была узкой).
- [x] **v0.2** (2026-11-07, quickseek 3d46a97, запушено в github.com:Rymond044/quickseek):
      файлы — `bin/quickseek-files index|search|recent`: индекс `fd` → `plocate-build -p` в `~/.cache/quickseek/{files,dot}.db`
      (75 тыс. путей, ~0,4 с, 0,7 с CPU; пути отсортированы от мелких к глубоким — лимит plocate 300 оставляет их),
      поиск `plocate -b` по каждому из запросов (как набран + ЙЦУКЕН↔QWERTY) ~10 мс, папка/файл и отсев удалённых — `test -d/-e`.
      Скрытые — только для запроса с точки (`dot.db`, глубина 3). Исключения + `~/.config/quickseek/ignore`.
      Downloads/Desktop/Documents — `fd` на каждое открытие (`recent`, ~30 мс), он же запускает пересборку, если индексу > 2 ч.
      Ранжирование файлов: имя режется на слова по `._-`, потолок 850 (точное имя = начало слова), −15 за уровень глубины (≤150).
      Иконки — `*-x-generic` по расширению, без темы — глиф файла/папки. Alt+Enter → `FileManager1.ShowItems` (gdbus), иначе opener папки.
      Файлы/URL открываются через `opener` = `gio open` (не xdg-open: xdg-utils 1.2.1 игнорирует `Terminal=true`, а
      JSON/текст у нас → nvim.desktop — nvim стартовал без терминала и сразу выходил; gio поднимает kitty). Проверено:
      «Open settings file» → kitty с nvim settings.json.
      Закрепление: Ctrl+P, `pins` в history.json, +2000 к счёту. Пустой экран: `emptyView` (`pinned`/`recent`/`popular`, по умолч. ничего).
      Настройки в окне: папка «quickseek settings» (Empty screen ▸, File search, Rebuild file index, Unpin all, Clear history, Open
      settings file); `Settings.set()` пишет settings.json (QSaveFile идёт по симлинку, проверено; битый JSON не перезаписывает).
      Юниты `systemd/quickseek-index.{service,timer}` в репо (30 мин, на батарее — только если индекс > 2 ч), **не включены**:
      `systemctl --user link ~/Apps/quickseek/systemd/quickseek-index.{service,timer} && systemctl --user enable --now quickseek-index.timer`.
      `QUICKSEEK_APPID` — id горячей клавиши для второй (dev) копии. Проверено через IPC + скриншоты dev-копии (свои state/cache):
      `diplom`/`вшздщь`, `pdf`, `.zshrc`, тумблеры, пины, пустой экран, Alt+Enter (Nautilus), выкл. поиска файлов.
      **Не проверено:** клавиатура (Ctrl+P, Alt+Enter), вертикальный DP-1.
      Иконки файлов видны только при `QT_QPA_PLATFORMTHEME=kde`: у текущего демона ещё `qt6ct` (сессия до задачи 11), с ним
      Quickshell тему иконок не видит → глифы. После перелогина пройдёт.
      Простой: ~10 пробуждений/с всплесками — **так же и у v0.1** (сравнено бок о бок), пустой Quickshell — 0. Зацепки для v0.3:
      FileView на несуществующем `~/.cache/wal/colors.json`, DesktopEntries. 05.11 было 0 — что-то в окружении.
- [x] **v0.3** (2026-11-09, quickseek ветка `v0.3` fb6f873, dotfiles ветка `worktree-quickseek-default` 4cd3487; обе запушены,
      **в main не слиты**). Решение пользователя: файлы ищутся **только по префиксу `f `** (и `а ` в русской раскладке) →
      «папка» `Find files ›` (чип, Backspace на пустой — выход; пусто — закреплённые/недавние файлы); в обычном поиске
      только закреплённые файлы. Старое поведение — `files.inline: true` (+ тумблер в quickseek settings). Без префикса
      fd/plocate не запускаются вообще. Плагины: `refresh` (сек) — на открытии `list` только если старше; вход в папку
      плагина и действие перечитывают всегда. У CC `refresh: 120`. IPC `rows` — текст выдачи (для тестов).
      Замеры (dev-копия, `/proc`): простой 0 пробуждений/0 % CPU, RSS 125 МБ после старта / ~165 после первого открытия
      (PSS ~90); открытие+закрытие ~75 мс + 10 мс дети; с запросом ~140 мс; `f …` ~125 + 105 мс (fd/plocate).
      Было ~1,4 с CPU на открытие: **1,2 с — `cc quickseek list`** (разделы по 50–250 мс: appearance, audio, wifi, bt).
      Всплески «~10/с» из v0.2 не воспроизвелись (оба демона 0/с) — были от окружения. README: раздел Cost.
      Бинды: Super+Space → quickseek, Super+Alt+Space → rofi-лаунчер (запасной). Super+Shift+A / Super+Esc пока rofi.
- [x] **v0.4** (2026-11-13, план пользователя; quickseek 7bd1b34, dotfiles 6f8aeb1, запушено; клавиатуру проверяет пользователь):
  1. [x] Esc/Tab уходили в окно под quickseek. Не воспроизвелось: эксклюзивный слой держит фокус (курсор над kitty,
         `hl.dsp.focus`, уведомление — проверено меткой `activeFocus` с контролем OnDemand; Hyprland 0.57 отказывает окнам в
         фокусе при `m_exclusiveKeyboardLSes`). Вероятно, Esc в папке закрывал окно и следующие клавиши шли в kitty.
         Теперь: Esc — закрыть превью / prompt / меню / выйти из папки, закрыть только с верхнего уровня (папка, в которой
         окно открыто, — верхний уровень, `baseDepth`); окно не снимается, пока зажата клавиша, нажатая в нём
         (`Engine.keyDown/keyUp`, страховка 1,5 с), в закрывающемся окне клавиши глотаются.
  2. [x] rofi убран (см. «Карту конфигов»). Ядро quickseek: папка `session`, `power` в настройках — id → команда или
         `{title, icon, command, order, confirm}`, `null` прячет.
  3. [x] Валюты: при денежном запросе, если `~/.local/share/qalculate/eurofxref-daily.xml` старше суток, — `qalc -e` в фоне
         и пересчёт; статус «rates ДАТА».
  4. [x] `Clipboard.qml` (clipse): `v `/`м `, Super+V → `folder clipboard`. Enter — `wl-copy` (картинка `--type image/png`).
         Pin/Delete пишут прямо в `clipboard_history.json` (компактный JSON, проверено: pin+unpin = исходный файл по `jq -S`).
  5. [x] Меню действий: → в конце строки / Ctrl+O; вложенные меню (Open with… из `gio mime`), Esc назад. Скрытые приложения —
         `hidden` в настройках, «Show hidden apps» в quickseek settings.
  6. [x] Превью: `Preview.qml` + `bin/quickseek-preview` (kind/mime/size/mtime/картинка; PDF — pdftoppm, видео — ffmpeg,
         прочие картинки — vipsthumbnail, кэш `~/.cache/quickseek/preview/`, чистка > 14 дней). Сбоку, если
         `(ширина − окно)/2 − 16 − max(pad, 24) ≥ 360` (HDMI — да, eDP/DP-1 — вместо окна); слой расширяется симметрично.
  7. [x] `>`: папка `command` — введённое (big), история `cmd:` (frecency), программы из $PATH; Tab дополняет;
         запуск `terminal` (`["kitty","-e"]`) + `$SHELL -ic 'cmd; exec $SHELL'` через launchPrefix. «Remove from history».
  8. [x] Эмодзи: `data/emoji.tsv` из `tools/emoji.py` (emojibase-data 16.0.3, MIT/CLDR), `Emoji.qml`, иконка без плитки
         (`iconType: "emoji"`), русское название с весом заголовка.
  - IPC для тестов: `key esc|down|ctrl+o|space…` (тот же `Engine.onKey`, что и клавиатура), `type ТЕКСТ` (через поле
    ввода, как набор), `field` (что в поле). Баг у пользователя: `>` первым символом не очищал поле (запрос "" → "" без
    сигнала) → `> btop` уходил в zsh как перенаправление (пустые файлы в ~, удалены). Исправлено сигналом `queryReplaced`.
  - Замер: простой — 1 пробуждение за 10 с; RSS ~245 МБ после тестов (было ~165) — эмодзи и превью остаются в памяти, проверить.
  - Не делаем: закладки браузера, недавние файлы GTK. `quickseek-index` — **не нужен** (решение пользователя, юниты удалены).
- [x] **v0.5** (2026-11-16, quickseek d8e2681, dotfiles 1e3bc31, запушено; клавиатуру v0.4 пользователь проверил — «всё нравится»):
      нативные папки `AudioSource.qml` (Quickshell.Services.Pipewire) и `BluetoothSource.qml` (Quickshell.Bluetooth) на базе
      `NativeSource.qml`; плагин монтирует их строкой с `"source": "audio"|"bluetooth"` (docs/plugins.md), cc audio/bt — только
      точки монтирования + действия для командной строки. Модули грузятся `LazyLoader` только при открытом окне, но синглтоны
      Pipewire/Bluetooth Quickshell после первого обращения живут до конца процесса. Первое открытие звука после старта демона —
      несколько секунд (холодная синхронизация Pipewire). `cc quickseek list` 0,47 → 0,24 с.
      Выгрузка после закрытия (`Engine.release()` через 0,8 с + gc): после эмодзи RSS 246 → 168 МБ. Превью 4K-картинки держит
      +45 МБ (не утечка, стабильно; причина не найдена). Простой после касания нативных папок: 0 пробуждений за 80 с (проверено мной).
      Не проверено: connect/pair/forget BT на реальном адаптере, смена выхода звука (агент менял только вход и вернул).
- Проверка: открытие мгновенное и плавное на всех 3 мониторах (включая вертикальный DP-1); `цфддзфзук` находит то же,
  что `wallpaper`; пункты подменю CC видны только внутри раздела или по поиску; в простое 0 % CPU и нет пробуждений.


## 2026-11-21 — System info, Applications, Help and circular navigation

Agreed with the owner: four copyable metrics in System info and at the top of Session,
above Lock/Suspend/Log out: elapsed since boot (including suspend), boot date, awake time
(excluding suspend), graphical session duration (including suspend). A missing or unverifiable
logind session is explicitly unavailable. One shared source; sample on demand and once a minute
while metrics are visible, no timer after closing. Python 3 helper uses Linux clocks and logind.
Applications browses existing visible desktop entries alphabetically; searching, hiding, launching
and actions reuse the current app source. Help shows configured prefixes, examples, keyboard
navigation and plugin descriptions. Optional plugin row `description` adds two lines below a title.
Up/down and their existing Ctrl aliases wrap globally, skipping headers and handling empty lists.
Dotfiles status is an external plugin owned by dotfiles: manual Refresh checks, a dated persisted
report, drill-down and copying detail. Reading the list never runs checks. No repair actions.
The empty screen stays configurable as before. Showing section shortcuts on an empty screen is
an agreed possible future improvement, not implemented now.

Validation: isolated KWin + nested Hyprland with no live output/input access, main window,
actions menus, nested report, copying metrics, hidden apps in browse/search, empty results,
headers, both wrap directions and Ctrl aliases. Scale 2 screenshots checked. Helper: four unit
checks, including sleep accounting and unavailable/wrong session identity. Dotfiles: six report
checks; all 54 installer tests passed. After closing: 0 CPU ticks and 0 context switches in 5 s.
An initial comparison used different workloads (new sections versus baseline app search), so its
RSS values do not establish a memory regression. Real physical keys and a new suspend/resume
cycle were not exercised. Real logind helper returned all four values on the owner's host.


## 2026-11-21 — Help scope, Session card and navigation mode

Owner refinement supersedes the earlier Session layout: Help hints (including plugin descriptions)
are visible/searchable only inside Help. The Help folder itself remains globally searchable.
Session keeps only power actions in its selectable list, followed by one non-selectable information
card with all four metrics; clicking a value copies it. The separate System info folder remains.
Up/down and Ctrl+J/Ctrl+K enter navigation mode. Existing circular behavior is preserved; j/k then
move down/up, and Space previews. Before navigation j/k and Space type normally; Ctrl+Space toggles
preview in typing mode. The search field is read-only in navigation with a NAV indicator. Slash
returns to typing without inserting a slash and closes preview, as does clicking the search field.
Prompt input is not made read-only and does not interpret plain j/k as navigation.
Validated on the isolated compositor at scale 2: Help exclusion from global app/prefix queries,
search inside Help, Session action-only rows and card screenshot, wrap and Ctrl keys. Temporary
QtTest event injection exercised actual TextInput key handling and mouse clicks: normal j/k/Space,
arrow/Ctrl entry, navigation j/k, both preview shortcuts, slash and click return. The driver was
removed before applying; no QtTest dependency was added to production. No physical input or
real power action was exercised. Test processes were stopped.


## 2026-11-21 — File wildcards and Russian NAV keys

File search accepts basename globs (*, ?, character classes and negated classes), alongside plain
words, without changing ordinary fuzzy queries. Two causes were reproduced: the shell expanded
unquoted query globs against the helper cwd, and fuzzy scoring discarded the remaining wildcard
results. The helper now disables pathname expansion; ranking uses raw basename patterns for glob
queries, including pinned/live/indexed candidates. No index timer or background work was added.
NAV j/k also recognizes о/л from the existing keyboard-layout mapping. SearchBar passes event text
and the engine falls back to the Qt key for synthetic events; typing outside NAV is unchanged.
Dotfiles status now supplies icons for every folder/timestamp via its own external plugin.
Validation: 7 quickseek regression tests (real fd/plocate index with conflicting cwd, actual JS
matcher and Engine handler, clocks); dotfiles 55 tests (including missing icons). Isolated UI
with real index confirmed *.rs, part?.rs, part[12].rs and * through ranking; Qt Cyrillic key events
and IPC о/л navigated both ways across the wrap. Root and child status icons checked visually.
Temporary event drivers removed. Test compositors stopped; no real power action exercised.
