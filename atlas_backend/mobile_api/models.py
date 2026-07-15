from django.db import models
from django.contrib.auth.models import User

# 1. User Profiles (Extends default Django user to add Roles)
class UserProfile(models.Model):
    ROLE_CHOICES = (
        ('faculty', 'Faculty'),
        ('student', 'Student'),
    )
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    role = models.CharField(max_length=10, choices=ROLE_CHOICES)
    department_or_program = models.CharField(max_length=100, blank=True) # e.g., "BSIT BA 3301"

    def __str__(self):
        return f"{self.user.first_name} {self.user.last_name} ({self.role})"

# 2. Courses Table
class Course(models.Model):
    code = models.CharField(max_length=20, unique=True) # e.g., "CICS-302"
    title = models.CharField(max_length=200)            # e.g., "Web Systems & Technologies"
    instructor = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, related_name='courses_taught')
    students = models.ManyToManyField(User, related_name='enrolled_courses', blank=True)

    def __str__(self):
        return f"{self.code} - {self.title}"

# 3. Assessments Table (Exams, Quizzes)
class Assessment(models.Model):
    course = models.ForeignKey(Course, on_delete=models.CASCADE, related_name='assessments')
    title = models.CharField(max_length=200)            # e.g., "Midterm Exam"
    date_due = models.DateTimeField()
    is_active = models.BooleanField(default=True)       # Triggers the "Ongoing Assessment" banner
    pending_scans = models.IntegerField(default=0)      # For the Faculty scanner UI

    def __str__(self):
        return f"{self.title} ({self.course.code})"

# 4. Student Grades & Competencies (For the Spider-Map & Recent Grades)
class StudentGrade(models.Model):
    student = models.ForeignKey(User, on_delete=models.CASCADE, related_name='grades')
    assessment = models.ForeignKey(Assessment, on_delete=models.CASCADE)
    score_achieved = models.IntegerField()
    total_score = models.IntegerField()
    is_passed = models.BooleanField(default=True)
    date_graded = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.student.username} - {self.assessment.title}: {self.score_achieved}/{self.total_score}"