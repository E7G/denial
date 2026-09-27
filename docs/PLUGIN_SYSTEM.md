# Denial plugin system: agent implementation contract

Status: accepted architecture; SDK foundation implemented, composition tooling pending.
Decision date: 2026-09-27.
Audience: agents designing, implementing, reviewing, or documenting Denial plugins.

Companion contract: [Plugin Manager distribution and backend](PLUGIN_MANAGER.md).
Read both for manager work. The companion records Git-first plugin distribution,
pub.dev-hosted SDKs, the catalog, and multi-package repository selection.

This document records the final architecture agreed with the user. It supersedes
earlier brainstorming about runtime plugin registries, arbitrary source rewriting,
and plugins limited to adding panels. It does not authorize implementation or
deployment. Follow repository `AGENTS.md` for execution and validation constraints.

MUST/MUST NOT identify architecture requirements. Proposed identifiers, directory
names, and code examples illustrate contracts; they are not existing APIs.

## 1. Objective and boundaries

- Users select desktop functionality by enabling and disabling plugins.
- Plugins can supply UI, behavior, layout, policies, and services through public
  contracts. They are not restricted to isolated widgets or additive overlays.
- The reference desktop is assembled from first-party plugins. It is not a
  privileged monolithic implementation with special third-party attachment points.
- A default desktop preset selects a coherent set of those plugins.
- Users can disable default plugins and select alternatives, subject to dependency
  and required-capability checks.
- Plugins may publish new contracts and depend on other plugins. The system must
  accommodate alternative desktop architectures, not just the current desktop.
- An alternative shell composition can replace the complete reference desktop
  while retaining Denial's platform services and compositor integration.
- Flutter remains embedded in the compositor and owns desktop composition.
- Native resource lifetimes, Wayland correctness, authentication enforcement, and
  recovery remain platform responsibilities. Dart plugins do not gain unimplemented
  native capabilities simply by supplying different UI.

Design around reusable platform primitives and extensible contracts, not a list
of special cases for the first demonstration plugin. No architecture guarantees
permanent compatibility with arbitrary internal changes; version public contracts.

## 2. Compilation and activation model

The plugin manager is a build-time composition tool. Plugin selection, discovery,
dependency resolution, provider selection, and registration-code generation happen
before Flutter compilation.

```text
user-selected plugin packages
  -> Pub dependency resolution
  -> static discovery and contract validation
  -> deterministic composition generation
  -> Flutter AOT compilation
  -> existing shell refresh mechanism
```

The result is one ordinary compiled Flutter shell application with a fixed plugin
composition. Enabling, disabling, or updating a plugin changes build inputs and
requires generating/building the resulting composition, or reusing a verified
cached build with identical inputs.

The resulting application MUST NOT require:

- runtime filesystem/package scanning for plugins;
- `dart:mirrors` or another runtime reflection mechanism;
- dynamic Dart module loading;
- runtime enable/disable or dependency resolution;
- a runtime plugin registry that decides which implementations to activate;
- runtime `Plugin.configure(registry)` calls to assemble the selected plugin set.

Ordinary object construction, initialization, widget lifecycle, service startup,
reactive state, and disposal still occur at runtime. Build-time activation means
deciding and generating the composition, not executing Flutter widgets during a
build. Generated factory calls and static provider wiring are permitted.

## 3. Package boundaries

Use the shared SDK package `denial_sdk`. Both plugins and the shell
runtime depend on it. The SDK MUST NOT depend on implementations in the runtime
or on particular plugins.

Illustrative structure:

```text
denial/
  compositor/
  packages/
    denial_sdk/
    denial_shell_runtime/
  plugins/
    ...first-party plugin packages...
  ...generated composition workspace outside authoritative source...
```

Dependency direction:

```text
generated application
  +-> shell runtime -------> SDK
  +-> first-party plugins -> SDK
  +-> third-party plugins -> SDK
```

