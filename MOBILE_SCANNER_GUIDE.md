# ATLAS Mobile — Bubble Sheet Scanner Setup Guide

## Prerequisites

| Tool | Minimum Version | Check |
|------|----------------|-------|
| Flutter SDK | 3.24+ | `flutter --version` |
| Android Studio | Hedgehog (2023.1+) | SDK Platforms: API 34+ |
| Xcode (macOS only) | 15.0+ | `xcodebuild -version` |
| Java JDK | 17 | `java -version` |
| Python (backend) | 3.10+ | `python --version` |
| ATLAS Backend | running | `docker compose up` or `python manage.py runserver 0.0.0.0:8000` |

---

## 1. Backend Configuration (C:\ATLAS-dev\atlas-dev)

### 1.1 ALLOWED_HOSTS

Edit `backend\atlas\settings\dev.py` (or your active settings file):

```python
ALLOWED_HOSTS = ['localhost', '127.0.0.1', '10.0.2.2', '192.168.*', '*.local', '*']
```

For production, add your server's actual IP/domain.

### 1.2 CORS (Cross-Origin Resource Sharing)

Edit `backend\atlas\settings\base.py` — add the mobile origin or allow all for dev:

```python
# Option A: Allow all origins (development only)
CORS_ALLOW_ALL_ORIGINS = True

# Option B: Explicitly add Flutter Web origin
CORS_ALLOWED_ORIGINS = os.environ.get(
    'CORS_ALLOWED_ORIGINS', 
    'http://localhost:5173,http://localhost:5174'
).split(',')
```

Native Android/iOS apps are not restricted by browser CORS, but `django-cors-headers` middleware still inspects the `Origin` header. Using `CORS_ALLOW_ALL_ORIGINS = True` in dev avoids this issue entirely.

### 1.3 Start the Backend

```bash
cd C:\ATLAS-dev\atlas-dev
docker compose up
# OR without Docker:
cd backend
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8000
```

Verify the API is reachable: `curl http://localhost:8000/api/token/`

---

## 2. Mobile App Configuration (C:\ATLAS-dev\ATLAS-Mobile\ATLAS-Mobile)

### 2.1 Install Flutter Dependencies

```bash
cd C:\ATLAS-dev\ATLAS-Mobile\ATLAS-Mobile
flutter pub get
```

### 2.2 Configure API Base URL

Edit `lib\core\network\api_client.dart`:

```dart
class ApiClient {
  late Dio dio;

  // ── Android Emulator ─────────────────────────────────────
  // 10.0.2.2 maps to the host machine's localhost.
  // static const String baseUrl = "http://10.0.2.2:8000/api/";

  // ── Physical Android Device (same Wi-Fi network) ─────────
  // Replace 192.168.x.x with your machine's LAN IP.
  // static const String baseUrl = "http://192.168.1.100:8000/api/";

  // ── iOS Simulator ────────────────────────────────────────
  // iOS simulator shares the host's network, so localhost works.
  static const String baseUrl = "http://localhost:8000/api/";
```

**Pick the right URL** based on where you're running the app:

| Runtime | URL |
|---------|-----|
| Android Emulator | `http://10.0.2.2:8000/api/` |
| Physical Android Device | `http://<your-lan-ip>:8000/api/` |
| iOS Simulator | `http://localhost:8000/api/` |
| Physical iOS Device | `http://<your-lan-ip>:8000/api/` |

### 2.3 Wire Up Real Authentication

Replace the mocked `AuthRepository` in `lib\features\auth\auth_repository.dart` with real API calls:

```dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/network/api_client.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();

  /// Logs in against POST /api/token/ and returns the user role.
  Future<String> login({
    required String username,
    required String password,
  }) async {
    try {
      // 1. Obtain JWT tokens
      final tokenResponse = await _apiClient.dio.post(
        '/token/',
        data: {'username': username, 'password': password},
      );

      final accessToken = tokenResponse.data['access'];
      final refreshToken = tokenResponse.data['refresh'];

      if (accessToken == null) {
        throw Exception('Login failed — no access token returned.');
      }

      // 2. Store tokens
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', accessToken);
      await prefs.setString('refresh_token', refreshToken);

      // 3. Fetch user profile to determine role
      final meResponse = await _apiClient.dio.get(
        '/auth/me/',
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );

      final role = meResponse.data['role']?.toString().toLowerCase() ?? 'student';
      return role;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('Invalid credentials. Check your username and password.');
      }
      throw Exception(e.response?.data?['detail'] ?? 'Network error. Is the backend running?');
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
  }
}
```

**Important:** Update `LoginScreen` to pass `username` instead of `email` to match the JWT endpoint:

In `lib\features\auth\bloc\auth_bloc.dart`, change the `LoginRequested` event:

```dart
// OLD (mock): LoginRequested(String email, String password)
// NEW (real): LoginRequested(String username, String password)
```

Then in the BLoC `on<LoginRequested>` handler:

