# 三棵树分别是什么

Flutter 运行时会围绕同一份界面描述，逐步建立三层结构：

1. `Widget` 树：描述界面配置，是声明式的结构。
2. `Element` 树：负责把 `Widget` 配置实例化到运行时，并维护父子关系、生命周期与更新逻辑。
3. `RenderObject` 树：负责布局、绘制与命中测试，是最终参与渲染的对象树。

可以先用一句话理解三者分工：

`Widget` 负责“描述要什么”，`Element` 负责“把描述变成运行时节点并持续维护”，`RenderObject` 负责“真正把界面算出来并画出来”。

# 三棵树的顶级对象

Flutter 在启动阶段会先确定三棵树的顶层入口：

1. 顶层 `Widget`：[lib/src/widgets/binding.dart](lib/src/widgets/binding.dart)`RootWidget`类
2. 顶层 `Element`：[lib/src/widgets/binding.dart](lib/src/widgets/binding.dart)`RootElement`类
3. 顶层 `RenderObject`：[lib/src/rendering/view.dart](lib/src/rendering/view.dart)`RenderView`类

这里要特别注意：

1. 从职责上看，`RootWidget` 是整个 `Widget` 树的包裹入口。
2. `RootElement` 是整个 `Element` 树的根节点。
3. `RenderView` 是渲染树根节点，最终和平台视图绑定。

# 从 `runApp()` 开始的整体链路

如果只看主流程，可以先记住下面这条时序：

> runApp(app)  -> WidgetsFlutterBinding.ensureInitialized()
> -> wrapWithDefaultView(app)
> -> scheduleAttachRootWidget(app)
> -> attachRootWidget(...)
> -> attachToBuildOwner(RootWidget(...))
> -> RootWidget.attach(...)
> -> RootWidget.createElement()
> -> RootElement.mount(...)
> -> RootElement._rebuild()
> -> updateChild(...)
> -> 递归创建整棵 Element 树
> -> 与 RenderObjectElement 对应的 RenderObject 树逐步建立

下面分段展开。

# 第一步：`runApp()` 触发启动

`runApp()` 做了两件关键事情：

1. 确保 `WidgetsBinding` 已初始化。
2. 把业务侧传入的根组件包装后，交给绑定对象继续处理。

> `runApp()` 并不直接创建三棵树，而是把入口组件交给 `WidgetsBinding`，后续由绑定对象调度根节点挂载。

```dart
void runApp(Widget app) {
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  _runWidget(binding.wrapWithDefaultView(app), binding, 'runApp');
}

void _runWidget(Widget app, WidgetsBinding binding, String debugEntryPoint) {
  assert(binding.debugCheckZone(debugEntryPoint));
  binding
    ..scheduleAttachRootWidget(app)
    ..scheduleWarmUpFrame();
}
```

这里的核心点是：

1. `ensureInitialized()` 会拿到 `WidgetsFlutterBinding`。
2. `wrapWithDefaultView(app)` 会先把业务 `app` 包到 `View` 中。
3. `scheduleAttachRootWidget(app)` 会安排后续去挂载根 `Widget`。

# 第二步：创建 `RootWidget`

进入 `WidgetsBinding` 后，真正被挂载到树顶层的并不是我们直接传入的业务组件，而是一个 `RootWidget`。

> `RootWidget` 是 Flutter 框架在树最顶层包出来的根 `Widget`，它的 `child` 才是业务传入的根组件。

```dart
@protected
void scheduleAttachRootWidget(Widget rootWidget) {
  Timer.run(() {
    attachRootWidget(rootWidget);
  });
}

void attachRootWidget(Widget rootWidget) {
  attachToBuildOwner(
    RootWidget(
      debugShortDescription: '[root]',
      child: rootWidget,
    ),
  );
}

void attachToBuildOwner(RootWidget widget) {
  final bool isBootstrapFrame = rootElement == null;
  _readyToProduceFrames = true;
  _rootElement = widget.attach(buildOwner!, rootElement as RootElement?);
  if (isBootstrapFrame) {
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}
```

这一段可以总结为：

