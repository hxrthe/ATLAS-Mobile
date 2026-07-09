import 'package:flutter/material.dart';

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'PRESCRIPTIVE ASSESSMENT ANALYTICS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8391A1), letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Class Performance Trend', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 24),
                // Mock Chart Area
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(child: Icon(Icons.bar_chart, size: 64, color: Color(0xFF8391A1))),
                ),
                const SizedBox(height: 16),
                const Text('Actionable Insight:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B1515))),
                const SizedBox(height: 4),
                const Text('Students are struggling with module parameters. Consider generating a targeted summative quiz.', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}