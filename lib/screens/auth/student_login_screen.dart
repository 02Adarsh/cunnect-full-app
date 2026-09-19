import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_client.dart';
import '../../services/app_store.dart';
import '../support_form_screen.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/platform_video.dart';
import '../dashboard/student_dashboard_screen.dart';
import '../vendor/vendor_login_screen.dart';

/// ⭐ Original myapp flow ka exact mirror:
/// step1 UID -> step2 password+captcha -> (step3 profile complete)
/// + REGISTER -> OTP verify -> login.
class StudentLoginScreen extends StatefulWidget {
  const StudentLoginScreen({super.key});

  @override
  State<StudentLoginScreen> createState() => _StudentLoginScreenState();
}

class _StudentLoginScreenState extends State<StudentLoginScreen> {
  String _step = 'uid'; // uid | pass | reg | otp | step3
  String? _error;
  String? _info;
  bool _busy = false;
  String _captcha = '';

  final _uid = TextEditingController();
  final _password = TextEditingController();
  final _captchaC = TextEditingController();
  final _fullName = TextEditingController();
  final _regUid = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPassword = TextEditingController();
  final _otpC = TextEditingController();
  final _s3Name = TextEditingController();
  final _s3Phone = TextEditingController();
  final _s3Dob = TextEditingController();
  final _s3Branch = TextEditingController();
  String _s3Gender = '';
  String _s3Year = '';
  String _s3Stay = '';
  bool _s3Consent = false;
  String _s3Email = '';
  Uint8List? _photoBytes;
  String _photoB64 = '';
  bool _videoError = false;
  String _dobD = '';
  String _dobM = '';
  String _dobY = '';

