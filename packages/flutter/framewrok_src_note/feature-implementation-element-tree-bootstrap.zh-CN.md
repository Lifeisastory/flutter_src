# Element Tree 创建流程实现分析

## 1. 分析范围
- 本次只分析 Flutter 在启动阶段如何创建 `Element Tree`，范围从 `runApp` 进入 framework 开始，到根 `Element` 建立并递归展开到 `View/RawView` 边界为止。
- 本次重点回答：
  - 根 `Element` 是在哪里创建的。
  - 普通 `Element` 是通过什么通用路径一层层创建出来的。
  - `View` 相关节点何时把 Element 侧的创建流程带到 render tree 边界。
- 本次不展开：
  - 完整的 render tree / layer tree 生命周期。
  - 后续帧里的 dirty element rebuild 调度细节。
  - 各具体业务 widget 的 build 内容。
- 项目总体索引入口：`packages/flutter/framewrok_src_note/启动流程与三棵树的创建.md`

## 2. 功能概览
- `Element Tree` 不是在 `runApp` 里一次性直接构造好的，而是先创建根 `RootElement`，再由每个父 `Element` 在自己的 build / rebuild 过程中，通过 `updateChild -> inflateWidget -> createElement -> mount` 这条统一路径递归展开。
- 对启动路径来说，真正的“创建动作”分成两段：
  - 根挂载阶段：`runApp -> attachToBuildOwner -> RootWidget.attach -> RootElement.mount`
  - 递归展开阶段：`RootElement._rebuild` 或 `ComponentElement.performRebuild` 调用 `updateChild`，再一路递归生成子 element
- 当递归展开到 `View -> RawView -> _RawViewInternal` 时，Element Tree 仍按同一套规则继续创建；只是 `_RawViewInternal` 同时也是 `RenderObjectWidget`，于是它的 element 在 mount 时会顺带建立 render tree 根。

## 3. 关键源码入口
- `packages/flutter/lib/src/widgets/binding.dart:1614-1617`
  - `runApp`，启动入口。
- `packages/flutter/lib/src/widgets/binding.dart:1679-1683`
  - `_runWidget`，安排根挂载与 warm-up frame。
- `packages/flutter/lib/src/widgets/binding.dart:1388-1422`
  - `scheduleAttachRootWidget / attachRootWidget / attachToBuildOwner`，把 `RootWidget` 接到 `BuildOwner`。
- `packages/flutter/lib/src/widgets/binding.dart:1714-1750`
  - `RootWidget` 与 `RootWidget.attach`，首次创建 `RootElement` 的直接入口。
- `packages/flutter/lib/src/widgets/binding.dart:1767-1833`
  - `RootElement`，framework 根 element；它通过 `_rebuild` 启动第一轮子节点创建。
- `packages/flutter/lib/src/widgets/framework.dart:3030-3057`
  - `BuildOwner.buildScope`，在受控作用域内执行根挂载和后续 build。
- `packages/flutter/lib/src/widgets/framework.dart:3982-4059`
  - `Element.updateChild`，决定“复用 / 更新 / 销毁 / 新建”子 element。
- `packages/flutter/lib/src/widgets/framework.dart:4556-4589`
  - `Element.inflateWidget`，新建 element 的通用入口。
- `packages/flutter/lib/src/widgets/framework.dart:4328-4360`
  - `Element.mount`，把新 element 接入树并继承 owner / buildScope。
- `packages/flutter/lib/src/widgets/framework.dart:5775-5860`
  - `ComponentElement.mount / _firstBuild / performRebuild`，普通组件型 element 如何递归展开子树。
- `packages/flutter/lib/src/widgets/framework.dart:7039-7042`
  - `RootElementMixin.assignOwner`，给根 element 绑定 `BuildOwner` 和根级 `BuildScope`。
- `packages/flutter/lib/src/widgets/view.dart:270-287`
  - `View.build`，把用户 child 继续包装进 `RawView`。
- `packages/flutter/lib/src/widgets/view.dart:370-382`
  - `RawView.build`，继续下钻到 `_RawViewInternal`。
- `packages/flutter/lib/src/widgets/view.dart:407-518`
  - `_RawViewInternal / _RawViewElement`，Element Tree 进入 view/render 边界的位置。

