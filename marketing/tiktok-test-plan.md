# Mixlings — TikTok Reach Smoke Test (2 тижні, 15 відео)

> Автор: Хайп (маркетинг). Мова відео — англійська; інструкції для засновника — українською.
> Мета тесту: перевірити, чи «мій Mixling + твій = ???» сам по собі збирає охоплення з нуля.
> **Критерій успіху: ≥2 з 15 відео >10 000 переглядів І ≥300 записів у waitlist (13+).**

---

## 0. Що показало дослідження (коротко)

| Висновок | Що беремо в план | Джерело |
|---|---|---|
| Pengu (віртуальний пінгвін для друзів) масштабувався не одним акаунтом, а потоком простих відео: screen-grab геймплею з текстом поверх, «безголосий» креатор + телефон, по 2–3 відео/день; 20 % відео давали 10× від медіани. | Прості рендери + текст поверх працюють; головне — обсяг спроб і швидкий відбір переможців. | [Shortimize — Pengu TikTok strategies](https://www.shortimize.com/blog/tiktok-strategies-pet-penguin-app-generating-millions-in-revenue) |
| Locket Widget злетів від **одного** TikTok-відео: ~5 млн реєстрацій за ~3 тижні. Віджет на чужому екрані = емоційний «POV». | 3 віджет-POV відео; показувати реальний телефон, а не абстракцію. | [KTLA — Locket](https://ktla.com/news/technology/this-22-year-old-created-a-photo-widget-app-to-stay-connected-with-his-girlfriend-and-it-went-viral/amp/), [Appfigures — widget growth](https://appfigures.com/resources/insights/20220114/5-new-year-new-widget-same-growth-strategy) |
| Focus Friend (Hank Green): 1,4 млн завантажень за тиждень, але переважно завдяки аудиторії автора, і сплеск швидко згас. | У нас нового акаунта без аудиторії немає «Хенка» — тому ставка на хук і коментарі, а не на особистість. Вимірюємо утримання, не лише піки. | [Appfigures — Focus Friend](https://appfigures.com/resources/insights/20250905/1-the-app-that-dethroned-chatgpt-isnt-what-youd-expect) |
| Для інді-ігор: хук у перші ~0,5 с, 15–30 с ролики, «сирий» WIP часто б'є полірований маркетинг, before/after, серії «Day N», лупи. | Хук 1,5 с, ролики 7–25 с, лупи в reveal-відео, чесний build-in-public. | [presskit.gg — TikTok indie game marketing](https://presskit.gg/field-guides/tiktok-indie-game-marketing) |
| TikTok має мітку «AI-generated» для контенту, створеного/суттєво зміненого ШІ. | Якщо використовуємо ШІ-голос або ШІ-згенеровані відео — вмикаємо мітку. Чесно кажемо, що гру робимо з ШІ. | [Search Engine Land — TikTok AI label](https://searchengineland.com/tiktok-new-label-ai-generated-content-432127) |

---

## 1. Налаштування акаунта

### 1.1 Варіанти хендла (новий акаунт, без зв'язку з PSDinfo/іншими брендами)
1. `@mixlings` (якщо вільний — пріоритет)
2. `@mixlings.app`
3. `@playmixlings`
4. `@mixlingsgame`
5. `@hatchmixlings`

Перевір доступність у TikTok **і** Instagram/YouTube одночасно — бажано однаковий хендл скрізь (для крос-постингу Reels/Shorts пізніше).

### 1.2 Біо (≤80 символів)
```
tiny pixel pets for your lock screen 🥚 breed with friends · coming soon
```
Альтернатива:
```
my Mixling + yours = ??? · pixel pets that never die · iOS coming soon
```

### 1.3 Посилання в біо / waitlist
- Посилання в біо на звичайному особистому акаунті з'являється лише після ~1 000 підписників; **бізнес-акаунт** зазвичай дає посилання одразу. Компроміс: бізнес-акаунт має доступ лише до Commercial Music Library (не всі трендові звуки). **Рекомендація:** бізнес-акаунт з першого дня — без посилання тест не виміряє waitlist. Перевір фактичну доступність поля «Website» під час створення.
- Посилання — на просту сторінку waitlist (окремий домен/лендинг Mixlings) з `?utm_source=tiktok&utm_campaign=smoke1`. Посилання в біо одне, тож окремий UTM для кожного відео неможливий. Тому атрибуція так: **кліки й реєстрації по днях** (Bitly/власний редирект) зіставляємо з датою публікації + на лендингу необов'язкове поле «Which video brought you?» з вибором (hatch / widget / devlog / vote / legendary).
- Вимоги до форми — див. розділ 5 (лише email + чекбокс «I'm 13 or older»).
- Pinned-коментар під кожним відео: `waitlist link in bio 🥚 (13+)`.

### 1.4 Розклад: 15 відео за 14 днів
Часові вікна (тестуємо два слоти, далі лишаємо переможця):
- **Слот A — «UK вечір / US обід»:** 19:00 Лондон = 14:00 Нью-Йорк (ET) = 11:00 Лос-Анджелес.
- **Слот B — «US вечір»:** 19:30 ET = 16:30 PT = 00:30 Лондон.
- Увага: UK переходить на зимовий час 25.10.2026, США — 01.11.2026. Між цими датами різниця Лондон–Нью-Йорк = 4 год, а не 5. Ставимо час публікації за **ET**, а не за Києвом.
- Київ (EET, UTC+2 після 25.10): слот A ≈ 21:00, слот B ≈ 02:30 → слот B став через планувальник TikTok Studio (desktop).

| День | Відео | Слот | Формат |
|---|---|---|---|
| D1 | #01 | A | Reveal |
| D2 | #02 | B | Widget POV |
| D3 | #03 | A | Build-in-public |
| D4 | #04 | B | Reveal |
| D5 | #05 | A | Interactive (вибір батьків) |
| D6 | #06 | B | Reveal (результат #05) |
| D7 | #07 | A | Mutation hype |
| D8 | #08 | B | Widget POV |
| D9 | #09 | A | Reveal (twin eggs) |
| D10 | #10 | A | Build-in-public / stitch |
| D10 | #11 | B | Reveal + duet bait |
| D11 | #12 | A | Interactive round 2 |
| D12 | #13 | B | Reveal (результат #12) |
| D13 | #14 | A | Widget POV |
| D14 | #15 | B | Mutation hype + waitlist push |

Правила:
- Перші 60 хв після публікації — відповідати на коментарі (відповіді-відео на найкращі коментарі — це «безкоштовні» додаткові ролики, не входять у 15, але дозволені).
- Якщо одне відео >10k — **не змінюємо план**, але наступного дня робимо його варіацію (той самий хук, інші батьки) замість найслабшого запланованого.
- Не видаляти «провальні» відео (це шкодить акаунту і тесту).

### 1.5 Хештеги
- 3–5 на відео, не більше. Структура: **1 широкий + 2 нішеві + 1 брендовий**.
- Широкі (по черзі): `#gaming` `#indiegame` `#cozygames`
- Нішеві: `#pixelart` `#virtualpet` `#tamagotchi` `#widget` `#lockscreen` `#iphonetips` `#cozygaming` `#gamedev` `#indiedev`
- Брендовий (завжди): `#mixlings`
- Для build-in-public: `#gamedev #indiedev #buildinpublic`
- Ключові слова — також у тексті на екрані й в описі (пошук TikTok індексує текст): "pixel pet", "lock screen pet", "breed with friends".

---

## 2. Сценарії 15 відео

Загальне:
- Формат 9:16, 1080×1920, 7–25 с. Піксель-арт масштабувати **лише nearest-neighbor, цілими кратними** (32 → 640 / 960 / 1024 px).
- Текст на екрані — у безпечній зоні (не нижче ~1500 px і не правіше ~900 px, щоб UI TikTok не перекривав).
- Звук: **трендовий звук на момент публікації**, що відповідає опису вайбу. Ніколи не використовуємо пісні поза бібліотекою, доступною акаунту.
- Кожне reveal-відео закінчується кадром, який візуально «склеюється» з першим (луп → більше переглядів до кінця).

---

### #01 — "My Mixling + yours = ???"
- **Формат:** Reveal
- **HOOK (0–1,5 с):** `my pet + my bestie's pet = ???`
- **Шот-лист:**
  - 0,0–1,5 — Parent A (синій круглий, плаский візерунок) ліворуч, Parent B (рожевий з вушками і хвостом) праворуч, між ними великий `+`
  - 1,5–3,0 — обидва «підстрибують» і зливаються в центр (2 кадри bounce + white flash)
  - 3,0–6,0 — яйце з'являється, хитається (egg shake, 3 цикли, з наростанням)
  - 6,0–6,5 — тріщини (crack frames 1–3)
  - 6,5–7,0 — hatch flash (білий спалах на весь екран)
  - 7,0–10,0 — hybrid reveal: гібрид із вушками B, кольором A, легке «дихання» (idle 2 кадри)
  - 10,0–11,0 — текст + повернення до кадру з двома батьками (луп)
- **Текст/VO (лише текст, без голосу):** "she sent me her Mixling" → "we hatched THIS" → "it's on both our phones now"
- **Аудіо:** милий, легкий трендовий звук з «drop» рівно на hatch flash (6,5 с).
- **CTA:** `Mixlings · iOS coming soon · waitlist in bio (13+)`
- **Коментар-промпт:** `name this baby 👇 best name becomes its official name`
- **Хештеги:** `#pixelart #virtualpet #cozygames #mixlings`

### #02 — "POV: a pet that lives on your lock screen"
- **Формат:** Widget POV
- **HOOK:** `POV: your lock screen has a tiny pet now`
- **Шот-лист:**
  - 0,0–1,5 — мокап iPhone, чорний екран, «натиснули» — вмикається Lock Screen з годинником і віджетом Mixling (маленький піксельний звір під часом)
  - 1,5–4,0 — zoom на віджет; звір кліпає (blink 2 кадри)
  - 4,0–7,0 — свайп на Home Screen: віджет середнього розміру, той самий звір, idle анімація
  - 7,0–9,0 — текст поверх, звір «махає» (wave/bounce)
- **Текст:** "checks phone 200x a day" → "might as well say hi to someone" → "it never dies. no ads."
- **Аудіо:** спокійний lo-fi / cozy трендовий звук.
- **CTA:** `waitlist in bio · coming soon to iPhone`
- **Коментар-промпт:** `what colour should mine be? 🎨 drop one`
- **Хештеги:** `#lockscreen #widget #iphonetips #mixlings`
- **Примітка:** показувати лише ті розміри віджетів, які реально заплановані в дизайні. Якщо Lock Screen-віджет поки не підтверджений — пишемо `concept` у кутку.

### #03 — "I'm building a pixel pet game with AI. Day 1."
- **Формат:** Build-in-public
- **HOOK:** `I'm making a pixel pet game with AI. honestly.`
- **Шот-лист:**
  - 0,0–1,5 — запис екрана: спрайт-лист (sheet.png) прокручується
  - 1,5–5,0 — split: зліва код/таблиця генів (body / eyes / head / tail / palette / aura), справа — відповідні частини на спрайті підсвічуються
  - 5,0–9,0 — швидкий монтаж: 6 тіл → 8 очей → голови → хвости збираються в одного звіра
  - 9,0–13,0 — breeding.png: два батьки → дитина
  - 13,0–15,0 — фінал: звір на віджеті в мокапі
- **Текст/VO (текст або голос засновника англійською; якщо ШІ-голос — вмикаємо мітку AI-generated):** "I'm one person + an AI teammate making a game" → "every creature is 8 genes" → "two pets breed, the baby inherits real genes" → "the AI helps me code. the creature designs are approved by me" → "following along?"
- **Чесність:** не кажемо «AI made the whole game»; не кажемо дату релізу, якої немає.
- **Аудіо:** тихий «study/work» трендовий звук, або оригінальний звук клавіатури.
- **CTA:** `follow for Day 2 · waitlist in bio`
- **Коментар-промпт:** `what should I add next? 👇 I read every comment`
- **Хештеги:** `#gamedev #indiedev #buildinpublic #mixlings`

### #04 — "Breeding the ugliest one with the cutest one"
- **Формат:** Reveal
- **HOOK:** `breeding the ugliest one with the cutest one`
- **Шот-лист:**
  - 0,0–1,5 — Parent A «ugly» (дивний колір, циклоп-око, без хвоста) з підписом `ugly` і Parent B «cute» (великі очі, вушка) з підписом `cute`
  - 1,5–3,0 — злиття + яйце
  - 3,0–5,5 — egg shake (короткий, швидкий)
  - 5,5–6,0 — hatch flash
  - 6,0–9,0 — гібрид (повинен бути реально смішним/несподіваним: напр. cute-очі + ugly-колір)
  - 9,0–10,0 — підпис `???` і зум на обличчя
- **Текст:** "ugly" / "cute" → "and the baby is…" → "honestly? perfect"
- **Аудіо:** комедійний трендовий звук з паузою перед «панчлайном».
- **CTA:** `Mixlings · coming soon · waitlist in bio`
- **Коментар-промпт:** `ugly, cute, or uglycute? 1/2/3 👇`
- **Хештеги:** `#pixelart #indiegame #virtualpet #mixlings`

### #05 — "You pick the parents"
- **Формат:** Interactive (poll)
- **HOOK:** `you pick who breeds. I hatch it tomorrow.`
- **Шот-лист:**
  - 0,0–1,5 — сітка 2×3 з шести різних Mixlings, кожен під номером 1–6
  - 1,5–8,0 — кожен по черзі «підстрибує» 1 с, з'являється назва-тип (напр. `1 blob` `2 horned` `3 sparkly`…)
  - 8,0–10,0 — всі шість разом, текст `comment 2 numbers`
- **Текст:** "6 Mixlings" → "comment 2 numbers" → "most liked combo hatches tomorrow"
- **Аудіо:** енергійний трендовий звук з битом на кожну появу.
- **CTA:** `follow so you see the hatch`
- **Коментар-промпт:** `comment 2 numbers like "3+5" 👇`
- **Хештеги:** `#virtualpet #pixelart #cozygaming #mixlings`
- **Операційно:** через ~20 год беремо коментар з найбільшою кількістю лайків, рендеримо реальний результат схрещування з рушія (engine-ts), без підтасовки.

### #06 — "You picked 3+5. Here's the baby."
- **Формат:** Reveal (результат #05)
- **HOOK:** `you voted 3+5. here's your baby.` (числа — фактичні)
- **Шот-лист:**
  - 0,0–1,5 — скрін коментаря-переможця (через функцію «Reply with video» на цей коментар — тоді він автоматично з'являється як наклейка)
  - 1,5–3,5 — Parent 3 і Parent 5 по боках, `+`
  - 3,5–6,5 — яйце, повільний shake з напругою (3 цикли)
  - 6,5–7,0 — hatch flash
  - 7,0–11,0 — гібрид + rarity-плашка, якщо вийшло uncommon/rare (лише фактична)
  - 11,0–12,0 — текст `round 2 soon?`
- **Текст:** "you chose" → "it's… actually adorable" → "who's the parent of round 2?"
- **Аудіо:** «suspense → reveal» трендовий звук.
- **CTA:** `waitlist in bio (13+)`
- **Коментар-промпт:** `name it 👇 top-liked name sticks`
- **Хештеги:** `#pixelart #virtualpet #indiegame #mixlings`

### #07 — "This is what a LEGENDARY Mixling looks like"
- **Формат:** Mutation / rare hype
- **HOOK:** `most eggs hatch normal. this one didn't.`
- **Шот-лист:**
  - 0,0–1,5 — звичайне яйце хитається; раптом — іскри aura
  - 1,5–4,0 — 3 «звичайні» вилуплення швидко (common, common, uncommon — з плашками)
  - 4,0–6,0 — четверте яйце: темніє екран, свічення, сильніший shake
  - 6,0–6,5 — кольоровий (не білий) hatch flash
  - 6,5–11,0 — legendary-гібрид з aura, повільне обертання камери (zoom-in/out), плашка `LEGENDARY`
  - 11,0–12,0 — повернення до першого кадру
- **Текст:** "common" / "common" / "uncommon" → "wait…" → "LEGENDARY"
- **Аудіо:** епічний / «aura» трендовий звук з великим drop.
- **CTA:** `coming soon · waitlist in bio`
- **Коментар-промпт:** `what would you name a legendary? 👇`
- **Хештеги:** `#pixelart #gaming #indiegame #mixlings`
- **Чесність:** НЕ називаємо конкретних шансів («1 in 1000»), поки баланс не затверджено. Тільки реальні тіри зі специфікації: common / uncommon / rare / legendary. Legendary-спрайт — реальний результат з рушія (рарність = сума рарностей генів).

### #08 — "POV: you and your bestie got twin eggs"
- **Формат:** Widget POV
- **HOOK:** `POV: you and your bestie hatched a baby together`
- **Шот-лист:**
  - 0,0–1,5 — два мокапи iPhone поруч (лівий «you», правий «bestie»), обидва з віджетами з різними Mixlings
  - 1,5–4,0 — на лівому телефоні з'являється стилізоване повідомлення-посилання (без справжнього месенджера/бренду; нейтральна «бульбашка» `🥚 breed with me?`)
  - 4,0–7,0 — на обох віджетах одночасно з'являється яйце, хитається
  - 7,0–9,0 — hatch на обох
  - 9,0–12,0 — на обох — одна дитина, але з трохи різним відтінком (twin palette shift)
- **Текст:** "she sent me a link" → "now we BOTH have the baby" → "twins. slightly different colours."
- **Аудіо:** «besties» / friendship трендовий звук.
- **CTA:** `send this to who you'd breed with 🥚 · waitlist in bio`
- **Коментар-промпт:** `tag the friend you'd hatch with 👇`
- **Хештеги:** `#widget #bestie #virtualpet #mixlings`
- **Чесність:** якщо інтерфейс посилання ще не намальований — плашка `concept`.

### #09 — "Same parents. Twin eggs. Not identical."
- **Формат:** Reveal
- **HOOK:** `twin eggs. same parents. spot the difference.`
- **Шот-лист:**
  - 0,0–1,5 — два однакові яйця поруч, підпис `you` / `them`
  - 1,5–4,0 — синхронний shake
  - 4,0–4,5 — подвійний hatch flash
  - 4,5–8,0 — двоє гібридів поруч, видно лише різницю відтінку
  - 8,0–10,0 — повільний зум, текст `spot it?`
- **Текст:** "both players get a twin" → "but not EXACTLY the same" → "which one's yours?"
- **Аудіо:** «spot the difference» / тихий lo-fi трендовий звук з паузою.
- **CTA:** `waitlist in bio · iOS coming soon`
- **Коментар-промпт:** `left or right? which would you keep 👇`
- **Хештеги:** `#pixelart #cozygames #virtualpet #mixlings`

### #10 — "How pixel genetics work (in 20 sec)"
- **Формат:** Build-in-public + stitch bait
- **HOOK:** `I gave pixel pets real genetics`
- **Шот-лист:**
  - 0,0–1,5 — один Mixling, поруч «ДНК»-смужка з 8 кольорових клітинок
  - 1,5–6,0 — кожна клітинка → частина тіла підсвічується (body, eyes, head, pattern, tail, palette, aura, temper)
  - 6,0–11,0 — два батьки, кожен з двома алелями; анімована стрілка `dominant wins` (напр. вушка проти без вушок)
  - 11,0–15,0 — дитина: «recessive» ознака несподівано проявляється
  - 15,0–17,0 — текст `stitch this with your guess`
- **Текст/VO:** "every Mixling has 8 genes" → "2 copies each, like real DNA" → "stronger genes win… usually" → "sometimes a hidden one shows up"
- **Аудіо:** «explainer» трендовий звук, або оригінальний голос засновника.
- **CTA:** `follow for the next devlog · waitlist in bio`
- **Коментар-промпт:** `which gene should I add next? 👇 wings? hats?` (лише як ідея; не обіцяємо реалізацію)
- **Хештеги:** `#gamedev #indiedev #buildinpublic #mixlings`

### #11 — "Guess the baby before it hatches"
- **Формат:** Reveal + duet bait
- **HOOK:** `draw what hatches. then watch.`
- **Шот-лист:**
  - 0,0–1,5 — два батьки + `?` в центрі
  - 1,5–5,0 — текст `pause & draw your guess` — порожня рамка 32×32 сітки в центрі (для дуету: люди малюють у своїй половині)
  - 5,0–8,0 — яйце, shake
  - 8,0–8,5 — hatch flash
  - 8,5–12,0 — гібрид з'являється в тій самій сітці
- **Текст:** "pause. draw. duet." → "how close were you?"
- **Аудіо:** «countdown / timer» трендовий звук.
- **CTA:** `duet this with your drawing · waitlist in bio`
- **Коментар-промпт:** `rate your guess 1–10 👇`
- **Хештеги:** `#pixelart #pixelartist #drawing #mixlings`

### #12 — "Round 2: your baby needs a partner"
- **Формат:** Interactive (round 2)
- **HOOK:** `your baby from round 1 is ready to breed`
- **Шот-лист:**
  - 0,0–1,5 — гібрид з #06 з іменем, яке обрали в коментарях
  - 1,5–8,0 — три кандидати-партнери A / B / C по черзі (по 2 с), кожен з коротким описом
  - 8,0–10,0 — усі разом, `A, B or C?`
- **Текст:** "meet [name] (you named it)" → "pick its partner" → "most-liked comment wins"
- **Аудіо:** «dating show / choose» трендовий звук.
- **CTA:** `follow to see the hatch`
- **Коментар-промпт:** `A, B or C? 👇 hatch drops in 24h`
- **Хештеги:** `#virtualpet #pixelart #cozygaming #mixlings`

### #13 — "Gen 2 just hatched"
- **Формат:** Reveal (результат #12) + challenge «name it»
- **HOOK:** `you made a GRANDBABY.`
- **Шот-лист:**
  - 0,0–1,5 — reply-наклейка на переможний коментар
  - 1,5–4,0 — «родинне дерево»: два прабатьки → дитина з #06 + партнер
  - 4,0–7,0 — яйце, shake
  - 7,0–7,5 — hatch flash
  - 7,5–12,0 — Gen 2 + rarity-плашка (фактична) + вигляд у мокапі віджета
- **Текст:** "round 1 → round 2" → "it kept grandma's ears" → "name it"
- **Аудіо:** «suspense → reveal» трендовий звук (інший, ніж у #06).
- **CTA:** `waitlist in bio (13+)`
- **Коментар-промпт:** `name the grandbaby 👇 + should we go round 3?`
- **Хештеги:** `#pixelart #virtualpet #indiegame #mixlings`

### #14 — "POV: you forgot your pet for a week"
- **Формат:** Widget POV
- **HOOK:** `POV: you forgot your pet for a whole week`
- **Шот-лист:**
  - 0,0–1,5 — мокап iPhone, календар/текст `7 days later…`
  - 1,5–4,0 — розблокування; на віджеті — Mixling на місці, idle-анімація
  - 4,0–7,0 — текст і zoom
  - 7,0–9,0 — Mixling кліпає / махає
- **Текст:** "my childhood tamagotchi would be gone" → "Mixlings don't die. ever." → "no guilt. no ads."
- **Аудіо:** ностальгічний / «childhood» трендовий звук.
- **CTA:** `the guilt-free pixel pet · waitlist in bio`
- **Коментар-промпт:** `how many tamagotchis did you lose? 💀 👇`
- **Хештеги:** `#tamagotchi #nostalgia #virtualpet #mixlings`
- **Чесність:** не показувати реакцію на відсутність гравця (сум, голод, бруд), якщо вона не спроєктована. Тільки «вона на місці».

### #15 — "We hatched 100 eggs. Here's what we got."
- **Формат:** Mutation hype + waitlist push
- **HOOK:** `we hatched 100 eggs. 1 was this.`
- **Шот-лист:**
  - 0,0–1,5 — швидка сітка 10×10 з реальних вилуплень (рендер з рушія), кольорові рамки за рарністю
  - 1,5–5,0 — зум до одного legendary/mutation серед них
  - 5,0–8,0 — повний legendary reveal з aura
  - 8,0–11,0 — фінальний кадр: мокап телефону з цим Mixling на віджеті + `coming soon`
  - 11,0–13,0 — `join the waitlist — link in bio`
- **Текст:** "100 eggs" → "count: common / uncommon / rare / legendary" (фактичні числа з симуляції) → "want one on your lock screen?"
- **Аудіо:** «zoom / reveal» трендовий звук з drop на зумі.
- **CTA:** `waitlist in bio · 13+ · iOS coming soon`
- **Коментар-промпт:** `which rarity would you get first? 👇`
- **Хештеги:** `#pixelart #gaming #indiegame #mixlings`
- **Чесність:** числа 100 вилуплень — **реальна** симуляція з рушія; підписати `simulated in our dev build`. Якщо мутації в тій симуляції не розблоковані — не показувати мутацію, тільки legendary-тір.

---

## 3. Візуальні ассети, які рендерить Claude (без дублів)

Усе — з `art/render.py` / `engine-ts`, nearest-neighbor, прозорий PNG (або MP4/GIF для анімацій), базовий спрайт 32×32.

### 3.1 Спрайти істот
| # | Ассет | Для відео |
|---|---|---|
| A1 | ~12 «героїв» (різні body/eyes/head/tail/palette), кожен PNG 32×32 + ×30 (960×960) | усі |
| A2 | Пара «ugly» + «cute» батьків | #04 |
| A3 | 6 кандидатів для голосування (нумеровані 1–6) | #05 |
| A4 | 3 кандидати-партнери A/B/C | #12 |
| A5 | Гібриди: реальні результати breed() для #01, #04, #06, #11, #13 (два останні — рендер після голосування) | reveal |
| A6 | Twin-пара: один гібрид з paletteShift 0 і 1 | #08, #09 |
| A7 | Legendary з aura (фактичний legendary з рушія) | #07, #15 |
| A8 | Idle-анімації: blink (2 кадри), breathe (2 кадри), bounce/wave (4 кадри) — для A1, A5, A7 | усі |

### 3.2 Анімація яйця і вилуплення (спільний набір)
| # | Ассет |
|---|---|
| B1 | Яйце 32×32 (базове) + варіант під палітру гібрида |
| B2 | Egg shake: 6 кадрів (наростання амплітуди) |
| B3 | Crack: 3 кадри |
| B4 | Hatch flash: білий full-frame (2 кадри) + кольоровий legendary-варіант |
| B5 | Merge-анімація: два батьки зливаються в центр (4 кадри) + спалах |
| B6 | Aura-ефект: іскри/свічення, 4 кадри, луп |
| B7 | Rarity-плашки: COMMON / UNCOMMON / RARE / LEGENDARY (піксельний шрифт) |

### 3.3 Мокапи телефону і віджетів (9:16)
| # | Ассет | Для відео |
|---|---|---|
| C1 | Generic iPhone-мокап (без логотипу Apple), 1080×1920: Lock Screen з годинником + Lock Screen-віджет | #02, #14 |
| C2 | Той самий — Home Screen з малим і середнім віджетом Mixlings | #02, #08, #13, #15 |
| C3 | Два телефони поруч (you / bestie), 1080×1920 | #08 |
| C4 | Нейтральна «бульбашка повідомлення» з `🥚 breed with me?` (без бренду месенджера) | #08 |
| C5 | Плашка `concept` для елементів, які ще не в дизайні | за потреби |

### 3.4 Композиції / шаблони 1080×1920
| # | Ассет | Для відео |
|---|---|---|
| D1 | Reveal-шаблон: батько A — `+` — батько B, яйце в центрі, safe-zone розмітка | #01, #04, #06, #09, #11, #13 |
| D2 | Сітка 2×3 з номерами | #05 |
| D3 | Сітка A/B/C | #12 |
| D4 | «ДНК»-смужка з 8 генами + підсвітка частин | #10 |
| D5 | Алелі A/B у двох батьків + стрілка домінантності | #10 |
| D6 | Порожня 32×32 сітка для дуету | #11 |
| D7 | Родинне дерево 2 поколінь | #13 |
| D8 | Сітка 10×10 із 100 реальних вилуплень з рамками рарності + таблиця підрахунку | #15 |
| D9 | Запис екрана: прокрутка sheet.png і breeding.png (build-in-public) | #03 |
| D10 | Фінальна картка CTA: `Mixlings · iOS coming soon · waitlist in bio (13+)` | усі |
| D11 | Аватар акаунта (Mixling-герой на однотонному фоні, 200×200 safe) | акаунт |

Монтаж (склеювання, текст, звук) — у CapCut/TikTok editor засновником або Claude готує MP4 без звуку, а трендовий звук додається в TikTok під час публікації.

---

## 4. Таблиця вимірювань

Заповнювати через **48 год** після публікації (основне) і ще раз через **7 днів**. Дані — з TikTok Studio → Analytics.

| Колонка | Опис |
|---|---|
| video_id | #01…#15 |
| post_datetime_ET | дата/час публікації (ET) |
| slot | A / B |
| format | reveal / POV / BIP / interactive / mutation / duet |
| hook_text | текст хука |
| length_s | тривалість |
| audio | який звук використали |
| views_48h | перегляди за 48 год |
| views_7d | перегляди за 7 днів |
| avg_watch_time_s | середній час перегляду |
| completion_pct | % досмотрів до кінця (watched full video) |
| retention_3s_pct | % тих, хто лишився після 3 с (якщо доступно) — показник сили хука |
| likes | |
| comments | |
| shares | |
| saves | |
| profile_views | |
| new_follows | |
| fyp_traffic_pct | % трафіку з For You (новий акаунт має бути >80 %) |
| top_geo | топ-країни (перевіряємо US/UK/англомовні) |
| bio_link_clicks | кліки по посиланню в біо в день публікації + наступний (з редиректа) |
| waitlist_signups | реєстрації за той самий період (з лендингу; + кодове слово, якщо вказали) |
| notes | що сталося (дубль звуку, бан, хейт, трендова хвиля) |

Похідні (формули):
- `engagement_rate = (likes + comments + shares + saves) / views_48h`
- `signup_per_1k_views = waitlist_signups / views_48h × 1000`
- `click_to_signup = waitlist_signups / bio_link_clicks`

### Правило Pass / Fail (через 14 днів + 48 год після #15)
- **PASS:** ≥2 відео мають `views_7d` > 10 000 **І** сумарно `waitlist_signups` ≥ 300.
- **PARTIAL:** виконано тільки одну умову → повторюємо тест 1 тиждень лише з форматами-переможцями (≥2× медіани переглядів), змінюємо хук / лендинг відповідно до того, що не виконано.
- **FAIL:** жодне відео >10k і <100 реєстрацій → гіпотезу «reveal-хук сам по собі тягне» відкидаємо; наступний тест — з людиною в кадрі (реакція/голос) або з UGC-креаторами.
- Додатковий сигнал якості: якщо `completion_pct` reveal-відео <30 % — скорочуємо до 6–8 с.

---

## 5. Безпека та відповідність

1. **Вік 13+.** Акаунт, контент і waitlist — тільки для 13+. Жодного контенту, орієнтованого на дітей до 13 (без «kids», шкільних тем молодших класів, дитячих персонажів-брендів). Рейтинг гри 13+ вказуємо в CTA.
2. **Мінімум даних у waitlist.** Лише email + обов'язковий чекбокс `I confirm I'm 13 or older` + згода на лист про запуск. Жодної дати народження, імені, телефону, геолокації, фото. Хто не підтвердив 13+ — запис не створюється. Окремо: у частині країн ЄС вік цифрової згоди — до 16 років; перед запуском waitlist юристу/засновнику вирішити — або обмежити ЄС 16+, або додати батьківську згоду. Політика конфіденційності — посилання під формою; право видалити email.
3. **Не збираємо даних з коментарів/DM.** Не просимо email, телефон, Discord чи інші контакти в коментарях або DM. Не пишемо першими в DM підліткам. Голосування — лише через публічні коментарі.
4. **Ніяких розіграшів/призів** у цьому тесті (окремі правила і вікові обмеження).
5. **Без оманливих тверджень.**
   - Завжди «coming soon», без дати релізу, поки її немає.
   - Не показуємо і не обіцяємо функцій, яких немає в дизайні (торгівля, PvP, бої, Android, NFT, гроші, нагороди). Елементи, що ще не намальовані фінально, — з плашкою `concept`.
   - Не називаємо шансів рарності/мутацій до затвердження балансу.
   - Усі результати схрещувань і «100 яєць» — реальні виходи рушія, не намальовані вручну «під хайп». Підпис `dev build` / `in-development footage`.
   - Не використовувати інтерфейс, логотипи чи назви чужих брендів (Apple, iMessage, Tamagotchi як бренд у візуалі; слово «tamagotchi» в тексті — як загальна ностальгічна відсилка, без натяку на зв'язок).
6. **Розкриття, що це наша гра.** Біо: «official account · we're making this game». У кожному описі — `our game, in development`. Не видаємо себе за «випадкового гравця, який знайшов гру» і не ведемо фейкових «фан-акаунтів».
7. **ШІ.** У build-in-public чесно: «I build it with an AI teammate». Якщо в ролику ШІ-голос, ШІ-згенероване відео чи фото — вмикаємо мітку TikTok «AI-generated content». Піксель-арт, згенерований нашим кодом за затвердженими дизайнами, описуємо як «procedurally rendered».
8. **Музика.** Тільки звуки з бібліотеки TikTok, доступні типу акаунта (бізнес → Commercial Music Library). Без завантаження сторонніх треків.
9. **Без зв'язку з іншими брендами засновника** — окремий email, окремий номер/акаунт, жодних згадок PSDinfo чи інших проєктів у відео, біо чи описах.
10. **Закритий доступ до внутрішніх матеріалів.** Цей план, спрайти та дані рушія не публікуємо і не передаємо назовні без прямої команди засновника — у відео йдуть лише готові ролики.