The SDK owns public models, platform-service interfaces, contribution contracts,
build-time metadata types, and necessary public Flutter integration helpers. The
runtime implements native bridging, bootstrap, and platform lifecycle. Plugins
use public APIs, not runtime-private bridge/state machinery.

Plugins obtain runtime services through generated composition/injection and public
interfaces. A specific injection mechanism is not selected by this document.

Plugin-specific extension APIs belong in their own packages, for example:

```text
alternative_desktop_api -> denial_sdk
alternative_desktop -> alternative_desktop_api
alternative_desktop_extension -> alternative_desktop_api
```

Do not move every ecosystem-specific concept into the core SDK. A package can
publish contracts without being an activatable plugin.

The default plugins MUST consume the same public platform contracts as external
plugins. Remove private shortcuts during extraction. Preserve stock behavior when
the default preset is selected.

## 4. Pub is the dependency authority

Plugin-to-plugin dependencies MUST be declared in the plugin's `pubspec.yaml`.
Do not invent a second dependency manifest or separately maintained plugin
dependency graph.

```yaml
# Illustrative package names and versions, not existing packages.
name: classic_taskbar
dependencies:
  denial_sdk: ^1.0.0
  application_catalog: ^1.0.0
```

If `application_catalog` is a plugin, selecting `classic_taskbar` brings it into
the composition automatically. Pub resolves compatible package versions; the
plugin manager discovers plugin contributions within the resolved application
dependency closure.

Rules:

- Record user-selected root plugins separately from automatically required plugins.
- An installed package is not necessarily a plugin. SDKs, API packages, and normal
  Dart libraries do not activate merely because Pub resolved them.
- Build/dev tooling dependencies MUST NOT accidentally become runtime plugins.
- A required plugin cannot be omitted while an enabled dependent requires it.
  Report the dependent chain and resolve the selection before compilation.
- Removing a root can remove dependencies no longer reachable from another root.
- Persist the resolved Pub lockfile with the composition inputs.
- Derive dependency information from Pub's result; do not maintain a contradictory
  resolver alongside Pub.

Pub resolves packages, not semantic capability conflicts. The composition builder
must separately validate the contracts supplied by the resolved plugins.

## 5. Static discovery and generated composition

Use Dart source analysis to discover declarations and resolve actual types.
The `analyzer` package is the proposed foundation. `build_runner`/`source_gen`
are possible orchestration tools, not required architectural dependencies.

Annotations such as `@Provides` are Denial-defined SDK APIs. They are
not built-in Dart functionality. Dart annotations and type references supply
metadata; the plugin manager supplies discovery and generation semantics.

Illustrative declaration:

```dart
@Provides(DesktopPanel)
class ClassicTaskbar implements DesktopPanel {
  // Implements the public contract.
}

@Provides(WindowFrame)
class ClassicWindowFrame implements WindowFrame {
  // Implements the public contract.
}
```

Illustrative generated application:

```dart
void main() {
  runDenialShell(
    panels: [ClassicTaskbar()],
    windowFrame: ClassicWindowFrame(),
  );
}
```

The builder must resolve declarations to their library/type identities, validate
contract conformance and construction requirements, and generate imports and
statically checked calls. Do not use unqualified class-name string matching as
the contract identity. Diagnostics must identify source package and declaration.

The resolved package configuration locates package sources. Discovery must be
restricted to the intended plugin/application dependency closure, rather than
indiscriminately activating every package found in `.dart_tool/package_config.json`.

The SDK defines `@Plugin()` on contribution libraries, `@ExtensionPoint` on public
contracts, and `@Provides(ContractType)` on implementation classes. Discovery is
still to be implemented: inspect marked libraries under a package's `lib/` within
the selected application dependency closure, excluding tests, examples, and build
tooling. It MUST NOT reintroduce runtime entry-point loading or duplicate Pub
dependencies. Constructor/factory wiring remains a separate builder design task.

Public contract references should be actual Dart types. Package IDs, source
locations, user selections, and serialized lock records naturally use strings.
There is no requirement to eliminate strings from build metadata.

