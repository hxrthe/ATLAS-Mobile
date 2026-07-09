import 'package:flutter/material.dart';

class StudentCoursesTab extends StatelessWidget {
  const StudentCoursesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final Color primaryRed = const Color(0xFF8B1515);
    final Color textGrey = const Color(0xFF8391A1);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'ENROLLED COURSES',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),

          _buildCourseCard(
            code: 'CICS-302',
            title: 'Web Systems & Technologies',
            instructor: 'Dr. Hearty Delacion',
            color: primaryRed,
          ),
          const SizedBox(height: 12),
          _buildCourseCard(
            code: 'CICS-301',
            title: 'Software Engineering',
            instructor: 'Noe Gonzales',
            color: Colors.blue.shade700,
          ),
          const SizedBox(height: 12),
          _buildCourseCard(
            code: 'CICS-202',
            title: 'Database Systems',
            instructor: 'Dr. Hearty Delacion',
            color: const Color(0xFFD4811B),
          ),
          const SizedBox(height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UPCOMING EXAMS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textGrey, letterSpacing: 0.5),
              ),
              const Icon(Icons.calendar_month, color: Color(0xFF8391A1), size: 18),
            ],
          ),
          const SizedBox(height: 16),

          _buildDeadlineCard(
            title: 'Midterm Examination',
            course: 'CICS-302',
            date: 'Tomorrow, 9:00 AM',
            isUrgent: true,
          ),
          const SizedBox(height: 12),
          _buildDeadlineCard(
            title: 'Summative Quiz 3',
            course: 'CICS-202',
            date: 'Friday, 2:30 PM',
            isUrgent: false,
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard({required String code, required String title, required String instructor, required Color color}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
                  const Icon(Icons.more_horiz, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(instructor, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('View Syllabus'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color.withOpacity(0.3)),
                  minimumSize: const Size(double.infinity, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeadlineCard({required String title, required String course, required String date, required bool isUrgent}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUrgent ? const Color(0xFF8B1515).withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isUrgent ? const Color(0xFF8B1515).withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(course, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(date, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isUrgent ? const Color(0xFF8B1515) : Colors.black87)),
              if (isUrgent) const Text('Due Soon', style: TextStyle(fontSize: 10, color: Color(0xFF8B1515), fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}