## 4. 主流程详解
### 4.1 起点：从 `runApp` 到根 widget 挂载
- `runApp` 先确保 `WidgetsFlutterBinding` 已初始化，然后调用 `_runWidget(binding.wrapWithDefaultView(app), binding, 'runApp')`。证据：`packages/flutter/lib/src/widgets/binding.dart:1614-1617`
- `_runWidget` 并不直接创建 element，而是做两件事：
  - `scheduleAttachRootWidget(app)`
  - `scheduleWarmUpFrame()`
  证据：`packages/flutter/lib/src/widgets/binding.dart:1679-1683`
- `scheduleAttachRootWidget` 使用 `Timer.run` 延后执行 `attachRootWidget`。证据：`packages/flutter/lib/src/widgets/binding.dart:1388-1391`
- `attachRootWidget` 会把外部根 widget 再包一层 `RootWidget(debugShortDescription: '[root]', child: rootWidget)`，然后交给 `attachToBuildOwner`。证据：`packages/flutter/lib/src/widgets/binding.dart:1403-1405`
- `attachToBuildOwner` 调用 `widget.attach(buildOwner!, rootElement as RootElement?)`；首次启动时 `rootElement == null`，因此会走创建根 element 的分支。证据：`packages/flutter/lib/src/widgets/binding.dart:1416-1422`

### 4.2 根节点创建：`RootWidget.attach`
- `RootWidget.attach` 是首次创建 `RootElement` 的直接入口。首次启动时它按这个顺序执行：
  1. `owner.lockState(...)`
  2. `element = createElement()`
  3. `element!.assignOwner(owner)`
  4. `owner.buildScope(element!, () { element!.mount(null, null); })`
  证据：`packages/flutter/lib/src/widgets/binding.dart:1736-1745`
- 这里的两个关键点：
  - `createElement()` 把 `RootWidget` 实例化成 `RootElement`。证据：`packages/flutter/lib/src/widgets/binding.dart:1726-1728`
  - `assignOwner(owner)` 不只是存一个字段，它还为根 element 建立根级 `BuildScope`。证据：`packages/flutter/lib/src/widgets/framework.dart:7039-7042`
- `owner.buildScope(...)` 的作用是把挂载和 build 放进受控更新作用域，避免 build 过程无序递归扩张。证据：`packages/flutter/lib/src/widgets/framework.dart:3030-3057`

### 4.3 根 element 如何启动第一轮递归创建
- `RootElement.mount` 先走 `super.mount(parent, newSlot)`，完成 element 接树的通用初始化，然后马上调用 `_rebuild()`。证据：`packages/flutter/lib/src/widgets/binding.dart:1788-1793`
- `super.mount` 对所有 element 都会做以下事情：
  - 记录 `_parent`
  - 写入 `_slot`
  - 把生命周期置为 `active`
  - 若有父节点则继承 `owner` 与 `buildScope`
  - 注册 `GlobalKey`
  证据：`packages/flutter/lib/src/widgets/framework.dart:4328-4360`
- `RootElement._rebuild()` 的核心只有一行：
  - `_child = updateChild(_child, (widget as RootWidget).child, null);`
  证据：`packages/flutter/lib/src/widgets/binding.dart:1820-1823`
- 这意味着根 element 自己并不直接 `new` 子 element；它只是把“当前 child widget 应该如何映射为 child element”这个问题交给 `updateChild` 处理。

### 4.4 通用创建链：`updateChild -> inflateWidget -> createElement -> mount`
- `Element.updateChild` 是整个 Element Tree 创建/更新的总闸门。对启动首帧来说，`child == null`，因此会直接走：
  - `newChild = inflateWidget(newWidget, newSlot);`
  证据：`packages/flutter/lib/src/widgets/framework.dart:3982-4059`
- `Element.inflateWidget` 是“从 widget 生成 element”的统一入口。对首次创建分支，它会执行：
  1. `newWidget.createElement()`
  2. `newChild.mount(this, newSlot)`
  证据：`packages/flutter/lib/src/widgets/framework.dart:4569-4589`
