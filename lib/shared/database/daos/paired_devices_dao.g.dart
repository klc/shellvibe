// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paired_devices_dao.dart';

// ignore_for_file: type=lint
mixin _$PairedDevicesDaoMixin on DatabaseAccessor<AppDatabase> {
  $PairedDevicesTable get pairedDevices => attachedDatabase.pairedDevices;
  PairedDevicesDaoManager get managers => PairedDevicesDaoManager(this);
}

class PairedDevicesDaoManager {
  final _$PairedDevicesDaoMixin _db;
  PairedDevicesDaoManager(this._db);
  $$PairedDevicesTableTableManager get pairedDevices =>
      $$PairedDevicesTableTableManager(_db.attachedDatabase, _db.pairedDevices);
}
