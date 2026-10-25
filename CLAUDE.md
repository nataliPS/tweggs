# Контекст для Claude

Tweggs — продукт компанії **Orizo Labs** (пишеться саме так). Приватний проєкт: нічого не публікувати й не ділитися назовні без прямої команди засновника.
Специфікації — у `docs/` (genome-spec, backend-spec, living-world-spec, wellbeing-spec). Рушій: `engine-ts/` (еталон) ↔ `MixlingsKit/` (Swift), паритет через golden-вектори — не ламати.
Збірка: `codemagic.yaml` (iOS check → iOS → TestFlight), Xcode-проєкт генерується з `App/project.yml` (XcodeGen), у git не комітиться.
Принципи: нічого не карає гравця, не продаємо випадковість, дитяча приватність (COPPA / Kids), контент wellbeing перевіряють люди.