- 这条链解释了 Element Tree 的基本生成规则：
  - 父 element 不关心子节点具体是 `StatelessElement`、`StatefulElement` 还是 `RenderObjectElement`
  - 父 element 只调用 `updateChild`
  - 真正的新建工作通过多态落到 `widget.createElement()`
  - 建好后再通过 `mount` 接回树里

## 5. 关键实现细节
- `RootElementMixin.assignOwner` 只发生在根节点，普通节点是在 `Element.mount` 里从父节点继承 `_owner` 和 `_parentBuildScope`。证据：
  - `packages/flutter/lib/src/widgets/framework.dart:7039-7042`
  - `packages/flutter/lib/src/widgets/framework.dart:4346-4352`
- `updateChild` 在首次挂载时之所以重要，是因为它统一了“首次创建”和“后续更新”两种场景。首次启动走 `child == null` 分支，后续 rebuild 则可能走：
  - `child.widget == newWidget`：直接复用
  - `Widget.canUpdate(...)`：原 element 原地 update
  - 否则：`deactivateChild` 后重新 `inflateWidget`
  证据：`packages/flutter/lib/src/widgets/framework.dart:3990-4054`
- `inflateWidget` 在创建前会先尝试通过 `GlobalKey` 复用 inactive element；只有没有可复用对象时才执行 `newWidget.createElement()`。这说明“创建 element”并不是绝对总发生，而是受 key 复用策略影响。证据：`packages/flutter/lib/src/widgets/framework.dart:4570-4575`
- 推断：从架构上看，Flutter 把“结构决策”放在 `updateChild`，把“实例化动作”放在 `inflateWidget/createElement`，把“接树动作”放在 `mount`。这样根节点、普通组件节点、view 边界节点都能复用同一套机制。

## 6. 普通组件是怎样继续把树展开的
- 根节点之后，最常见的路径是 `ComponentElement`。它在 `mount` 完成通用接树后会立即执行 `_firstBuild()`。证据：`packages/flutter/lib/src/widgets/framework.dart:5789-5795`
- `_firstBuild()` 直接调用 `rebuild()`，最终会落到 `performRebuild()`。证据：`packages/flutter/lib/src/widgets/framework.dart:5797-5800`
- `ComponentElement.performRebuild()` 的核心顺序是：
  1. `built = build()`
  2. `super.performRebuild()` 清 dirty 标记
  3. `_child = updateChild(_child, built, slot)`
  证据：`packages/flutter/lib/src/widgets/framework.dart:5810-5860`
- 这就是 Element Tree 递归长出来的原因：
  - 每个组件 element 先把当前 widget 配置执行成下一个 widget
  - 再把这个 widget 交给 `updateChild`
  - `updateChild` 必要时继续 `inflateWidget`
  - 新 element 再在自己的 `mount` 里重复同样流程

## 7. 到 `View` 为止发生了什么
- `runApp` 在最外层先用 `wrapWithDefaultView` 把用户根 widget 包成 `View(...)`。证据：`packages/flutter/lib/src/widgets/binding.dart:1359-1380`
- 当递归创建走到 `View` 对应的 element 后，`View.build` 会产出 `RawView(...)`。证据：`packages/flutter/lib/src/widgets/view.dart:270-287`
- `RawView.build` 再继续产出 `_RawViewInternal(...)`。证据：`packages/flutter/lib/src/widgets/view.dart:370-382`
- `_RawViewInternal` 仍然遵循同一套 element 创建规则：
  - `createElement() => _RawViewElement(this)`
  - 随后由父 element 的 `updateChild/inflateWidget` 触发 mount
  证据：`packages/flutter/lib/src/widgets/view.dart:437-443`
- 但 `_RawViewInternal` 同时还是 `RenderObjectWidget`，因此 `_RawViewElement.mount` 在 element 接树后还会做三件 render 侧动作：
  - `_effectivePipelineOwner.rootNode = renderObject`
  - `_attachView()`
  - `_updateChild()`
  证据：`packages/flutter/lib/src/widgets/view.dart:499-505`
- 这里的 `_updateChild()` 说明：即便到了 view/render 边界，Element Tree 的递归展开仍没有停，`_RawViewElement` 自己也还是通过 `updateChild` 去创建其 widget 子树。证据：`packages/flutter/lib/src/widgets/view.dart:478-481`

