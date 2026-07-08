# Implementation Plan – Diagnostic App

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter Desktop App                     │
│                                                           │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  Home Screen │  │ Input Screen │  │ Result Screen  │  │
│  │ (file pick)  │→ │ (dyn. form)  │→ │ + Eval Dialog  │  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
│          │                 │                  │           │
│          └─────────────────▼──────────────────┘           │
│                      API Service                          │
│                   (http on localhost)                     │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP (REST)
┌────────────────────────▼────────────────────────────────┐
│              FastAPI Backend (subprocess)                 │
│                                                           │
│  POST /model/load   GET /model/domain   POST /predict     │
│                                                           │
│              Orange3 Python Library                       │
│            (loads .pkcls, runs classifier)               │
└─────────────────────────────────────────────────────────┘
                         │
              Local filesystem only
         (CSV log, config YAML, model file)
```

**Key design decisions:**
- Flutter spawns the FastAPI backend as a child process on startup; kills it on exit.
- All communication is HTTP on localhost (no network required).
- The backend binary is bundled inside the Flutter app's assets and extracted at first run.
- Config is a single YAML file editable by the user without recompiling.
- CSV log is written incrementally (one row per session).

---

## Project Structure

```
diagnostic_app/
├── frontend/                        Flutter desktop app
│   ├── lib/
│   │   ├── main.dart                Entry point; starts backend, loads config
│   │   ├── app.dart                 MaterialApp, router
│   │   ├── config/
│   │   │   ├── app_config.dart      Dart model for app_config.yaml
│   │   │   └── config_loader.dart   Reads YAML from assets or app-data dir
│   │   ├── models/
│   │   │   ├── orange_variable.dart Mirrors Orange Variable types
│   │   │   ├── model_domain.dart    List of variables + class variable
│   │   │   ├── prediction_result.dart  Class + probabilities
│   │   │   └── session_record.dart  One CSV row
│   │   ├── screens/
│   │   │   ├── home_screen.dart     Load model file, backend status indicator
│   │   │   ├── input_screen.dart    Renders DynamicForm, submit button
│   │   │   ├── result_screen.dart   Shows PredictionResult widget
│   │   │   └── settings_screen.dart Open/edit app_config.yaml
│   │   ├── widgets/
│   │   │   ├── dynamic_form.dart    Builds form fields from ModelDomain
│   │   │   ├── variable_field.dart  TextField (continuous) or Dropdown (discrete)
│   │   │   ├── result_display.dart  Card/banner/detailed renderers (config-driven)
│   │   │   └── evaluation_dialog.dart  Doctor diagnosis + notes entry
│   │   └── services/
│   │       ├── backend_manager.dart Starts/stops backend subprocess, health-poll
│   │       ├── api_service.dart     Typed HTTP client (dio or http package)
│   │       └── csv_service.dart     Appends SessionRecord rows to CSV
│   ├── assets/
│   │   ├── config/app_config.yaml   Shipped default config
│   │   └── backend/                 Populated by build script (see Phase 6)
│   │       └── diagnostic_backend   (binary, platform-specific)
│   └── pubspec.yaml
│
├── backend/                         FastAPI Python service
│   ├── main.py                      Uvicorn entry point
│   ├── routers/
│   │   ├── model_router.py          /model/load, /model/domain, /model/status
│   │   └── predict_router.py        /predict
│   ├── services/
│   │   ├── model_service.py         Orange3 load + domain introspection
│   │   └── predict_service.py       Run classifier, extract probabilities
│   ├── schemas/
│   │   ├── domain_schema.py         Pydantic: VariableInfo, DomainResponse
│   │   └── predict_schema.py        Pydantic: PredictRequest, PredictResponse
│   ├── requirements.txt
│   └── build_backend.py             PyInstaller one-file build script
│
├── config/
│   └── app_config.yaml              User-editable configuration template
│
└── docs/
    └── IMPLEMENTATION_PLAN.md       This file
