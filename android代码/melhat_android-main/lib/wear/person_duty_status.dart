enum PersonDutyStatus {
  onDuty('ON_DUTY', '在岗'),
  offDuty('OFF_DUTY', '离岗'),
  unknown('UNKNOWN', '待确认');

  const PersonDutyStatus(this.code, this.label);

  final String code;
  final String label;

  static const choices = [onDuty, offDuty];

  static PersonDutyStatus from(Object? value) =>
      values.where((status) => status.code == value).firstOrNull ?? unknown;
}
