class Course {
  final int id;
  final String code;
  final String title;

  Course({required this.id, required this.code, required this.title});

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'],
      code: json['code'],
      title: json['title'],
    );
  }
}

class Assessment {
  final int id;
  final String title;
  final String courseCode;
  final String dateDue;
  final bool isActive;
  final int pendingScans;

  Assessment({
    required this.id,
    required this.title,
    required this.courseCode,
    required this.dateDue,
    required this.isActive,
    required this.pendingScans,
  });

  factory Assessment.fromJson(Map<String, dynamic> json) {
    return Assessment(
      id: json['id'],
      title: json['title'],
      courseCode: json['course_code'], // Matches the Django JSON key
      dateDue: json['date_due'],
      isActive: json['is_active'],
      pendingScans: json['pending_scans'],
    );
  }
}

class StudentGrade {
  final int id;
  final String assessmentTitle;
  final String courseCode;
  final dynamic scoreAchieved;
  final dynamic totalScore;
  final bool isPassed;
  final String? dateGraded;

  StudentGrade({
    required this.id,
    required this.assessmentTitle,
    required this.courseCode,
    this.scoreAchieved,
    this.totalScore,
    required this.isPassed,
    this.dateGraded,
  });

  factory StudentGrade.fromJson(Map<String, dynamic> json) {
    return StudentGrade(
      id: json['id'],
      assessmentTitle: json['assessment_title'],
      courseCode: json['course_code'],
      scoreAchieved: json['score_achieved'],
      totalScore: json['total_score'],
      isPassed: json['is_passed'],
      dateGraded: json['date_graded'],
    );
  }
}