```dart
on<LoginRequested>((event, emit) async {
  emit(AuthLoading());
  try {
    final role = await authRepository.login(
      username: event.username,
      password: event.password,
    );
    emit(AuthSuccess(role));
  } catch (e) {
    emit(AuthFailure(e.toString()));
  }
});
```

---

## 3. Implementing the Scanner Screen

The scanner (`lib\features\scanner\scanner_screen.dart`) currently has a camera viewfinder with no capture logic. Below is the implementation plan.

### 3.1 Add Required Dependencies

Add to `pubspec.yaml` inside `dependencies:`:

```yaml
dependencies:
  # ---- existing ----
  # ---- new (scanner) ----
  image: ^4.2.0           # Image manipulation (grayscale, crop)
  path_provider: ^2.1.2   # Local file paths for temp images
  permission_handler: ^11.3.0  # Clean camera permission handling
```

Run: `flutter pub get`

### 3.2 Capture the Photo

In `lib\features\scanner\scanner_screen.dart`, replace the `onPressed` of the capture FAB:

```dart
FloatingActionButton.large(
  backgroundColor: const Color(0xFF8B1515),
  onPressed: () => _captureAndSubmit(context),
  child: const Icon(Icons.camera, color: Colors.white, size: 36),
),
```

Add the capture method to `_ScannerScreenState`:

```dart
Future<void> _captureAndSubmit(BuildContext context) async {
  if (_controller == null || !_controller!.value.isInitialized) return;

  try {
    // 1. Capture the frame
    final XFile picture = await _controller!.takePicture();

    // 2. Show scanning overlay
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading sheet for OMR grading...')),
    );

    // 3. Upload to backend for server-side OMR
    final result = await _submitScan(picture.path);

    if (!mounted) return;

    // 4. Show result
    if (result != null) {
      _showResultDialog(context, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scan failed. Try again.')),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: ${e.toString()}')),
    );
  }
}
```

### 3.3 Submit Scan to Backend

Add the submission method — requires `template_id` to be passed from the course selector:

```dart
import 'dart:io';
import '../../core/network/api_client.dart';

final ApiClient _api = ApiClient();

/// Submits the captured image to POST /api/grading/omr/bubble/scans/
/// for server-side OMR processing.
Future<Map<String, dynamic>?> _submitScan(String imagePath) async {
  try {
    final formData = FormData.fromMap({
      'template_id': templateId,       // must be passed in or selected before scanning
      'image': await MultipartFile.fromFile(imagePath, filename: 'scan.jpg'),
    });

    final response = await _api.dio.post(
      '/grading/omr/bubble/scans/',
      data: formData,
    );

    if (response.data['success'] == true) {
      return response.data['scan'] as Map<String, dynamic>;
    }
    return null;
  } on DioException catch (e) {
    debugPrint('Scan submit error: ${e.response?.data}');
    return null;
  }
}
```

### 3.4 Display Results

```dart
void _showResultDialog(BuildContext context, Map<String, dynamic> scan) {
  final studentId = scan['student_identifier'] ?? 'Unknown';
  final score = scan['score_raw'] ?? '—';
  final percent = scan['score_percent'] ?? '—';
  final maxScore = scan['max_score'] ?? '—';
  final flagged = scan['is_flagged'] == true;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            flagged ? Icons.warning_amber : Icons.check_circle,
            color: flagged ? Colors.orange : const Color(0xFF198754),
          ),
          const SizedBox(width: 8),
          const Text('Scan Result'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultRow('Student ID', studentId),
          const SizedBox(height: 8),
          _resultRow('Score', '$score / $maxScore ($percent%)'),
          if (flagged) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Low confidence — flagged for review.',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Scan Next'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B1515),
          ),
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.pop(context); // back to dashboard
          },
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Widget _resultRow(String label, String value) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 80,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ],
  );
}
```

---

## 4. Scanner Screen Navigation — Passing Template ID

The scanner needs to know which `template_id` to scan against. Update the navigation from the faculty dashboard:

**Option A — Hardcoded for initial testing:**
In `lib\features\scanner\scanner_screen.dart`, add a temporary hardcoded template ID:

```dart
// TODO: Replace with course/assessment selector
static const String templateId = 'PUT-YOUR-TEMPLATE-UUID-HERE';
```

**Option B — Pass template ID via constructor (recommended):**

Update `ScannerScreen` to accept `templateId`:

```dart
class ScannerScreen extends StatefulWidget {
  final String templateId;
  const ScannerScreen({super.key, required this.templateId});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}
```

Then in `FacultyDashboardScreen`, pass it when navigating:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ScannerScreen(
      templateId: 'your-template-uuid',
    ),
  ),
);
```

---

## 5. Run the Mobile App

### 5.1 Android Emulator

```bash
cd C:\ATLAS-dev\ATLAS-Mobile\ATLAS-Mobile

# List available emulators
flutter emulators

# Launch an emulator
flutter emulators --launch Pixel_6_API_34