```

---

## Phase 1 – FastAPI Backend Core

**Goal:** A working Python service that loads an Orange `.pkcls` model and exposes prediction endpoints.

### 1.1 – Project bootstrap

File: `backend/requirements.txt`
```
fastapi>=0.111
uvicorn[standard]>=0.29
orange3>=3.36
pydantic>=2.0
python-multipart>=0.0.9
```

File: `backend/main.py`
- Create `FastAPI` app.
- Mount routers.
- Add `/health` endpoint returning `{"status": "ok"}` – used by Flutter to know the backend is ready.
- Run with `uvicorn.run(app, host="127.0.0.1", port=8765)`.
- Accept `--port` CLI argument so Flutter can pass a dynamic port if 8765 is taken.

### 1.2 – Orange model service

File: `backend/services/model_service.py`

Singleton `ModelService` class:
- `load(path: str) -> None` — calls `pickle.load` (Orange models are pickled); stores `model` and `domain`.
- `get_domain() -> DomainResponse` — introspects `domain.attributes` and `domain.class_var`:
  - `ContinuousVariable` → `type: "continuous"`, includes `min/max` if `.values` has them.
  - `DiscreteVariable` → `type: "discrete"`, includes `values: list[str]`.
  - `StringVariable` → `type: "string"` (informational only, excluded from prediction input).
  - `class_var` → special entry with `role: "class"`.
- `is_loaded() -> bool`.

### 1.3 – Prediction service

File: `backend/services/predict_service.py`

- Accept dict `{variable_name: value, ...}` from Flutter.
- Build an `Orange.data.Instance` using the loaded domain.
- Handle missing values: map the configured `missing_value_token` to `Orange.data.Unknown`.
- Call `model(instance)`.
- Extract predicted class label and probability distribution.
- Return `{predicted_class: str, probabilities: {label: float, ...}}`.

### 1.4 – Routers

File: `backend/routers/model_router.py`
```
POST /model/load         body: {path: str}  → loads model, returns domain summary
GET  /model/domain       → returns full DomainResponse
GET  /model/status       → {"loaded": bool, "path": str|null}
```

File: `backend/routers/predict_router.py`
```
POST /predict            body: PredictRequest  → PredictResponse
```

### 1.5 – Pydantic schemas

`domain_schema.py`:
```python
class VariableInfo(BaseModel):
    name: str
    type: Literal["continuous", "discrete", "string"]
    role: Literal["feature", "class"]
    values: list[str] | None       # discrete only
    min: float | None              # continuous hint
    max: float | None

class DomainResponse(BaseModel):
    features: list[VariableInfo]
    class_var: VariableInfo
```

`predict_schema.py`:
```python
class PredictRequest(BaseModel):
    values: dict[str, str | float | None]

class PredictResponse(BaseModel):
    predicted_class: str
    probabilities: dict[str, float]
```

---

## Phase 2 – Flutter Project Bootstrap

**Goal:** A runnable Flutter desktop app that starts/stops the backend.

### 2.1 – Flutter project creation

```bash
flutter create --platforms=windows,macos frontend
```

Key `pubspec.yaml` dependencies:
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0               # REST calls
  yaml: ^3.1.2               # Parse app_config.yaml
  file_picker: ^8.0.0        # .pkcls file browser
  csv: ^5.1.1                # CSV write
  path_provider: ^2.1.3      # App data directory
  provider: ^6.1.2           # State management
  go_router: ^13.0.0         # Navigation

dev_dependencies:
  flutter_test:
    sdk: flutter
```

Assets registration in `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/config/app_config.yaml
    - assets/backend/
```

### 2.2 – Backend manager service

File: `frontend/lib/services/backend_manager.dart`

```dart
class BackendManager {
  Process? _process;

  Future<void> start({required String executablePath, required int port}) async {
    _process = await Process.start(executablePath, ['--port', '$port']);
    await _waitUntilReady(port);    // polls GET /health with timeout
  }

  Future<void> stop() async => _process?.kill();

  Future<void> _waitUntilReady(int port) async {
    // Retry GET http://127.0.0.1:{port}/health every 500 ms
    // Throw TimeoutException after config.backendStartupTimeoutSeconds
  }
}
```

**Executable resolution logic** (`main.dart`):
1. In debug mode: run `python backend/main.py` from repo root.
2. In release mode: extract bundled binary from `assets/backend/` to the app cache directory, then execute it.

### 2.3 – App entry point

File: `frontend/lib/main.dart`
- Load `AppConfig` from YAML.
- Start `BackendManager`.
- Show a splash/loading screen while the backend starts.
- On success, navigate to `HomeScreen`.
- Register `WidgetsBindingObserver` to kill backend on app exit.

---

## Phase 3 – Dynamic Form Generation

**Goal:** Flutter reads the Orange domain from the backend and renders an appropriate input form.

