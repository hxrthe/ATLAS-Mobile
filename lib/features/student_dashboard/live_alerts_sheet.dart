import 'package:flutter/material.dart';

class LiveAlertsSheet extends StatelessWidget {
  const LiveAlertsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const Color darkBackground = Color(0xFF16181D);
    const Color cardBackground = Color(0xFF22252A);
    const Color primaryRed = Color(0xFF8B1515);
    const Color textGrey = Color(0xFF8391A1);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85, // Takes up 85% of the screen
      decoration: const BoxDecoration(
        color: darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Area
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
                      child: Icon(Icons.notifications, color: Theme.of(context).colorScheme.surfaceContainer),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LIVE ALERTS CHANNEL',
                          style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
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
                    foregroundColor: Theme.of(context).colorScheme.surfaceContainer,
                    side: BorderSide(color: Theme.of(context).colorScheme.surfaceContainer),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Clear all', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),

          Divider(color: Theme.of(context).colorScheme.surfaceContainer, height: 1),

          // 2. Scrollable Alerts List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Newest Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('NEWEST', style: TextStyle(color: primaryRed, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    Container(height: 6, width: 6, decoration: const BoxDecoration(color: primaryRed, shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 16),

                // Newest Alert Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: const Border(left: BorderSide(color: primaryRed, width: 4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('ASSESSMENT PROCESSED', style: TextStyle(color: primaryRed, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          Text('Just now', style: TextStyle(color: textGrey, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'CICS-302 Web Systems Quiz 4',
                        style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 13, height: 1.4),
                          children: [
                            TextSpan(text: 'Your evaluation sheet has been processed. Achievement unlocked: '),
                            TextSpan(text: 'High-level Database Optimization mastery.', style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.surfaceContainer)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const CircleAvatar(radius: 12, backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=33')),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: primaryRed, shape: BoxShape.circle),
                            child: Icon(Icons.emoji_events, color: Theme.of(context).colorScheme.surfaceContainer, size: 12),
                          ),
                          const SizedBox(width: 8),
                          const Text('Earned +50 XP', style: TextStyle(color: textGrey, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Historical Feed Section
                const Text('HISTORICAL FEED', style: TextStyle(color: textGrey, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                const SizedBox(height: 16),

                // Historical Card 1
                _buildHistoricalCard(
                  context: context, // <--- Add this line!
                  category: 'System',
                  time: '2 hours ago',
                  title: 'Maintenance',
                  body: 'Server down.',
                ),
                const SizedBox(height: 12),

                // Historical Card 2
                _buildHistoricalCard(
                  context: context, // <--- Add this line!
                  category: 'System',
                  time: '2 hours ago',
                  title: 'Maintenance',
                  body: 'Server down.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalCard({required BuildContext context, required String category, required String time, required String title, required String body}) {
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
              Text(category, style: const TextStyle(color: Color(0xFF8391A1), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Text(time, style: const TextStyle(color: Color(0xFF8391A1), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: Theme.of(context).colorScheme.surfaceContainer, fontSize: 13, height: 1.4)),
        ],
      ),
    );
  }
}