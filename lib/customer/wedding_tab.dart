import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/widgets.dart';
import 'explore_tab.dart';

class _Counts {
  int done = 0, pending = 0, skipped = 0, notDone = 0;
  int get total => done + pending + skipped + notDone;
  double get progress => (total - skipped) == 0 ? 0 : done / (total - skipped);

  static _Counts of(Iterable<Map<String, dynamic>> tasks) {
    final c = _Counts();
    for (final t in tasks) {
      switch (t['status']) {
        case 'done':
          c.done++;
        case 'skipped':
          c.skipped++;
        case 'not_done':
          c.notDone++;
        default:
          c.pending++;
      }
    }
    return c;
  }
}

Future<List<Map<String, dynamic>>> _loadEvents() async {
  final rows = await supa
      .from('wedding_events')
      .select('*, event_checklists(*)')
      .eq('customer_id', myId)
      .order('event_date', ascending: true)
      .order('sort', ascending: true);
  return rows;
}

/// "My Wedding" tab: all events with progress, plus the overall summary.
class WeddingTab extends StatelessWidget {
  const WeddingTab({super.key});

  Future<void> _addEvent(BuildContext context, List<Map<String, dynamic>> existing) async {
    final names = existing.map((e) => str(e['name']).toLowerCase()).toSet();
    final result = await showModalBottomSheet<(String, DateTime?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventSheet(suggestions: weddingEvents.where((e) => !names.contains(e.toLowerCase())).toList()),
    );
    if (result == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.rpc('add_wedding_event', params: {
        'p_name': result.$1,
        'p_date': result.$2 == null ? null : ymd(result.$2!),
      });
    }, success: '${result.$1} added with its checklist');
    if (ok) bumpData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Wedding')),
      body: Loader<List<Map<String, dynamic>>>(
        load: _loadEvents,
        builder: (context, events, reload) {
          final allTasks = events.expand((e) => asList(e['event_checklists']));
          final overall = _Counts.of(allTasks);
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              AppCard(
                color: kMaroon,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Overall progress',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                    const Spacer(),
                    Text('${(overall.progress * 100).round()}%',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: kGold)),
                  ]),
                  const SizedBox(height: 10),
                  ProgressBar(overall.progress, color: kGold),
                  const SizedBox(height: 14),
                  Row(children: [
                    _count('Completed', overall.done, Colors.white),
                    _count('Pending', overall.pending + overall.notDone, Colors.white),
                    _count('Skipped', overall.skipped, Colors.white70),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              if (events.isEmpty)
                EmptyView(
                  icon: Icons.event_note,
                  title: 'No events yet',
                  subtitle: 'Add Aiburo Bhat, Gaye Holud, Biye, Bou Bhat and more. Each comes with a checklist.',
                  action: FilledButton.icon(
                    onPressed: () => _addEvent(context, events),
                    icon: const Icon(Icons.add),
                    label: const Text('Add event'),
                  ),
                ),
              for (final e in events) _EventCard(event: e),
            ]),
          );
        },
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          backgroundColor: kMaroon,
          foregroundColor: Colors.white,
          onPressed: () async {
            try {
              final events = await _loadEvents();
              if (context.mounted) await _addEvent(context, events);
            } catch (e) {
              if (context.mounted) showSnack(context, friendlyError(e), error: true);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('Add event'),
        ),
      ),
    );
  }

  Widget _count(String label, int n, Color color) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w700)),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ]),
      );
}

class _EventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  const _EventCard({required this.event});
  @override
  Widget build(BuildContext context) {
    final c = _Counts.of(asList(event['event_checklists']));
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => EventChecklistScreen(eventId: event['id'] as String))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: kCream, shape: BoxShape.circle),
            child: const Icon(Icons.celebration, color: kMaroon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(str(event['name']), style: Theme.of(context).textTheme.titleMedium),
              Text(
                '${fmtDate(event['event_date'], 'Date not set')}${str(event['location']).isEmpty ? '' : ' · ${str(event['location'])}'}',
                style: const TextStyle(color: kMuted, fontSize: 12),
              ),
            ]),
          ),
          Text('${c.done}/${c.total - c.skipped}', style: const TextStyle(fontWeight: FontWeight.w700, color: kMaroon)),
          const Icon(Icons.chevron_right, color: kMuted),
        ]),
        const SizedBox(height: 12),
        ProgressBar(c.progress),
        const SizedBox(height: 6),
        Text('${c.done} done · ${c.pending + c.notDone} pending · ${c.skipped} skipped',
            style: const TextStyle(fontSize: 12, color: kMuted)),
      ]),
    );
  }
}