## 6. Build-time programmable composition

Support a path for Dart-authored build logic when declarations alone cannot express
composition. Such logic runs in the plugin manager's build process and operates
on source declarations/composition data to emit code.

It MUST NOT require importing and executing Flutter widget implementations in an
ordinary Dart command-line process. Analyze Flutter source statically and emit
references to runtime implementations instead.

Exact script API, ordering, execution isolation, allowed side effects, and cache
input declaration require design before implementation. Do not introduce an
unrestricted script runner as an undocumented shortcut. If scripts can observe
untracked inputs, do not claim deterministic/reproducible builds or reuse caches
as though those inputs did not exist.

This programmable path does not adopt arbitrary rewriting of shell method bodies
as the normal plugin mechanism. Generate composition against public contracts.

## 7. Contracts and composition rules

The plugin loader must remain generic. Domain concepts belong to versioned public
contracts, including contracts published by plugins.

Useful general mechanisms include:

- supplying an implementation of a contract;
- selecting an implementation for an exclusive capability;
- contributing multiple implementations/items to a collection;
- explicitly composing decorators/wrappers where a contract supports them;
- connecting typed commands, events, services, and state;
- declaring ownership and lifecycle of resources.

The generated application may contain these normal runtime abstractions. It must
not rediscover or resolve its plugin set at startup.

Define cardinality and requirements per contract. Optional collections can be
empty. Required exclusive capabilities need one selected implementation. Multiple
candidate providers must not silently win by installation or filesystem order.
Generate explicit selection/composition, or fail with actionable diagnostics.

Support deterministic ordering where order has meaning. Dependency relationships
alone are not a universal ordering rule for UI, wrappers, or service startup.
Define initialization/disposal and dependency-cycle behavior before relying on it.

Allow composition at multiple scales, including the complete shell. Do not make
the default desktop's widget hierarchy the only representable desktop structure.
Public composition data may support rearrangement and selection; private Flutter
implementation details must not become implicit permanent compatibility promises.

## 8. Installer/build pipeline

1. Determine the installed/running Denial source identity and engine compatibility
   inputs from authoritative metadata. Do not fetch a moving branch or infer the
   release from Cargo/Dart manifest versions.
2. Materialize the matching shell/platform source in a dedicated build workspace,
   including generated protocol packages and required assets/build inputs.
3. Fetch user-selected plugins and resolve their declared Pub dependencies. Record
   exact source identities and integrity information for the resulting inputs.
4. Discover typed contributions and execute supported build-time composition logic.
5. Validate requirements, selected providers, ordering, and compatibility.
6. Generate the root application's dependencies, imports, factories, and composition.
7. Analyze and compile an AOT bundle with Denial's matching pinned toolchain/engine.
8. Stage the bundle in a new directory and validate it before activation.
9. Invoke the existing native-controlled shell refresh path.

Keep the active shell running while preparing the replacement. Build failures must
leave the active composition usable. Preserve the packaged recovery bundle and
retain sufficient previous-build/configuration information for rollback.

Do not overwrite active mapped libraries or truncate files used by the running
shell. Ordinary plugin composition changes do not require changing the native
engine. Do not rebuild Rust or the Flutter engine for each plugin installation.

Source fetches, toolchain setup, local runtime transitions, and validation remain
subject to `AGENTS.md`; this design does not authorize restarting a local session.

Cache keys must cover source/SDK identity, resolved plugins and dependencies,
generation tooling and inputs, selection/order, toolchain/engine compatibility,
target architecture, and build configuration. Do not promise instant rebuilds or
reproducibility without measurement and input accounting.

## 9. Refresh, persistence, distribution, and trust

Reuse existing shell refresh and packaged-shell recovery infrastructure. Do not
design a second refresh engine or claim that refresh needs to be invented.
Inspect the current bundle preparation/validation paths before integrating the
builder; existing custom-optimized support is profile-oriented. A release custom
bundle may need integration changes, not a new runtime replacement mechanism.

