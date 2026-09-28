# Slowed + Reverb — правила работы с проектом

iPhone-приложение: пользователь загружает трек, замедляет или ускоряет его (varispeed: темп и тон меняются вместе), добавляет reverb и сохраняет результат в `.m4a`. Стиль: ночной ретро-панк / 8-bit, пиксельный шрифт, неон.

## Юнит-тесты (обязательно)

- После каждого изменения кода: собери проект и запусти все юнит-тесты (`MyAppTests`).
- Если какой-то тест упал — исправь причину, а не сам тест, и запусти снова.
- В конце ответа коротко напиши: сколько тестов прошло, сколько упало и почему.
- Если добавляешь новую логику (не UI), добавь к ней тесты.
- Тесты пишутся на Swift Testing (`import Testing`, `@Test`, `#expect`), не на XCTest.
- Тесты лежат в `MyAppTests/`: `AudioEngineTests`, `AudioExporterTests`, `GifTests`, `LevelMeterTests`, `MeterDisplayTests`, `TrackTests`, `MyAppTests`.

## Проверка работы

- Сборка: `BuildProject`, плюс `GetBuildLog` с `severity: warning`. Цель — ноль ошибок и ноль предупреждений.
- Не запускать сессии симулятора или устройства (device interaction) и не делать скриншоты для проверки UI. Хватает сборки, тестов и адаптивной вёрстки.
- Не запускать много процессов, экономить токены; для правок UI — просто править UI.
- Если пользователь спрашивает «где находится X», ответить ссылкой `файл:строка` и ничего не менять.
- Чтобы проверить не-UI логику на реальных данных, достаточно быстрого `RunCodeSnippet`.

## Проект и окружение

- Проект `Untitled Project 2.xcodeproj`, таргет `MyApp`, папки синхронизируются с диском: новые файлы в `MyApp/` попадают в сборку сами.
- Только iPhone, портретная ориентация, тёмная тема. Минимальная iOS — **26.0**, SDK — iOS 27.
- Bundle ID: `com.smitanderson.SlowedReverb`.
- Swift 5 mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Код, который работает на аудио-потоке или в фоне, помечается `nonisolated` / `@concurrent`.
- Настройки таргета меняются через `UpdateTargetBuildSetting`, ключи Info.plist — через `AddInfoPlist`.
- `project.pbxproj` правится руками только с разрешения пользователя. После такой правки Xcode перечитывает проект, и несохранённые настройки откатываются. Поэтому потом нужно проверить bundle ID и deployment target.
- Metal Toolchain установлен, шейдеры в `Gif/GifShaders.metal` компилируются. Для `xcrun metal` из терминала нужен `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Совместимость iOS 26 / 27

Часть API AVFAudio в iOS 27 устарела или появилась только там. Всё это собрано в обёртках в `AudioEngine` / `AudioExporter`, используй их, а не прямые вызовы:

| Задача | iOS 27 | iOS 26 |
|---|---|---|
| Соединение узлов | `connectNode(_:to:format:)` | `connect(_:to:format:)` |
| Старт плеера | `playAudio()` | `play()` |
| Tap уровней | `installAudioTap` (`AVReadOnlyAudioPCMBuffer`) | `installTap` |
| Прерывания | `didBecomeInactiveNotification` | `interruptionNotification` |

Любой новый API iOS 27 — только за `if #available(iOS 27, *)` с запасной веткой.

## Архитектура

- `MyApp.swift` — поток экранов: сплеш (1.6 с) → `WelcomeView` → `PlayerView`. Один `AudioEngine` на всё приложение.
- `Audio/`
  - `AudioEngine` (`@Observable`): граф player → mixer → varispeed → reverb → main mixer. Здесь play, pause, seek, перемотка (`startWinding`) и импорт через `NSFileCoordinator`.
  - `LevelMeter`: уровни L/R для индикатора, отдельная модель, чтобы частые обновления перерисовывали только индикатор. Tap режет буферы на куски по 20 мс.
  - `AudioExporter`: офлайн-рендер той же цепочки в AAC `.m4a` плюс хвост реверба 2.5 с. `TrackExporter` — состояние кнопки REC и меню «Поделиться».
- `Gif/`: `GiphyService` (поиск аниме-гифок по GIPHY, ключ внутри), `AnimatedGIF` (декодирование с лимитом памяти 48 МБ), `GifChannel` (состояния экрана), `GifEffect` + `GifShaders.metal` (эффекты Pixel / CRT / VHS / Neon, по умолчанию выключены).
- `Player/`: компоненты экрана плеера. `PhysicalKeyStyle` — «физические» клавиши с продавливанием и хаптиками.
- `Theme/`: `RetroTheme` (палитра, `pixelUnit`, `lcdGlow`, `Scanlines`, `.playerPreview()`), `PixelFont` (свой шрифт 5×7 с латиницей и кириллицей), `PixelShapes`.
- `Welcome/`: аркадный приветственный экран и пиксель-арт (`PixelCassetteSprite`, `ExtrudedPixelLogo`, `PixelStarfield`).

## Правила UI

- Вёрстка адаптивная по ширине и высоте: размеры от `GeometryReader`, `pixelUnit` и `vScale`, без хардкода под одно устройство. Свободная высота делится между `Spacer`-ами поровну.
- Весь текст в UI рисуется `PixelText` (пиксельный шрифт), с пиксельными размерами через `PixelText.snapped` / `snappedDown`.
- Цвета только из `RetroTheme`.
- Раскладка плеера сверху вниз:
  1. Гифка на всю ширину: около 40% высоты, уходит под статус-бар, без эффектов по умолчанию.
  2. Индикатор L/R, светодиод, EJECT и REC.
  3. Слайдеры Speed и Reverb.
  4. Единый блок: название трека, таймлайн, клавиши.
  5. Надпись бренда.
- Слайдеры шагают по 0.05 (Speed) и 5% (Reverb), каждый шаг даёт хаптик.
- Анимации, которые считаются на каждом кадре (`ReelMotion`-подобные, `GifClock`, `MeterBallistics`), — это простые классы, которые продвигаются внутри `TimelineView`. Такие `TimelineView` ставятся на паузу, когда анимировать нечего.
- В каждом файле с View должен быть `#Preview`. Для компонентов плеера используй `.playerPreview()`: без `pixelUnit` компоненты в превью выглядят крошечными.

## Стиль кода

- Отступы 4 пробела. `@State private var` для состояния, `let` для констант, никаких force unwrap без необходимости.
- Swift concurrency (async/await, `Task`), без Combine.
- Комментарии на английском, короткие, объясняют неочевидное.
- Менять только то, о чём просили.
