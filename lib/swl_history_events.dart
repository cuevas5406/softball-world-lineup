/// A pitch is shown only if the stored event completed the plate appearance.
/// All other event types, including actions by runners, keep their entries.
bool swlIsHistoryPlay(Map<String, dynamic> event) {
  final type = event['event_type']?.toString().trim().toUpperCase();
  if (type == 'FOUL') return false;
  if (type != 'BALL' && type != 'STRIKE') return true;
  final data = event['event_data'];
  return data is Map && data['plate_appearance_completed'] == true;
}
