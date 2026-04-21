# Feature Implementation Record: element-tree-bootstrap

## Metadata
- feature: Flutter element tree bootstrap during app startup
- project_root: `D:/My/flutter_source`
- architecture_index: `packages/flutter/framewrok_src_note/启动流程与三棵树的创建.md`
- analysis_scope: Trace how Flutter creates the root element and recursively expands the element tree from `runApp` until the `View/RawView` boundary.
- output_date: 2026-04-21
- confidence: high

## Entry Points
- symbol: `runApp`
  file: `packages/flutter/lib/src/widgets/binding.dart`
  lines: `1614-1617`
  role: Public startup entrypoint for bootstrapping the widget/element tree.

- symbol: `WidgetsBinding.attachToBuildOwner`
  file: `packages/flutter/lib/src/widgets/binding.dart`
  lines: `1416-1422`
  role: Hands the wrapped `RootWidget` to the `BuildOwner` and stores the resulting root element.

- symbol: `RootWidget.attach`
  file: `packages/flutter/lib/src/widgets/binding.dart`
  lines: `1736-1750`
  role: Direct root-element creation/reuse gateway.

## Core Flow
1. step: Enter framework startup
   file: `packages/flutter/lib/src/widgets/binding.dart`
   lines: `1614-1617`
   symbols: `runApp`, `WidgetsFlutterBinding.ensureInitialized`, `_runWidget`
   summary: `runApp` initializes the binding and forwards the app widget after wrapping it in a default `View`.
   evidence: `runApp` calls `_runWidget(binding.wrapWithDefaultView(app), binding, 'runApp')`.

2. step: Schedule root attachment
   file: `packages/flutter/lib/src/widgets/binding.dart`
   lines: `1679-1683`
   symbols: `_runWidget`, `scheduleAttachRootWidget`, `scheduleWarmUpFrame`
   summary: Startup defers actual element creation by scheduling root attachment and a warm-up frame.
   evidence: `_runWidget` chains `scheduleAttachRootWidget(app)` and `scheduleWarmUpFrame()`.

3. step: Wrap the external root in a framework root widget
   file: `packages/flutter/lib/src/widgets/binding.dart`
   lines: `1403-1405`
   symbols: `attachRootWidget`, `RootWidget`
   summary: The user root widget is wrapped in `RootWidget(debugShortDescription: '[root]', child: rootWidget)`.
   evidence: `attachRootWidget` directly passes a new `RootWidget` into `attachToBuildOwner`.

4. step: Create the root element and assign ownership
   file: `packages/flutter/lib/src/widgets/binding.dart`
   lines: `1736-1745`
   symbols: `RootWidget.attach`, `createElement`, `assignOwner`, `BuildOwner.buildScope`
   summary: On first boot, Flutter creates a `RootElement`, assigns the `BuildOwner`, then mounts it within a build scope.
   evidence: `element = createElement(); element!.assignOwner(owner); owner.buildScope(element!, () { element!.mount(null, null); })`.

5. step: Initialize generic element state for the root
   file: `packages/flutter/lib/src/widgets/framework.dart`
   lines: `4328-4360`
   symbols: `Element.mount`
   summary: `mount` sets lifecycle state, parent/slot, depth, inheritance, owner propagation rules, and notification tree linkage.
   evidence: The method writes `_parent`, `_slot`, `_lifecycleState`, `_depth`, optionally `_owner`, `_parentBuildScope`, and registers `GlobalKey`s.

6. step: Root element triggers first child expansion
   file: `packages/flutter/lib/src/widgets/binding.dart`
   lines: `1788-1823`
   symbols: `RootElement.mount`, `RootElement._rebuild`, `updateChild`
   summary: After root mount, Flutter immediately asks `updateChild` to materialize the root widget child as the first subtree node.
   evidence: `RootElement.mount` calls `_rebuild()`, and `_rebuild()` calls `updateChild(_child, (widget as RootWidget).child, null)`.

7. step: Decide whether to reuse or create a child element
   file: `packages/flutter/lib/src/widgets/framework.dart`
   lines: `3982-4059`
   symbols: `Element.updateChild`, `Widget.canUpdate`, `inflateWidget`
   summary: `updateChild` centralizes child lifecycle decisions; on first build with no prior child it always delegates to `inflateWidget`.
   evidence: When `child == null`, the method returns `inflateWidget(newWidget, newSlot)`.

8. step: Instantiate the new element from the widget
   file: `packages/flutter/lib/src/widgets/framework.dart`
   lines: `4556-4589`
   symbols: `Element.inflateWidget`, `Widget.createElement`, `Element.mount`
   summary: `inflateWidget` creates the element via widget polymorphism and mounts it under the current parent element.
   evidence: `final Element newChild = inactiveChild ?? newWidget.createElement(); ... newChild.mount(this, newSlot);`.