  @override
  void dispose() {
    for (final c in [
      _uid, _password, _captchaC, _fullName, _regUid, _regEmail,
      _regPassword, _otpC, _s3Name, _s3Phone, _s3Dob, _s3Branch,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(String step) => setState(() {
        _step = step;
        _error = null;
      });

  Future<void> _next1() async {
    final store = context.read<AppStore>();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final data = await store.authLogin1(_uid.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (data['error'] != null) {
      final legacyMsg = data['error'].toString();
      setState(() => _error = legacyMsg);
      if (legacyMsg.contains('other device') ||
          legacyMsg.contains('another device')) {
        _showDeviceWarning(legacyMsg);
      }
      return;
    }
    if (data['registered'] == false) {
      _regUid.text = _uid.text.trim();
      setState(() => _info = 'User not registered. Please register first.');
      _go('reg');
      return;
    }
    _captcha = (data['captcha'] ?? '').toString();
    _captchaC.clear();
    _go('pass');
  }

  Future<void> _login2() async {
    final store = context.read<AppStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = await store.authLogin2(
        _uid.text, _password.text, _captchaC.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (data['error'] != null) {
      // fetch a new captcha (the original served a fresh captcha on every failure)
      final msg = data['error'].toString();
      final d1 = await store.authLogin1(_uid.text);
      if (!mounted) return;
      setState(() {
        _error = msg;
        if (d1['captcha'] != null) _captcha = d1['captcha'].toString();
        _captchaC.clear();
      });
      // ⭐ v70: single-device rule — make the warning impossible to miss.
      if (msg.contains('other device') || msg.contains('another device')) {
        _showDeviceWarning(msg);
      }
      return;
    }
    if (data['need_step3'] == true) {
      _s3Name.text = (data['name'] ?? '').toString();
      _s3Email = (data['email'] ?? '').toString();
      _go('step3');
    } else {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const StudentDashboardScreen()));
    }
  }

  Future<void> _register() async {
    final store = context.read<AppStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = await store.authRegister({
      'full_name': _fullName.text.trim(),
      'user_id': _regUid.text.trim(),
      'email': _regEmail.text.trim(),
      'password': _regPassword.text,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (data['error'] != null) {
      setState(() => _error = data['error'] as String);
      return;
    }
    _otpC.clear();
    _go('otp');
    setState(() => _info = 'OTP has been sent to your email.');
  }

  Future<void> _verifyOtp() async {
    final store = context.read<AppStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = await store.authOtpVerify(_regUid.text.trim(), _otpC.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (data['error'] != null) {
      setState(() => _error = data['error'] as String);
      return;
    }
    _uid.text = _regUid.text.trim();
    _go('uid');
    setState(() => _info = 'Registration successful! You can now login.');
  }

  Future<void> _resendOtp() async {
    final store = context.read<AppStore>();
    final data = await store.authResendOtp(_regUid.text.trim());
    if (!mounted) return;
    setState(() => _info = data['error'] != null
        ? data['error'] as String
        : 'New OTP has been sent.');
  }

  /// ⭐ step3 profile photo — file_picker se image lo, base64 backend ko.
  Future<void> _pickPhoto() async {
    try {
      final res = await FilePicker.platform
          .pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null || bytes.isEmpty) return;
      if (bytes.length > 2 * 1024 * 1024) {
        setState(() => _error = 'Keep the photo under 2 MB.');
        return;
      }
      setState(() {
        _photoBytes = bytes;
        _photoB64 = base64Encode(bytes);
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not pick a photo: $e');
    }
  }

  Future<void> _completeProfile() async {
    final store = context.read<AppStore>();
    if (_photoB64.isEmpty) {
      setState(() =>
          _error = 'Profile photo is required — registration cannot be completed without a photo.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final data = await store.authCompleteProfile({
      'full_name': _s3Name.text.trim(),
      'phone': _s3Phone.text.trim(),
      'dob': _s3Dob.text.trim(),
      'gender': _s3Gender,
      'branch': _s3Branch.text.trim(),
      'year': _s3Year,
      'stay_type': _s3Stay,
      'consent': _s3Consent,
      if (_photoB64.isNotEmpty) 'photo': _photoB64,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (data['error'] != null) {
      setState(() => _error = data['error'] as String);
      return;
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const StudentDashboardScreen()));
  }

  Widget _field(TextEditingController c, String hint, IconData icon,
      {bool obscure = false, TextInputType? keyboard, bool caps = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      textCapitalization:
          caps ? TextCapitalization.characters : TextCapitalization.none,
      autocorrect: false,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.placeholder, fontSize: 13),
        prefixIcon: Icon(icon, size: 16, color: AppColors.muted),
        filled: true,
        fillColor: const Color(0xFF0C0C0C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF363636)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.red),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        height: 47,
        child: ElevatedButton(
          onPressed: _busy ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(label),
        ),
      );

  Widget _link(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFFFF9CA5), fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  String get _heading {
    switch (_step) {
      case 'pass':
        return 'PASSWORD';
      case 'reg':
        return 'REGISTRATION';
      case 'otp':
        return 'OTP VERIFICATION';
      case 'step3':
        return 'COMPLETE YOUR PROFILE';
      default:
        return 'LOGIN';
    }
  }

  String get _sub {
    switch (_step) {
      case 'pass':
        return 'Enter password + captcha for ${_uid.text.trim()}';
      case 'reg':
        return 'Register with your official @culkomail.in email';
      case 'otp':
        return 'Enter the 6-digit OTP sent to your email';
      case 'step3':
        return 'Please fill the following details to continue';
      default:
        return 'Enter your UID to continue';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ⭐ background video (like the original login page) — with sound
          if (!_videoError)
            platformVideo(
                '${ApiConfig.baseUrl}/static/images/login_background.mp4',
                'login-bg-video', false, onError: () {
              if (mounted) setState(() => _videoError = true);
            })
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.85, -0.8),
                  radius: 0.6,
                  colors: [Color(0x38F10B1D), Colors.transparent],
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(color: Color(0x73000000)),
          ),
          Positioned.fill(
            child: Container(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 390),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(25, 34, 25, 25),
                  decoration: BoxDecoration(
                    color: const Color(0xED121212),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF2B2B2B)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(.6),
                          blurRadius: 55,
                          offset: const Offset(0, 18)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const CunnectWordmarkClassic(fontSize: 42),
                      const SizedBox(height: 3),
                      const Text('YOUR CAMPUS. CONNECTED.',
                          style: TextStyle(
                              color: AppColors.gold,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2)),
                      const SizedBox(height: 26),
                      Text(_heading,
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 7),
                      Text(_sub,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12.5)),
                      const SizedBox(height: 20),
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0x1AF10B1D),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: const Color(0x80F10B1D)),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFFFABB2),
                                  fontSize: 12,
                                  height: 1.4)),
                        ),
                      if (_info != null)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 11, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0x142ECC71),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: const Color(0x662ECC71)),
                          ),
                          child: Text(_info!,
                              style: const TextStyle(
                                  color: Color(0xFF9BE8B8),
                                  fontSize: 12,
                                  height: 1.4)),
                        ),
                      ..._stepBody(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _stepBody() {
    switch (_step) {
      case 'pass':
        return [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0C),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF363636)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('CAPTCHA',
                    style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5)),
                Text(_captcha,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 6,
                        color: AppColors.gold)),
              ],
            ),
          ),
          _field(_password, 'App password (set at registration)',
              Icons.lock_outline,
              obscure: true),
          const SizedBox(height: 14),
          _field(_captchaC, 'Type captcha', Icons.shield_outlined, caps: true),
          const SizedBox(height: 20),
          _button('LOGIN', _login2),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _link('← Back', () => _go('uid')),
              // ⭐ v58: real reset — emails a secure link to set a new
              // password (replaces the old contact-us fallback).
              _link('Forgot password?',
                  () => openForgotPasswordSheet(context)),
            ],
          ),
          const SizedBox(height: 14),
        ];
      case 'reg':
        return [
          _field(_fullName, 'Full name', Icons.person_outline),
          const SizedBox(height: 14),
          _field(_regUid, 'User ID', Icons.badge_outlined),
          const SizedBox(height: 14),
          _field(_regEmail, 'Email (@culkomail.in)', Icons.mail_outline,
              keyboard: TextInputType.emailAddress),
          const SizedBox(height: 14),
          _field(_regPassword, 'Set password', Icons.lock_outline, obscure: true),
          const SizedBox(height: 20),
          _button('SEND OTP', _register),
          const SizedBox(height: 14),
          _link('← Back to login', () => _go('uid')),
          const SizedBox(height: 14),
        ];
      case 'otp':
        return [
          _field(_otpC, '6-digit OTP', Icons.pin_outlined,
              keyboard: TextInputType.number),
          const SizedBox(height: 20),
          _button('VERIFY OTP', _verifyOtp),
          const SizedBox(height: 14),
          _link('Resend OTP', _resendOtp),
          const SizedBox(height: 14),
        ];
      case 'step3':
        return [
          // ⭐ profile photo upload
          Center(
            child: GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x1FFF0000),
                  border: Border.all(color: AppColors.red, width: 2),
                ),
                alignment: Alignment.center,
                child: _photoBytes != null
                    ? ClipOval(
                        child: Image.memory(_photoBytes!,
                            width: 92, height: 92, fit: BoxFit.cover),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              color: Color(0xFFFF9CA5), size: 28),
                          SizedBox(height: 2),
                          Text('PHOTO',
                              style: TextStyle(
                                  color: Color(0xFFFF9CA5),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1)),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
                _photoBytes != null
                    ? 'Photo selected — tap to change'
                    : 'Upload your photo (required)',
                style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ),
          const SizedBox(height: 16),
          _readonlyBox('User ID (UID)', _uid.text.trim(),
              'This User ID cannot be changed.'),
          _readonlyBox('Email Address', _s3Email,
              'This email is verified and cannot be changed.'),
          _readonlyBox('Full Name', _s3Name.text, 'This name cannot be changed.'),
          _field(_s3Phone, 'Phone Number (WhatsApp)', Icons.phone_outlined,
              keyboard: TextInputType.phone),
          const SizedBox(height: 14),
          const Text('Date of Birth',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: _dropdown('Date', _dobD,
                  ['', for (var i = 1; i <= 31; i++) '$i'.padLeft(2, '0')],
                  (v) => _setDob(d: v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown('Month', _dobM,
                  ['', ..._MONTHS.keys], (v) => _setDob(m: v)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _dropdown('Year', _dobY,
                  ['',
                    for (var i = 0; i < 70; i++)
                      '${DateTime.now().year - 16 - i}'],
                  (v) => _setDob(y: v)),
            ),
          ]),
          const SizedBox(height: 14),
          _dropdown('Select Gender', _s3Gender, ['', 'Male', 'Female', 'Other'],
              (v) => _s3Gender = v),
          const SizedBox(height: 14),
          _coursePicker(),
          const SizedBox(height: 14),
          _dropdown('Select Year', _s3Year, ['', '1st Year', '2nd Year'],
              (v) => _s3Year = v),
          const SizedBox(height: 14),
          _dropdown('Hostel / Day Scholar', _s3Stay,
              ['', 'Hostel', 'Day Scholar'], (v) => _s3Stay = v),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _s3Consent,
                activeColor: AppColors.red,
                onChanged: (v) => setState(() => _s3Consent = v ?? false),
              ),
              const Expanded(
                child: Text(
                    'I agree to receive updates and offers via WhatsApp/Email',
                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _button('COMPLETE REGISTRATION', _completeProfile),
        ];
      default:
        return [
          _field(_uid, 'Enter UID', Icons.person_outline),
          const SizedBox(height: 20),
          _button('NEXT', _next1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFF333333))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR',
                      style: TextStyle(
                          color: AppColors.muted.withOpacity(.7), fontSize: 11)),
                ),
                const Expanded(child: Divider(color: Color(0xFF333333))),
              ],
            ),
          ),
          InkWell(
            onTap: () => _go('reg'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x99D4C7A3)),
              ),
              child: const Text('CLICK HERE FOR REGISTRATION',
                  style: TextStyle(
                      color: AppColors.gold,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          // ⭐ chota vendor login option — student login screen pe hi
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Partner?  ',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const VendorLoginScreen())),
                child: const Text('Partner Login',
                    style: TextStyle(
                        color: Color(0xFFFF9CA5),
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ];
    }
  }

  Widget _dropdown(String label, String value, List<String> options,
      ValueChanged<String> onCh) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C0C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF363636)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF141414),
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          hint: Text(label,
              style: const TextStyle(color: AppColors.placeholder, fontSize: 12.5)),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(o.isEmpty ? label : o)),
          ],
          onChanged: (v) => setState(() => onCh(v ?? '')),
        ),
      ),
    );
  }

  static const _MONTHS = {
    'January': '01', 'February': '02', 'March': '03', 'April': '04',
    'May': '05', 'June': '06', 'July': '07', 'August': '08',
    'September': '09', 'October': '10', 'November': '11', 'December': '12',
  };

  void _setDob({String? d, String? m, String? y}) {
    setState(() {
      if (d != null) _dobD = d;
      if (m != null) _dobM = m;
      if (y != null) _dobY = y;
      if (_dobD.isNotEmpty && _dobM.isNotEmpty && _dobY.isNotEmpty) {
        _s3Dob.text = '$_dobY-${_MONTHS[_dobM]}-$_dobD';
      }
    });
  }

  Widget _readonlyBox(String label, String value, String note) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF363636)),
            ),
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Text(note,
                style:
                    const TextStyle(color: Color(0xFF71717A), fontSize: 10)),
          ),
        ],
      );

