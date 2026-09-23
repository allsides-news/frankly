# GitHub Actions workflows

Flutter/Dart jobs pin **`subosito/flutter-action`** to **Flutter 3.41.4** (stable). When upgrading the SDK, bump `flutter-version` in every workflow below and follow **`client/UPGRADE-README.md`**.

## Client (Flutter web)

| Workflow | Trigger | Notes |
|----------|---------|--------|
| **`deploy_client_prod.yaml`** | Push to `main`, or manual | Production hosting deploy. |
| **`deploy_client_staging.yaml`** | Push to `staging`, or manual | Runs client steps when **`client/**`** changed on push, or always on **`workflow_dispatch`**. |
| **`deploy-preview.yml`** | Manual only | Preview channel; steps run when **`client/**`** changed vs default branch **or** on **`workflow_dispatch`** (so manual runs are not skipped). |
| **`test_client.yaml`** | PR (any branch) | Tests/build only if **`client/**`** changed. |

## Firebase

| Workflow | Trigger | Notes |
|----------|---------|--------|
| **`deploy_firebase_prod.yaml`** | Manual | Functions/rules workflow (currently oriented around manual deploy). |
| **`deploy_firebase_staging.yaml`** | Push to `staging`, or manual | Paths filter **`firebase/functions`**, Firestore, shared **`data_models`** paths; **`workflow_dispatch`** forces the toolchain steps. |
| **`test_firebase.yaml`** | PR | Builds/tests Functions when relevant paths change. |

## Other

| Workflow | Purpose |
|----------|---------|
| **`docs.yml`** | MkDocs deploy to GitHub Pages from `docs/` on **`staging`** pushes or manual. |
| **`playwright.yml`** | Manual E2E against staging (`client/e2e`). |

Optional local lint: [actionlint](https://github.com/rhysd/actionlint) over `*.yaml` / `*.yml` in this folder.
