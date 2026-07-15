from rest_framework import serializers
from django.contrib.auth.models import User
from .models import UserProfile, Course, Assessment, StudentGrade

# 1. User Translator (Grabs the email and their role)
class UserSerializer(serializers.ModelSerializer):
    role = serializers.CharField(source='profile.role', read_only=True)

    class Meta:
        model = User
        fields = ['id', 'username', 'role'] # 'username' holds the email in our setup

# 2. Course Translator
class CourseSerializer(serializers.ModelSerializer):
    class Meta:
        model = Course
        fields = ['id', 'code', 'title']

# 3. Assessment Translator (Includes the course code for the UI banners)
class AssessmentSerializer(serializers.ModelSerializer):
    course_code = serializers.CharField(source='course.code', read_only=True)

    class Meta:
        model = Assessment
        fields = ['id', 'title', 'course_code', 'date_due', 'is_active', 'pending_scans']

# 4. Grade Translator (For the student's spider-map and grade lists)
class StudentGradeSerializer(serializers.ModelSerializer):
    assessment_title = serializers.CharField(source='assessment.title', read_only=True)
    course_code = serializers.CharField(source='assessment.course.code', read_only=True)

    class Meta:
        model = StudentGrade
        fields = ['id', 'assessment_title', 'course_code', 'score_achieved', 'total_score', 'is_passed', 'date_graded']


from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

class CustomTokenObtainPairSerializer(TokenObtainPairSerializer):
    def validate(self, attrs):
        data = super().validate(attrs)
        
        # 1. Inject the role
        if hasattr(self.user, 'profile'):
            data['role'] = self.user.profile.role.lower()
        else:
            data['role'] = 'student' # Default fallback
            
        # 2. Inject the name
        # Combines first and last name, or falls back to username if they are blank
        full_name = f"{self.user.first_name} {self.user.last_name}".strip()
        data['name'] = full_name if full_name else self.user.username
            
        return data