Ship a precompiled default composition. Users do not need a compiler for initial
use. Custom composition builds require the compatible build tooling, which can be
cached and reused.

The planned manager installs plugin source packages from Git and lists built-ins
alongside entries from a Denial-owned YAML catalog. SDK packages are intended for
pub.dev; plugin authors do not need to publish there. Multi-package repositories
use package-level selection and repository-relative paths. See
[PLUGIN_MANAGER.md](PLUGIN_MANAGER.md) for the accepted distribution/backend
contract and remaining decisions. Pub remains the dependency authority. Local
development/installations should use the same composition rules.

These plugins compile into trusted shell code and share its process/failure domain.
Compile-time discovery is not a runtime security sandbox. Do not present package
signatures, interface conformance, or build success as proof of harmless behavior.

Persist selection and resolved build provenance separately from ephemeral runtime
state. Compatibility checks, last-working rollback, startup recovery, and durable
custom-selection behavior need explicit implementation verification. Existing
refresh support alone does not establish that these are all implemented.

## 10. Known implementation gaps and source anchors

These are observations from the design review, not a complete current-state audit.
Reinspect before editing; do not freeze internal filenames as public contracts.

- Public framework/default assembly separation already exists:
  [custom shells](CUSTOM_SHELLS.md), `dart_shell/lib/denial.dart`, and
  `dart_shell/lib/src/features/default_shell/default_shell_app.dart`.
- The framework is not yet a separate plugin SDK/runtime/default-plugin package
  graph. Extract public boundaries without making plugins import `lib/src`.
- System-bar rendering now lives in `plugins/denial_top_bar`. The compatibility
  host in `dart_shell/lib/src/desktop/desktop_system_bar.dart` delegates to the typed
  selection in `features/default_shell/panel_composition.dart`. It currently selects
  `denial_taskbar` from the sibling `../denial_taskbar_plugin` checkout; the
  original bar remains independently available.
- Work-area modeling includes built-in system-bar assumptions in
  `dart_shell/lib/src/models/display_layout.dart`. General panel/reservation
  contracts must keep native layout and Flutter presentation consistent.
- The semantic window-action facade in
  `dart_shell/lib/src/core/shell_windows.dart` is narrower than internal desktop
  operations. Expose reusable actions without coupling plugins to private state.
- Frame/content geometry assumes uniform borders in
  `dart_shell/lib/src/desktop/desktop_workspace.dart` and
  `compositor/src/bin/deniald/wayland_frontend/window_management.rs`.
- Decoration negotiation and window facts currently impose server-frame policy;
  inspect `wayland_frontend/handlers.rs` and `wayland_frontend/managed_window.rs`.
- Refresh implementation and remaining limitations are documented in
  [UI development](UI_DEVELOPMENT.md) and implemented in native UI runtime control.

General geometry APIs must consistently account for outer frame, client content,
per-edge insets, input ownership, client configure sizes, popup coordinates,
minimum sizes, fullscreen/maximize, tiling, and animated/overview presentation.
Do not solve these with plugin-specific branches in core.

Decoration APIs must distinguish client preference, negotiated ownership, and
relevant X11 hints. Presence of an XDG decoration object does not mean the client
draws its own title bar. Follow protocol configure/commit state; do not infer
decoration ownership from application names or visual inspection.

## 11. Demonstration scenario, not an architecture boundary

The user proposed a plugin composition that:

- adds a taskbar;
- removes the default top CPU/GPU/etc. cards;
- supplies title bars with window controls;
- avoids adding title bars where clients own decorations.

Use this as an integration exercise, not as the list of capabilities the system
is allowed to support. Taskbar appearance, grouping, title-bar buttons, and chosen
desktop organization belong in plugins. Core changes must be general SDK/runtime,
protocol, or composition infrastructure.

