# Large remainder collision inspection

Twelve meshes in the prepared town remainder exceed the original generic
collision reader's 50,000-vertex / 20,000-triangle limits. The new Editor-only
`ULivingTownRemainderCollisionInspectionV2` handles those exact asset paths.
The existing generic, context and ground inspectors keep their original scopes
and limits. The other 5,250 remainder definitions use the generic reader.

This is import verification support. It does not place buildings or vegetation,
approve material appearance, change runtime gameplay, or demonstrate town FPS.

## API

`ReadRemainderConfigurationMetadataV2(UStaticMesh*)` observes an already loaded
scoped mesh before the importer configures and saves it. It reports CPU-access,
Nanite, package dirty state, BodySetup identity/GUID and collision settings.
It does not create physics, repair assets, save packages or qualify raw arrays.

`ExportRemainderCollisionMeshesV2(AssetPaths, RelativeOutputDirectory)` exports
binary MeshDescription, render-position/index, collision-provider and actual
Chaos arrays from already loaded, saved, clean assets. The public cached
MeshDescription wrapper must already be resident, compilation must be complete,
and created Chaos arrays must be nonempty. Package bytes, GUIDs and dirty state
are checked before and after the read. UVs, tangents, normals and colors remain
the responsibility of the existing raw-render exporter.

The output owner is `LIVING_TOWN_BOOTSTRAP_OUTPUT`, with the project at its
`Project` child. Each relative output leaf must be fresh, 1–64 ASCII
alphanumeric/underscore characters, and outside Content/Engine. Existing files
are never overwritten. A refusal terminates this API session; the consumer must
stop that process rather than retry the rejected operation.

## Bounds and interpretation

The twelve paths and their bounds are compiled into the new inspector.
For each asset, the native vertex/ID limit is
`W = max(source vertex count, 3 * positive source triangle count)`; the triangle
limit is the source triangle count. This accounts for import-time corner splits
without changing source geometry. Absolute ceilings are 300,000 vertices and
100,000 triangles; two complement meshes need a bound above 200,000 corners.

Exports allow at most eight meshes per call, 32 MiB per file, 256 MiB per call,
512 MiB per session, and a tighter 133,751,848-byte aggregate bound for the exact
twelve-asset roster. Each mesh permits one metadata observation and one binary
export. The version-2 binary header distinguishes these files from the old
context format; consumers must validate the header and entry table.

Chaos material indices are the effective values returned by `GetMaterialIndex`.
They do not expose the engine's private stored material array. Asset-default
collision observations also do not prove live-world collision or navigation.

## Validation

The 161-file preparation retained all 159 predecessor files byte-for-byte and
added only this inspector's header and implementation. Its 112 native inputs
compiled with Unreal 5.8.4, MSVC 14.44 and Windows SDK 22621.

An actual owned Editor process ran these two tests successfully, with zero test
errors or warnings and a closed process tree:

- `LivingTown.RemainderCollisionV2.Refusals`
- `LivingTown.RemainderCollisionV2.ScopeBudget`

The tests exercise actual null/foreign/traversal refusals, real worker-thread
refusals during an active operation, completion after refusal, the twelve-path
roster and quota boundaries. Ready/Active/Terminal compare-and-exchange
transitions prevent a successful operation from clearing a concurrent refusal.
Positive imported-mesh
readback, independent cold reopen, full town placement, material fidelity and
performance remain separate validation steps.