class _EventSheet extends StatefulWidget {
  final List<String> suggestions;
  final String initialName;
  final DateTime? initialDate;
  final String title;
  const _EventSheet({this.suggestions = const [], this.initialName = '', this.initialDate, this.title = 'Add event'});
  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late DateTime? _date = widget.initialDate;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (widget.suggestions.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in widget.suggestions)
              ActionChip(label: Text(s), onPressed: () => setState(() => _name.text = s)),
          ]),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: inputDeco('Event name', hint: 'e.g. Biye, Sangeet'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: Text(_date == null ? 'Choose date (optional)' : fmtDate(_date)),
          onPressed: () async {
            final d = await pickDate(context, initial: _date, first: DateTime(2020));
            if (d != null) setState(() => _date = d);
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) {
              showSnack(context, 'Enter an event name', error: true);
              return;
            }
            Navigator.pop(context, (_name.text.trim(), _date));
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- checklist

class EventChecklistScreen extends StatelessWidget {
  final String eventId;
  const EventChecklistScreen({super.key, required this.eventId});

  Future<Map<String, dynamic>> _load() async {
    final e = await supa.from('wedding_events').select('*, event_checklists(*)').eq('id', eventId).maybeSingle();
    if (e == null) throw Exception('Event not found.');
    return e;
  }

  Future<void> _update(BuildContext context, String taskId, Map<String, dynamic> values, {String? success}) async {
    final ok = await runAction(context, () async {
      await supa.from('event_checklists').update(values).eq('id', taskId);
    }, success: success);
    if (ok) bumpData();
  }

  Future<void> _markDone(BuildContext context, Map<String, dynamic> task) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProviderSheet(task: task),
    );
    if (result == null || !context.mounted) return;
    await _update(context, task['id'] as String, {...result, 'status': 'done'}, success: 'Marked as done');
  }

  Future<void> _markNotDone(BuildContext context, Map<String, dynamic> task) async {
    await _update(context, task['id'] as String, {'status': 'not_done'});
    if (!context.mounted) return;
    _findVendors(context, task);
  }

  void _findVendors(BuildContext context, Map<String, dynamic> task) {
    final cat = task['category_id'] as String?;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExploreScreen(category: cat, title: 'Vendors for "${str(task['title'])}"')),
    );
  }

  Future<void> _taskMenu(BuildContext context, Map<String, dynamic> task) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit details'), onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(leading: const Icon(Icons.drive_file_rename_outline), title: const Text('Rename task'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.restart_alt), title: const Text('Reset to pending'), onTap: () => Navigator.pop(ctx, 'reset')),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
              title: const Text('Delete task'),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;
    final id = task['id'] as String;
    switch (action) {
      case 'edit':
        await _markDone(context, task);
      case 'rename':
        final name = await promptText(context, 'Rename task', label: 'Task', initial: str(task['title']), maxLines: 1);
        if (name != null && context.mounted) await _update(context, id, {'title': name});
      case 'reset':
        await _update(context, id, {
          'status': 'pending',
          'provider_name': null,
          'provider_contact': null,
          'provider_notes': null,
          'amount': null,
        });
      case 'delete':
        if (await confirmDialog(context, 'Delete task?', str(task['title']), confirm: 'Delete', destructive: true) &&
            context.mounted) {
          final ok = await runAction(context, () async {
            await supa.from('event_checklists').delete().eq('id', id);
          });
          if (ok) bumpData();
        }
    }
  }

  Future<void> _addTask(BuildContext context, List<Map<String, dynamic>> tasks) async {
    final title = await promptText(context, 'Add task', label: 'Task', maxLines: 1);
    if (title == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.from('event_checklists').insert({
        'event_id': eventId,
        'customer_id': myId,
        'title': title,
        'sort': tasks.length + 1,
      });
    });
    if (ok) bumpData();
  }

  Future<void> _editEvent(BuildContext context, Map<String, dynamic> e) async {
    final result = await showModalBottomSheet<(String, DateTime?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EventSheet(
        title: 'Edit event',
        initialName: str(e['name']),
        initialDate: parseDate(e['event_date']),
      ),
    );
    if (result == null || !context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.from('wedding_events').update({
        'name': result.$1,
        'event_date': result.$2 == null ? null : ymd(result.$2!),
      }).eq('id', eventId);
    }, success: 'Event updated');
    if (ok) bumpData();
  }

  Future<void> _deleteEvent(BuildContext context, Map<String, dynamic> e) async {
    final yes = await confirmDialog(context, 'Delete ${str(e['name'])}?', 'The event and its checklist will be removed.',
        confirm: 'Delete', destructive: true);
    if (!yes || !context.mounted) return;
    final ok = await runAction(context, () async {
      await supa.from('wedding_events').delete().eq('id', eventId);
    });
    if (ok && context.mounted) {
      bumpData();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kIvory,
      child: Loader<Map<String, dynamic>>(
      load: _load,
      builder: (context, e, reload) {
        final tasks = asList(e['event_checklists'])..sort((a, b) => toI(a['sort']).compareTo(toI(b['sort'])));
        final c = _Counts.of(tasks);
        return Scaffold(
          appBar: AppBar(
            title: Text(str(e['name'])),
            actions: [
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editEvent(context, e)),
              IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteEvent(context, e)),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: kMaroon,
            foregroundColor: Colors.white,
            onPressed: () => _addTask(context, tasks),
            child: const Icon(Icons.add),
          ),
          body: RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDate(e['event_date'], 'Date not set'), style: const TextStyle(color: kMuted)),
                  const SizedBox(height: 8),
                  ProgressBar(c.progress),
                  const SizedBox(height: 8),
                  Text('${c.done} completed · ${c.pending + c.notDone} pending · ${c.skipped} skipped'),
                ]),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Mark each task Done, Not done or Skip. Changes save automatically.',
                    style: TextStyle(color: kMuted, fontSize: 12)),
              ),
              if (tasks.isEmpty)
                const EmptyView(icon: Icons.checklist, title: 'No tasks', subtitle: 'Add your own tasks with the + button.'),
              for (final t in tasks)
                _TaskTile(
                  task: t,
                  onDone: () => _markDone(context, t),
                  onNotDone: () => _markNotDone(context, t),
                  onSkip: () => _update(context, t['id'] as String, {'status': 'skipped'}),
                  onFind: () => _findVendors(context, t),
                  onMenu: () => _taskMenu(context, t),
                ),
            ]),
          ),
        );
      },
    ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onDone, onNotDone, onSkip, onFind, onMenu;
  const _TaskTile({
    required this.task,
    required this.onDone,
    required this.onNotDone,
    required this.onSkip,
    required this.onFind,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final status = str(task['status'], 'pending');
    final cat = task['category_id'] == null ? null : categoryById(task['category_id'] as String);
    Widget choice(String label, String value, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: status == value,
            selectedColor: StatusChip.colorFor(value).withAlpha(40),
            onSelected: (_) => onTap(),
            visualDensity: VisualDensity.compact,
          ),
        );
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(cat?.icon ?? Icons.check_box_outline_blank, color: kMaroon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(str(task['title']),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: status == 'skipped' ? TextDecoration.lineThrough : null,
                  color: status == 'skipped' ? kMuted : kInk,
                )),
          ),
          if (status != 'pending') StatusChip(status),
          IconButton(icon: const Icon(Icons.more_vert, size: 20), onPressed: onMenu),
        ]),
        if (status == 'done' && (str(task['provider_name']).isNotEmpty || task['amount'] != null))
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 2),
            child: Text(
              [
                if (str(task['provider_name']).isNotEmpty) 'Arranged with ${str(task['provider_name'])}',
                if (str(task['provider_contact']).isNotEmpty) str(task['provider_contact']),
                if (task['amount'] != null) money(task['amount']),
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: kMuted),
            ),
          ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            choice('Done', 'done', onDone),
            choice('Not done', 'not_done', onNotDone),
            choice('Skip', 'skipped', onSkip),
            if (status == 'not_done' && cat != null)
              TextButton.icon(onPressed: onFind, icon: const Icon(Icons.search, size: 18), label: Text('Find ${cat.name.toLowerCase()}')),
          ]),
        ),
      ]),
    );
  }
}

