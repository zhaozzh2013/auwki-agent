# Linux 构建用本地补丁记录（2026-08-27 迁移到 CachyOS）

`flutter build linux --release` 在 clang 22 + -Werror 下，两个上游插件源码编译失败。
已直接修改 pub cache 中的插件源码（本机生效，不修改项目代码）：

1. `hotkey_manager_linux-0.2.0/linux/hotkey_manager_linux_plugin.cc`
   - 两处 `const char* identifier/keystring;` 未初始化（查找未命中时为未定义行为）
   - 修改为 `= "";`（`-Wsometimes-uninitialized` 修复）

2. `tray_manager-0.2.4/linux/tray_manager_plugin.cc`
   - `app_indicator_new()` 在 libayatana-appindicator 0.6.0 弃用（`-Wdeprecated-declarations`）
   - 文件头部插入：
     ```cpp
     #if defined(__clang__)
     #pragma clang diagnostic ignored "-Wdeprecated-declarations"
     #endif
     ```

注意：重新 `flutter pub get` 会从 pub.dev 重新解压覆盖这些文件，
需重放本补丁（sed 命令见上）。升级插件版本后需重新评估。

## 依赖库（用户级工具链，无 root）

系统缺以下 pkg-config 模块时，从 Arch 镜像下载预编译包解压到
`/home/zzh/项目/toolchain/prefix`（见 `toolchain/fetch-arch-pkgs.sh`）：
libayatana-appindicator、libayatana-indicator、libdbusmenu-glib、
libdbusmenu-gtk3、ayatana-ido；keybinder3 为自编译（同目录）。
.pc 文件中的 `/usr` 前缀需 sed 替换为 prefix 路径。
## 键盘断言崩溃规避（2026-08-27）

Flutter 引擎已知 bug（上游 issue #150326 等）：GTK 收到"孤儿 key release"
（无对应按下记录，常发生于按着键切换窗口/输入法组合键）时，
FlKeyEmbedderResponder 断言 `lookup_hash_table(pressing_records) != 0` 崩溃
（日志出现 `CRITICAL: update_pressing_state ... assertion failed`）。

规避：`linux/runner/my_application.cc` 挂载 key-press/release 事件过滤器，
维护已按下键集合；孤儿 release 直接拦截（return TRUE）不传给引擎。
正常按键行为不变。