## 8. 时序总结
1. `runApp(app)` 进入 framework。证据：`packages/flutter/lib/src/widgets/binding.dart:1614-1617`
2. `_runWidget` 安排根挂载。证据：`packages/flutter/lib/src/widgets/binding.dart:1679-1683`
3. `attachRootWidget` 把外部根包装成 `RootWidget`。证据：`packages/flutter/lib/src/widgets/binding.dart:1403-1405`
4. `attachToBuildOwner` 调用 `RootWidget.attach`。证据：`packages/flutter/lib/src/widgets/binding.dart:1416-1422`
5. `RootWidget.attach` 创建 `RootElement`，赋 `BuildOwner`，再在 `buildScope` 中执行 `mount`。证据：`packages/flutter/lib/src/widgets/binding.dart:1736-1745`
6. `RootElement.mount` 调用 `_rebuild()`。证据：`packages/flutter/lib/src/widgets/binding.dart:1788-1793`
7. `RootElement._rebuild` 调用 `updateChild` 处理根 child。证据：`packages/flutter/lib/src/widgets/binding.dart:1820-1823`
8. `updateChild` 在首次创建时转入 `inflateWidget`。证据：`packages/flutter/lib/src/widgets/framework.dart:4055-4059`
9. `inflateWidget` 调用 `newWidget.createElement()`，然后 `newChild.mount(this, newSlot)`。证据：`packages/flutter/lib/src/widgets/framework.dart:4574-4588`
10. 若新 child 是组件型 element，则它在 `mount -> _firstBuild -> performRebuild` 中再次执行 `build + updateChild`。证据：`packages/flutter/lib/src/widgets/framework.dart:5789-5860`
11. 如此递归，直到遇到 `View -> RawView -> _RawViewInternal`。证据：
  - `packages/flutter/lib/src/widgets/view.dart:270-287`
  - `packages/flutter/lib/src/widgets/view.dart:370-382`
12. `_RawViewElement.mount` 一边继续 `updateChild` 展开 element 子树，一边启动 render tree 根。证据：`packages/flutter/lib/src/widgets/view.dart:478-505`

## 9. 边界情况与注意点
- `Element Tree` 的创建不是 `runApp` 直接完成的，而是 `RootWidget.attach` 只负责拉起根，真正的“树扩张”由每层 element 在 build/rebuild 中持续递归完成。
- 根节点和普通节点的 owner 绑定方式不同：
  - 根节点：`assignOwner`
  - 普通节点：`mount` 时从父节点继承
- `updateChild` 不是“只用于更新”的函数，首次创建同样走这里；因此它才是理解 Element Tree 创建流程的中心节点。
- `_RawViewElement` 很容易被误解成“render tree 逻辑”，但它本身仍然是 element；只是它位于 element/render 两棵树的交界处。
- 推断：如果后续你要继续深挖 `StatelessWidget`、`StatefulWidget`、`InheritedWidget` 的 element 创建差异，最值得继续看的不是 `runApp`，而是各 widget 的 `createElement()` 返回哪种 element，以及对应 element 的 `performRebuild()` 有没有特殊逻辑。

## 10. 关键证据
- `packages/flutter/lib/src/widgets/binding.dart:1359-1380`
- `packages/flutter/lib/src/widgets/binding.dart:1388-1422`
- `packages/flutter/lib/src/widgets/binding.dart:1614-1683`
- `packages/flutter/lib/src/widgets/binding.dart:1714-1750`
- `packages/flutter/lib/src/widgets/binding.dart:1767-1833`
- `packages/flutter/lib/src/widgets/framework.dart:3030-3057`
- `packages/flutter/lib/src/widgets/framework.dart:3982-4059`
- `packages/flutter/lib/src/widgets/framework.dart:4328-4360`
- `packages/flutter/lib/src/widgets/framework.dart:4556-4589`
- `packages/flutter/lib/src/widgets/framework.dart:5775-5860`
- `packages/flutter/lib/src/widgets/framework.dart:7039-7042`
- `packages/flutter/lib/src/widgets/view.dart:270-287`
- `packages/flutter/lib/src/widgets/view.dart:370-382`
- `packages/flutter/lib/src/widgets/view.dart:407-518`