/// "Where did you arrange it?" sheet for completed tasks.
class _ProviderSheet extends StatefulWidget {
  final Map<String, dynamic> task;
  const _ProviderSheet({required this.task});
  @override
  State<_ProviderSheet> createState() => _ProviderSheetState();
}

class _ProviderSheetState extends State<_ProviderSheet> {
  late final _name = TextEditingController(text: str(widget.task['provider_name']));
  late final _contact = TextEditingController(text: str(widget.task['provider_contact']));
  late final _amount = TextEditingController(
      text: widget.task['amount'] == null ? '' : toD(widget.task['amount']).toStringAsFixed(0));
  late final _notes = TextEditingController(text: str(widget.task['provider_notes']));

  @override
  void dispose() {
    for (final c in [_name, _contact, _amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(str(widget.task['title']), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Where did you arrange it? All fields are optional.', style: TextStyle(color: kMuted)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: inputDeco('Provider / vendor name', icon: Icons.storefront_outlined)),
          const SizedBox(height: 12),
          TextField(
              controller: _contact,
              keyboardType: TextInputType.phone,
              decoration: inputDeco('Provider contact', icon: Icons.phone_outlined)),
          const SizedBox(height: 12),
          TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: inputDeco('Amount spent (₹)', icon: Icons.currency_rupee, helper: 'Counts towards your budget')),
          const SizedBox(height: 12),
          TextField(controller: _notes, maxLines: 2, decoration: inputDeco('Notes')),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, <String, dynamic>{
              'provider_name': nullIfEmpty(_name.text),
              'provider_contact': nullIfEmpty(_contact.text),
              'provider_notes': nullIfEmpty(_notes.text),
              'amount': double.tryParse(_amount.text.trim()),
            }),
            child: const Text('Mark as done'),
          ),
        ]),
      ),
    );
  }
}
