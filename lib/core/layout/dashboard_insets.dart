import 'package:flutter/widgets.dart';

/// Bottom nav content height (not including the home-indicator inset).
const double kDashboardNavBarHeight = 64.0;

/// How far the center scanner FAB sits above the nav bar top edge.
const double kDashboardFabOverhang = 36.0;

/// Scroll padding so tab content clears the docked nav + scanner FAB when
/// [Scaffold.extendBody] is true.
EdgeInsets dashboardScrollPadding(
  BuildContext context, {
  double left = 24,
  double top = 24,
  double right = 24,
}) {
  final bottomInset = MediaQuery.paddingOf(context).bottom;
  final bottom = kDashboardNavBarHeight + bottomInset + kDashboardFabOverhang;
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}