9. step: Recursively expand component-style elements
   file: `packages/flutter/lib/src/widgets/framework.dart`
   lines: `5789-5860`
   symbols: `ComponentElement.mount`, `_firstBuild`, `performRebuild`, `build`, `updateChild`
   summary: Component elements recursively expand the element tree by building a child widget and immediately routing it back through `updateChild`.
   evidence: `mount` calls `_firstBuild()`, `_firstBuild()` calls `rebuild()`, and `performRebuild()` executes `built = build(); _child = updateChild(_child, built, slot);`.

10. step: Reach the view boundary while still using the same element-creation protocol
   file: `packages/flutter/lib/src/widgets/view.dart`
   lines: `270-287`, `370-382`, `437-443`
   symbols: `View.build`, `RawView.build`, `_RawViewInternal.createElement`
   summary: The widget path becomes `View -> RawView -> _RawViewInternal`, and `_RawViewInternal` still participates in normal element creation through `createElement`.
   evidence: `View.build` returns `RawView`, `RawView.build` returns `_RawViewInternal`, and `_RawViewInternal.createElement()` returns `_RawViewElement(this)`.

11. step: Cross into the render boundary without stopping element expansion
   file: `packages/flutter/lib/src/widgets/view.dart`
   lines: `478-505`
   symbols: `_RawViewElement._updateChild`, `_RawViewElement.mount`
   summary: `_RawViewElement` both continues element subtree creation via `updateChild` and installs the `RenderView` root for rendering.
   evidence: `mount` sets `_effectivePipelineOwner.rootNode = renderObject`, calls `_attachView()`, then `_updateChild()`, and `_updateChild()` itself uses `updateChild(_child, child, null)`.

## Key Symbols
- symbol: `RootWidget.attach`
  kind: method
  file: `packages/flutter/lib/src/widgets/binding.dart`
  lines: `1736-1750`
  role: Creates or reuses the root element for the framework tree.
  used_by: `WidgetsBinding.attachToBuildOwner`
  calls_into: `createElement`, `RootElementMixin.assignOwner`, `BuildOwner.buildScope`, `Element.mount`

- symbol: `RootElement._rebuild`
  kind: method
  file: `packages/flutter/lib/src/widgets/binding.dart`
  lines: `1820-1823`
  role: Starts root child materialization from the root widget's `child`.
  used_by: `RootElement.mount`, `RootElement.update`
  calls_into: `Element.updateChild`

- symbol: `Element.updateChild`
  kind: method
  file: `packages/flutter/lib/src/widgets/framework.dart`
  lines: `3982-4059`
  role: Central branch point for child reuse, update, deactivation, or creation.
  used_by: `RootElement._rebuild`, `ComponentElement.performRebuild`, `_RawViewElement._updateChild`
  calls_into: `deactivateChild`, `updateSlotForChild`, `Element.update`, `Element.inflateWidget`

- symbol: `Element.inflateWidget`
  kind: method
  file: `packages/flutter/lib/src/widgets/framework.dart`
  lines: `4556-4589`
  role: Converts a widget into a mounted child element.
  used_by: `Element.updateChild`
  calls_into: `_retakeInactiveElement`, `Widget.createElement`, `Element.mount`, `Element._activateWithParent`

- symbol: `Element.mount`
  kind: method
  file: `packages/flutter/lib/src/widgets/framework.dart`
  lines: `4328-4360`
  role: Performs generic tree attachment and owner/build-scope inheritance.
  used_by: `RootWidget.attach`, `Element.inflateWidget`
  calls_into: `_updateInheritance`, `attachNotificationTree`

- symbol: `ComponentElement.performRebuild`
  kind: method
  file: `packages/flutter/lib/src/widgets/framework.dart`
  lines: `5810-5860`
  role: Builds the next widget configuration and recursively expands or updates the child subtree.
  used_by: `ComponentElement._firstBuild`, later rebuild scheduling
  calls_into: `build`, `super.performRebuild`, `Element.updateChild`

- symbol: `_RawViewElement.mount`
  kind: method
  file: `packages/flutter/lib/src/widgets/view.dart`
  lines: `499-505`
  role: View-boundary root element that both attaches the render root and continues element child creation.
  used_by: `Element.inflateWidget`
  calls_into: `super.mount`, `_attachView`, `_updateChild`, `RenderView.prepareInitialFrame`

## State and Data Changes
- location: `packages/flutter/lib/src/widgets/framework.dart:7039-7042`
  mutation: `_owner = owner` and `_parentBuildScope = BuildScope()`
  purpose: Attach the root element to the `BuildOwner` and establish the root build scope.
  triggered_by: `RootWidget.attach`

- location: `packages/flutter/lib/src/widgets/framework.dart:4342-4352`
  mutation: `_parent`, `_slot`, `_lifecycleState`, `_depth`, inherited `_owner`, inherited `_parentBuildScope`
  purpose: Attach a newly created element into the active tree.
  triggered_by: `Element.mount`