1. `scheduleAttachRootWidget()` 使用异步调度触发根挂载。
2. `attachRootWidget()` 会把传入的根组件包装成 `RootWidget`。
3. `attachToBuildOwner()` 开始把 `RootWidget` 接到 `BuildOwner` 管理体系中。

# 第三步：创建 `RootElement`

`RootWidget` 并不只是一层包装，它还负责创建对应的根 `Element`。

> `RootWidget.attach()` 中最重要的动作，是通过 `createElement()` 创建 `RootElement`，然后把它和 `BuildOwner` 关联起来。

```dart
RootElement attach(BuildOwner owner, [RootElement? element]) {
  if (element == null) {
    owner.lockState(() {
      element = createElement();
      assert(element != null);
      element!.assignOwner(owner);
    });
    owner.buildScope(element!, () {
      element!.mount(/* parent */ null, /* slot */ null);
    });
  } else {
    element._newWidget = this;
    element.markNeedsBuild();
  }
  return element!;
}
```

这里可以看到几个重要职责：

1. `createElement()` 创建根 `Element`。
2. `assignOwner(owner)` 说明真正绑定 `BuildOwner` 的是 `Element`。
3. `buildScope()` 中调用 `mount()`，表示开始正式把根节点挂到树上。

也就是说，`BuildOwner` 虽然是从 `WidgetsBinding` 一路传下来的，但最终是服务于 `Element` 树的构建与更新。

# 第四步：`RootElement.mount()` 递归展开整棵 `Element` 树

根节点创建出来以后，真正把整棵运行时树“长出来”的关键步骤，是 `RootElement.mount()` 以及后续的 `_rebuild()`。

> `mount()` 负责挂载当前节点，`_rebuild()` 负责从根节点开始向下展开子节点。

```dart
@override
void mount(Element? parent, Object? newSlot) {
  assert(parent == null); // We are the root!
  super.mount(parent, newSlot);
  _rebuild();
  assert(_child != null);
  super.performRebuild(); // clears the "dirty" flag
}

void _rebuild() {
  try {
    _child = updateChild(_child, (widget as RootWidget).child, /* slot */ null);
  } catch (exception, stack) {
    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: exception,
      stack: stack,
      library: 'widgets library',
      context: ErrorDescription('attaching to the render tree'),
    );
    FlutterError.reportError(details);
    _child = null;
  }
}
```

这一段是理解三棵树创建流程的关键。

## 为什么 `updateChild()` 很重要

`_rebuild()` 里最核心的一句是：

> `_child = updateChild(_child, (widget as RootWidget).child, null);`

它表达的是：

1. 取出 `RootWidget` 的业务子节点。
2. 用这个新的 `Widget` 配置去更新当前已有子节点。
3. 如果子节点不存在，就创建新的 `Element`。
4. 如果子节点已存在且可复用，就更新旧 `Element`。
5. 然后继续对子节点做同样的事情，于是递归展开整棵树。

所以，`updateChild()` 可以看作 `Element` 树维护的核心模板方法。它不仅用于首帧创建，也用于后续更新阶段的复用、替换和销毁判断。

## 递归是如何开始的

第一次进入 `_rebuild()` 时：

1. 当前节点是 `RootElement`。
2. `widget` 是 `RootWidget`。
3. `(widget as RootWidget).child` 就是最初传入的应用根组件。
4. `updateChild()` 会为这个根组件创建对应 `Element`。
5. 该子 `Element` 在挂载时又会继续处理它自己的子 `Widget`。

于是整棵 `Element` 树会从根节点一层层向下递归创建出来。

# `RenderObject` 树是怎么接上的

`RenderObject` 树并不是对整个 `Element` 树逐节点复制，而是和其中的 `RenderObjectElement` 部分相对应。

这意味着：

1. `StatelessWidget`、`StatefulWidget` 这类组件更多承担组合和配置职责。
2. 真正进入布局和绘制阶段的，是那些能够生成 `RenderObject` 的 `RenderObjectWidget`。
3. 对应的 `Element` 类型通常是 `RenderObjectElement`。

可以把这层关系理解为：

```text
Widget
  -> Element
    -> 只有当 Element 属于 RenderObjectElement 体系时
       才会继续创建并维护 RenderObject
```

