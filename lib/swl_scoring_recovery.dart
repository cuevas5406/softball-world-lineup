/// PostgREST reports both HTTP statuses and five-character PostgreSQL codes.
/// A SQL rejection rolls back the transaction, even for all-numeric codes.
bool swlIsUncertainHttpStatus(String? code) {
  if (code == null || !RegExp(r'^\d{3}$').hasMatch(code)) return false;
  final status = int.parse(code);
  return status == 408 || status >= 500 && status <= 599;
}

enum SwlScoringRecovery { waitForRead, reviewAdvanced, retryAfterReview }

SwlScoringRecovery swlScoringRecovery({
  required int sentVersion,
  required int? officialVersion,
  required bool explicitRefresh,
}) {
  if (officialVersion == null || officialVersion < sentVersion) {
    return SwlScoringRecovery.waitForRead;
  }
  if (officialVersion > sentVersion) return SwlScoringRecovery.reviewAdvanced;
  // A manual retry is a new version-checked request. If the previous request
  // is still finishing, the server can commit only one mutation of this version.
  return explicitRefresh
      ? SwlScoringRecovery.retryAfterReview
      : SwlScoringRecovery.waitForRead;
}
