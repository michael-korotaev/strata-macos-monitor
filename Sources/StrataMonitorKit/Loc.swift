import Foundation

/// Interface language. Switched in settings, independent of the system locale.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case russian = "ru"
    case english = "en"

    public var id: String { rawValue }

    /// Language name - always in its own language.
    public var title: String {
        switch self {
        case .russian: return "Русский"
        case .english: return "English"
        }
    }
}

/// Interface strings: Russian and English.
public enum Loc {
    static let ru: [String: String] = [
        "app.name": "Strata Monitor",
        "status.generating": "Генерация",
        "status.prompt": "Промпт",
        "status.loading": "Загрузка",
        "status.queued": "В очереди",
        "status.idle": "Простой",
        "status.connecting": "Подключение",
        "status.offline": "Нет связи",

        "unit.tps": "tok/s",
        "unit.prefillTps": "prefill tok/s",
        "unit.tokens": "ток.",
        "unit.seconds": "с",
        "unit.requests": "запр.",

        "label.gpu": "GPU",
        "label.vram": "VRAM",
        "label.temp": "Темп",
        "label.power": "Питание",
        "label.cpu": "CPU",
        "label.ram": "RAM",

        "speed.mean": "среднее",
        "speed.window": "окно 2 с",
        "speed.uptime": "аптайм",
        "speed.connecting": "подключение…",
        "speed.generating": "генерация",

        "live.elapsed": "прошло",
        "live.prefill": "prefill",

        "level.compact": "Компактно",
        "level.expanded": "Подробно",

        "action.openBrowser": "Открыть монитор в браузере",
        "action.copy": "Скопировать срез показателей",
        "action.settings": "Настройки",
        "action.quit": "Выйти",
        "action.back": "Назад",

        "settings.title": "Настройки",
        "settings.endpoint": "Адрес сервера",
        "settings.flavor": "Установка Strata",
        "settings.endpointPlaceholder": "http://host:port",
        "settings.apply": "Применить",
        "settings.openBrowser": "В браузере",
        "settings.interval": "Интервал опроса",
        "settings.menubar": "В меню-баре",
        "settings.launchAtLogin": "Запуск при входе",
        "settings.language": "Язык интерфейса",
        "settings.updated": "Обновлено",
        "settings.launchFailed": "Не удалось",

        "setup.title": "Подключение к Strata",
        "setup.hint": "Укажите адрес, на котором открывается веб-морда Strata (например http://192.168.1.10:12387). Путь можно не указывать — приложение найдёт данные монитора само.",
        "setup.connect": "Подключиться",
        "setup.cancel": "Отмена",
        "setup.placeholder": "http://192.168.1.10:12387",

        "menubar.format.iconAndNumber": "Значок + число",
        "menubar.format.numberOnly": "Только число",
        "menubar.format.iconOnly": "Только значок",

        "flavor.automatic": "Определить автоматически",
        "flavor.sourceBuild": "Сборка из исходников (git)",
        "flavor.desktop": "Desktop-приложение",

        "section.engine": "Движок",
        "section.cache": "Кеш диалогов",
        "section.totals": "Итого за сессию",
        "section.requests": "Последние запросы",
        "section.hardware": "Железо",

        "engine.model": "модель",
        "engine.version": "версия движка",
        "engine.backend": "бэкенд",
        "engine.quant": "квант",
        "engine.layers": "слои",
        "engine.host": "хост",
        "engine.context": "контекст",
        "engine.kv": "KV",
        "engine.speculative": "спекулятивное декодирование",
        "engine.experts": "эксперты",
        "engine.expertCache": "экспертный кеш",
        "engine.vramFree": "VRAM свободно",
        "engine.arena": "арена",
        "engine.poolWorkers": "пул воркеров",
        "engine.prefillCap": "prefill cap",

        "cache.state": "состояние",
        "cache.enabled": "включён",
        "cache.disabled": "выключен",
        "cache.slots": "слоты",
        "cache.reuse": "переиспользование",
        "cache.requestsWithCache": "запросов с кешем",
        "cache.tokensFromCache": "токенов из кеша",
        "cache.evictions": "вытеснений",

        "totals.requests": "запросов",
        "totals.promptTokens": "prompt-токенов",
        "totals.fromCache": "из кеша",
        "totals.outputTokens": "ответов (токенов)",
        "totals.decodeTime": "время декода",
        "totals.avgTps": "средняя скорость",
        "totals.ttft": "ttft",
        "totals.drafts": "принято драфтов",
        "totals.sessionStart": "сессия с",

        "requests.empty": "запросов ещё не было",
        "requests.time": "время",
        "requests.seconds": "сек",
        "requests.tps": "tok/s",
        "requests.ttft": "ttft",
        "requests.output": "out",
        "requests.drafts": "драфт",

        "hardware.gpu": "GPU",
        "hardware.cpu": "CPU",
        "hardware.cores": "ядер",
        "hardware.pcie": "PCIe",
        "hardware.disk": "диск",
        "hardware.diskFree": "свободно на диске",
        "hardware.tempRange": "темп (мин/макс)",
        "hardware.powerRange": "питание (мин/макс)",
        "hardware.pcieIn": "МБ/с вход",
        "hardware.pcieOut": "МБ/с выход",
        "hardware.diskRead": "чтение",
        "hardware.diskWrite": "запись",
        "hardware.threads": "потоков",

        "offline.hint": "Сервер не отвечает. Проверьте адрес в настройках (шестерёнка внизу панели) — обычно это http://<ip>:12387",

        "error.timeout": "Таймаут",
        "error.unreachable": "Сервер недоступен",
        "error.lost": "Соединение потеряно",
        "error.badURL": "Некорректный адрес:",
        "error.badStatus": "Сервер ответил HTTP %d",
        "error.emptyBody": "Пустой ответ сервера",
        "error.noMonitor": "Не нашёл данные монитора на сервере"
    ]

