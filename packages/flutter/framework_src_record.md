# Flutter Framework 层源码解析

我正在分析Flutter Framework源码，我需要你帮我完成【任务】。

【任务】完成【Framework启动流程】，我会给你大概流程和相关文件，你模仿我完成的“runApp”来完成后续流程，你可以自行完善内容。注意需要链接到相关文件，以及将关键代码使用引用贴在下方。

## Framework启动流程

[runApp()](lib/src/widgets/binding.dart)

> ```dart
> void runApp(Widget app) {
> final WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
>   _runWidget(binding.wrapWithDefaultView(app), binding, 'runApp');
> }
> ```

静态方法[ensureInitialized()](lib/src/widgets/binding.dart)，检查是否已经初始化，如果没有会调用当前类的构造方法。

当前类继承自[BindingBase](lib/src/foundation/binding.dart)，其中的 `initInstances()` 由各个 binding 混入类实现。

各个混入类构成责任链，依次调用混入类中的 `initInstances()` ，[GestureBinding](lib/src/gestures/binding.dart)
