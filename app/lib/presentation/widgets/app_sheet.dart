import 'package:flutter/material.dart';
import '../../core/theme/app_space.dart';
import '../../core/theme/app_typography.dart';

/// Единый заголовок нижней шторки (ручка 32×4 как в теме, заголовок, подзаголовок и доп. действие).
class AppSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showHandle;
  final bool showClose;
  final EdgeInsetsGeometry? padding;

  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.showHandle = false,
    this.showClose = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x2,
            Space.x4,
            Space.x3,
          ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHandle) ...[
            Center(
              child: Container(
                width: Space.x8,
                height: Space.x1,
                decoration: BoxDecoration(
                  color: p.sheetHandle,
                  borderRadius: Radii.chipAll,
                ),
              ),
            ),
            const SizedBox(height: Space.x3),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppTypography.title.copyWith(color: p.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Space.x2),
                trailing!,
              ],
              if (showClose && Navigator.canPop(context)) ...[
                const SizedBox(width: Space.x1),
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  tooltip: 'Закрыть',
                  icon: Icon(
                    Icons.close_rounded,
                    size: IconSizes.md,
                    color: p.inkSecondary,
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: Space.x1),
            Text(
              subtitle!,
              style: AppTypography.bodySm.copyWith(color: p.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Единый каркас нижней шторки: ограничитель ширины (640 dp), заголовок,
/// прокручиваемая область, уведомление поверх шторки и закреплённый низ (`SafeArea`).
class AppSheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? headerExtra;
  final Widget child;
  final Widget? footer;
  final double maxHeightFactor;
  final bool scrollable;
  final bool showHandle;
  final bool showClose;
  final String? noticeText;
  final bool noticeIsError;
  final EdgeInsetsGeometry? bodyPadding;

  const AppSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.headerExtra,
    required this.child,
    this.footer,
    this.maxHeightFactor = 0.9,
    this.scrollable = true,
    this.showHandle = false,
    this.showClose = false,
    this.noticeText,
    this.noticeIsError = false,
    this.bodyPadding,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final mq = MediaQuery.of(context);
    final textScale = mq.textScaler.scale(1.0);
    final basePadding = bodyPadding ??
        const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4);
    final resolvedPadding = footer == null && mq.viewInsets.bottom > 0
        ? basePadding.add(EdgeInsets.only(bottom: mq.viewInsets.bottom))
        : basePadding;
    final maxH = mq.size.height * maxHeightFactor;
    final scrollEntireSheet = AppLayout.isTightSheet(mq.size.height, textScale);

    final headerWidget = AppSheetHeader(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      showHandle: showHandle,
      showClose: showClose,
    );

    final noticeWidget = noticeText != null && noticeText!.isNotEmpty
        ? Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.x4,
                Space.x2,
                Space.x4,
                0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.x3,
                  vertical: Space.x2,
                ),
                decoration: BoxDecoration(
                  color: noticeIsError ? p.dangerSoft : p.accentSoft,
                  borderRadius: Radii.fieldAll,
                ),
                child: Row(
                  children: [
                    Icon(
                      noticeIsError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: IconSizes.btn,
                      color: noticeIsError ? p.danger : p.accent,
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(
                      child: Text(
                        noticeText!,
                        style: AppTypography.bodySm.copyWith(
                          color: noticeIsError ? p.danger : p.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        : null;

    final footerWidget = footer != null
        ? Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(
                top: BorderSide(color: p.divider, width: 1),
              ),
            ),
            padding: EdgeInsets.fromLTRB(
              Space.x4,
              Space.x3,
              Space.x4,
              Space.x4 + mq.viewInsets.bottom,
            ),
            child: footer!,
          )
        : null;

    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: Space.maxWidth,
          maxHeight: maxH,
        ),
        child: Material(
          color: p.surface,
          borderRadius: Radii.sheetTop,
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: scrollEntireSheet
                ? SingleChildScrollView(
                    padding: EdgeInsets.only(
                      bottom: footer == null ? mq.viewInsets.bottom : 0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        headerWidget,
                        if (headerExtra != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Space.x4,
                              0,
                              Space.x4,
                              Space.x3,
                            ),
                            child: headerExtra!,
                          ),
                        Divider(height: 1, thickness: 1, color: p.divider),
                        Padding(padding: basePadding, child: child),
                        if (noticeWidget != null) noticeWidget,
                        if (footerWidget != null) footerWidget,
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      headerWidget,
                      if (headerExtra != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.x4,
                            0,
                            Space.x4,
                            Space.x3,
                          ),
                          child: headerExtra!,
                        ),
                      Divider(height: 1, thickness: 1, color: p.divider),
                      Flexible(
                        fit: FlexFit.loose,
                        child: scrollable
                            ? SingleChildScrollView(
                                padding: resolvedPadding,
                                child: child,
                              )
                            : Padding(
                                padding: resolvedPadding,
                                child: child,
                              ),
                      ),
                      if (noticeWidget != null) noticeWidget,
                      if (footerWidget != null) footerWidget,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
