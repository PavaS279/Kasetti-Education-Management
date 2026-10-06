# KEM Staff Assistant (Agentforce employee agent)

The agent definition is kept apart from `force-app` because an active agent
version cannot be overwritten by a normal deployment, and `scripts/deploy.sh`
deploys the whole of `force-app` on every release.

| Path                                                             | What                                                                          |
| ---------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `force-app/main/default/bots/KEM_Staff_Assistant`                | The agent (employee agent, Agentforce Employee Agent template) and version v1 |
| `force-app/main/default/genAiPlannerBundles/KEM_Staff_Assistant` | Its planner, using the **Kasetti Education** topic                            |

The topic (`KEM_Kasetti_Education`) and its five actions (`KEM_*` GenAiFunctions,
backed by the `Agent*` Apex classes) live in `force-app` and are deployed with
the rest of the solution.

## Deploying a change to the agent

1. Deactivate the agent: Setup → Agents → KEM Staff Assistant → Deactivate
   (or `POST /services/data/v65.0/connect/bot-versions/<versionId>/activation`
   with `{"status":"Inactive"}`).
2. From this folder: `sf project deploy start -d force-app -o edu-org`.
3. Activate it again (same endpoint with `{"status":"Active"}`).

Staff need the **KEM AI User** permission set to use the actions, and an
Agentforce user licence or permission set licence to open the agent in Lightning.
