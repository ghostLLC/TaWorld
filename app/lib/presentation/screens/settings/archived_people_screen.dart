import 'package:flutter/material.dart';
import '../../../data/models/partner.dart';
import '../../../services/local/partner_service.dart';

class ArchivedPeopleScreen extends StatefulWidget {
  const ArchivedPeopleScreen({super.key});
  @override
  State<ArchivedPeopleScreen> createState() => _ArchivedPeopleScreenState();
}

class _ArchivedPeopleScreenState extends State<ArchivedPeopleScreen> {
  List<Partner> _people = [];
  bool _loading = true;
  String? _error, _restoring;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await PartnerService.getAll(includeDissolved: true);
      if (!mounted) return;
      setState(() {
        _people = people.where((p) => p.status != 'active').toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '暂时无法读取，请重试';
        });
      }
    }
  }

  Future<void> _restore(Partner person) async {
    setState(() => _restoring = person.id);
    try {
      await PartnerService.restore(person.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已恢复${person.nickname}，原资料和提醒设置已保留')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('恢复未完成，请重试')));
      }
    } finally {
      if (mounted) setState(() => _restoring = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('已移出的人')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text('移出列表后，资料仍保存在这部手机。恢复后会按原来的开关重新安排提醒。'),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('重试')),
              ] else if (_people.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('没有已移出的人')),
                )
              else
                for (final person in _people)
                  Card(
                    child: ListTile(
                      title: Text(person.nickname),
                      subtitle: Text(
                        [
                          person.typeLabel,
                          if (person.city?.isNotEmpty == true) person.city!,
                        ].join(' · '),
                      ),
                      trailing: TextButton(
                        onPressed: _restoring == null
                            ? () => _restore(person)
                            : null,
                        child: Text(_restoring == person.id ? '恢复中' : '恢复'),
                      ),
                    ),
                  ),
            ],
          ),
  );
}