- location: `packages/flutter/lib/src/widgets/binding.dart:1822`
  mutation: `_child = updateChild(...)`
  purpose: Store the root element's only child after materialization or update.
  triggered_by: `RootElement._rebuild`

- location: `packages/flutter/lib/src/widgets/framework.dart:5841`
  mutation: `_child = updateChild(_child, built, slot)`
  purpose: Replace or create the single child under a component element after `build()`.
  triggered_by: `ComponentElement.performRebuild`

- location: `packages/flutter/lib/src/widgets/view.dart:501-504`
  mutation: `_effectivePipelineOwner.rootNode = renderObject` and `_child = updateChild(_child, child, null)`
  purpose: Install the `RenderView` root and continue expanding the element subtree under the view boundary.
  triggered_by: `_RawViewElement.mount`

## Decision Points
- condition: `rootElement == null`
  location: `packages/flutter/lib/src/widgets/binding.dart:1417-1421`
  effect_if_true: Treat startup as bootstrap and ensure a visual update after attaching the root.
  effect_if_false: Reuse the existing root element path.

- condition: `element == null`
  location: `packages/flutter/lib/src/widgets/binding.dart:1737-1749`
  effect_if_true: Create a new `RootElement`, assign owner, and mount it.
  effect_if_false: Store `_newWidget` on the existing root element and mark it dirty.

- condition: `child == null`
  location: `packages/flutter/lib/src/widgets/framework.dart:4055-4059`
  effect_if_true: Create a new child through `inflateWidget`.
  effect_if_false: Attempt reuse/update/deactivate decisions for the existing child.

- condition: `inactiveChild != null`
  location: `packages/flutter/lib/src/widgets/framework.dart:4579-4588`
  effect_if_true: Reactivate a previously inactive keyed element instead of creating a new one.
  effect_if_false: Mount a freshly created element.

## Side Effects
- effect: Schedules async root attachment
  location: `packages/flutter/lib/src/widgets/binding.dart:1388-1391`
  when: `_runWidget` startup path

- effect: Opens a build scope and state lock around root mount
  location: `packages/flutter/lib/src/widgets/binding.dart:1738-1745`, `packages/flutter/lib/src/widgets/framework.dart:3013-3057`
  when: First root element creation

- effect: Registers global keys for mounted elements
  location: `packages/flutter/lib/src/widgets/framework.dart:4354-4357`
  when: Any element mount with a `GlobalKey`

- effect: Attaches a render root to the pipeline owner and renderer binding
  location: `packages/flutter/lib/src/widgets/view.dart:501-517`
  when: `_RawViewElement.mount`

## Related Files
- file: `packages/flutter/lib/src/widgets/binding.dart`
  relevance: primary
  reason: Startup entry, root widget wrapping, and root element bootstrap.

- file: `packages/flutter/lib/src/widgets/framework.dart`
  relevance: primary
  reason: Generic element lifecycle, child update rules, widget-to-element instantiation, and component rebuild recursion.

- file: `packages/flutter/lib/src/widgets/view.dart`
  relevance: primary
  reason: The `View`/`RawView` boundary where the same element protocol reaches render bootstrap.

- file: `packages/flutter/framewrok_src_note/启动流程与三棵树的创建.md`
  relevance: secondary
  reason: Architecture index used to narrow the scan to the startup and tree-bootstrap path.

## Open Questions
- question: Which exact `Element` subclasses are returned for each concrete widget type encountered below `RootWidget` in a real app?
  status: partially-answered
  note: The generic creation protocol is confirmed, but per-widget subclass mapping depends on each widget's `createElement()` implementation and was intentionally not exhaustively scanned here.

- question: How do multi-view or `runWidget` scenarios alter the same root bootstrap chain?
  status: partially-answered
  note: The root creation machinery is shared, but this analysis stayed on the `runApp` path with default `View` wrapping.

## Inferences
- statement: Flutter intentionally separates structural child decisions, element instantiation, and tree attachment into `updateChild`, `inflateWidget/createElement`, and `mount` respectively so the same protocol can serve root, component, and view-boundary nodes.
  basis: Confirmed call sites show the same sequence reused in `RootElement`, `ComponentElement`, and `_RawViewElement`.

## Retrieval Hints
- If asked "Where is the first `Element` created?", start from `packages/flutter/lib/src/widgets/binding.dart:1736-1745` at `RootWidget.attach`.
- If asked "What function actually creates child elements from widgets?", start from `packages/flutter/lib/src/widgets/framework.dart:4556-4589` at `Element.inflateWidget`.
- If asked "Why does the element tree keep growing recursively after the root?", start from `packages/flutter/lib/src/widgets/framework.dart:5810-5842` at `ComponentElement.performRebuild`.
- If asked "Where does the element tree meet the render tree?", start from `packages/flutter/lib/src/widgets/view.dart:499-505` at `_RawViewElement.mount`.