/// ⭐ grouped + searchable course picker from the original login_step3.html
  static const Map<String, List<String>> _COURSE_GROUPS = {
    'Collaboration': [
      'B.Tech - CSE with AI & ML',
      'B.Tech - CSE with Data Science',
      'B.Tech - CSE Cyber Security',
      'B.Tech - CSE with Cloud Computing',
      'M.Tech - CSE with AI & ML',
      'BBA Fintech + ACCA (International Accounting & Finance)',
      'BBA(H) - Business Analytics',
      'MBA - Applied Finance',
      'MBA Fintech',
      'MBA - Data Science & AI',
      'MBA Business Analytics',
      'MBA - Strategic HR',
      'B.Com(H) + ACCA (International Accounting & Finance)',
      'BCA(H) - Data Science',
      'MCA - AI & ML',
    ],
    'Engineering': [
      'B.Tech - Civil Engineering',
      'B.Tech - Mechanical Engineering',
      'B.Tech - Aerospace Engineering',
      'B.Tech - Electronics and Communication Engineering',
      'B.Tech - Biotechnology',
      'B.Tech - Electrical Engineering',
      'B.Tech - Robotics & Automation',
      'B.Tech - Computer Science & Engineering',
      'B.Tech - Information Technology',
      'B.Tech - CSE IoT & AI',
      'M.Tech - CSE Data Science',
    ],
    'Applied Sciences': [
      'B.Sc. (Hons./Hons. with Research) Data Science',
      'B.Sc. (Hons./Hons. with Research) Biotechnology',
      'B.Sc. (Hons./Hons. with Research) Forensic Science',
      'B.Sc. (Hons. with Research) Microbiology',
      'M.Sc. Data Science',
      'M.Sc. Biotechnology',
    ],
    'Business': [
      'BBA (Hons)',
      'BBA-DM (Hons)',
      'BBA - Branding & Advertising (Hons)',
      'MBA - Global Business Management',
      'MBA',
      'MBA (Digital Marketing)',
    ],
    'Liberal Arts & Behavioural Science': [
      'B.A. Liberal Arts (Hons)',
      'B.A. Psychology (Hons)',
    ],
    'Legal Studies': [
      'Bachelor of Law (LLB)',
      'B.A. LL.B. (Hons) Integrated',
      'BBA.LL.B. (Hons) Integrated',
      'LL.M. in Criminal Law',
      'LL.M. in Constitutional Law',
      'LL.M. in Corporate and Business Law',
    ],
    'Computing': [
      'BCA (Hons)',
      'BCA (Hons) AI & ML',
      'MCA',
      'MCA Data Science',
    ],
    'Design': [
      'Bachelor of Design - Fashion & Design',
      'Bachelor of Design - Interior Design',
    ],
    'Media Studies': [
      'BA-JMC',
      'B.Sc. (Hons) - Animation, VFX & Gaming',
    ],
    'Commerce': ['B.Com (Hons)'],
    'Pharmacy': ['Bachelor of Pharmacy'],
    'Hospitality': ['B.Sc. - Hotel and Hospitality Management'],
    'Travel and Tourism': ['B.Sc. - Airlines & Airport Management'],
    'Architecture and Planning': ['B.Arch'],
  };

  Widget _coursePicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Course',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () async {
              final picked = await showDialog<String>(
                  context: context, builder: (_) => const _CourseSearchDialog());
              if (picked != null) setState(() => _s3Branch.text = picked);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF363636)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                      _s3Branch.text.isEmpty
                          ? 'Search and select your course'
                          : _s3Branch.text,
                      style: TextStyle(
                          color: _s3Branch.text.isEmpty
                              ? AppColors.placeholder
                              : Colors.white,
                          fontSize: 12.5)),
                ),
                const Icon(Icons.arrow_drop_down,
                    color: Color(0xFFA1A1AA), size: 20),
              ]),
            ),
          ),
        ],
      );

  Widget _portalLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(label,
          style: const TextStyle(
              color: Color(0xFFFF9CA5), fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  /// ⭐ v70: the account is live on another phone — say it loudly.
  void _showDeviceWarning(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.smartphone_rounded,
                color: Color(0xFFFFD34D), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text('Already signed in',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
              color: Color(0xFFB7B7BC), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK',
                style: TextStyle(
                    color: Color(0xFFF10B1D),
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

}

/// ⭐ searchable + grouped course dropdown like the original login_step3.html
class _CourseSearchDialog extends StatefulWidget {
  const _CourseSearchDialog();
  @override
  State<_CourseSearchDialog> createState() => _CourseSearchDialogState();
}

class _CourseSearchDialogState extends State<_CourseSearchDialog> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase().trim();
    final groups = _StudentLoginScreenState._COURSE_GROUPS.entries
        .map((e) => MapEntry(
            e.key,
            e.value
                .where((c) =>
                    q.isEmpty ||
                    c.toLowerCase().contains(q) ||
                    e.key.toLowerCase().contains(q))
                .toList()))
        .where((e) => e.value.isNotEmpty)
        .toList();
    return Dialog(
      backgroundColor: const Color(0xFF18181B),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 430),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF363636)),
              ),
              child: TextField(
                controller: _c,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search course...',
                    hintStyle:
                        TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: Color(0xFFA1A1AA))),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: groups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No course found',
                          style: TextStyle(
                              color: Color(0xFFA1A1AA), fontSize: 12)),
                    )
                  : SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final g in groups) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 10, 8, 4),
                                child: Text(g.key.toUpperCase(),
                                    style: const TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: .8)),
                              ),
                              for (final c in g.value)
                                InkWell(
                                  onTap: () =>
                                      Navigator.of(context).pop(c),
                                  borderRadius: BorderRadius.circular(9),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    child: Text(c,
                                        style: const TextStyle(
                                            color: Color(0xFFE5E5E5),
                                            fontSize: 12)),
                                  ),
                                ),
                            ],
                          ]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }


}
