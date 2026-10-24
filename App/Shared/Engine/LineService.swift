import Foundation
import MixlingsGenome
#if canImport(FoundationModels)
import FoundationModels
#endif

/// THE line service (§0, §2): every short line the creature "says" (speech bubble, widget,
/// notification, diary, chat bubbles) comes from here and passes the same guardrails.
///
/// - Templates (en / uk) always work and are the fallback.
/// - On iOS 26 devices with Apple Intelligence, `LineService.generate` may ask the on-device
///   Foundation Models for a fresh line. Input = only the creature's name, temper, weather kind
///   and category; nothing personal, nothing leaves the device. Output is filtered and capped.
/// - The "Lines written by on-device AI" label is shown only when a shown line came from AI.
enum LineCategory: String, Codable, CaseIterable, Sendable {
    case selfCare, encouragement, weather, banter, diary, chat
}

struct Line: Equatable, Sendable {
    var text: String
    var category: LineCategory
    var byAI: Bool
}

enum LineLanguage: String, Sendable {
    case en, uk

    static var current: LineLanguage {
        let pref = Bundle.main.preferredLocalizations.first ?? Locale.current.identifier
        return pref.hasPrefix("uk") ? .uk : .en
    }
}

/// Guardrails shared by templates and AI output (§2).
enum LineGuard {
    static let maxLength = 80

    /// Topics lines must never touch (medical, mental health, diet, relationships, guilt,
    /// crisis). Matched on lowercased text, as substrings. Deliberately broad.
    static let bannedFragments: [String] = [
        // en
        "doctor", "medic", "pills", "diagnos", "therap", "depress", "anxiet", "suicid", "kill", " die ",
        "dying", "dead", "death", "self-harm", " harm", "hurt yourself", "diet", "calorie", "weight",
        " fat ", "skinny", "boyfriend", "girlfriend", "crush", " date ", "dating", "kiss", "love you",
        "miss you", "sad you", "you left", "abandon", "lonely", "alone without", "your fault",
        "disappoint", "blood", "drug", "alcohol", "beer", "wine", "weapon", "gun",
        "http", "www", "@", "address", "phone", "password",
        // uk
        "лікар", "ліки", "таблет", "діагноз", "терап", "депрес", "тривож", "суїцид", "самогуб",
        "вбит", "помер", "смерт", "мертв", "шкоду", "дієт", "калор", "вага", "схудн", "товст",
        "хлопець", "дівчина", "кохан", "побачен", "поцілу", "сумую за", "ти пішов", "ти пішла",
        "покинув", "покинула", "самотн", "твоя провина", "розчарув", "кров", "алкогол", "пиво",
        "вино", "зброя", "пароль", "адрес", "телефон",
    ]

    /// Returns the cleaned line, or nil if it breaks a rule.
    static func filter(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip wrapping quotes the model likes to add.
        let quotes: Set<Character> = ["\"", "“", "”", "«", "»", "'"]
        while let f = t.first, quotes.contains(f) { t.removeFirst() }
        while let l = t.last, quotes.contains(l) { t.removeLast() }
        t = t.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t.count <= maxLength else { return nil }
        let lower = " " + t.lowercased() + " "
        // Same text with punctuation as spaces, so " die " also catches "die!".
        let spaced = String(lower.map { $0.isLetter || $0.isNumber ? $0 : " " })
        if bannedFragments.contains(where: { lower.contains($0) || spaced.contains($0) }) { return nil }
        if NameFilter.containsBlockedWord(t) || NameFilter.looksLikeContactInfo(t) { return nil }
        if t.filter(\.isNumber).count >= 5 { return nil }
        return t
    }
}

enum LineService {
    // MARK: Templates

    /// Picks a deterministic template for `seed` (same seed → same line, so the widget, the
    /// app and the diary agree). `{name}`, `{other}`, `{winner}` are substituted.
    static func template(_ category: LineCategory, seed: String, language: LineLanguage = .current,
                         name: String, other: String? = nil, temper: Int = 0,
                         weather: WeatherKind = .none, scene: LifeScene? = nil, winner: String? = nil) -> Line {
        let pool = LineTemplates.pool(category, language: language, temper: temper, weather: weather, scene: scene)
        let pick = pool.isEmpty ? "" : pool[Int(Hash.fnv1a32("\(category.rawValue)|\(seed)") % UInt32(pool.count))]
        let text = pick
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{other}", with: other ?? name)
            .replacingOccurrences(of: "{winner}", with: winner ?? name)
        // Names are already filtered (NameFilter); a long name may push past 80 chars: trim.
        let capped = text.count > LineGuard.maxLength ? String(text.prefix(LineGuard.maxLength - 1)) + "…" : text
        return Line(text: capped, category: category, byAI: false)
    }

