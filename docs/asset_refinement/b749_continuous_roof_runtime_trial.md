# Continuous roof runtime trial

The new opt-in B749 profile replaces the two disconnected slate-strip meshes
with continuous roof surfaces. The other 747 building roles, furnishing
overrides, ground dependencies and daylight settings retain their accepted
values. This is an uncooked integration trial; gameplay contact, final lighting,
performance and a new cooked package still need validation.

The two replacement meshes contain 44 triangles in total. Native export and
independent cold readback preserved their geometry, UV0/UV1, tangent basis,
material graph and textures. A controlled-exposure exterior view made the slate
courses and continuous surfaces readable. Its isolated dark background and
lighting are not the finished town presentation. The loft view shows its
finished plaster underside; it does not establish direct visibility of the
underlying roof mesh.

The final descriptor and root map were saved separately and reopened in a fresh
Editor process. Their real identities are:

| Package | Bytes | SHA-256 |
| --- | ---: | --- |
| `DA_B749_ContinuousRoofRuntime_v001` | 1,315,931 | `80a800bd4583156eddbebf06072a165f266a73c20a24a00fccb90ea1eb9f928d` |
| `L_B749_ContinuousRoofRuntime_v001` | 17,747 | `80785169981299c509b5d4c229d638a09c0605166271f9232f4e3d6b6f24f551` |
| Immutable roof building unit | 701,814 | `1a6c9f9d2bdb3ffa95c41f09118bdbc8afad6189c6bd331c96e21dabe9865049` |

Both final packages are under
`/Game/LivingTown_UEPilot/FullTownIntegrationB749_ContinuousRoofRuntime_v001`.
The unit remains under `FullTownIntegrationB749_ContinuousRoof_v001/Units`.
The profile is `B749_ContinuousRoofRuntime_v001`.

Cold reopening verified the descriptor's three unit records, the enabled final
driver's exact descriptor bytes/hash, all eight ordinary root actors and the
three engine services created naturally when the world becomes active. The
inactive saved duplicate contains the eight ordinary actors. No service actors
were manufactured. The original source roots and their driver states remained
unchanged.

The C++ candidate adds explicit root/descriptor/profile pairings and verifies
the two roof assets with the existing native mesh inspector and collision GUIDs.
It retains the original B749 and cooked-startup profiles. The new profile
refuses cooked use until a corresponding cooked admission exists. Source tests
cover foreign root/unit identities and independent changes to roof slot name,
default material, override, admission and blend mode. Coherent Game and Editor
build027 passed, followed by all three native B749 shape, hidden-transform and
stored-override tests. The native source family is
`f5ebbee1035ca4413ba41fcee11c81b68828bb6dc464992f8ec4fce59e906b18`.

The next runtime checks must exercise the streamed unit, loft/stair footing,
roof-edge collision, appearance under the player camera and comparable
screenshot-free timing intervals. Saved collision settings and GUIDs do not
establish physical contact or frame rate.

An ordinary Editor027 `-game` trial now passes a 202.57 m, 27-waypoint route
through the café approach, ground seam, doorway and room M0231, then back.
It records 1,042 grounded observations and 9,743 real input frames, with four
independently decoded player-camera images and natural exit 0. The combined
5,856-package source carries exactly the four previously qualified Game008
collision packages (`G0000`, corrected `G0001`, `M0142`, `M0143`); the other
5,852 packages, final root/descriptor/unit and roof pins remain unchanged.
All four native mesh-owned BodySetup flags read back as 3 before movement.
No collision setter, physics rebuild, asset save or pawn relocation runs in play.

This accepts the combined source for the tested ground/room journey. It uses
the existing café pawn; the casual wardrobe has its separate lifecycle/movement
trial. These four views do not demonstrate roof visibility or roof/stair contact.
The approach image retains a Lumen cached-lighting exposure-clipping warning.
Lighting and presentation still need work. No CSV was collected, and no final
art, frame-rate, full-town gameplay or cooked acceptance follows from this run.
