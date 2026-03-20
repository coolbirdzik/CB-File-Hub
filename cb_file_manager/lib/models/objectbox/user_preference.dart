enum PreferenceType {
  string,
  integer,
  double,
  boolean,
}

class UserPreference {
  int id;
  final String key;
  String? stringValue;
  int? intValue;
  double? doubleValue;
  bool? boolValue;
  int typeValue;
  final int timestamp;

  PreferenceType get type => PreferenceType.values[typeValue];
  set type(PreferenceType value) => typeValue = value.index;

  UserPreference({
    this.id = 0,
    required this.key,
    this.stringValue,
    this.intValue,
    this.doubleValue,
    this.boolValue,
    required this.typeValue,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  UserPreference.string({
    this.id = 0,
    required this.key,
    required String value,
    int? timestamp,
  })  : stringValue = value,
        intValue = null,
        doubleValue = null,
        boolValue = null,
        typeValue = PreferenceType.string.index,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  UserPreference.integer({
    this.id = 0,
    required this.key,
    required int value,
    int? timestamp,
  })  : stringValue = null,
        intValue = value,
        doubleValue = null,
        boolValue = null,
        typeValue = PreferenceType.integer.index,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  UserPreference.double({
    this.id = 0,
    required this.key,
    required double value,
    int? timestamp,
  })  : stringValue = null,
        intValue = null,
        doubleValue = value,
        boolValue = null,
        typeValue = PreferenceType.double.index,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  UserPreference.boolean({
    this.id = 0,
    required this.key,
    required bool value,
    int? timestamp,
  })  : stringValue = null,
        intValue = null,
        doubleValue = null,
        boolValue = value,
        typeValue = PreferenceType.boolean.index,
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;
}