    /// Chat bubble for pair scenes: emotes only (no free text between creatures, §9 / §10).
    static func chatBubble(seed: String) -> String {
        let pool = LineTemplates.chatEmotes
        return pool[Int(Hash.fnv1a32("chat|\(seed)") % UInt32(pool.count))]
    }

    /// The Home speech bubble: weather comment when there is weather, else banter by temper,
    /// with an occasional encouragement / self-care nudge. Deterministic per hour.
    static func homeLine(for c: Creature, activity: Activity, now: Date, timeZone: TimeZone = .current,
                         language: LineLanguage = .current) -> Line {
        let traits = PhenotypeMapper.traits(for: c)
        let hourKey = "\(c.id)|\(CollectingEngine.dayKey(now, timeZone: timeZone))|\(ActivityStateMachine.localHour(now, timeZone))"
        let roll = Hash.fnv1a32("home|" + hourKey) % 10
        let category: LineCategory
        if activity.weather != .none && activity.weather != .night && roll < 6 {
            category = .weather
        } else if roll < 2 {
            category = .encouragement
        } else if roll < 4 {
            category = .selfCare
        } else {
            category = .banter
        }
        return template(category, seed: hourKey, language: language, name: c.name, temper: traits.temper,
                        weather: activity.weather)
    }

    // MARK: On-device AI (iOS 26+, optional)

    static var aiAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }
        #endif
        return false
    }

    /// Tries the on-device model; falls back to `fallback` on any failure, timeout, or a line
    /// that fails the guardrails. Never throws, never blocks the UI (call from a Task).
    static func generate(_ category: LineCategory, name: String, temperName: String, weather: WeatherKind,
                         language: LineLanguage = .current, fallback: Line) async -> Line {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            guard case .available = SystemLanguageModel.default.availability else { return fallback }
            let lang = language == .uk ? "Ukrainian" : "English"
            let instructions = """
            You write one short, cheerful line said by a tiny pixel pet in a kids' game. \
            Rules: at most 70 characters, \(lang) only, one sentence, no quotes, no emojis \
            except at most one. Always positive. Never give medical, mental-health, diet or \
            relationship advice. Never mention death, sadness about being left, guilt, or anything scary. \
            Never ask personal questions.
            """
            let topic: String
            switch category {
            case .selfCare: topic = "a gentle nudge to drink water, stretch, rest your eyes or go to bed on time"
            case .encouragement: topic = "warm encouragement like 'you showed up today'"
            case .weather: topic = "a playful comment about the weather: \(weatherWord(weather))"
            case .banter: topic = "a line that shows a \(temperName) personality"
            case .diary: topic = "a one-line diary note about a cosy day at home"
            case .chat: return fallback // chat bubbles are emotes only
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: "The pet is called \(name). Write \(topic).")
                if let clean = LineGuard.filter(response.content), clean.count <= 70 {
                    return Line(text: clean, category: category, byAI: true)
                }
            } catch {
                return fallback
            }
        }
        #endif
        return fallback
    }

    private static func weatherWord(_ w: WeatherKind) -> String {
        switch w {
        case .none: return "a clear day"
        case .rain: return "rain (puddles are fun and cosy)"
        case .heat: return "a hot sunny day"
        case .snow: return "snow and frost"
        case .wind: return "strong wind"
        case .night: return "a starry night"
        }
    }

    // MARK: Diary lines (§9)

    static func diaryLine(_ entry: LivingEngine.DiaryEntry, a: Creature, b: Creature?,
                          language: LineLanguage = .current) -> String {
        let seed = "\(a.id)|\(Int(entry.date.timeIntervalSince1970 / 3600))"
        let other = b?.name
        switch entry.kind {
        case .scene(let scene):
            let winner = entry.winnerId.flatMap { id in [a, b].compactMap { $0 }.first { $0.id == id }?.name }
            return template(.diary, seed: seed, language: language, name: a.name, other: other,
                            scene: scene, winner: winner).text
        case .weather(let w):
            return template(.diary, seed: seed, language: language, name: a.name, other: other, weather: w).text
        case .slept:
            return template(.diary, seed: seed, language: language, name: a.name, other: other,
                            weather: .night).text
        }
    }
}

/// Raw template tables. Every template must pass `LineGuard.filter` with a 16-letter name
/// (enforced by tests). Keep them short, kind, and free of advice.
enum LineTemplates {
    static let chatEmotes = ["😊💬", "🎨✨", "♟️🤔", "🍪?", "⭐️⭐️", "😂", "🌧️☂️", "💡!", "🎵", "🫶"]

