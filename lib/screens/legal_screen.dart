import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/common.dart';

/// ⭐ v52: In-app Terms & Conditions and Privacy Policy.
/// Opened from the profile panel on the dashboard — everything renders
/// inside the app, no browser needed.
class LegalScreen extends StatefulWidget {
  /// 0 = Terms & Conditions tab, 1 = Privacy Policy tab.
  final int initialTab;

  const LegalScreen({super.key, this.initialTab = 0});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.page,
      body: SafeArea(
        child: Column(children: [
          CunnectHeader(onBack: () => Navigator.of(context).pop()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Legal',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                const Text(
                    'Please read these carefully — using CUnnect means you '
                    'agree to them.',
                    style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                const SizedBox(height: 12),
                // ---- tab switch ----
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2B2B2B)),
                  ),
                  child: Row(children: [
                    for (final t in const [
                      (0, 'Terms & Conditions'),
                      (1, 'Privacy Policy'),
                    ])
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tab = t.$1),
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _tab == t.$1
                                  ? const Color(0x26F10B1D)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                  color: _tab == t.$1
                                      ? const Color(0x8CF10B1D)
                                      : Colors.transparent),
                            ),
                            alignment: Alignment.center,
                            child: Text(t.$2,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _tab == t.$1
                                        ? const Color(0xFFFF9CA4)
                                        : const Color(0xFF9A9A9A))),
                          ),
                        ),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              children:
                  _tab == 0 ? _termsSections() : _privacySections(),
            ),
          ),
        ]),
      ),
    );
  }

  // ==================================================================
  // TERMS & CONDITIONS
  // ==================================================================
  List<Widget> _termsSections() => [
        _updated(),
        _section('1. Acceptance of Terms',
            'CUnnect is a campus companion app that brings food ordering, '
            'printout services, hostel essentials, the campus store, the '
            'CUnnect Feed and university (UMS) tools into one place. By '
            'creating an account or using any part of the app, you agree '
            'to these Terms & Conditions and to our Privacy Policy. If '
            'you do not agree, please do not use the app.'),
        _section('2. Eligibility & Accounts',
            'CUnnect is intended for students and campus partners '
            '(vendors) of the supported campus. You must register with '
            'accurate details — your name, university UID, phone number '
            'and email. You are responsible for keeping your login '
            'credentials safe and for all activity that happens through '
            'your account. Creating an account with false information, '
            'or using another person\'s identity or UID, is prohibited.'),
        _section('3. Orders & Payments',
            'Food, printout and hostel-essential orders placed through '
            'CUnnect are fulfilled by independent campus vendors. Prices, '
            'availability, preparation and delivery times are set by the '
            'vendor. Payments are made directly to the vendor via UPI '
            '(QR scan or UPI ID) — CUnnect does not process, hold or '
            'transfer money and is not a payment gateway. When you enter '
            'a transaction ID, you confirm it is genuine; submitting '
            'fake or reused transaction IDs is a serious violation and '
            'may lead to account suspension. Refunds, cancellations and '
            'order disputes are resolved between you and the vendor; the '
            'CUnnect team can assist through the in-app support form but '
            'is not liable for vendor-side failures.'),
        _section('4. Printout Service',
            'Documents you upload for printing are shared with the print '
            'vendor only after they accept your order. Do not upload '
            'unlawful, copyrighted (without permission) or inappropriate '
            'material for printing. You are responsible for the content '
            'of the files you submit.'),
        _section('5. UMS Tools',
            'The UMS section lets you view your own attendance, timetable, '
            'marks and related academic data by logging in with your own '
            'university credentials. CUnnect only displays this data to '
            'you and does not alter any university records. This feature '
            'is provided for convenience; the university\'s own portal '
            'remains the authoritative source. Do not use another '
            'student\'s credentials.'),
        _section('6. CUnnect Feed & Community Content',
            'The Feed shows announcements, polls and posts. You may react '
            'and comment. Do not post or comment anything abusive, '
            'hateful, obscene, misleading, or that harasses another '
            'person. The CUnnect team may remove content and restrict '
            'accounts that violate these rules. You own the content you '
            'post but grant CUnnect the right to display it within the '
            'app.'),
        _section('7. Prohibited Conduct',
            'You must not: (a) attempt to access another user\'s account '
            'or data; (b) interfere with, overload or reverse-engineer '
            'the app or its servers; (c) place fraudulent orders or '
            'submit fake payment confirmations; (d) capture, copy or '
            'redistribute screens of the app — screen capture is blocked '
            'throughout the app for the safety of user data; (e) use the '
            'app for any unlawful purpose.'),
        _section('8. Account Suspension',
            'The CUnnect team may suspend or disable accounts that '
            'violate these terms, abuse vendors or other users, or '
            'attempt to defraud the platform. A disabled account is '
            'logged out automatically and cannot sign in again until '
            're-enabled by the team.'),
        _section('9. Service Availability',
            'CUnnect is provided "as is". We work hard to keep the app '
            'fast and available, but we do not guarantee uninterrupted '
            'service — outages, maintenance windows and vendor '
            'unavailability can occur. Features may be added, changed or '
            'removed as the app evolves, and updates may be required to '
            'continue using the app.'),
        _section('10. Limitation of Liability',
            'To the maximum extent permitted by law, CUnnect and its '
            'team are not liable for indirect or consequential losses, '
            'for the quality of vendor goods and services, for payment '
            'disputes between you and vendors, or for the accuracy of '
            'university data displayed in the UMS section.'),
        _section('11. Changes to These Terms',
            'We may update these Terms & Conditions from time to time. '
            'The latest version is always available here in the app, and '
            'continued use after an update means you accept the revised '
            'terms.'),
        _section('12. Contact',
            'Questions, complaints or requests? Use the in-app support '
            'form: Profile → Contact Us. The CUnnect team reviews every '
            'request and acknowledges it through an in-app notification.'),
      ];

  // ==================================================================
  // PRIVACY POLICY
  // ==================================================================
  List<Widget> _privacySections() => [
        _updated(),
        _section('1. What This Policy Covers',
            'This Privacy Policy explains what information the CUnnect '
            'app collects, why it is collected, how it is used and the '
            'choices you have. We collect only what is needed to run the '
            'services you use — nothing more.'),
        _section('2. Information You Give Us',
            '• Account details: name, university UID, phone number, '
            'email and password (stored securely as a hash — we never '
            'see your plain password).\n'
            '• Profile photo, if you add one.\n'
            '• Order details: items, delivery address / hostel & room, '
            'notes, and the UPI transaction ID you enter to confirm a '
            'payment.\n'
            '• Documents you upload for the printout service.\n'
            '• Feed activity: posts, comments, reactions and poll votes.\n'
            '• Support messages you send through the contact form.'),
        _section('3. UMS Credentials',
            'If you use the UMS section, your university login is used '
            'to fetch YOUR OWN attendance, timetable and academic data '
            'for display inside the app. Credentials are stored on your '
            'device to keep you signed in and are transmitted securely '
            'only to perform this fetch. We do not sell or share your '
            'UMS data with anyone — it is shown to you alone.'),
        _section('4. Information Collected Automatically',
            '• Device push-notification token (so order updates and '
            'announcements reach your phone).\n'
            '• Basic usage signals such as app opens and screen visits, '
            'used in aggregate (e.g. daily traffic counts) to improve '
            'the app.\n'
            'CUnnect does NOT collect your GPS location, contacts, call '
            'logs, SMS or files beyond what you explicitly upload.'),
        _section('5. How Your Information Is Used',
            '• To create and secure your account.\n'
            '• To pass your order to the vendor you chose — the vendor '
            'sees only what is needed to fulfil the order (your name, '
            'order items, delivery details and payment confirmation; a '
            'print vendor sees your document and phone number only '
            'after accepting the job).\n'
            '• To send order status and campus notifications.\n'
            '• To respond to your support requests.\n'
            '• To understand overall usage (aggregate statistics) and '
            'keep the platform safe from fraud and abuse.'),
        _section('6. What We Never Do',
            '• We never sell your personal data.\n'
            '• We never share your data with advertisers.\n'
            '• We never read your UMS academic data for any purpose '
            'other than showing it to you.\n'
            '• We never store your card/bank details — payments happen '
            'directly in your own UPI app.'),
        _section('7. Data Sharing',
            'Your data is shared only with: (a) the vendor fulfilling '
            'your order, to the minimum extent needed; (b) our hosting '
            'and push-notification infrastructure providers, which '
            'process data on our behalf; and (c) authorities, if the '
            'law genuinely requires it. Administrators of CUnnect can '
            'access operational data (orders, support requests, account '
            'status) to run the service.'),
        _section('8. Data Security',
            'All traffic between the app and our servers is encrypted '
            'over HTTPS. Passwords are hashed. Access to admin tools is '
            'restricted to the CUnnect team. Additionally, screen '
            'capture is blocked throughout the app to protect the '
            'information displayed on your screen.'),
        _section('9. Data Retention & Deletion',
            'Your account data is kept while your account is active. '
            'Order history is retained for service and dispute purposes. '
            'You may request deletion of your account and associated '
            'personal data at any time through the in-app support form '
            '(Profile → Contact Us); we will remove it except where a '
            'record must be retained by law.'),
        _section('10. Your Choices',
            '• You can update your profile details in the app.\n'
            '• You can disable notifications in your phone settings '
            '(order updates will not reach you in real time).\n'
            '• You can log out of the UMS section at any time, which '
            'stops any further fetching of university data.\n'
            '• You can request a copy or deletion of your data via the '
            'support form.'),
        _section('11. Children',
            'CUnnect is intended for university students and campus '
            'partners. It is not directed at children under 16.'),
        _section('12. Changes to This Policy',
            'If this policy changes, the updated version will appear '
            'here in the app. Material changes will be announced through '
            'an in-app notification.'),
        _section('13. Contact',
            'For any privacy question or request, reach the CUnnect team '
            'through the in-app support form: Profile → Contact Us.'),
      ];

  // ------------------------------------------------------------------
  Widget _updated() => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 2),
        child: Row(children: [
          const Icon(Icons.verified_user_outlined,
              size: 13, color: AppColors.gold),
          const SizedBox(width: 6),
          Text('CUnnect — Campus Companion · Last updated: September 2026',
              style: const TextStyle(color: AppColors.muted, fontSize: 9.5)),
        ]),
      );

  Widget _section(String title, String body) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF3F3F3))),
            const SizedBox(height: 7),
            Text(body,
                style: const TextStyle(
                    color: Color(0xFFB9B9B9), fontSize: 11.5, height: 1.65)),
          ],
        ),
      );
}
