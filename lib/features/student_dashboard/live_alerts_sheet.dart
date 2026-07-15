import 'package:flutter/material.dart';

class LiveAlertsSheet extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;

  const LiveAlertsSheet({super.key, this.alerts = const []});

  @override
  Widget build(BuildContext context) {
    const Color darkBackground = Color(0xFF16181D);
    const Color primaryRed = Color(0xFF8B1515);
    const Color textGrey = Color(0xFF8391A1);

    final newestAlert = alerts.isNotEmpty ? alerts.first : null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryRed,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.notifications, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIVE ALERTS CHANNEL',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                        Text(
                          'System Notifications',
                          style: TextStyle(color: textGrey, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('NEWEST', style: TextStyle(color: primaryRed, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                  ],
                ),
                const SizedBox(height: 16),

                if (newestAlert != null)
                  _buildNewestCard(newestAlert)
                else
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No recent activity.', style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ),

                if (alerts.length > 1) ...[
                  const SizedBox(height: 32),
                  const Text('HISTORICAL FEED', style: TextStyle(color: textGrey, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                  const SizedBox(height: 16),
                  for (int i = 1; i < alerts.length && i < 20; i++) ...[
                    if (i > 1) const SizedBox(height: 12),
                    _buildHistoricalCard(alerts[i]),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewestCard(Map<String, dynamic> alert) {
    final code = alert['course_code'] ?? '';
    final name = alert['template_name'] ?? 'Unknown';
    final score = alert['score'] ?? 'N/A';
    final isPassed = alert['is_passed'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF22252A),
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: isPassed ? const Color(0xFF00E676) : const Color(0xFF8B1515), width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ASSESSMENT GRADED', style: TextStyle(color: Color(0xFF8B1515), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(_timeAgo(alert['created_at'] ?? ''), style: const TextStyle(color: Color(0xFF8391A1), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$code $name',
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Score: $score — ${isPassed ? "PASSED" : "FAILED"}',
            style: TextStyle(color: isPassed ? const Color(0xFF00E676) : Colors.red.shade300, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalCard(Map<String, dynamic> alert) {
    final code = alert['course_code'] ?? '';
    final name = alert['template_name'] ?? 'Unknown';
    final score = alert['score'] ?? 'N/A';
    final isPassed = alert['is_passed'] == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF22252A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('GRADED SCAN', style: const TextStyle(color: Color(0xFF8391A1), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(_timeAgo(alert['created_at'] ?? ''), style: const TextStyle(color: Color(0xFF8391A1), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text('$code — $name', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Result: $score (${isPassed ? "Passed" : "Failed"})',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} mins ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
