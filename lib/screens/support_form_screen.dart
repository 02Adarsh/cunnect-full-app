import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_store.dart';
import '../widgets/common.dart';

/// ⭐ CUnnect support form — shared by students and partners.
/// v58: the subject is a dropdown (Feedback / Suggestion / Query).
void openCunnectSupportForm(BuildContext context) {
  final store = context.read<AppStore>();
  final messageController = TextEditingController();
  String? subject;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x8CF1000D)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Contact Us',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              const Text(
                  'Tell us how we can help. Our team will review your request.',
                  style: TextStyle(
                      color: Color(0xFFA5A5A5), fontSize: 11, height: 1.4)),
              const SizedBox(height: 18),
              // ⭐ v58: subject dropdown — Feedback / Suggestion / Query
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D0D0D),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFF303030)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: subject,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1B1B1B),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xFF8A8A8A), size: 19),
                    hint: const Text('Select a subject',
                        style: TextStyle(
                            color: Color(0xFF7A7A7A), fontSize: 12)),
                    style: const TextStyle(
                        color: Color(0xFFF2F2F2), fontSize: 12.5),
                    items: const [
                      DropdownMenuItem(
                          value: 'Feedback', child: Text('Feedback')),
                      DropdownMenuItem(
                          value: 'Suggestion', child: Text('Suggestion')),
                      DropdownMenuItem(value: 'Query', child: Text('Query')),
                      // ⭐ v66: brands / creators reach out for collabs.
                      DropdownMenuItem(
                          value: 'Collaboration',
                          child: Text('Collaboration')),
                    ],
                    onChanged: (v) => setSheetState(() => subject = v),
                  ),
                ),
              ),
              const SizedBox(height: 11),
              TextField(
                controller: messageController,
                maxLines: 5,
                style: const TextStyle(fontSize: 12, height: 1.4),
                decoration: cunnectInputDecoration(
                    placeholder: 'Write your issue or suggestion...'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final message = messageController.text.trim();
                    if (subject == null || message.isEmpty) {
                      showCunnectToast(context,
                          'Please pick a subject and write your message.');
                      return;
                    }
                    final error =
                        await store.sendSupportRequest(subject!, message);
                    if (!context.mounted) return;
                    Navigator.of(sheetContext).pop();
                    showCunnectToast(
                        context,
                        error != null
                            ? error
                            : 'Support request sent. We will get back to you!');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1000D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  child: const Text('SEND REQUEST'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// ⭐ v58: Forgot-password sheet — sends a themed reset LINK to the
/// account's registered email (replaces the old contact-us fallback).
void openForgotPasswordSheet(BuildContext context) {
  final store = context.read<AppStore>();
  final idController = TextEditingController();
  bool busy = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0x8CF1000D)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Forgot password?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              const Text(
                  'Enter your User ID, registered email, or (partners) your '
                  'registered phone number. We will email you a secure link '
                  'to set a new password.',
                  style: TextStyle(
                      color: Color(0xFFA5A5A5), fontSize: 11, height: 1.4)),
              const SizedBox(height: 18),
              TextField(
                controller: idController,
                style: const TextStyle(fontSize: 12.5),
                decoration: cunnectInputDecoration(
                    placeholder: 'User ID / email / registered phone'),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final id = idController.text.trim();
                          if (id.isEmpty) {
                            showCunnectToast(
                                context, 'Enter your User ID first.');
                            return;
                          }
                          setSheetState(() => busy = true);
                          final r = await store.authForgotLink(id);
                          if (!context.mounted) return;
                          setSheetState(() => busy = false);
                          final err = r['error'];
                          if (err != null) {
                            showCunnectToast(context, '$err', error: true);
                            return;
                          }
                          Navigator.of(sheetContext).pop();
                          showCunnectToast(
                              context,
                              'Reset link sent to ${r['email'] ?? 'your email'}'
                              ' — set a new password from there, then log in.');
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF1000D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('EMAIL ME A RESET LINK'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
