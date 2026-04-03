# Інтеграція AdaptyFlowKit в MrScan

## Інформація про пакет

- **GitHub**: https://github.com/balabon7/AdaptyFlowKit
- **Локація**: /Users/oleksandrbalabon/Documents/Developer/AdaptyFlowKit
- **Версія**: 1.0.0

## Швидкий старт

### 1. Додати пакет в Xcode

#### Варіант A: З GitHub (для production)

1. Відкрий **MrScan.xcodeproj** в Xcode
2. File → Add Package Dependencies...
3. Вставити URL: `https://github.com/balabon7/AdaptyFlowKit`
4. Dependency Rule: "Up to Next Major Version" → 1.0.0
5. Add to Target: **MrScan**
6. Натисни "Add Package"

#### Варіант B: Локально (для розробки)

1. Відкрий **MrScan.xcodeproj** в Xcode
2. File → Add Package Dependencies...
3. Натисни "Add Local..."
4. Вибери `/Users/oleksandrbalabon/Documents/Developer/AdaptyFlowKit`
5. Add to Target: **MrScan**
6. Натисни "Add Package"

### 2. Оновити імпорти в MrScan

Замінити прямі імпорти файлів на імпорт модуля:

#### AppDelegate.swift
```swift
// Додати на початок файлу:
import AdaptyFlowKit

// Або окремо:
import OnboardingKit
import PaywallKit
import RatingKit
```

#### Файли що використовують Kit-и:

**MSWelcomeViewController.swift**:
```swift
import UIKit
import AdaptyFlowKit  // Додати

class MSWelcomeViewController: UIViewController {
    // Код без змін - AFAppFlowKit, AFOnboardingKit тепер доступні
}
```

**MSSettingsViewController.swift**:
```swift
import UIKit
import AdaptyFlowKit  // Додати

// Використання AFPaywallKit, AFRatingKit без змін
```

**MSPaywallViewController.swift**:
```swift
import UIKit
import AdaptyFlowKit  // Додати

// Використання AFPaywallKitUI без змін
```

### 3. Видалити старі файли (ОПЦІОНАЛЬНО)

⚠️ **Тільки після успішної інтеграції та тестування!**

Можна видалити папку:
```
MrScan/MrScan/AdaptyFlowKit/
```

Але краще залишити її як backup, поки не впевнишся що все працює.

### 4. Перевірка

1. **Build проєкт**: Cmd+B
2. **Перевірити помилки**: Не має бути import errors
3. **Запустити додаток**: Cmd+R
4. **Протестувати**:
   - Onboarding flow
   - Paywall presentation  
   - Rating prompt

## Конфігурація (без змін)

Вся конфігурація в **AppDelegate** залишається незмінною:

```swift
// В AppDelegate.swift - все як є
AFOnboardingKit.configure(...)
AFPaywallKit.configure(...)
AFRatingKit.configure(...)
AFAppFlowKit.configure(...)
```

## Переваги після інтеграції

✅ **Версіонування**: Легко оновлювати через Git tags
✅ **Переважне використання**: Можна використати в інших проєктах
✅ **Чистота коду**: MrScan містить тільки бізнес-логіку
✅ **Оновлення**: Централізовані оновлення в одному місці
✅ **Тестування**: Незалежне тестування SDK

## Оновлення пакету

### З GitHub:
1. Xcode → File → Packages → Update to Latest Package Versions
2. Або вибрати конкретну версію через Resolve Package Versions

### Локально:
Зміни в `/Users/oleksandrbalabon/Documents/Developer/AdaptyFlowKit` автоматично підхопляться при rebuild.

## Troubleshooting

### "No such module 'AdaptyFlowKit'"

**Рішення**:
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Xcode → File → Packages → Reset Package Caches
3. Rebuild (Cmd+B)

### "Ambiguous use of..."

**Рішення**: Можливо конфлікт між старими файлами та пакетом.
Переконайся що імпортуєш тільки `AdaptyFlowKit`, а не окремі файли.

### Build errors в package

**Рішення**: Перевір версію Adapty SDK в MrScan vs AdaptyFlowKit Package.swift.
Вони повинні співпадати!

## Контакти

- **Issues**: https://github.com/balabon7/AdaptyFlowKit/issues
- **Discussions**: https://github.com/balabon7/AdaptyFlowKit/discussions

---

**Готово до інтеграції!** 🚀
