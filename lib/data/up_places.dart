/// ⭐ v73: BUILT-IN places for CUnnect Ride.
///
/// Verified coordinates (OpenStreetMap / Nominatim) for the campus area
/// (Nawabganj - Parsandan, Unnao) plus Lucknow and Kanpur, so every
/// important place is found INSTANTLY and keeps working even with no
/// internet. Online search still runs for anything else.
///
/// Each entry is: (name, area, latitude, longitude)
const List<(String, String, double, double)> kUpPlaces = [
  ('Chandigarh University UP', 'campus', 26.621884, 80.687916),
  ('Nawabganj', 'campus', 26.613966, 80.658155),
  ('Unnao', 'unnao', 26.567326, 80.619819),
  ('Unnao Junction railway station', 'unnao', 26.549238, 80.487437),
  ('Shuklaganj', 'unnao', 26.478904, 80.388953),
  ('Bangarmau', 'unnao', 26.891645, 80.215060),
  ('Safipur', 'unnao', 26.737783, 80.344557),
  ('Hasanganj', 'unnao', 26.782903, 80.575085),
  ('Purwa', 'unnao', 26.486340, 80.836714),
  ('Magarwara', 'unnao', 26.515200, 80.430805),
  ('Achalganj', 'unnao', 26.452458, 80.565055),
  ('Charbagh railway station', 'lucknow', 26.832402, 80.923113),
  ('Lucknow Junction railway station', 'lucknow', 26.831510, 80.922298),
  ('Hazratganj', 'lucknow', 26.847528, 80.943200),
  ('Gomti Nagar', 'lucknow', 26.861174, 81.003920),
  ('Chaudhary Charan Singh Airport', 'lucknow', 26.760803, 80.893603),
  ('Alambagh bus station', 'lucknow', 26.818473, 80.907293),
  ('Aminabad', 'lucknow', 26.848700, 80.927000),
  ('Chowk', 'lucknow', 26.867715, 80.904214),
  ('Indira Nagar', 'lucknow', 26.882318, 80.990034),
  ('Aliganj', 'lucknow', 26.905150, 80.947991),
  ('Rajajipuram', 'lucknow', 26.841045, 80.852590),
  ('Lulu Mall', 'lucknow', 26.784447, 80.991520),
  ('Phoenix Palassio', 'lucknow', 26.808772, 81.012793),
  ('University of Lucknow', 'lucknow', 26.926086, 80.938124),
  ('Babu Banarasi Das University', 'lucknow', 26.888806, 81.058904),
  ('Integral University', 'lucknow', 26.958616, 81.000090),
  ('SGPGI', 'lucknow', 26.743574, 80.945172),
  ('Kaiserbagh', 'lucknow', 26.849875, 80.931454),
  ('Gomti Nagar railway station', 'lucknow', 26.861174, 81.003920),
  ('Kanpur Central railway station', 'kanpur', 26.453861, 80.351243),
  ('Kanpur Anwarganj railway station', 'kanpur', 26.455843, 80.328103),
  ('IIT Kanpur', 'kanpur', 26.513188, 80.236484),
  ('Chakeri Airport', 'kanpur', 26.405476, 80.415360),
  ('Z Square Mall', 'kanpur', 26.473372, 80.352682),
  ('Rave 3 Mall', 'kanpur', 26.491632, 80.327992),
  ('Chhatrapati Shahu Ji Maharaj University', 'kanpur', 26.503012, 80.267839),
  ('Jhakarkati bus station', 'kanpur', 26.450415, 80.340218),
  ('Civil Lines', 'kanpur', 26.476009, 80.346510),
  ('Kalyanpur', 'kanpur', 26.503716, 80.252547),
  ('Govind Nagar', 'kanpur', 26.467216, 80.304741),
  ('Kidwai Nagar', 'kanpur', 26.440989, 80.341988),
  ('Rawatpur', 'kanpur', 26.482866, 80.300073),
  ('Kanpur Nagar district', 'kanpur', 26.441011, 80.265280),
];

/// The default campus pin — Chandigarh University, Uttar Pradesh
/// (Parsandan / Nawabganj, Unnao district).
const String kCampusName = 'Chandigarh University UP';
const double kCampusLat = 26.621884;
const double kCampusLng = 80.687916;

/// Case-insensitive match against the built-in list — instant, offline.
List<(String, String, double, double)> searchUpPlaces(String query,
    {int limit = 12}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final starts = <(String, String, double, double)>[];
  final contains = <(String, String, double, double)>[];
  for (final p in kUpPlaces) {
    final name = p.$1.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(p);
    } else if (name.contains(q)) {
      contains.add(p);
    }
  }
  return <(String, String, double, double)>[...starts, ...contains]
      .take(limit)
      .toList();
}