    static let en: [String: String] = [
        "app.name": "Strata Monitor",
        "status.generating": "Generating",
        "status.prompt": "Prompt",
        "status.loading": "Loading",
        "status.queued": "Queued",
        "status.idle": "Idle",
        "status.connecting": "Connecting",
        "status.offline": "Offline",

        "unit.tps": "tok/s",
        "unit.prefillTps": "prefill tok/s",
        "unit.tokens": "tok",
        "unit.seconds": "s",
        "unit.requests": "req",

        "label.gpu": "GPU",
        "label.vram": "VRAM",
        "label.temp": "Temp",
        "label.power": "Power",
        "label.cpu": "CPU",
        "label.ram": "RAM",

        "speed.mean": "mean",
        "speed.window": "2 s window",
        "speed.uptime": "uptime",
        "speed.connecting": "connecting…",
        "speed.generating": "generating",

        "live.elapsed": "elapsed",
        "live.prefill": "prefill",

        "level.compact": "Compact",
        "level.expanded": "Detailed",

        "action.openBrowser": "Open monitor in browser",
        "action.copy": "Copy snapshot",
        "action.settings": "Settings",
        "action.quit": "Quit",
        "action.back": "Back",

        "settings.title": "Settings",
        "settings.endpoint": "Server address",
        "settings.flavor": "Strata installation",
        "settings.endpointPlaceholder": "http://host:port",
        "settings.apply": "Apply",
        "settings.openBrowser": "In browser",
        "settings.interval": "Poll interval",
        "settings.menubar": "Menu bar",
        "settings.launchAtLogin": "Launch at login",
        "settings.language": "Interface language",
        "settings.updated": "Updated",
        "settings.launchFailed": "Failed",

        "setup.title": "Connect to Strata",
        "setup.hint": "Enter the address where the Strata web UI is served (for example http://192.168.1.10:12387). The path is optional — the app finds the monitor endpoint on its own.",
        "setup.connect": "Connect",
        "setup.cancel": "Cancel",
        "setup.placeholder": "http://192.168.1.10:12387",

        "menubar.format.iconAndNumber": "Icon + number",
        "menubar.format.numberOnly": "Number only",
        "menubar.format.iconOnly": "Icon only",

        "flavor.automatic": "Detect automatically",
        "flavor.sourceBuild": "Source build (git)",
        "flavor.desktop": "Desktop application",

        "section.engine": "Engine",
        "section.cache": "Conversation cache",
        "section.totals": "Session totals",
        "section.requests": "Recent requests",
        "section.hardware": "Hardware",

        "engine.model": "model",
        "engine.version": "engine version",
        "engine.backend": "backend",
        "engine.quant": "quant",
        "engine.layers": "layers",
        "engine.host": "host",
        "engine.context": "context",
        "engine.kv": "KV",
        "engine.speculative": "speculative decoding",
        "engine.experts": "experts",
        "engine.expertCache": "expert cache",
        "engine.vramFree": "VRAM free",
        "engine.arena": "arena",
        "engine.poolWorkers": "pool workers",
        "engine.prefillCap": "prefill cap",

        "cache.state": "state",
        "cache.enabled": "enabled",
        "cache.disabled": "disabled",
        "cache.slots": "slots",
        "cache.reuse": "reuse",
        "cache.requestsWithCache": "requests with cache",
        "cache.tokensFromCache": "tokens from cache",
        "cache.evictions": "evictions",

        "totals.requests": "requests",
        "totals.promptTokens": "prompt tokens",
        "totals.fromCache": "from cache",
        "totals.outputTokens": "output tokens",
        "totals.decodeTime": "decode time",
        "totals.avgTps": "average speed",
        "totals.ttft": "ttft",
        "totals.drafts": "drafts accepted",
        "totals.sessionStart": "session since",

        "requests.empty": "no requests yet",
        "requests.time": "time",
        "requests.seconds": "sec",
        "requests.tps": "tok/s",
        "requests.ttft": "ttft",
        "requests.output": "out",
        "requests.drafts": "draft",

        "hardware.gpu": "GPU",
        "hardware.cpu": "CPU",
        "hardware.cores": "cores",
        "hardware.pcie": "PCIe",
        "hardware.disk": "disk",
        "hardware.diskFree": "disk free",
        "hardware.tempRange": "temp (min/max)",
        "hardware.powerRange": "power (min/max)",
        "hardware.pcieIn": "MB/s in",
        "hardware.pcieOut": "MB/s out",
        "hardware.diskRead": "read",
        "hardware.diskWrite": "write",
        "hardware.threads": "threads",

        "offline.hint": "Server is not responding. Check the address in settings (gear icon at the bottom) — usually http://<host-ip>:12387",

        "error.timeout": "Timed out",
        "error.unreachable": "Host unreachable",
        "error.lost": "Connection lost",
        "error.badURL": "Invalid address:",
        "error.badStatus": "Server replied HTTP %d",
        "error.emptyBody": "Empty response from the server",
        "error.noMonitor": "No monitor data on the server"
    ]

    /// String for a key in the given language; an unknown key is returned as is.
    public static func string(_ key: String, language: AppLanguage) -> String {
        switch language {
        case .russian: return ru[key] ?? en[key] ?? key
        case .english: return en[key] ?? ru[key] ?? key
        }
    }
}
