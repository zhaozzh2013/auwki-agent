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
    final child = super.visitElementAfter(element, preferredStyle);

    return Stack(
      children: [
        if (child != null) child,
        Positioned(
          top: 4,
          right: 4,
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
      ],
    );
  }
}
