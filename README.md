# Kasetti Education Management — Salesforce Education Cloud

Education management on Salesforce Education Cloud for Kasetti Technologies: enquiries, admissions, enrolment, scheduling, attendance, assessment, billing, documents, portal (Phase 1), and waitlists, transfers, recurring billing, instalments, credit and refunds, messaging, teacher cover, grading and report cards, a richer portal and an operations console (Phase 2), and multi-branch templates, limit-aware batch processing, generic LMS and ERP APIs, advanced analytics, retention workflows, online payments in the portal and a library module (Phase 3), and AI and expansion: Salesforce Einstein assistants with review and measurement, the Agentforce **KEM Staff Assistant**, document extraction, enrolment and cash forecasting, transport, exams and hall tickets, and alumni and referrals (Phase 4).

**Status (2026-10-06):** Phases 0–4 complete — APEX_FIGURES, 163 Jest tests, every feature checked live in the org. AI benefit: [docs/ai/MEASURED-BENEFIT.md](docs/ai/MEASURED-BENEFIT.md).

| Start here                                 |                                          |
| ------------------------------------------ | ---------------------------------------- |
| [docs/PROGRESS.md](docs/PROGRESS.md)       | What is built, deployed and tested       |
| [docs/DEMO-SCRIPT.md](docs/DEMO-SCRIPT.md) | Demo and acceptance tests (Phases 1–4)   |
| [docs/NEXT-STEPS.md](docs/NEXT-STEPS.md)   | Hand-over: open actions, how to continue |
| [docs/README.md](docs/README.md)           | All documentation                        |

Demo runners: `scripts/demo/full-journey.sh` (Phase 1), `scripts/demo/phase2-journey.sh` (Phase 2), `scripts/demo/phase3-journey.sh` (Phase 3) and `scripts/demo/phase4-journey.sh` (Phase 4). Deploy with `scripts/deploy.sh`.

---

# Salesforce DX Project

Salesforce DX is a development approach that brings source-driven development, team collaboration, and continuous integration to the Salesforce Platform. Instead of working directly in an org through a web browser, you work with metadata as source files in a local DX project, track changes in version control, and deploy through automated processes.

This project template gets you started with the tools and structure you need to build Salesforce applications using source control, scratch orgs, and the Salesforce CLI.

## Prerequisites

Before you start, make sure you have:

- **Salesforce CLI** - Download from [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli). See [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) for details.
- **VS Code with Salesforce Extension Pack** - See [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html) for details. Includes the Agentforce Vibes extension.
- **A development org** - Sign up for a free Developer Edition org [here](https://developer.salesforce.com/signup).
- **Dev Hub enabled** (optional, required to create scratch orgs) - You can enable Dev Hub in your development org under Setup > Dev Hub. See [Provide Developers Access to Salesforce DX Tools](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_dx_tools.htm).

## Project Structure

Your DX project follows this structure:

- **`force-app/main/default/`** - Your metadata source files live in this default package directory. You can configure additional package directories in the `sfdx-project.json` file.
- **`config/`** - Scratch org definitions and project settings
- **`scripts/`** - Automation scripts for common tasks
- **`sfdx-project.json`** - Project manifest that defines package directories, namespace, API version, and other project-level settings

See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm).

## Get Started

Ready to start developing? The [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) guide walks you through your first project, from creating a scratch org to creating a simple Apex class or LWC to deploying your code to a sandbox.

## Authorize the Education Cloud Org

Org credentials are stored by the Salesforce CLI on **your machine** (in `~/.sf` / `~/.sfdx`), never in this repo. The project-level `.sf/` and `.sfdx/` folders are gitignored, so every developer authorizes once locally.

1. Install the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) and check it with `sf --version`.
2. From the repo root, log in. A browser window opens for the Salesforce login:

   | Org type                                                | Command                                                                                                |
   | ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
   | Production, Developer Edition, or Education Cloud trial | `npm run org:login`                                                                                    |
   | Sandbox                                                 | `npm run org:login:sandbox`                                                                            |
   | Org with My Domain enforced                             | `sf org login web --alias edu-dev --set-default --instance-url https://<yourdomain>.my.salesforce.com` |

   `--set-default` makes the org the default target for this project, so `sf project deploy start` and `sf project retrieve start` use it without `--target-org`.