Validate dependency closure, typed discovery, provider conflicts, generated builds,
disabled-plugin absence, default-preset behavior, geometry/input correctness,
decoration negotiation, refresh, and recovery as applicable. The user owns visual
validation. Never trigger visible test events or inspect screenshots without the
authorization required by `AGENTS.md`.

## 12. Superseded approaches / do not reintroduce

- A runtime plugin registry populated by imported plugins calling `configure()`.
- Treating imports alone as activation or relying on top-level registration effects.
- A second manifest that duplicates plugin dependencies from `pubspec.yaml`.
- Requiring users to manually enable plugin dependencies.
- A privileged monolithic default shell that third-party code can only decorate.
- An extension system restricted to the first taskbar example.
- Arbitrary AST/source rewriting or raw patches as the supported default mechanism.
- Assuming `@Provides`, `@Replaces`, or `@Wraps` are existing Dart features.
- Depending on Dart's discontinued macro project or experimental dynamic loading.
- Runtime reflection/scanning to discover the enabled composition.
- A process-per-plugin architecture as the selected design.
- Treating compile-time composition as execution of Flutter UI during the build.

## 13. Decisions still required during implementation design

Resolve these within the accepted architecture; do not mistake illustrative syntax
for a completed API specification:

- exact package extraction and public API/versioning boundaries;
- discovery implementation (the SDK now defines a `@Plugin()` library marker,
  `@ExtensionPoint` contract metadata, and typed `@Provides` declarations);
- constructor/factory injection and generated root application API;
- contract cardinality, selection, decorator ordering, and conflict diagnostics;
- build-script contract, declared inputs, and execution isolation;
- dependency-cycle and runtime resource-lifecycle rules;
- selection persistence, configuration migration, and incompatible-upgrade behavior;
- bundle manifest/compatibility integration and persistent recovery behavior;
- store source provenance, package verification, and publication workflow.

The initial SDK lives in [packages/denial_sdk](../packages/denial_sdk/README.md):
typed contribution metadata, shared application/window-action/system models, and
analyzer tests. [packages/denial_flutter_sdk](../packages/denial_flutter_sdk/README.md)
adds the typed panel contract, service injection, theme, effects, and input-region
primitives. [plugins/denial_top_bar](../plugins/denial_top_bar/README.md) owns bar
presentation and uses those public APIs without importing shell internals.

The shell includes the plugin through a Pub path dependency and direct static
composition, as explicitly requested for this increment. Annotations are not yet
consumed by a generator. Existing placement, reservations, native service
lifetimes, and tray menu/input ownership remain runtime-owned. The default shell
has not yet been fully split into plugins. General panel layout, plugin selection,
generated composition, and manager-driven installation/deployment remain
unimplemented. Manual plugin builds and lab deployments have been exercised.

Current desktop composition selects `TaskbarPlugin` (`material_ui`) directly.
`ShellPanel.placement` can request a fixed edge/thickness; the default assembly
injects this into `DenialShell.desktopPanelPlacement`. Runtime bindings apply it
to both native reservations and the Flutter display layout, respecting hidden
panels and configured output selection. Custom shells opt in explicitly; mobile
layout is unchanged. `ShellServices` additionally exposes application-window
summaries, activation, launcher access, and icon rendering. Tray presentation
supports wrapped icons for overflow flyouts. This is still one selected panel,
not a general multi-panel placement solver or an implemented plugin manager.
`PanelPlacement.reserveWindowSpacing` additionally lets the host reserve configured
window spacing while painting the panel at its original thickness against the
output edge. The taskbar uses this option and Denial's shared glass primitives.

Local development extraction: `denial_taskbar` now lives in its own Git repository
at `../denial_taskbar_plugin`, outside the Denial checkout. Its two SDK dependencies
point back to `../denial/packages/denial_sdk` and
`../denial/packages/denial_flutter_sdk`. The shell deliberately keeps it selected
through a path dependency. Both checkouts are required for this local composition;
this is not SDK publication or a plugin-manager installation mechanism.
