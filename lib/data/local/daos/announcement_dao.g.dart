// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'announcement_dao.dart';

// ignore_for_file: type=lint
mixin _$AnnouncementDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $AnnouncementsTable get announcements => attachedDatabase.announcements;
  $FeedbackTable get feedback => attachedDatabase.feedback;
  AnnouncementDaoManager get managers => AnnouncementDaoManager(this);
}

class AnnouncementDaoManager {
  final _$AnnouncementDaoMixin _db;
  AnnouncementDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$AnnouncementsTableTableManager get announcements =>
      $$AnnouncementsTableTableManager(_db.attachedDatabase, _db.announcements);
  $$FeedbackTableTableManager get feedback =>
      $$FeedbackTableTableManager(_db.attachedDatabase, _db.feedback);
}