3. Verify the connection:

   ```bash
   npm run org:list      # shows the org and its alias; (U) marks the project default
   npm run org:display   # shows username, instance URL, and API version
   npm run org:open      # opens the org in a browser
   ```

4. Retrieve existing metadata into `force-app/` to start working:

   ```bash
   sf project retrieve start --manifest manifest/package.xml
   ```

In VS Code you can use **SFDX: Authorize an Org** from the Command Palette instead of step 2.

### Deploy from GitHub (no local machine needed)

`.github/workflows/salesforce-deploy.yml` deploys `force-app/` straight from this repo:

- **Push to `main`** (changes under `force-app/`): deploys to the org.
- **Pull request**: validates the deployment without saving changes.
- **Actions tab → Salesforce Deploy → Run workflow**: deploys on demand.

The workflow authorizes with the OAuth client credentials flow (`scripts/ci/sf-login.sh`), so it needs no browser login. One-time setup, all done in a web browser:

1. **In Salesforce Setup**, open **External Client App Manager** and select **New External Client App**:
   - Enable OAuth, with any callback URL (for example `https://login.salesforce.com/services/oauth2/success`).
   - OAuth scopes: **Manage user data via APIs (api)** and **Perform requests at any time (refresh_token, offline_access)**.
   - Select **Enable Client Credentials Flow**.
2. Open the app's **Policies** tab, select **Enable Client Credentials Flow**, and set **Run As** to an admin user who has permission to deploy metadata (for example **Modify All Data** or **Modify Metadata Through Metadata API Functions**).
3. On the **Settings** tab, select **Consumer Key and Secret** and copy both values.
4. In **GitHub → Settings → Secrets and variables → Actions**, add these repository secrets:

   | Secret             | Value                                                                                        |
   | ------------------ | -------------------------------------------------------------------------------------------- |
   | `SF_INSTANCE_URL`  | Your My Domain URL, for example `https://kasetti.my.salesforce.com` (from Setup → My Domain) |
   | `SF_CLIENT_ID`     | Consumer key                                                                                 |
   | `SF_CLIENT_SECRET` | Consumer secret                                                                              |

5. Run the workflow from the **Actions** tab to confirm that the login works.

The client credentials flow requires the My Domain URL; `login.salesforce.com` and `test.salesforce.com` do not work for it. Never commit the consumer secret.

## Common Salesforce CLI Commands

Here are common CLI commands that you'll use the most:

- `sf org login web`: Authorize an org
- `sf org open`: Open your org in a browser
- `sf org create scratch`: Create a scratch org
- `sf project deploy start`: Deploy metadata to your org
- `sf project retrieve start`: Retrieve metadata from your org
- `sf template generate <artifact>`: Scaffold new components, such as Apex classes and triggers, LWC components, Lightning apps, and more
- `sf apex <command>`: Run Apex tests, run anonymous Apex blocks, and view logs
- `sf data <command>`: Work with test data
- `sf alias <command>`: Manage org aliases
- `sf config <command>`: Configure CLI settings

## Use Agentforce Vibes to Build Lightning Apps

Transform your ideas into custom Lightning apps that extend CRM workflows directly in Lightning Experience. Through natural conversations with Agentforce Vibes, implement custom objects and fields, complex business logic, and dynamic UI components. See [Build a Lightning App Using Agentforce Vibes](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/lexapp-overview.html).

## Additional Resources

- [Agentforce Vibes Developer Guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Salesforce CLI Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce CLI Plugin Development Guide](https://developer.salesforce.com/docs/platform/salesforce-cli-plugin/guide/conceptual-overview.html)
- [Salesforce VS Code Extensions Documentation](https://developer.salesforce.com/tools/vscode/)
