import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../models/dashboard_models.dart';

class ReportsTab extends StatelessWidget {
  final List<Assessment> assessments;
  final Future<void> Function() onRefresh;

  const ReportsTab({super.key, required this.assessments, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryRed = const Color(0xFF8B1515);
    final headerColor = isDark ? Colors.white : primaryRed;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade700;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: onRefresh,
        color: primaryRed,
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          children: [
            Text('Assessment Analytics', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: headerColor)),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(child: _buildMetricCard(isDark, 'Pending Scans', '${assessments.length}', Icons.document_scanner, const Color(0xFFD4811B), textColor, subtitleColor)),
                const SizedBox(width: 16),
                Expanded(child: _buildMetricCard(isDark, 'Avg. Score', '--%', Icons.analytics, const Color(0xFF00E676), textColor, subtitleColor)),
              ],
            ),
            const SizedBox(height: 24),

            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Class Performance Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                      const SizedBox(height: 8),
                      Text('Data will populate after initial exam scans.', style: TextStyle(color: subtitleColor, fontSize: 12)),
                      const SizedBox(height: 32),
                      Center(child: Icon(Icons.show_chart, size: 80, color: isDark ? Colors.white24 : Colors.black12)),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(bool isDark, String title, String value, IconData icon, Color color, Color textColor, Color subtitleColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 16),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 4),
              Text(title, style: TextStyle(color: subtitleColor, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}