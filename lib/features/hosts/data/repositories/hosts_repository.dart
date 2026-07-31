import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/hosts_dao.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';

class HostsRepository {
  final HostsDao hostsDao;

  HostsRepository({required this.hostsDao});

  // --- Hosts CRUD ---

  Future<HostModel> saveHost({
    String? id,
    required String workspaceId,
    String? groupId,
    String? identityId,
    required String label,
    required String hostname,
    int port = 22,
    String protocol = 'ssh',
    String? colorTag,
    String? jumpHostId,
  }) async {
    final hostId = id ?? const Uuid().v4();
    final now = DateTime.now();

    final companion = HostsCompanion(
      id: Value(hostId),
      workspaceId: Value(workspaceId),
      groupId: groupId != null ? Value(groupId) : const Value.absent(),
      identityId: identityId != null ? Value(identityId) : const Value.absent(),
      label: Value(label),
      hostname: Value(hostname),
      port: Value(port),
      protocol: Value(protocol),
      colorTag: colorTag != null ? Value(colorTag) : const Value.absent(),
      jumpHostId: jumpHostId != null ? Value(jumpHostId) : const Value.absent(),
      createdAt: Value(now),
    );

    if (id == null) {
      await hostsDao.insertHost(companion);
    } else {
      await hostsDao.updateHost(companion);
    }

    return HostModel(
      id: hostId,
      workspaceId: workspaceId,
      groupId: groupId,
      identityId: identityId,
      label: label,
      hostname: hostname,
      port: port,
      protocol: protocol,
      colorTag: colorTag,
      jumpHostId: jumpHostId,
      createdAt: now,
    );
  }

  Future<List<HostModel>> getAllHosts() async {
    final rows = await hostsDao.getAllHosts();
    return rows
        .map(
          (row) => HostModel(
            id: row.id,
            workspaceId: row.workspaceId,
            groupId: row.groupId,
            identityId: row.identityId,
            label: row.label,
            hostname: row.hostname,
            port: row.port,
            protocol: row.protocol,
            colorTag: row.colorTag,
            jumpHostId: row.jumpHostId,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }

  Future<HostModel?> getHostById(String id) async {
    final row = await hostsDao.getHostById(id);
    if (row == null) return null;
    return HostModel(
      id: row.id,
      workspaceId: row.workspaceId,
      groupId: row.groupId,
      identityId: row.identityId,
      label: row.label,
      hostname: row.hostname,
      port: row.port,
      protocol: row.protocol,
      colorTag: row.colorTag,
      jumpHostId: row.jumpHostId,
      createdAt: row.createdAt,
    );
  }

  Future<void> deleteHost(String id) async {
    await hostsDao.deleteHost(id);
  }

  Stream<List<Host>> watchHosts() {
    return hostsDao.watchAllHosts();
  }

  // --- Host Groups CRUD ---

  Future<HostGroupModel> saveHostGroup({
    String? id,
    required String workspaceId,
    String? parentId,
    required String name,
    String? colorTag,
  }) async {
    final groupId = id ?? const Uuid().v4();

    final companion = HostGroupsCompanion(
      id: Value(groupId),
      workspaceId: Value(workspaceId),
      parentId: parentId != null ? Value(parentId) : const Value.absent(),
      name: Value(name),
      colorTag: colorTag != null ? Value(colorTag) : const Value.absent(),
    );

    if (id == null) {
      await hostsDao.insertHostGroup(companion);
    } else {
      await hostsDao.updateHostGroup(companion);
    }

    return HostGroupModel(
      id: groupId,
      workspaceId: workspaceId,
      parentId: parentId,
      name: name,
      colorTag: colorTag,
    );
  }

  Future<List<HostGroupModel>> getAllHostGroups() async {
    final rows = await hostsDao.getAllHostGroups();
    return rows
        .map(
          (row) => HostGroupModel(
            id: row.id,
            workspaceId: row.workspaceId,
            parentId: row.parentId,
            name: row.name,
            colorTag: row.colorTag,
          ),
        )
        .toList();
  }

  Future<HostGroupModel?> getHostGroupById(String id) async {
    final row = await hostsDao.getHostGroupById(id);
    if (row == null) return null;
    return HostGroupModel(
      id: row.id,
      workspaceId: row.workspaceId,
      parentId: row.parentId,
      name: row.name,
      colorTag: row.colorTag,
    );
  }

  Future<void> deleteHostGroup(String id) async {
    await hostsDao.deleteHostGroup(id);
  }

  Stream<List<HostGroup>> watchHostGroups() {
    return hostsDao.watchAllHostGroups();
  }
}
