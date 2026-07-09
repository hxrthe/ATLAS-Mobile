import 'package:flutter/material.dart';

class CoursesTab extends StatelessWidget {
  const CoursesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'COURSE MANAGEMENT',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF8391A1), letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          _buildCourseCard('CICS-302', 'Web Systems & Technologies', true),
          const SizedBox(height: 12),
          _buildCourseCard('CICS-301', 'Software Engineering', true),
          const SizedBox(height: 12),
          _buildCourseCard('CICS-202', 'Database Systems', false),
          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.auto_awesome),
            label: const Text('LLM Syllabus-to-Exam Generation', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B1515),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(String code, String title, bool isActive) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? const Color(0xFF8B1515) : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: isActive ? const Color(0xFF8B1515).withOpacity(0.1) : Colors.grey.shade100,
          child: Icon(Icons.book, color: isActive ? const Color(0xFF8B1515) : Colors.grey),
        ),
        title: Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(title, style: const TextStyle(fontSize: 13, color: Color(0xFF8391A1))),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
      ),
    );
  }
}