    static func pool(_ c: LineCategory, language: LineLanguage, temper: Int, weather: WeatherKind,
                     scene: LifeScene?) -> [String] {
        let uk = language == .uk
        switch c {
        case .selfCare: return uk ? selfCareUK : selfCareEN
        case .encouragement: return uk ? encouragementUK : encouragementEN
        case .weather: return (uk ? weatherUK : weatherEN)[weather] ?? (uk ? weatherUK : weatherEN)[WeatherKind.none] ?? []
        case .banter:
            let table = uk ? banterUK : banterEN
            return table.indices.contains(temper) ? table[temper] : table[0]
        case .diary:
            if let scene { return (uk ? diaryUK : diaryEN)[scene] ?? [] }
            return (uk ? diaryWeatherUK : diaryWeatherEN)[weather] ?? []
        case .chat: return chatEmotes
        }
    }

    static let selfCareEN = [
        "Sip of water? I'm having one too!",
        "Stretch break! Reach for the sky with me.",
        "Let's rest our eyes for a moment.",
        "Bedtime soon? I'm already yawning.",
        "Wiggle your toes! I just did.",
        "Look out the window for a bit with me.",
    ]
    static let selfCareUK = [
        "Ковток води? Я теж п'ю!",
        "Перерва на потягушки! Тягнемося до неба.",
        "Дамо очам трохи відпочити.",
        "Скоро спати? Я вже позіхаю.",
        "Поворуши пальчиками! Я вже.",
        "Подивимося трохи у вікно разом.",
    ]

    static let encouragementEN = [
        "You showed up today. That counts!",
        "I like it when you're here.",
        "Small steps are still steps!",
        "You're doing great, {name} says so.",
        "Today is a good day to try something.",
    ]
    static let encouragementUK = [
        "Ти сьогодні тут. Це вже круто!",
        "Мені подобається, коли ти поруч.",
        "Маленькі кроки — теж кроки!",
        "У тебе все виходить, так каже {name}.",
        "Сьогодні гарний день, щоб спробувати щось нове.",
    ]

    static let weatherEN: [WeatherKind: [String]] = [
        .none: ["What a nice clear sky!", "Perfect day for a little adventure."],
        .rain: ["Puddles! Splash time!", "Rain sounds so cosy.", "I love the pitter-patter."],
        .heat: ["Phew, it's hot! Shade, please.", "Sunny! Where's my hat?"],
        .snow: ["Snow! Let's make tiny snowballs.", "Brr! Scarf weather."],
        .wind: ["Whoosh! My ears are flying!", "The wind wants to play tag."],
        .night: ["Look, stars!", "The moon is out. Sleepy time."],
    ]
    static let weatherUK: [WeatherKind: [String]] = [
        .none: ["Яке ясне небо!", "Чудовий день для маленької пригоди."],
        .rain: ["Калюжі! Час хлюпатися!", "Дощик звучить так затишно.", "Люблю, як дощ стукотить."],
        .heat: ["Ух, спекотно! Хочу в тінь.", "Сонечко! Де мій капелюх?"],
        .snow: ["Сніг! Зліпимо крихітні сніжки.", "Брр! Погода для шарфика."],
        .wind: ["Ууух! Мої вушка літають!", "Вітер хоче погратися в квача."],
        .night: ["Дивись, зорі!", "Місяць зійшов. Час спатки."],
    ]

    /// Index = `temper` variant (calm, playful, shy, brave, grumpy, curious, sneaky, dreamy, noble, chaotic).
    static let banterEN: [[String]] = [
        ["Let's take it slow today.", "Mmm, a calm cup of nothing."],
        ["Tag! You're it!", "Can we play? Pleeease?"],
        ["Oh! Hi… I didn't see you there.", "I'll just sit here quietly."],
        ["I'm not scared of anything! Mostly.", "Adventure time!"],
        ["Hmph. Fine. Hi.", "I'm not grumpy. I'm thinking."],
        ["What's that? And that? And THAT?", "I found a shiny pebble!"],
        ["I didn't take the cookie. Probably.", "Shh, I'm hiding."],
        ["I dreamt of a cloud made of jam.", "Do clouds have dreams too?"],
        ["Greetings, friend of the realm.", "A fine day, wouldn't you agree?"],
        ["Bloop! Zing! Hi!", "I licked a rainbow. Tasted blue."],
    ]
    static let banterUK: [[String]] = [
        ["Сьогодні нікуди не поспішаймо.", "Ммм, спокійненько."],
        ["Квач! Ти ловиш!", "Пограємося? Ну будь ласочка?"],
        ["Ой! Привіт… я тебе не помітив.", "Я просто тихенько посиджу."],
        ["Я нічого не боюся! Майже.", "Час пригод!"],
        ["Хм. Гаразд. Привіт.", "Я не буркочу. Я думаю."],
        ["А це що? А це? А ОЦЕ?", "Я знайшов блискучий камінчик!"],
        ["Я не брав печиво. Мабуть.", "Тсс, я ховаюся."],
        ["Мені наснилася хмарка з варення.", "А хмаркам теж щось сниться?"],
        ["Вітаю, друже королівства.", "Чудовий день, чи не так?"],
        ["Блуп! Дзинь! Привіт!", "Я лизнув веселку. Смакує синім."],
    ]

