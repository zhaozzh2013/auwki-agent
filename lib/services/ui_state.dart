import 'package:flutter/foundation.dart';

/// 轻量全局 UI 状态（C12 工具气泡折叠等）。
class UiState {
  UiState._();

  /// C12：全部工具气泡一键折叠/展开。
  static final ValueNotifier<bool> collapseTools = ValueNotifier(false);

  static void toggleCollapseTools() {
    collapseTools.value = !collapseTools.value;
  }
}
