# Receiving Tripo detail assets in Unreal

The isolated intake supports native MCP control of Tripo Bridge 1.0.5 in UE 5.8.4, with matching BuildId `55116800` and a project-local plugin. The user supplies the vendor ZIP separately. Its source, binaries and content are outside this repository and its MIT license.

| Native tool | Effect |
| --- | --- |
| `read_bridge_status` | Read receiver and client-handshake state. |
| `start_bridge` | Start the adapter-owned loopback receiver. |
| `stop_bridge` | Stop the receiver owned by this adapter. |

The adapter requires the game thread, its exact owned intake project, the project-local DLL and an Editor world without PIE. Startup registers tools without starting the listener. This tested prototype deliberately binds one installation's project and scope; its source remains in the retained delivery files rather than becoming a vendor dependency in the game's normal build. Negative guard paths have not all been exercised.

## Receiving a candidate

1. Prepare a fresh bounded receiving session with a private editor profile, keeping the completed exercise and its receipts intact. Keep the intake project separate from the town.
2. Start the receiver through native MCP and confirm `running: true`. Its endpoint is `ws://127.0.0.1:60620`.
3. Enable **Unreal Engine** in Studio's **DCC Bridge** panel and send the selected candidate. Confirm an actual `client_connected: true` reply; a running listener alone does not establish a Studio connection.
4. Inspect the received assets. The vendor implementation targets `/Game/TripoModels`, saves imported packages and places an actor in the intake world; those effects still require an actual receipt test. Record the source task/model, references, original download and hashes without storing credentials.
5. Review matched face, hair, hands and rear-clothing views. Check PBR channels, metric scale, UVs, topology and skeleton before testing walk/eat/sleep actions. Preserve the original download and portable mesh/maps, then promote an accepted candidate into the town separately.

Immediate detail targets are natural hair, readable eyes and skin, separated fingers, and a front-only apron with ties over rear trousers. Studio generation, texture refinement and rigging perform that work; the bridge receives assets. The same intake discipline applies to furniture and small architectural props, including physical dimensions, usable pivots and material detail at walking distance.

## Actual control evidence

The native exercise passed in 45.453 seconds with 3,980,660,736 bytes peak private memory: stopped → running → stopped, all recorded guards true, then controlled owned-job termination and complete reaping. Startup did not start the listener. No Studio client connected and no candidate was received. This verifies receiver control, with import quality, frame rate and heavy-asset performance still pending.

The retained evidence is `tripo_ue_mcp_control_actual_v1_002/launch/CONTROL_RECEIPT.json`, SHA-256 `9270330e24b041cafd3c4c71086f7310916d6b2f9b1736883d9af0d6f16e20ce`, under the delivery root. The corrected adapter and vendor source clone also compiled successfully in 90.984 seconds; the earlier compile failure remains preserved.

A later command used the existing Windows manual proxy for its own process and confirmed API access at `2026-10-28T03:11:42Z`, with 960 available credits and none frozen. Windows network settings and credentials were unchanged. One [two-view cafe-worker candidate](character_cafe_worker_multiview_v002.md) subsequently completed for 60 credits, leaving an observed 900 available. Its original GLB and maps are preserved for Blender review. This API result does not establish a Studio handshake or UE bridge transfer; both remain pending.
