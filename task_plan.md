# RyzenStatus — Porting Plan: Missing Upstream Features

**Goal:** Port all 20 files / 6 feature groups from upstream that are not yet in our project, without breaking existing AMD monitoring functionality.

**Strategy:** One feature per phase, port + integrate + verify before moving on. Each phase includes:
1. Copy/adapt source files (fix paths, bundle IDs, branding)
2. Register defaults and feature catalog entries
3. Integrate UI into Settings and/or menu panel
4. Add localization strings
5. Build + test (`./build.sh --test`)
6. Commit

---

## Phase 1 — Boost Limiter 🎤 (1 file, bajo esfuerzo)

**Files:**
- `Services/Audio/BoostLimiter.swift`

**Dependencies:** None (standalone service)

**Integration:**
- Wire into existing audio service infrastructure
- No UI needed (invisible)
- No new defaults keys

**Riesgo:** Muy bajo — servicio aislado, sin UI

---

## Phase 2 — Space Hop 🚀 (3 files, esfuerzo medio)

**Files:**
- `Services/Switcher/SpaceHop.swift`
- `Services/Switcher/SpaceHopSupport.swift`
- `Services/Switcher/SpaceWindowBridge.swift`

**Dependencies:** Switcher infrastructure (ya existe)

**Integration:**
- Feature entry en FeatureCatalog (grupo windowsDock)
- Shortcut registration
- Depende de `CGSCopyActiveMenuBarDisplayIdentifier` y funciones CGS
- Localization strings

**Riesgo:** Medio — usa APIs privadas CGS que pueden no estar disponibles. Verificar compilación primero.

---

## Phase 3 — Mouse Exceptions List 🖱️ (1 file, bajo esfuerzo)

**Files:**
- `UI/Settings/MouseExceptionsList.swift`

**Dependencies:** Mouse features infrastructure (ya existe)

**Integration:**
- Vista de lista de excepciones en Settings de Mouse
- Reutiliza la lógica de excepciones existente (smoothScrollExceptions, etc.)

**Riesgo:** Bajo — solo UI, no toca lógica existente

---

## Phase 4 — App Appearance Controller 🌗 (3 files, esfuerzo medio)

**Files:**
- `App/AppAppearanceController.swift`
- `Core/AppAppearance.swift`
- `Core/AppearanceStrings.swift`

**Dependencies:** Window manager infra

**Integration:**
- Feature entry en FeatureCatalog
- Nuevo control en panel o settings
- Localization strings

**Riesgo:** Medio — puede requerir permisos de accesibilidad

---

## Phase 5 — Snippet Library View 📋 (1 file, esfuerzo medio)

**Files:**
- `UI/SnippetLibraryView.swift`

**Dependencies:** Text snippets infra (ya existe)

**Integration:**
- ViewController o SwiftUI view para la biblioteca de snippets
- Ya tenemos `snippetLibraryEnabled` en DefaultsKey

**Riesgo:** Medio — puede requerir integración con la UI existente de snippets

---

## Phase 6 — WhatsApp Download Manager 📥 (8 files, esfuerzo alto)

**Files:**
- `Services/ManagedDownloads/WhatsAppDownloadManager.swift`
- `Services/ManagedDownloads/WhatsAppDownloadOrganizer.swift`
- `Services/ManagedDownloads/WhatsAppDownloadScheduler.swift`
- `Services/ManagedDownloads/WhatsAppDownloadSupport.swift`
- `Core/WhatsAppDownloadStrings.swift`
- `Core/WhatsAppOrganizerStrings.swift`
- `UI/Settings/WhatsAppDownloadsSettings.swift`
- `Services/EnhancedUserInterfaceSuspension.swift`
- `Services/ShortcutCapture.swift`
- `Services/ShortcutRecordingTap.swift`

**Dependencies:** File system access, scheduler infrastructure

**Integration:**
- Feature entry en FeatureCatalog
- Settings page dedicada
- Backend service con scheduling

**Riesgo:** Alto — feature grande con scheduler, downloads, UI compleja. Dejarlo para el final.

---

## Decisiones de diseño

**Naming:** Mantener bundle ID `com.ryzenstatus.utils`, paths bajo `Sources/RyzenStatus/`

**Branding:** Reemplazar cualquier mención a la identidad original por RyzenStatus

**AMD features:** Nunca tocar archivos en `Services/AMD/`, `UI/Settings/*Amd*`, `UI/MenuPanel/*Amd*`

**Testing:** Correr `./build.sh --test` después de cada fase

**Commits:** Un commit por feature portada, con mensaje tipo `feat: port X from upstream`

---

## Timeline estimado

| Fase | Archivos | Esfuerzo | Prioridad |
|------|----------|----------|-----------|
| 1. Boost Limiter | 1 | 🟢 Bajo | 1ª |
| 2. Space Hop | 3 | 🟡 Medio | 2ª |
| 3. Mouse Exceptions | 1 | 🟢 Bajo | 3ª |
| 4. App Appearance | 3 | 🟡 Medio | 4ª |
| 5. Snippet Library | 1 | 🟡 Medio | 5ª |
| 6. WhatsApp Downloads | 8+ | 🔴 Alto | 6ª |