### 3.1 – Domain model (Dart)

File: `frontend/lib/models/orange_variable.dart`
```dart
enum VariableType { continuous, discrete, string }
enum VariableRole { feature, classVar }

class OrangeVariable {
  final String name;
  final VariableType type;
  final VariableRole role;
  final List<String>? values;   // discrete
  final double? min;
  final double? max;
}
```

File: `frontend/lib/models/model_domain.dart`
```dart
class ModelDomain {
  final List<OrangeVariable> features;
  final OrangeVariable classVar;
}
```

### 3.2 – Variable field widget

File: `frontend/lib/widgets/variable_field.dart`

Renders one input control based on `OrangeVariable.type`:

| Orange type   | Widget                        | Validation                  |
|---------------|-------------------------------|-----------------------------|
| continuous    | `TextFormField` (number)      | Parse as double, check range |
| discrete      | `DropdownButtonFormField`     | Must pick from `values`     |
| string        | Hidden (not sent to backend)  | —                           |

- Each field shows the variable name as label.
- If `show_tooltips: true` and description available, shows `?` icon with tooltip.
- If `show_range_hints: true` and min/max present, shows hint text `(min – max)`.
- A "?" or "Unknown" option is always available for each field (maps to missing value).

### 3.3 – Dynamic form widget

File: `frontend/lib/widgets/dynamic_form.dart`

- Accepts `ModelDomain` and a `ValueNotifier<Map<String, dynamic>>`.
- Uses `Form` + `ListView.builder` over `domain.features`.
- Renders one `VariableField` per feature.
- `validate()` / `save()` follows standard Flutter form pattern.
- Provides `Map<String, dynamic> collectValues()` for submission.

---

## Phase 4 – Prediction & Result Display

### 4.1 – API service

File: `frontend/lib/services/api_service.dart`

Typed methods:
```dart
Future<ModelDomain> getDomain();
Future<void> loadModel(String path);
Future<PredictionResult> predict(Map<String, dynamic> values);
Future<ModelStatus> getModelStatus();
```

Error handling: throws typed exceptions (`ModelNotLoadedException`, `BackendUnavailableException`) caught by screens.

### 4.2 – Prediction result model

File: `frontend/lib/models/prediction_result.dart`
```dart
class PredictionResult {
  final String predictedClass;
  final Map<String, double> probabilities;
  final DateTime timestamp;
}
```

### 4.3 – Result display widget

File: `frontend/lib/widgets/result_display.dart`

Three renderers, selected by `config.resultDisplay.style`:

**card** – Material card with class label in large text, probability bar chart.  
**banner** – Full-width colored banner (color from config `positiveClassColor` / `negativeClassColor`), label centered.  
**detailed** – Table showing all class labels with their probabilities.

---

## Phase 5 – Evaluation Dialog & CSV Logging

### 5.1 – Evaluation dialog

File: `frontend/lib/widgets/evaluation_dialog.dart`

`AlertDialog` shown after result display (if `config.evaluationDialog.autoOpenAfterResult: true`).

Fields rendered in the order specified by `config.evaluationDialog.fieldOrder`:
- `doctor_diagnosis` → `DropdownButtonFormField` using `doctorDiagnosisOptions`.
- `notes` → multiline `TextFormField`.

Returns `EvaluationData {doctorDiagnosis: String, notes: String}` on confirm.

### 5.2 – Session record model

File: `frontend/lib/models/session_record.dart`
```dart
class SessionRecord {
  final DateTime timestamp;
  final Map<String, dynamic> inputs;    // raw form values
  final String predictedClass;
  final Map<String, double> probabilities;
  final String? doctorDiagnosis;
  final String? notes;
}
```

### 5.3 – CSV service

File: `frontend/lib/services/csv_service.dart`

- On first call, write header row from `SessionRecord` fields.
- Subsequent calls append one data row.
- File path: `{appDocumentsDir}/{config.csvLogging.outputPath}`.
- Uses the `csv` package to handle quoting/escaping.
- Header columns: `timestamp, [feature_names...], predicted_class, [class_probabilities...], doctor_diagnosis, notes`.

---

## Phase 6 – Configuration System

### 6.1 – Config loader

File: `frontend/lib/config/config_loader.dart`

Resolution order (first found wins):
1. `{appDocumentsDir}/app_config.yaml` — user-edited copy.
2. Bundled `assets/config/app_config.yaml` — shipped default.

