import 'package:flutter/material.dart';

/// 全局 SnackBar 通道（供无 BuildContext 的组件使用）。
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();
