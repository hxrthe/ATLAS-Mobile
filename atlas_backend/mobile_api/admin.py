from django.contrib import admin
from django.contrib.auth.models import User
from .models import UserProfile, Course, Assessment, StudentGrade

@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'role', 'department_or_program')
    list_filter = ('role',)

@admin.register(Course)
class CourseAdmin(admin.ModelAdmin):
    list_display = ('code', 'title', 'instructor')
    search_fields = ('code', 'title')
    
    # Upgrades the student selection UI to a modern dual-box layout
    filter_horizontal = ('students',) 

    # Filter the Instructor dropdown to ONLY show Faculty
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "instructor":
            kwargs["queryset"] = User.objects.filter(profile__role='faculty')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    # Filter the Students list to ONLY show Students
    def formfield_for_manytomany(self, db_field, request, **kwargs):
        if db_field.name == "students":
            kwargs["queryset"] = User.objects.filter(profile__role='student')
        return super().formfield_for_manytomany(db_field, request, **kwargs)

@admin.register(Assessment)
class AssessmentAdmin(admin.ModelAdmin):
    list_display = ('title', 'course', 'date_due', 'is_active')
    list_filter = ('is_active', 'course')

@admin.register(StudentGrade)
class StudentGradeAdmin(admin.ModelAdmin):
    list_display = ('student', 'assessment', 'score_achieved', 'total_score', 'is_passed')