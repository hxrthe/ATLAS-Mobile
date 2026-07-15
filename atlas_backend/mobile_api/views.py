from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from .models import Course, Assessment, StudentGrade
from .serializers import CourseSerializer, AssessmentSerializer, StudentGradeSerializer

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def faculty_dashboard(request):
    """
    Serves the Faculty Dashboard.
    Only returns courses taught by the currently logged-in faculty member.
    """
    # Grab courses where the instructor matches the logged-in user
    courses = Course.objects.filter(instructor=request.user)
    
    # Grab active assessments specifically for those courses
    assessments = Assessment.objects.filter(course__in=courses, is_active=True)

    return Response({
        'courses': CourseSerializer(courses, many=True).data,
        'active_assessments': AssessmentSerializer(assessments, many=True).data
    })

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def student_dashboard(request):
    """
    Serves the Student Dashboard.
    Only returns courses and grades linked to the logged-in student.
    """
    courses = Course.objects.filter(students=request.user)
    grades = StudentGrade.objects.filter(student=request.user)

    return Response({
        'enrolled_courses': CourseSerializer(courses, many=True).data,
        'recent_grades': StudentGradeSerializer(grades, many=True).data
    })


from rest_framework_simplejwt.views import TokenObtainPairView
from .serializers import CustomTokenObtainPairSerializer

class CustomTokenObtainPairView(TokenObtainPairView):
    serializer_class = CustomTokenObtainPairSerializer