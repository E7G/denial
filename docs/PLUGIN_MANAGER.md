# Denial Plugin Manager: agent implementation contract

Status: accepted product/distribution direction; manager implementation pending.
Decision date: 2026-09-27.
Audience: agents implementing the manager, SDK distribution, catalog, or builder.

Read [PLUGIN_SYSTEM.md](PLUGIN_SYSTEM.md) first. This document extends that
contract with the agreed distribution and management model. It supersedes the
earlier proposal that plugin authors must publish their plugins to pub.dev.
It does not authorize implementation, publication, or deployment. Follow
`AGENTS.md` for all execution and validation constraints.

MUST/MUST NOT denote requirements. Examples use illustrative package names,
versions, URLs, and field names; they are not published packages, assigned
repository locations, or a finalized storage/IPC schema.

## 1. Accepted shape

- Plugin Manager is a separate Flutter application, analogous to Settings.
- Define and implement the backend before the store UI.
- Initial external plugin installation accepts a Git repository URL.
- Plugin authors MUST NOT need a pub.dev account or publication step.
- Plugins remain ordinary Dart packages with `pubspec.yaml` and annotated Dart
  contribution libraries. Git distribution does not eliminate package structure.
- Publish Denial's public SDK packages on pub.dev so authors can reference them
  without cloning the Denial repository.
- Show built-in plugins and entries from a Denial-owned catalog repository.
- Support direct Git installation independently of catalog inclusion.
- A repository may contain multiple independently selectable plugin packages.
- Pub remains the dependency authority. Activation remains compile-time.

Future hosted-plugin and local-directory sources should fit the backend model.
They are not prerequisites for the first Git installation path. SDK hosting on
pub.dev is accepted; requiring all plugins to use pub.dev is not.

## 2. Authority boundaries

| Concern | Authority |
| --- | --- |
| Built-in availability and matching source versions | Installed Denial release manifest |
| External catalog membership | Denial-owned catalog |
| Explicitly selected plugins | User composition configuration |
| Package names, dependencies, version constraints | Package pubspecs |
| Exact resolved dependency graph and Git commits | Pub resolution and retained application lockfile |
| Contributions and contract identities | Static analysis of annotated libraries |
| Denial runtime, engine, and toolchain identity | Installed release/source compatibility metadata |
| Active bundle and recovery | Existing native shell-control infrastructure |

Catalog inclusion MUST NOT activate a plugin. Removing a catalog entry MUST NOT
silently uninstall or disable an existing selection. Treat explicit removal,
update, and any future revocation policy as separate operations.

Keep selected roots distinguishable from dependencies. If a selected plugin
depends on another plugin, Pub brings that package into the graph and static
discovery includes its contributions automatically. An ordinary library remains
a library. Do not require separate user enablement of plugin dependencies.

## 3. Git sources and revisions

The common author layout is:

```text
my_taskbar/
  pubspec.yaml
  lib/
    my_taskbar.dart
```

A URL alone MUST be sufficient when there is one plugin package at the root.
The default branch supplies the initial revision. Optional selection can specify
a branch, tag, commit, or package subdirectory.

Retain these concepts separately:

- Requested source: repository URL, package path, and requested ref/default-branch
  policy. This expresses what the user follows for updates.
- Resolved source: package name, actual Git commit, package path, and resolved
  dependency graph. This identifies the input used for a particular build.

The manager must read the package pubspec to obtain its name; a repository name
is not necessarily the Dart package name. Verify that generated dependency keys
match the selected packages. Do not execute package code to discover metadata.

Generated dependency example:

```yaml
dependencies:
  my_taskbar:
    git:
      url: https://github.com/example/desktop_plugins.git
      path: taskbar
      ref: <resolved-commit>
```

Retain the lockfile alongside the generated composition. Rebuild/apply MUST NOT
implicitly advance previously locked Git revisions. Updating deliberately resolves
new revisions and creates a new candidate. A moving branch or tag alone is not
sufficient build provenance. Record resolved commits for transitive Git packages
as well as roots, using Pub's result rather than a second dependency resolver.

