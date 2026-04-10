# Flutter Embedder 源码解析

现在我需要分析 Embedder 的启动流程，我给你一篇参考文章，你帮我将流程梳理出来。需要注意的是，文章中使用的 Flutter 版本可能比较老，有些代码会有变动，所以请关注源码中的有关迁移的注释。

在分析过程中，需要将过程记录在此markdown文件中，并将当前 Flutter 源码与文章中不一致的地方标记出来。

记录的过程中，需要将源代码文件以链接的形式记录，比如'[io/flutter/app/FlutterApplication.java](io/flutter/app/FlutterApplication.java)'，点击即可跳转对应文件。

文章链接如下：[https://vimerzhao.top/articles/flutter-source-code-analyze-3/](https://vimerzhao.top/articles/flutter-source-code-analyze-3/)

---

## 启动流程梳理与源码对比分析

根据提供的文章，Android Embedder 的启动流程最初分为 `FlutterApplication` 阶段和 `FlutterActivity` 阶段。但在当前较新版本的 Flutter 源码中，第一阶段的逻辑发生了显著的变化（V1 嵌入层已被移除/废弃）。

### 1. 初始化入口的变化（`FlutterApplication` 已废弃）

- **文章描述**：整个启动流程由 `FlutterApplication#onCreate` 发起，其内部主动调用 `FlutterLoader#startInitialization` 异步加载 Engine，执行准备工作。
- **当前源码差异**：
  在最新的源码中，[io/flutter/app/FlutterApplication.java](io/flutter/app/FlutterApplication.java) 已被标记为 `@Deprecated`，并且内部变为了空实现。根据其注释：`Empty implementation of the Application class, provided to avoid breaking older Flutter projects.` 它提示这只是为了兼容老项目，V1 Android Embedding 已被完全移除，推荐开发者直接使用 `android.app.Application`。
  **现在的 `FlutterLoader` 初始化逻辑已经后移至 `FlutterEngine` 构造阶段自动触发**，或者由开发者在自定义 `Application` 或者 `Activity` 启动时提前调用。

### 2. Activity 的创建与代理机制（`FlutterActivity` 与 `Delegate`）

- **文章与源码一致点**：[io/flutter/embedding/android/FlutterActivity.java](io/flutter/embedding/android/FlutterActivity.java) 依然是启动引擎的主要入口。在它的 `onCreate` 方法中，创建了一个 [io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java](io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java) 作为实际的业务代理。
- `FlutterActivity` 会依次调用代理 Delegate 相关生命周期的钩子函数，如 `onAttach`、`onRestoreInstanceState`、`onCreateView` (这是在源码的 `setContentView` 中主动调用 `createFlutterView()` 内部调用的) 等。

### 3. `FlutterEngine` 的初始化与准备

- **流程**：在代理 [io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java](io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java) 的 `onAttach` 中，判断当前如果是全新的启动，则调用内部方法 `setUpFlutterEngine` 方法去新建或者从缓存组中提取出 `FlutterEngine` 对象。
- **与当前源码差异**：在新建 [io/flutter/embedding/engine/FlutterEngine.java](io/flutter/embedding/engine/FlutterEngine.java) 时，其构造方法不仅创建了与 Native 交互的近乎 20 种 Channel 对象（在现代源码中新增了很多例如 `SpellCheckChannel`, `ProcessTextChannel`），更重要的是如果发现底层的 `FlutterJNI` 还未附加 (`!flutterJNI.isAttached()`)，会自动调用：
  ```java
  flutterLoader.startInitialization(context.getApplicationContext());
  flutterLoader.ensureInitializationComplete(context, dartVmArgs);
  ```

  这意味着，文章第一步中必须在 `Application` 做的底层so库、资源加载准备阶段，现在推迟到 Engine 创建周期来执行了。
- **Native 绑定**：`FlutterEngine` 构造最后阶段，调用内部的 `attachToJni()` 真正连接到底层 C++ 层。

### 4. 视图层挂载（完全舍弃了 `FlutterSplashView`）

- **文章描述**：在 `FlutterActivityAndFragmentDelegate#onCreateView` 中，不仅会根据渲染模式创建 `FlutterSurfaceView`/`FlutterTextureView`，并且会包裹在一层 `FlutterSplashView` 中以处理启动加载页的过渡。
- **当前源码差异**：阅读现代版本的 `FlutterActivity.java` 类的注释可知，Flutter 相关的 "splash screen" 在 Flutter 2.5 之后已经彻底废弃不用了。官方推荐的做法是利用原生的 Android 系统主题实现无缝衔接 (`switchLaunchThemeForNormalTheme()`)。
  因此在如今的 [io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java](io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java) `#onCreateView` 的实现中，没有任何 `FlutterSplashView` 相关的代码，创建出来的一个承载组件的引用 `FlutterView` 在被设置为被监控状态且与 `FlutterEngine` (`flutterView.attachToFlutterEngine(flutterEngine)`) 相关联后，就被直接作为子级被放回到 Activity 展示了。

### 5. Dart VM 的启动与入口文件执行

- **文章与源码一致点**：在宿主 Activity 走到 `onStart` 时触发代理 `FlutterActivityAndFragmentDelegate#onStart`。其中调用了核心方法 `doInitialFlutterViewRun()`。该方法内部会：
  - 加载应用的 `initialRoute` (初始路由)，经由 `NavigationChannel` 投递给 Flutter (`setInitialRoute`)。
  - 获取 App Bundle 的入口与方法名（由于迁移，现在还能拿到库的 URI），实例化为 `DartExecutor.DartEntrypoint` 对象。
  - 最后发起最本质的调用 [io/flutter/embedding/engine/FlutterEngine.java](io/flutter/embedding/engine/FlutterEngine.java) 中的 `dartExecutor.executeDartEntrypoint(...)` 来正式告知底层执行 Dart 层 UI 并最终启动业务代码页面过程。

### 6. 生命周期的通知

- **流程**：当 Android 引擎收到系统各种可见性事件比如 `onResume` 的时候，就会通过 [io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java](io/flutter/embedding/android/FlutterActivityAndFragmentDelegate.java) 继续由之前 `FlutterEngine` 创建时缓存好的专门处理生命周期相关事务的通道 `getLifecycleChannel()` 去执行 `appIsResumed()`。相应的 `onPause` 等也会触发诸如 `appIsInactive()`、`appIsPaused()` 的消息，这些设计大体上在这些年间维持了一致。
