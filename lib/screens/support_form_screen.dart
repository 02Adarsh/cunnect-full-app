import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_store.dart';
import '../widgets/common.dart';

/// ⭐ CUnnect support form — student + partner dono ke liye common.
void openCunnectSupportForm(BuildContext context) {
  final store = context.read<AppStore>();
  final subjectController = TextEditingController();
  final messageController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
            const Text('Tell us how we can help. Our team will review your request.',
                style:
                    TextStyle(color: Color(0xFFA5A5A5), fontSize: 11, height: 1.4)),
            const SizedBox(height: 18),
            TextField(
              controller: subjectController,
              style: const TextStyle(fontSize: 12),
              decoration: cunnectInputDecoration(placeholder: 'Subject'),
            ),
            const SizedBox(height: 11),
            TextField(
              controller: messageController,
              maxLines: 5,
              style: const TextStyle(fontSize: 12, height: 1.4),
              decoration:
                  cunnectInputDecoration(placeholder: 'Write your issue or suggestion...'),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final subject = subjectController.text.trim();
                  final message = messageController.text.trim();
                  if (subject.isEmpty || message.isEmpty) {
                    showCunnectToast(
                        context, 'Please fill in both subject and message.');
                    return;
                  }
                  final error =
                      await store.sendSupportRequest(subject, message);
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
                  textStyle:
                      const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                child: const Text('SEND REQUEST'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