因此，`Element` 树是三棵树之间最关键的桥梁：

1. 向上承接 `Widget` 的声明式配置。
2. 向下驱动 `RenderObject` 的创建、更新与销毁。

# `RenderView` 的创建时机

`RenderView` 的准备时机其实非常早。

> 在 `runApp()` 中，`WidgetsBinding` 初始化完成后，`RenderView` 就已经准备好了；随后才继续执行 `RootWidget` 和 `RootElement` 的挂载。

```dart
void runApp(Widget app) {
  final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  _runWidget(binding.wrapWithDefaultView(app), binding, 'runApp');
}

Widget wrapWithDefaultView(Widget rootWidget) {
  return View(
    view: platformDispatcher.implicitView!,
    deprecatedDoNotUseWillBeRemovedWithoutNoticePipelineOwner: pipelineOwner,
    deprecatedDoNotUseWillBeRemovedWithoutNoticeRenderView: renderView,
    child: rootWidget,
  );
}

late final RenderView renderView =
    _ReusableRenderView(view: platformDispatcher.implicitView!);

class _ReusableRenderView extends RenderView {
  // ...
}
```

这里可以得到一个结论：

1. 从创建先后顺序来说，`RenderView` 早于 `RootWidget` 和 `RootElement`。
2. 但从理解框架主流程的角度，分析重点依然应该放在 `RootWidget -> RootElement -> updateChild()` 这条链上。

因为 UI 树的递归展开，是在这条链路里真正完成的。

# 用一条完整主线重新串起来

如果把三棵树的创建过程压缩成一条清晰的主线，可以写成下面这样：

1. 调用 `runApp(app)`，Flutter 确保 `WidgetsBinding` 初始化完成。
2. 绑定对象把业务根组件包装进 `View`，并调度根节点挂载。
3. 框架再把这个根组件包装成 `RootWidget`。
4. `RootWidget.attach()` 调用 `createElement()` 创建 `RootElement`。
5. `RootElement` 绑定 `BuildOwner`，并执行 `mount()`。
6. `mount()` 内部调用 `_rebuild()`。
7. `_rebuild()` 调用 `updateChild()`，把 `RootWidget.child` 转成子 `Element`。
8. 子 `Element` 继续递归执行相同流程，整棵 `Element` 树逐步建立。
9. 在递归过程中，凡是属于 `RenderObjectWidget / RenderObjectElement` 这条分支的节点，会继续建立对应的 `RenderObject` 树。
10. 最终形成完整的 `Widget` 树、`Element` 树和 `RenderObject` 树协同工作。

# 最容易混淆的几个点

## `Widget` 不是长期维护状态的核心

`Widget` 更像一份不可变配置，真正常驻并参与更新流程的是 `Element`。

## `Element` 才是三棵树之间的枢纽

`Widget` 通过 `Element` 落地为运行时结构，`RenderObject` 也通过 `Element` 被创建和维护，所以理解 Flutter 框架时，`Element` 是最值得重点掌握的一层。

## `RenderView` 虽然创建更早，但不影响对主流程的理解

从源码时序看，`RenderView` 的确更早准备好；但应用树真正“从无到有”地展开，关键还是 `RootWidget`、`RootElement` 以及 `updateChild()` 的递归构建过程。

# 一页式记忆

最后可以把整套流程记成下面这几句话：

> `runApp()` 不是直接创建整棵树，而是把入口 `Widget` 交给 `WidgetsBinding`。

> `WidgetsBinding` 会先包装出 `RootWidget`，再由 `RootWidget` 创建 `RootElement`。

> `RootElement.mount()` 中通过 `_rebuild()` 调用 `updateChild()`，从根开始递归创建并维护整棵 `Element` 树。

> `RenderObject` 树只对应 `Element` 树中的 `RenderObjectElement` 分支，由它们继续向下建立。

如果只保留一个最核心的结论，那就是：

> Flutter 三棵树的创建关键，不在于“先有哪棵树”，而在于：
> RootWidget 创建 RootElement，
> RootElement 通过 updateChild() 递归展开整棵 Element 树，
> RenderObject 树再由其中的 RenderObjectElement 分支继续建立。
