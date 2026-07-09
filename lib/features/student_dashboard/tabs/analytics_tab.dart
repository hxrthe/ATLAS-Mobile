import 'package:flutter/material.dart';

class StudentProfileScreen extends StatelessWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryRed = const Color(0xFF8B1515);
    final Color darkRed = const Color(0xFF5A0C0C);
    final Color textGrey = const Color(0xFF8391A1);
    final Color backgroundGrey = const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundGrey,
      appBar: AppBar(
        backgroundColor: backgroundGrey,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'STUDENT MATRIX ANALYTICS',
          style: TextStyle(
            color: Colors.black38,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_active, color: Color(0xFF8B1515)),
                onPressed: () {
                  // TODO: Open the Live Alerts Channel (Image 2)
                },
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  height: 8,
                  width: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Profile Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACADEMIC PROFILE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textGrey, letterSpacing: 0.5),
                    ),
                    const Text(
                      'Jasmin Esperida',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1E232C)),
                    ),
                    Text(
                      '24-21400 • BSIT BA 3301',
                      style: TextStyle(fontSize: 13, color: textGrey),
                    ),
                  ],
                ),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=5'),
                    ),
                    Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E676),
                        shape: BoxShape.circle,
                        border: Border.all(color: backgroundGrey, width: 2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 2. Global Outcome Attainment Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryRed, darkRed],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: primaryRed.withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'Global Outcome Attainment',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '78% Mastery',
                        style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress Bar
                  Stack(
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Container(
                        height: 8,
                        width: MediaQuery.of(context).size.width * 0.55, // 78% representation
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text(
                    'Calculated across 14 tracked outcomes (SDG 4 & SDG 9 aligned)',
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 24),

                  // Grade Metrics
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: const [
                          Text('A+', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          Text('CURRENT GRADE', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                      Container(height: 40, width: 1, color: Colors.white.withOpacity(0.2)),
                      Column(
                        children: const [
                          Text('1.25', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                          Text('GWA EQUIVALENT', style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 0.5)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // 3. Recent Competency Gains Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RECENT COMPETENCY GAINS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
                ),
                GestureDetector(
                  onTap: () {
                    // TODO: Open Spider-Map Analytics (Image 3)
                  },
                  child: Row(
                    children: [
                      Text(
                        'View Spider-Map',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primaryRed),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: primaryRed),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Competency List
            _buildCompetencyCard(
              badge: 'AN',
              badgeColor: const Color(0xFF00E676).withOpacity(0.15),
              badgeTextColor: const Color(0xFF00C853),
              status: 'Analysis Level Unlocked',
              statusColor: const Color(0xFF00C853),
              title: 'CICS-302 Outcome 3:',
              subtitle: 'Normalization & Index Tuning',
            ),
            const SizedBox(height: 12),
            _buildCompetencyCard(
              badge: 'AP',
              badgeColor: Colors.blue.shade50,
              badgeTextColor: Colors.blue.shade700,
              status: 'Application Level Confirmed',
              statusColor: Colors.blue.shade700,
              title: 'CICS-301 Outcome 1:',
              subtitle: 'Repository Management',
            ),
            const SizedBox(height: 12),
            _buildCompetencyCard(
              badge: 'FD',
              badgeColor: primaryRed.withOpacity(0.08),
              badgeTextColor: primaryRed,
              status: 'Foundation Level Mastered',
              statusColor: primaryRed,
              title: 'CICS-202 Outcome 4:',
              subtitle: 'Relational Query Structures',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompetencyCard({
    required String badge,
    required Color badgeColor,
    required Color badgeTextColor,
    required String status,
    required Color statusColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                badge,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: badgeTextColor),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}