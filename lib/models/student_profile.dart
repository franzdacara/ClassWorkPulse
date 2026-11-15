/// Pronouns used when writing about the student.
enum Pronouns {
  she('she/her', subject: 'she', object: 'her', possessive: 'her'),
  he('he/him', subject: 'he', object: 'him', possessive: 'his'),
  they('they/them', subject: 'they', object: 'them', possessive: 'their');

  const Pronouns(
    this.label, {
    required this.subject,
    required this.object,
    required this.possessive,
  });

  final String label;
  final String subject;
  final String object;
  final String possessive;

  /// Looks up the stored value, falling back to the neutral form.
  static Pronouns fromName(String? name) =>
      values.firstWhere((p) => p.name == name, orElse: () => Pronouns.they);
}

/// Who the app is tracking, and how parent updates are addressed and signed.
class StudentProfile {
  const StudentProfile({
    this.id,
    required this.studentName,
    required this.pronouns,
    this.teacherName = '',
    this.parentTitle = defaultParentTitle,
  });

  final int? id;

  /// Ways of addressing the parent in an update.
  static const List<String> parentTitles = ["Ma'am", 'Sir', "Ma'am/Sir"];
  static const String defaultParentTitle = "Ma'am";

  final String studentName;
  final Pronouns pronouns;

  /// The teacher's name as it appears in the sign-off; may be empty.
  final String teacherName;
  final String parentTitle;
}
