import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

import '../i18n/strings.dart';
import '../theme.dart';

/// 代码块渲染增强（B01）：每个代码块右上角加复制按钮。
class CopyCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final lines = element.textContent.split('\n').toList();
    // 去掉 ```lang 与结尾 ``` 标记行。
    if (lines.isNotEmpty && lines.first.trimLeft().startsWith('```')) {
      lines.removeAt(0);
    }
    if (lines.isNotEmpty && lines.last.trim() == '```') {
      lines.removeLast();
    }
    final code = lines.join('\n').trimRight();

    // 注意 1：不能用 Stack + Positioned —— markdown 块级元素在垂直方向
    // 是无界约束，Positioned 子项会导致 Stack 尺寸计算失败（TransformLayer
    // invalid matrix / 文字堆叠）。Align 是普通子项，布局安全。
    // 注意 2：不要依赖 super.visitElementAfter* —— 其默认实现返回 null，
    // 而本 builder 只要返回非 null 的 widget，flutter_markdown 就会用它
    // 完全替代默认渲染（代码块内容必须由我们自行渲染）。
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.55,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 4, right: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  messenger
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          I18n.t('conv.copy.done'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        duration: const Duration(seconds: 1),
                        backgroundColor: AppColors.surfaceAlt,
                      ),
                    );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.copy,
                        size: 11,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        I18n.t('conv.copy'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
