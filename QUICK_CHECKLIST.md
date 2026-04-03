# ✅ Швидкий чеклист інтеграції AdaptyFlowKit

## Передумови

- [ ] MrScan проєкт відкритий в Xcode
- [ ] Git changes збережено (для rollback якщо щось піде не так)

## Крок 1: Додати AdaptyUI (ОБОВ'ЯЗКОВО!)

⚠️ **MrScan зараз не має AdaptyUI, але AdaptyFlowKit його потребує!**

```
1. У Xcode: File → Add Package Dependencies
2. URL: https://github.com/adaptyteam/AdaptyUI-iOS.git
3. Dependency Rule: "Up to Next Major Version" → 3.0.0
4. Add to Target: MrScan
5. Click "Add Package"
```

- [ ] AdaptyUI додано успішно

## Крок 2: Додати AdaptyFlowKit

### Варіант A: З GitHub (Production)
```
1. File → Add Package Dependencies
2. URL: https://github.com/balabon7/AdaptyFlowKit
3. Dependency Rule: "Up to Next Major Version" → 1.0.0
4. Add to Target: MrScan
5. Click "Add Package"
```

### Варіант B: Локально (Development)
```
1. File → Add Package Dependencies
2. "Add Local..."
3. Вибрати: /Users/oleksandrbalabon/Documents/Developer/AdaptyFlowKit
4. Add to Target: MrScan
5. Click "Add Package"
```

- [ ] AdaptyFlowKit додано успішно

## Крок 3: Оновити imports

### AppDelegate.swift
```swift
// Додати на початку після UIKit:
import AdaptyFlowKit
```
- [ ] AppDelegate.swift оновлено

### MSWelcomeViewController.swift
```swift
import UIKit
import AdaptyFlowKit  // Додати цей рядок
```
- [ ] MSWelcomeViewController.swift оновлено

### MSSettingsViewController.swift
```swift
import UIKit
import AdaptyFlowKit  // Додати цей рядок
```
- [ ] MSSettingsViewController.swift оновлено

### MSPaywallViewController.swift
```swift
import UIKit
import AdaptyFlowKit  // Додати цей рядок
```
- [ ] MSPaywallViewController.swift оновлено

### Інші файли (якщо використовують Kit-и)
```swift
import AdaptyFlowKit  // Додати там де потрібно
```
- [ ] Інші файли оновлено

## Крок 4: Clean & Build

```
1. Product → Clean Build Folder (Cmd+Shift+K)
2. Wait for completion
3. Product → Build (Cmd+B)
4. Check for errors
```

- [ ] Build успішний (0 errors)

## Крок 5: Run & Test

```
1. Select Simulator or Device
2. Product → Run (Cmd+R)
3. Test:
   - App launches
   - Onboarding flow works
   - Paywall opens
   - Rating prompt (якщо тестуєш)
```

- [ ] App запускається
- [ ] Onboarding працює
- [ ] Paywall відкривається
- [ ] Все працює як раніше

## Крок 6: Commit changes

```bash
git add .
git commit -m "Integrate AdaptyFlowKit package"
git push
```

- [ ] Changes committed

## Опціонально: Видалити старі файли

⚠️ **ТІЛЬКИ після успішного тестування!**

```
Видалити папку:
MrScan/MrScan/AdaptyFlowKit/

Можна залишити як backup на деякий час.
```

- [ ] Старі файли видалено (або залишено як backup)

## 🐛 Якщо щось пішло не так

### Build fails з "No such module 'AdaptyFlowKit'"
```
1. Xcode → File → Packages → Reset Package Caches
2. Product → Clean Build Folder
3. Rebuild
```

### Build fails з помилками про AdaptyUI
```
Переконайся що AdaptyUI додано в Step 1!
```

### App crashes at runtime
```
1. Check imports у всіх файлах
2. Check що конфігурація Kit-ів залишилась незмінною
3. Restart Xcode
```

### Rollback
```bash
git reset --hard HEAD
# або
git revert HEAD
```

## 📊 Фінальний статус

- [ ] ✅ Всі кроки виконані
- [ ] ✅ Build успішний
- [ ] ✅ Tests пройдені
- [ ] ✅ App працює стабільно
- [ ] ✅ Changes committed

## 🎉 Готово!

AdaptyFlowKit успішно інтегровано в MrScan!

**Переваги:**
- Модульна архітектура
- Легке оновлення через package manager
- Можна переіспользувати в інших проєктах
- Чистий код в MrScan

---

**Час виконання**: ~10-15 хвилин
**Складність**: Легко

Питання? Перевір:
- INTEGRATION_GUIDE.md
- FINAL_STATUS.md
- README.md
