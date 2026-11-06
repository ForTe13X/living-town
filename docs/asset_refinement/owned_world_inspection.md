# Inspection of private author worlds

Roof material refinement rendered a valid before/after comparison, then stopped while inspecting its saved-world duplicate. The original collision reader accepts four fixed map packages; the new candidate package was outside that list. Adding another literal for each material experiment would make the asset pipeline depend on repeated C++ changes.

`ReadOwnedWorldComponentCollisionResponses` adds a separate read-only entry point. Its caller supplies the already-loaded `UWorld`, its exact long package name and one to sixty-four static mesh components. The original four-map API remains unchanged.

The new reader requires a non-commandlet Editor without a Game or PIE context. The supplied world must be Editor or Inactive, and its pointer and package must agree. Every component and owner must belong to that exact world and package. External packages, pending loads, templates, duplicate components and invalid input counts refuse. It reports all sixty-four serialized collision responses, bounds JSON to 2 MiB, and checks that package dirtiness, registration and physics-state presence remain unchanged during the read. It performs no loading, world activation, registration, collision repair or asset save.

The expected package is a caller-declared scope. It does not establish source ownership or asset fidelity. Consumers must still bind their source, compare the returned component identities and qualify their saved output separately. Registration may differ between an active Editor world and an inactive duplicate; serialized collision policy can still be compared while each call proves that it did not alter either world's state.

## Exposure default

The project now explicitly enables the extended EV100 exposure range in `DefaultEngine.ini`. A fresh process is required. This is the same setting previously verified in the isolated Game008 café/house/return run, where it removed gross white clipping with the physical 35,000 lux sun unchanged.

The new native startup check verifies the actual CVar and constructor bounds of -10 to 20 EV100. It does not read final GPU exposure or establish finished lighting. Café interior illumination, blur and character/material refinement remain open.

## Validation

The coherent Unreal 5.8.4 Editor build completed successfully. All eleven selected native automation cases passed in a fresh Cmd/nullRHI process, which exited naturally with code 0 and no remaining owned descendants. The seven existing cases still pass. The four additions are:

- `LivingTown.OwnedWorldComponentCollisionResponses.BoundedReadOnly`: actual Editor and Inactive fixtures, one/sixty-four components, every response channel, repeat equality and unchanged state.
- `LivingTown.OwnedWorldComponentCollisionResponses.ScopeRefusals`: wrong pointer/package, another world in the same package, external ownership, pending loads, PIE/Game scope and input bounds.
- `LivingTown.OwnedWorldComponentCollisionResponses.NonGTRefusal`: returns before touching UObject or Editor state off the game thread.
- `LivingTown.RendererConfiguration.ExtendedExposureDefaults`: checks project configuration, actual startup CVar and native EV100 defaults.

Independent review verified the exact two loaded DLLs, source and staged bytes/timestamps, resource records and the seven preservation scopes. Six unrelated engine warning lines are retained in the test record rather than described as a warning-free run. NullRHI tests provide no GPU or frame-rate result.

The authored roof duplicate subsequently saved its four new packages and reopened directly in a fresh Editor process. Independent replay checked all 865 package files, 760 protected actor states, 752 components with all 64 collision responses, the 59-node material parent and two instances, and both complete native roof buffers. The original 381 material arrays remained intact, with two intentional roof overrides. Each process completed its checks and its owned tree was stopped and reaped. This accepts saved-data persistence; final roof appearance and transfer into the playable streamed unit remain separate work.