# Run the app
flutter run
```

### 5.2 Physical Android Device

1. Enable **Developer Options** and **USB Debugging** on your device.
2. Connect via USB cable.
3. Accept the RSA fingerprint prompt on the device.
4. Run:
   ```bash
   flutter devices   # should list your device
   flutter run
   ```

### 5.3 iOS Simulator (macOS only)

```bash
cd C:\ATLAS-dev\ATLAS-Mobile\ATLAS-Mobile\ios
pod install
cd ..
flutter run
```

---

## 6. Testing the Full Scanning Pipeline

### Step 1: Create a Bubble Sheet Template

Generate one from the ATLAS web app (Faculty Workspace → Assessments → Bubble Sheets):

```
POST /api/grading/omr/bubble/templates/
{
  "course_id": "<your-course-uuid>",
  "name": "Midterm Exam Bubble Sheet",
  "total_items": 50,
  "num_choices": 4,
  "parts": [
    {"label": "Part I", "start_item": 1, "end_item": 50}
  ]
}
```

### Step 2: Generate the PDF layout

```
POST /api/grading/omr/bubble/templates/<template_id>/generate-pdf/
```

This populates `layout_metadata` with the bubble positions the OMR engine needs.

### Step 3: Set the Answer Key

```
POST /api/grading/omr/bubble/templates/<template_id>/answer-key/
{
  "answer_key": {
    "1": "A", "2": "C", "3": "B", ... "50": "D"
  }
}
```

### Step 4: Print and fill

Print the generated PDF. Fill in bubbles manually for testing.

### Step 5: Scan from the mobile app

Open the ATLAS Mobile app → Login as faculty → Tap "Scan Exam Sheets" → Align the sheet in the viewfinder → Capture.

Expected response (from `POST /api/grading/omr/bubble/scans/`):

```json
{
  "success": true,
  "scan": {
    "scan_id": "uuid",
    "template_id": "uuid",
    "student_identifier": "2024-00123",
    "responses": {"1": "A", "2": "C", "3": "?"},
    "score_raw": "42.00",
    "score_percent": "84.00",
    "max_score": "50.00",
    "is_flagged": false,
    "flag_reason": null,
    "created_at": "2026-07-14T10:30:00Z"
  }
}
```

---

## 7. Key API Endpoints (Quick Reference)

| Method | URL | Purpose |
|--------|-----|---------|
| `POST` | `/api/token/` | Login (JWT) — body: `{username, password}` |
| `POST` | `/api/token/refresh/` | Refresh access token — body: `{refresh}` |
| `GET` | `/api/auth/me/` | Current user profile |
| `GET` | `/api/grading/omr/bubble/templates/?course_id=` | List templates |
| `GET` | `/api/grading/omr/bubble/templates/<id>/` | Template detail + answer_key + layout_metadata |
| `POST` | `/api/grading/omr/bubble/scans/` | Submit scan image (multipart) for server-side OMR |
| `GET` | `/api/grading/omr/bubble/templates/<id>/scans/` | List all scans for a template |
| `PATCH` | `/api/grading/omr/bubble/scans/<id>/` | Correct a scan's responses or student ID |
| `DELETE` | `/api/grading/omr/bubble/scans/<id>/` | Delete a bad scan |
| `GET` | `/api/grading/student-scores/?course_id=&assessment_id=` | All student scores for grading |

---

## 8. Troubleshooting

| Problem | Solution |
|---------|----------|
| `Connection refused` | Ensure backend is running on `0.0.0.0:8000` (not just `127.0.0.1`) |
| `401 Unauthorized` | Token expired — call `/api/token/refresh/` with the stored `refresh_token` |
| `403 Forbidden` | User must have `faculty` role to access grading endpoints |
| `400 Generate the PDF first` | Template needs PDF generation before scanning — hit the `generate-pdf` endpoint |
| `500 Server Error` | Check `layout_metadata` is populated and `answer_key` is set on the template |
| `Camera unavailable` | Run on a physical device or emulator with camera support (not web) |
| `Android build fails` | Check `compileSdkVersion` ≥ 34 in `android/app/build.gradle.kts` |
| `iOS build fails` | Run `cd ios && pod install && cd ..` after adding new dependencies |

---

## 9. Architecture Summary

```
  Mobile App (Flutter)          Django Backend (Port 8000)        PostgreSQL
  ─────────────────────         ─────────────────────────        ──────────

  [ Camera Capture ] ─────────▶ POST /bubble/scans/
  (camera package)                    │
                                BubbleSheetScanner
                                      │
  [ Result Dialog ] ◀─────────── OpenCV OMR engine
  (score, flagged)                     │
                                Save + Return result
```

OMR processing happens **server-side** via OpenCV. The mobile app is responsible for:
1. Authenticating (JWT)
2. Capturing a high-quality image
3. Uploading it to `POST /api/grading/omr/bubble/scans/`
4. Displaying the instant result (score, flagged status)