Pub supports Git refs and repository-relative package paths. It also supports
version selection from matching tags via `tag_pattern`; adopting a tag convention
is optional future work, not an author requirement for initial installation.
See [Pub Git dependencies](https://dart.dev/tools/pub/dependencies#git-packages).

## 4. Multiple plugins in one repository

```text
desktop_plugins/
  taskbar/
    pubspec.yaml                 # name: my_taskbar
    lib/
  window_decorations/
    pubspec.yaml                 # name: my_window_decorations
    lib/
  shared/
    pubspec.yaml                 # ordinary shared library
    lib/
```

The package is the enable/disable unit; the repository is a source container.
Several annotated contribution libraries/classes within one package activate
together. Independently selectable plugins MUST be separate packages, even when
they share a repository.

For a pasted URL containing multiple plugin packages, inspect the repository's
package candidates and offer the plugin packages individually. Do not implicitly
enable every package in the repository. Ordinary shared libraries and development
fixtures MUST NOT appear as plugins merely because they have a pubspec.

Repository discovery and compilation discovery are distinct:

- Repository inspection finds installable package candidates without executing
  their code; resolved annotation identities establish actual plugin declarations.
- Compilation discovery examines only the resolved application dependency closure
  for the selected composition, excluding dev/build tooling.

Packages in the same repository declare dependencies through their pubspecs.
Do not infer dependencies from sibling directories or add a catalog dependency
list. A taskbar depending on the decorations plugin brings it in automatically;
a taskbar not depending on it leaves it independently selectable.

Source identity must include repository URL and package path, with exact revision
recorded per resolution. Pub's package-name identity still applies: two sources
declaring the same package name cannot be treated as unrelated namespaced plugins.
Report source/version conflicts instead of silently selecting a winner.

## 5. Catalog and built-ins

A YAML file in a Denial-owned repository is sufficient for the initial catalog:

```yaml
schema: 1
plugins:
  - git: https://github.com/example/single_plugin.git
  - git: https://github.com/example/desktop_plugins.git
    path: taskbar
  - git: https://github.com/example/desktop_plugins.git
    path: window_decorations
```

Catalog entries identify sources/packages. The catalog MUST NOT duplicate Pub's
dependency graph, SDK constraints, or Dart contribution definitions. Prefer package
metadata for names/descriptions/documentation. Categories, featured entries, version
restrictions, and review status may be added later with explicit semantics.

Built-ins use the same SDK and composition rules as external plugins. Their exact
source identities come from the installed release rather than a moving repository
branch. Preserve the packaged default shell as the recovery root. Shipping/caching
built-in source and dependency artifacts is desirable for offline default rebuilds;
do not claim that capability until the complete toolchain/input set is available.

## 6. SDK publication and compatibility

Publish these existing package boundaries:

- `denial_sdk`: Dart-only public types and contribution metadata.
- `denial_flutter_sdk`: Flutter contracts, shared presentation, and input APIs.

Illustrative plugin dependencies after publication:

```yaml
dependencies:
  flutter:
    sdk: flutter
  denial_sdk: ^0.1.0
  denial_flutter_sdk: ^0.1.0
```

SDK versions express public API compatibility independently of Denial release
numbers. Each Denial release must identify its supported SDK versions and matching
runtime/toolchain. Plugins declare supported SDK ranges through Pub constraints.
Reject incompatible combinations; do not silently force them with overrides.
All contributions must share the resolved SDK type identities.

Current SDKs/plugins are repository-local, use `publish_to: none`, and have source
metadata version `0.0.0`. Publication requires intentional versioning and replacing
the Flutter SDK package's relative dependency with a hosted SDK dependency. Pub.dev
publication requires hosted/SDK dependencies, not ordinary Git/path dependencies.
See [publication requirements](https://dart.dev/tools/pub/publishing#prepare-your-package-for-publication).

Downloading an SDK package does not install Denial's custom Flutter engine.
Compilation of fork-dependent Flutter APIs requires the release-matched toolchain.
Provision it through the manager/development workflow; do not replace it with stock
Flutter merely because Pub successfully resolved the package graph.

## 7. Backend and application boundary

The backend owns resolution, planning, generation, builds, and activation requests.
The separate GUI presents catalog/state, user selections, progress, and failures.
Provide a CLI path to the same backend so recovery does not depend on shell UI.
Build jobs should survive closing the GUI; worker lifetime and IPC remain to be
specified. Do not put long-running compilation exclusively inside a widget process.

Proposed operations, not finalized method names or an implemented API:

| Operation | Responsibility |
| --- | --- |
| Catalog/status | Available packages, selected roots, required dependencies, active build, job state |
| Plan(selection) | Resolve a candidate, report dependency changes and composition conflicts |
| Build(plan) | Generate direct typed wiring, compile, emit progress, retain validated artifacts |
| Activate(build) | Ask existing native control to switch to the prepared compatible bundle |
| Restore | Ask existing native control to restore the packaged shell |

The manager owns a generated application workspace based on the installed Denial
source revision. It MUST NOT edit the installed checkout or an arbitrary user's
development project when changing plugin selections. Persist selection intent
separately from generated files and exact successful build provenance.

Candidate pipeline:

1. Identify release/runtime/toolchain and obtain matching build inputs.
2. Materialize a candidate generated project from selection and retained lock.
3. Resolve via `flutter pub get` using Denial's pinned toolchain.
4. Inspect typed contributions, validate contracts, generate direct composition.
5. Compile and validate a new immutable bundle.
6. Request activation through existing native control; retain previous working
   artifacts and packaged recovery.

Failed resolution, generation, or compilation MUST leave the active bundle
usable. Keep apply/rebuild and update operations distinct. Native refresh support
is existing infrastructure, but persistent custom composition integration and
recovery behavior still require implementation and verification.

## 8. Prerequisites, first milestone, and unresolved decisions

Current `dart_shell/pubspec.yaml` depends on both bars, while handwritten
`features/default_shell/panel_composition.dart` selects one. This is temporary.
Before automatic discovery, remove optional-plugin dependencies from the runtime
boundary. Only the generated application should introduce selected plugin roots;
otherwise both bars remain reachable and would be discovered as active plugins.

First backend milestone: resolve a selection containing either existing bar,
discover its typed contribution, generate the wiring, build, and activate through
the existing control path. Exercise a Git package at the repository root and a
package selected by subdirectory. Keep the original plugin architecture's broader
contracts; this milestone MUST NOT turn the manager into a taskbar-specific tool.

Decisions still open:

- SDK publication versions, API stability policy, release compatibility metadata;
- catalog repository location, exact schema, update/cache policy;
- repository package discovery boundaries and identity normalization;
- default-branch tracking and optional tag/version conventions;
- handling coordinated updates of several packages from one repository;
- authentication UX for private Git sources;
- backend implementation language, worker lifetime, IPC, durable job/selection schema;
- constructor/factory generation, ordering, conflict diagnostics;
- stale-plan/concurrent activation handling, health checks, persistent rollback;
- source provenance/review/revocation policy and build-script execution rules.

Do not convert these open choices into requirements without a design decision.
Do not claim catalog listing, Git hosting, or pub.dev hosting provides runtime
isolation: plugins compile into the shell's process and failure domain.