On first launch, copy the asset to the documents dir so the user can edit it.

### 6.2 – Config model

File: `frontend/lib/config/app_config.dart`

Dart class with `fromYaml(Map yaml)` factory. All keys mirror `config/app_config.yaml`.  
Provide defaults for every optional key so missing keys never crash.

### 6.3 – Settings screen

File: `frontend/lib/screens/settings_screen.dart`

- Shows current config path.
- "Open in editor" button: `launchUrl(Uri.file(configPath))` to open the YAML in system default editor.
- "Reload config" button: re-reads the YAML and triggers a hot-reload of the UI.

---

## Phase 7 – Packaging & Distribution

### 7.1 – Backend bundling (PyInstaller)

File: `backend/build_backend.py`

```bash
pyinstaller \
  --onefile \
  --name diagnostic_backend \
  --hidden-import orange3 \
  --collect-all Orange \
  backend/main.py
```

Output: `dist/diagnostic_backend` (Linux/Mac) or `dist/diagnostic_backend.exe` (Windows).

Copy the binary into `frontend/assets/backend/` before `flutter build`.

Automation: `scripts/build_all.sh` / `scripts/build_all.ps1` that:
1. Creates a Python venv, installs `requirements.txt`.
2. Runs PyInstaller.
3. Copies binary to Flutter assets.
4. Runs `flutter build windows` / `flutter build macos`.

### 7.2 – Executable extraction at runtime

`BackendManager` in release mode:
1. Compute SHA256 of the bundled binary asset.
2. Check if `{cacheDir}/diagnostic_backend` exists with matching SHA.
3. If not, extract asset to cache dir, set executable permissions (chmod +x on Mac).
4. Start process.

### 7.3 – Port conflict handling

`BackendManager.start()`:
1. Try port from config.
2. If bind fails (backend returns non-zero exit quickly), increment port by 1 and retry up to 5 times.
3. Pass the resolved port to `ApiService`.

---

## Screen Flow

```
App start
   │
   ├─ [BackendManager.start()] ──→ Splash / Loading screen
   │
   └─ Backend ready
         │
         └─ HomeScreen
               │  Pick .pkcls file
               │  POST /model/load
               │
               └─ InputScreen (renders DynamicForm from GET /model/domain)
                     │  Fill fields, press "Predict"
                     │  POST /predict
                     │
                     └─ ResultScreen
                           │  Shows PredictionResult widget
                           │
                           └─ [if evaluation enabled] EvaluationDialog
                                 │  Doctor fills diagnosis
                                 │  CsvService.append(SessionRecord)
                                 │
                                 └─ Back to InputScreen (for next patient)
```

---

## Implementation Order & Milestones

| # | Milestone | Deliverables |
|---|-----------|-------------|
| 1 | Backend skeleton | `main.py`, `/health`, routers wired, uvicorn running |
| 2 | Orange integration | `model_service.py` loads a real `.pkcls`, `/model/domain` returns correct schema |
| 3 | Prediction working | `/predict` returns class + probabilities for a test instance |
| 4 | Flutter project + backend manager | App starts, splash, kills backend on exit |
| 5 | Domain fetch + dynamic form | `InputScreen` renders correct fields for any loaded model |
| 6 | End-to-end predict flow | Full path: load model → fill form → see result |
| 7 | Evaluation dialog + CSV | Dialog appears, row saved to CSV |
| 8 | Config-driven UI | All display style / dialog order settings take effect |
| 9 | Settings screen | User can open and reload YAML |
| 10 | PyInstaller bundle | Release binary works, extracted correctly by Flutter |
| 11 | Windows build | `flutter build windows` produces working installer |
| 12 | macOS build | `flutter build macos` produces working `.app` |

---

## Open Technical Risks

| Risk | Mitigation |
|------|-----------|
| PyInstaller + Orange3 binary size (~300 MB) | Use `--exclude-module` for unused Orange add-ons; consider `--onedir` instead of `--onefile` for faster startup |
| Orange API differences across versions | Pin `orange3` version in `requirements.txt`; test domain introspection against actual model files |
| Port 8765 already in use on user's machine | Implement port-retry logic (Phase 7.3) |
| Flutter process.kill() doesn't terminate Python tree on Windows | Use `taskkill /F /T /PID` on Windows to kill entire process tree |
| macOS Gatekeeper blocking unsigned binary | Document notarization steps for distribution; provide developer mode workaround |
