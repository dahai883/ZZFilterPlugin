# ZZFilterPlugin v8 修正版

修复 v8 GitHub Actions 编译失败：`ZZRuntimeFiltering.m` 使用了运行时诊断变量但没有声明，导致 `use of undeclared identifier`。

本版补齐这些变量的静态声明，并让 Hook 失败计数在主要失败分支递增。

仍保持 v8 的稳定性策略：
- 只处理类自己声明的候选 selector；
- 不提升继承方法为类方法；
- 不 Hook `requestDataWithPageIndex:`；
- 只 Hook void 返回的候选方法；
- 不涉及宿主 App 的激活、授权、许可证或安全校验。