    static let diaryEN: [LifeScene: [String]] = [
        .chess: ["{name} and {other} played chess. {winner} won!", "A long chess game. {winner} won."],
        .painting: ["{name} and {other} painted a picture.", "They painted a sunny meadow together."],
        .chatting: ["{name} and {other} chatted for ages.", "They told each other funny stories."],
        .pillowFort: ["They built a huge pillow fort.", "{name} and {other} made a pillow castle."],
        .napping: ["{name} and {other} had a cosy nap.", "Nap time, side by side."],
        .cooking: ["{name} and {other} baked tiny cookies.", "They cooked pancakes. Yum!"],
        .stargazing: ["They counted stars at the window.", "{name} found a star shaped like {other}."],
        .breakfast: ["Breakfast time! {name} had seconds.", "A sunny breakfast at home."],
        .backpack: ["{name} packed the backpack.", "Backpack ready. Pencils too!"],
        .homework: ["{name} did homework with a tiny pencil.", "Homework done! High five."],
        .dinner: ["Dinner together. Soup!", "{name} and {other} shared dinner."],
        .meditating: ["{name} sat very still and breathed slowly.", "A quiet, calm moment for {name}."],
        .windDown: ["{name} yawned and dimmed the lights.", "A cosy evening. {name} got sleepy."],
    ]
    static let diaryUK: [LifeScene: [String]] = [
        .chess: ["{name} і {other} грали в шахи. Переміг {winner}!", "Довга партія в шахи. Переміг {winner}."],
        .painting: ["{name} і {other} намалювали картину.", "Вони разом намалювали сонячну галявину."],
        .chatting: ["{name} і {other} довго балакали.", "Вони розповідали одне одному смішні історії."],
        .pillowFort: ["Вони збудували величезну фортецю з подушок.", "{name} і {other} зробили замок з подушок."],
        .napping: ["{name} і {other} затишно подрімали.", "Тиха година, пліч-о-пліч."],
        .cooking: ["{name} і {other} спекли крихітне печиво.", "Вони насмажили млинців. Смакота!"],
        .stargazing: ["Вони рахували зорі біля вікна.", "{name} знайшов зірку, схожу на {other}."],
        .breakfast: ["Час сніданку! {name} попросив добавки.", "Сонячний сніданок удома."],
        .backpack: ["{name} зібрав рюкзак.", "Рюкзак готовий. Олівці теж!"],
        .homework: ["{name} робив домашку крихітним олівцем.", "Домашку зроблено! Дай п'ять."],
        .dinner: ["Вечеря разом. Супчик!", "{name} і {other} разом повечеряли."],
        .meditating: ["{name} тихенько сидів і повільно дихав.", "Тиха спокійна хвилинка для {name}."],
        .windDown: ["{name} позіхнув і пригасив світло.", "Затишний вечір. {name} захотів спати."],
    ]

    static let diaryWeatherEN: [WeatherKind: [String]] = [
        .rain: ["It rained. {name} splashed in every puddle.", "Rainy hours, cosy hours."],
        .heat: ["So hot! {name} hid in the shade.", "A sunny, sunny afternoon."],
        .snow: ["Snow fell! {name} caught a snowflake.", "Frosty windows, warm house."],
        .wind: ["A windy day. {name}'s ears flew!", "The wind sang outside."],
        .night: ["{name} slept like a baby.", "A quiet night of sweet dreams."],
        .none: ["A calm, sunny hour."],
    ]
    static let diaryWeatherUK: [WeatherKind: [String]] = [
        .rain: ["Йшов дощ. {name} хлюпав у кожній калюжі.", "Дощові години — затишні години."],
        .heat: ["Так спекотно! {name} ховався в тіні.", "Сонячний-пресонячний день."],
        .snow: ["Випав сніг! {name} спіймав сніжинку.", "Морозні вікна, тепла хатинка."],
        .wind: ["Вітряний день. Вушка {name} літали!", "За вікном співав вітер."],
        .night: ["{name} солодко спав.", "Тиха ніч і гарні сни."],
        .none: ["Спокійна сонячна година."],
    ]
}
