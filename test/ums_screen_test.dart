import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:cunnect_food/services/api_client.dart';
import 'package:cunnect_food/services/app_store.dart';
import 'package:cunnect_food/screens/ums/ums_dashboard_screen.dart';

Map<String, dynamic> demo() => {
      'student_name': 'Demo Student',
      'uid': 'DEMO0001',
      'overall_attendance': 82.4,
      'total_attended': 91,
      'total_held': 113,
      'total_missed': 22,
      'attendance': [
        {'code': 'CSE201', 'title': 'Data Structures', 'attended': 34, 'total': 40, 'percentage': 85.0, 'miss': 5, 'need': 0},
        {'code': 'CSE202', 'title': 'Operating Systems', 'attended': 27, 'total': 38, 'percentage': 71.1, 'miss': 0, 'need': 5},
      ],
      'timetable': {
        'MON': {
          'slots': [
            {'time': '09:00 - 10:00', 'type': 'THEORY', 'title': 'Data Structures', 'teacher': 'Dr. Sharma', 'code': 'CSE201', 'room': 'AB-204'},
          ],
        },
      },
      'course_plan': {
        'found': true,
        'page_pdfs': [
          {'label': 'Academic Calendar', 'view_url': 'http://x/cal.pdf'},
        ],
        'courses': [
          {
            'code': 'CSE201',
            'title': 'Data Structures',
            'meta': ['4 CREDITS'],
            'plan_view_url': 'http://x/plan.pdf',
            'plan': [
              {'rows': [
                ['Unit', 'Topic', 'Lectures'],
                ['1', 'Arrays', 'L1-L6'],
              ]},
            ],
          },
        ],
      },
      'exam_results': [
        {
          'semester': 'Sem 1',
          'sgpa': '8.3',
          'sessions': [
            {
              'name': 'End Sem',
              'subjects': [
                {'code': 'CSE101', 'title': 'PF', 'credits': 4, 'internal': 28, 'external': 45, 'score': 73.0, 'grade': 'A'},
              ],
            },
          ],
        },
      ],
      'notices': [
        {
          'title': 'Mid-sem schedule',
          'department': 'Examination Cell',
          'date': '21 Aug 2026',
          'desc': 'Exams 1-7 September tak honge. ' * 8,
          'files': [
            {'name': 'exam_schedule.pdf', 'url': 'http://x/f.pdf'},
          ],
        },
      ],
      'fee_summary': {'total': 95000, 'paid': 70000, 'due': 25000, 'latest': '15 Jul 2026', 'receipt_count': 2},
      'fee_records': [
        {'receipt': 'RCPT-1023', 'title': 'Tuition', 'amount': 45000, 'date': '10 Jan 2026', 'status': 'Paid'},
      ],
      'hostel_details': {
        'found': true,
        'kv': [
          {'label': 'Hostel Name', 'value': 'BH2'},
          {'label': 'Room No', 'value': 'B2-114'},
        ],
      },
      'student_profile': {
        'found': true,
        'name': 'Demo Student',
        'sections': [
          {'heading': 'Academic', 'rows': [
            {'label': 'UID', 'value': 'DEMO0001'},
          ]},
        ],
      },
    };

Future<Widget> pumpApp(WidgetTester tester, Map<String, dynamic> data) async {
  final client = MockClient((req) async => http.Response(
      jsonEncode({'ok': true, 'data': data}), 200,
      headers: {'content-type': 'application/json'}));
  final store = AppStore(apiClient: ApiClient(httpClient: client));
  await tester.pumpWidget(ChangeNotifierProvider<AppStore>.value(
    value: store,
    child: const MaterialApp(home: UmsDashboardScreen()),
  ));
  await tester.pump();
  await tester.pump();
  return const UmsDashboardScreen();
}

void main() {
  testWidgets('demo shape: saare tabs render', (tester) async {
    await pumpApp(tester, demo());
    expect(find.text('Attendance'), findsWidgets);
    for (final label in ['SCHEDULE', 'COURSES', 'RESULTS', 'NOTICES', 'FEES', 'HOSTEL', 'PROFILE', 'ATTENDANCE']) {
      await tester.tap(find.text(label));
      await tester.pump();
      expect(find.byType(UmsDashboardScreen), findsOneWidget);
    }
    // courses tab pe PDF button
    await tester.tap(find.text('COURSES'));
    await tester.pump();
    expect(find.text('▤ LECTURE PLAN · OPEN PDF'), findsNothing); // collapsed
    await tester.tap(find.text('Data Structures').last);
    await tester.pump();
    expect(find.text('▤ LECTURE PLAN · OPEN PDF'), findsOneWidget);
  });

  testWidgets('predict sheet opens + slider', (tester) async {
    await pumpApp(tester, demo());
    await tester.tap(find.text('PREDICT ↗'));
    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    expect(find.text('Attendance Prediction'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('real shape: subject_grades + kv profile', (tester) async {
    final data = demo();
    data.remove('exam_results');
    data['subject_grades'] = [
      {'code': 'CSE101', 'title': 'PF', 'internal': 28, 'external': 45, 'score': 73, 'grade': 'A'},
    ];
    data['student_profile'] = {
      'found': true,
      'name': 'Real Student',
      'kv': [
        {'label': 'Program', 'value': 'BTech CSE'},
      ],
    };
    await pumpApp(tester, data);
    await tester.tap(find.text('RESULTS'));
    await tester.pump();
    expect(find.text('PF'), findsWidgets);
    await tester.tap(find.text('PROFILE'));
    await tester.pump();
    expect(find.text('Real Student'), findsWidgets);
  });

  testWidgets('kharab shape bhi crash na kare', (tester) async {
    final data = demo();
    data['timetable'] = 'galat-string';
    data['attendance'] = [42, null, 'x'];
    data['notices'] = {'nahi': 'list'};
    data['course_plan'] = [1, 2];
    data['fee_summary'] = 'x';
    data['hostel_details'] = 7;
    data['student_profile'] = false;
    await pumpApp(tester, data);
    for (final label in ['SCHEDULE', 'COURSES', 'NOTICES', 'FEES', 'HOSTEL', 'PROFILE', 'ATTENDANCE']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(find.byType(UmsDashboardScreen), findsOneWidget);
  });

  testWidgets('empty data -> empty state', (tester) async {
    await pumpApp(tester, {});
    expect(find.text('PORTAL OFFLINE · NO DATA'), findsOneWidget);
  });
}
