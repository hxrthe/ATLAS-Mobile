import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'report_issue_screen.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  final Color primaryRed = const Color(0xFF8B1515);
  final Color darkText = const Color(0xFF1E232C);
  final Color grayText = const Color(0xFF8391A1);
  final Color borderColor = const Color(0xFFE8ECF4);

  Future<void> _launchEmail(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? 'Unknown';
    final String email = 'atlasdegdev@gmail.com';
    final String subject = 'Support Request - [$userId]';
    final String body = 'Hello ATLAS Support Team,\n\nI need assistance with...';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    try {
      final bool launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        throw Exception('No email app found');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open email app. Please email us at atlasdegdev@gmail.com'),
            action: SnackBarAction(
              label: 'Copy Email',
              onPressed: () {
                // You could add clipboard support here if needed
              },
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: darkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Help & Support',
          style: TextStyle(color: darkText, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('FAQ\'S'),
            const SizedBox(height: 16),
            _buildFAQTile(
              'How do I scan an answer sheet?',
              'Navigate to the camera tab, align the four corner markers with the paper squares in the viewfinder, and hold steady. The app will automatically capture and grade the sheet once all corners are locked.',
            ),
            _buildFAQTile(
              'What if the QR code isn\'t recognized?',
              'Ensure the QR code is well-lit and not obscured. Avoid direct glare by tilting the paper slightly. The QR code must contain valid assessment data for the system to identify the template.',
            ),
            _buildFAQTile(
              'Can I edit scores manually?',
              'Yes. In the "Review Papers" section, tap on any record to view details, then select "Edit Answers" to manually correct any misread bubbles.',
            ),
            _buildFAQTile(
              'What does "Ambiguous" mean?',
              'The system flags an item as ambiguous if multiple bubbles are shaded or if the shading is too light to be certain. These should be reviewed manually in the paper detail view.',
            ),
            _buildFAQTile(
              'How do I sync my data?',
              'The app syncs automatically when you have an internet connection. You can also pull down to refresh on most screens to force a synchronization with the server.',
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('TROUBLESHOOTING'),
            const SizedBox(height: 16),
            _buildActionTile(
              icon: Icons.bug_report_outlined,
              title: 'Report an Issue / Bug',
              subtitle: 'Send technical errors to our team',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportIssueScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.email_outlined,
              title: 'Direct Support Contact',
              subtitle: 'atlasdegdev@gmail.com',
              onTap: () => _launchEmail(context),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('LEGAL'),
            const SizedBox(height: 16),
            _buildActionTile(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              subtitle: 'Read our usage terms',
              onTap: () => _showLegalDoc(context, 'Terms of Service', _termsOfService),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'How we handle your data',
              onTap: () => _showLegalDoc(context, 'Privacy Policy', _privacyPolicy),
            ),
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Text(
                    'App Version',
                    style: TextStyle(color: grayText, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '1.0.0+1',
                    style: TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: grayText,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFAQTile(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: darkText,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
            child: Text(
              answer,
              style: TextStyle(color: grayText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: primaryRed),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: darkText,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: grayText, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: grayText),
          ],
        ),
      ),
    );
  }

  void _showLegalDoc(BuildContext context, String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: darkText,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  content,
                  style: TextStyle(color: darkText, height: 1.6, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _termsOfService = '''
TERMS OF SERVICE AND USER RESPONSIBILITIES

1. ACCEPTANCE OF TERMS
By accessing or using the ATLAS Mobile application, you agree to be bound by these Terms of Service. If you do not agree to all of the terms and conditions, you are prohibited from using the application.

2. USER ELIGIBILITY AND ACCOUNT SECURITY
The ATLAS Mobile application is designed for use by authorized faculty of Batangas State University. Faculty accounts must be created on the ATLAS website before signing in here. You are responsible for maintaining the confidentiality of your account credentials, including your institutional email and secure password. Any activity occurring under your account is your sole responsibility. You must immediately notify the ATLAS support team of any unauthorized use of your account.

3. PROHIBITED CONDUCT AND USER RESPONSIBILITIES
As a user of ATLAS, you agree not to:
- Use the application for any fraudulent or illegal purposes.
- Attempt to circumvent the OMR grading logic or manipulate assessment results.
- Reverse engineer, decompile, or attempt to extract the source code of the application.
- Submit false bug reports or malicious technical data.
- Impersonate another user or gain unauthorized access to data belonging to other faculty members.
- Use the application in a manner that interferes with its normal operation or imposes an unreasonable load on our infrastructure.

4. INTELLECTUAL PROPERTY RIGHTS
All content, features, and functionality of the ATLAS Mobile application, including but not limited to the OMR engine, UI design, graphics, and logos, are the exclusive property of the ATLAS development team and are protected by international copyright and intellectual property laws.

5. ACADEMIC INTEGRITY
ATLAS is a tool designed to support academic assessment. Faculty users are expected to uphold the highest standards of academic integrity. Any attempt to use the application to facilitate cheating or academic dishonesty will be reported to the appropriate university authorities.

6. LIMITATION OF LIABILITY
The ATLAS application is provided "as is" and "as available." To the maximum extent permitted by law, the developers shall not be liable for any indirect, incidental, special, or consequential damages resulting from the use or inability to use the application, including but not limited to loss of data or academic standing.

7. MODIFICATIONS TO SERVICE
We reserve the right to modify or discontinue the service (or any part thereof) at any time, with or without notice. We shall not be liable to you or any third party for any modification, suspension, or discontinuance of the service.

8. GOVERNING LAW
These terms shall be governed by and construed in accordance with the laws of the Republic of the Philippines, without regard to its conflict of law provisions.
''';

  static const String _privacyPolicy = '''
PRIVACY POLICY AND DATA PROTECTION

1. INFORMATION WE COLLECT
ATLAS Mobile collects information necessary to provide and improve our academic assessment services. This includes:
- Personal Identifiers: Your name and institutional email address (g.batstate-u.edu.ph).
- Academic Data: Faculty course assignments, assessment templates, scanned answer sheet images, and grading results.
- Technical Data: Device model, operating system version, and system logs (when explicitly submitted via bug reports).

2. HOW WE USE YOUR INFORMATION
The information collected is used solely for:
- Authenticating users and securing access to academic records.
- Facilitating the scanning and automated grading of OMR answer sheets.
- Providing academic analytics and grading reports to faculty.
- Improving the accuracy and performance of the OMR engine.
- Responding to support requests and technical issues.

3. DATA STORAGE AND SECURITY
We implement robust technical and organizational measures to protect your data. Your credentials (email and password) are stored locally using hardware-backed secure storage. Academic data is transmitted over encrypted channels (HTTPS) to our secure servers. Images of answer sheets are processed on-device and uploaded to facilitate faculty review and long-term record keeping.

4. DATA SHARING AND DISCLOSURE
We do not sell, trade, or otherwise transfer your personal information to outside parties. Data is only accessible to:
- You (the faculty account holder).
- Authorized faculty members for courses they teach.
- The ATLAS technical support team (only when necessary for troubleshooting).

5. USER RIGHTS AND CHOICES
You have the right to:
- Access and review the personal and academic data associated with your account.
- Correct any inaccuracies in your profile information.
- Request the deletion of your account and associated data (subject to institutional record-keeping policies).
- Opt-out of local credential storage via the "Account & Security" settings.

6. COOKIES AND LOCAL STORAGE
The application uses local storage (SharedPreferences and SecureStorage) to maintain your session and preferences. These are essential for the application to function correctly.

7. THIRD-PARTY SERVICES
ATLAS Mobile may utilize third-party services such as Google Sign-In and Supabase for authentication. These services have their own privacy policies governing how they handle your data.

8. CHANGES TO THIS PRIVACY POLICY
We may update our Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy within the application. You are advised to review this policy periodically for any changes.
''';
}
