import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'my_issue_reports_screen.dart';
import 'report_issue_screen.dart';
import '../../core/theme/app_theme.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  Future<void> _launchEmail(BuildContext context) async {
    final String email = 'atlasdegdev@gmail.com';
    final String subject = 'Help with ATLAS Mobile';
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
    final colors = context.atlas;
    return Scaffold(
      backgroundColor: colors.scaffold,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(colors, 'FAQs'),
            const SizedBox(height: 16),
            _buildFAQTile(
              context,
              colors,
              'How do I scan an answer sheet?',
              'Open the scan button on the home screen. Point the camera so the four black squares on the sheet sit inside the frame, then hold still. The app reads the sheet on your phone and shows the score.',
            ),
            _buildFAQTile(
              context,
              colors,
              'What if the code on the sheet is not recognized?',
              'Use a bright room and keep the sheet flat, without glare. The exam also has to be one of yours. Open the app once while you have internet so that exam is saved on the phone. After that, you can scan it even without internet.',
            ),
            _buildFAQTile(
              context,
              colors,
              'Can I scan without internet?',
              'Yes, after the app has saved your exams on the phone. A short message appears near the top of the screen while that is happening, and your phone shows a notification from ATLAS. Pulling down to refresh the home screen updates your classes. It does not start that save again.',
            ),
            _buildFAQTile(
              context,
              colors,
              'When do scores reach the class record?',
              'If you are online, the score is sent after the scan. If you are not, it stays on the phone and is sent on its own when the internet is back. You can also open the scanned paper and send it yourself.',
            ),
            _buildFAQTile(
              context,
              colors,
              'Can I correct an answer that was read wrong?',
              'Yes. Open Review Papers, tap the sheet, and change the answers. If the score has not been sent yet, the corrected one is what gets sent.',
            ),
            _buildFAQTile(
              context,
              colors,
              'What does Invalid mean?',
              'A question is marked invalid when more than one bubble is shaded, or the mark is too light to read. Check that question on the paper and correct it if you need to.',
            ),
            _buildFAQTile(
              context,
              colors,
              'What is saved on my phone?',
              'Your exams, the correct answers, the sheet layout, and your class sections. That is what lets you scan, and check that a student belongs in the class, even without internet. If a student is missing from a section you already have, you can add them. That change is sent with the score when you are back online.',
            ),
            _buildFAQTile(
              context,
              colors,
              'What is a major examination in the app?',
              'Major examinations you create here share the same course records as ATLAS Web — answer keys and scores sync both ways. You can also scan course exams prepared on the website, including offline once they are saved on the phone.',
            ),
            _buildFAQTile(
              context,
              colors,
              'Who sees a problem I report?',
              'Your message goes to the admin for your campus. That admin can send it on to the ATLAS team if the campus needs more help. You can also email atlasdegdev@gmail.com.',
            ),
            _buildFAQTile(
              context,
              colors,
              'How do I sign in?',
              'Use the same faculty account as the ATLAS website, with your email and password or with Google. The app signs you out after 15 minutes without use. Students do not sign in to ATLAS.',
            ),
            const SizedBox(height: 32),
            _buildSectionTitle(colors, 'TROUBLESHOOTING'),
            const SizedBox(height: 16),
            _buildActionTile(
              colors,
              icon: Icons.bug_report_outlined,
              title: 'Report an issue',
              subtitle: 'Send a note to your campus admin',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportIssueScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              colors,
              icon: Icons.history_outlined,
              title: 'My issue reports',
              subtitle: 'See status updates, including when resolved',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyIssueReportsScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              colors,
              icon: Icons.email_outlined,
              title: 'Direct Support Contact',
              subtitle: 'atlasdegdev@gmail.com',
              onTap: () => _launchEmail(context),
            ),
            const SizedBox(height: 32),
            _buildSectionTitle(colors, 'LEGAL'),
            const SizedBox(height: 16),
            _buildActionTile(
              colors,
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              subtitle: 'Read our usage terms',
              onTap: () => _showLegalDoc(context, 'Terms of Service', _termsOfService),
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              colors,
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
                    'App version',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const _AppVersionLabel(),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(AtlasColors colors, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: colors.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFAQTile(
    BuildContext context,
    AtlasColors colors,
    String question,
    String answer,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: colors.primary.withValues(alpha: 0.08),
          highlightColor: colors.primary.withValues(alpha: 0.04),
        ),
        child: ExpansionTile(
          iconColor: colors.textSecondary,
          collapsedIconColor: colors.textSecondary,
          title: Text(
            question,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Text(
                answer,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    AtlasColors colors, {
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
          color: colors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: colors.textSecondary),
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
      builder: (sheetContext) {
        final colors = sheetContext.atlas;
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.85,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: colors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              Divider(color: colors.divider),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: TextStyle(
                      color: colors.textPrimary,
                      height: 1.6,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static const String _termsOfService = '''
TERMS OF SERVICE
ATLAS website and ATLAS mobile app
Batangas State University – Lipa Campus
November 2026

These terms cover the ATLAS website and the ATLAS mobile app. They apply to faculty and campus administrators. Students do not sign in.

By using ATLAS you agree to these terms. If you do not agree, do not use the website or the app.

1. ACCOUNTS
Use the faculty or admin account created for your campus. You are responsible for your password and for what happens under your account. You can sign in with your email and password, or with Google where that is offered. On the website, a session ends after 15 minutes without activity, after 12 hours, or when you sign in on another device. In the app, you are signed out after 15 minutes without use. Tell us right away at atlasdegdev@gmail.com if someone else uses your account.

2. WHAT ATLAS IS FOR
ATLAS helps a campus prepare classes and check written exams.
On the website, faculty work on syllabi, modules, assessments, grading, class results, and the knowledge base. Campus admins look after people, the academic structure, the syllabus format, and campus records. The super admin looks after the system for this campus.
In the app, faculty scan answer sheets, create major exams, and review scores. The app saves your exams, the correct answers, the sheet layout, and your class sections on the phone so scanning still works without internet. Scores checked while you are offline are sent to the class record when the internet is back.

3. DRAFTS FROM THE ASSISTANT
The website can draft syllabi, modules, and assessments for you to review. Those drafts can be wrong. Read and approve them before you rely on them or share them with students.

4. SPREADSHEETS
If you connect a Google Sheet, ATLAS only reads the range you name. It does not change the Sheet. You need permission to use that Sheet.

5. CAMPUS SUBSCRIPTION
A campus may start with a short trial. Paid access is handled through PayMongo. ATLAS does not store your card number. A campus whose subscription has ended may lose access until it is renewed.

6. YOUR RESPONSIBILITIES
Use ATLAS for real teaching work.
Do not share your account, open records that are not yours, or change scores so they no longer match the paper.
Do not try to break sign-in, campus limits, or another person’s classes.
Do not upload files you have no right to use.
A problem you report from the app should describe something that really happened. Your campus admin receives it and may send it to the ATLAS team.

7. ACADEMIC HONESTY
Using ATLAS to cheat, invent grades, or present an unchecked draft as finished work can be reported to the campus and can close your access. Follow your campus rules and CHED CMO No. 46, s. 2012.

8. YOUR WORK AND OURS
You keep the syllabi, exams, and files you create. ATLAS keeps the website, the app, and its design. You allow ATLAS to store and process your materials so the service can run.

9. AVAILABILITY
ATLAS is provided as it is. We may change, pause, or limit it. Access can be paused for misuse, a security problem, or an unpaid campus subscription. Closing an admin account does not erase the campus’s classes or other people.

10. LIMITS
To the extent the law allows, ATLAS is not responsible for indirect loss, including a lost score or a decision made from an unchecked draft. Check results before you rely on them. Where a limit is required, responsibility is capped at the fees paid for the previous three months, or PHP 5,000 when the campus is on a trial or unpaid plan.

11. LAW
These terms follow the laws of the Republic of the Philippines. Try to settle a dispute in good faith before going to the courts of Batangas.

12. CONTACT
ATLAS Development Team
atlasdegdev@gmail.com
Lipa City, Batangas, Philippines
''';

  static const String _privacyPolicy = '''
PRIVACY POLICY
ATLAS website and ATLAS mobile app
Batangas State University – Lipa Campus
November 2026
Republic Act No. 10173 (Data Privacy Act)

This notice covers the ATLAS website and the ATLAS mobile app for Batangas State University – Lipa Campus. ATLAS and the campus are responsible for this information. Services that host or deliver it act on our instructions.

1. WHO USES ATLAS
Faculty and administrators. Students do not sign in. A student’s name, ID number, section, and scores reach ATLAS when a faculty member scans a sheet, adds someone to a class section, or connects a spreadsheet.

2. WHAT WE KEEP
Your account: name, email, role, campus, profile photo, and a protected password. We never store the password in a form we can read.
Your teaching work: courses, sections, syllabi, modules, assessments, answer keys, sheet layouts, scanned sheets, scores, and files you upload for the knowledge base.
Class results: scores tied to a student ID, including scans made in the app.
On the phone: a copy of your exams, correct answers, sheet layouts, and class sections, so you can scan without internet. Scores waiting to be sent stay on the phone until the connection returns.
Sign-in activity and a record of important actions. If you turn on alerts in the browser, we keep what is needed to deliver them.
If you choose to include phone details with a problem report, we receive the kind of phone and the app version. We do not take a running record from your phone.
Campus plan status and payment references. Card details stay with PayMongo.

3. HOW WE USE IT
To sign you in and show you only your own classes.
To prepare drafts, read a spreadsheet you connected, score answer sheets, and keep class results.
To save exams on your phone and send scores when you are online.
To let a campus admin read a problem you report, and to let that admin pass it to the ATLAS team.
To run the campus subscription, send account and maintenance notices, and keep the service secure.
We do not sell personal information, and we do not use it for advertising.

4. WHY WE MAY DO THIS
Your consent, when you register, upload a file, connect a spreadsheet, or include phone details with a report.
The service you asked for.
The security and integrity of academic records.
A legal duty to keep or disclose a record.

5. OTHER SERVICES
Drafting on the website may send course details and short excerpts of your files to an outside writing service. Do not put passwords in what you upload.
Google Sheets: only the range you name is read, and nothing is written back.
PayMongo handles payment.
Email is used for sign-in codes and notices.
Google sign-in is used only if you choose it.

6. WHERE IT IS KEPT
Records are stored for the campus and reached through ATLAS over an encrypted connection. The app keeps your sign-in and the saved exams on the phone. Faculty see the courses assigned to them. Campus admins see their campus. The super admin sees how the system is running.

7. HOW LONG, AND YOUR CHOICES
We keep teaching records while the campus uses ATLAS, and as long as the campus must keep them. You can ask for access, a correction, or deletion, subject to those campus rules.
You can review your account in the app or on the website.
You can leave out phone details when you report a problem.
Signing out ends the session. On the website, closing the tab also ends it.
Browser alerts can be turned off in the website settings.

8. CONTACT
Questions about your information: atlasdegdev@gmail.com, Lipa City, Batangas. You may also contact the National Privacy Commission.

9. CHANGES
When the way ATLAS handles information changes, this notice is updated in the app and on the website.
''';
}

class _AppVersionLabel extends StatefulWidget {
  const _AppVersionLabel();

  @override
  State<_AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<_AppVersionLabel> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = info.version);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.atlas;
    return Text(
      _version.isEmpty ? '…' : _version,
      style: TextStyle(
        color: colors.textPrimary,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
    );
  }
}
