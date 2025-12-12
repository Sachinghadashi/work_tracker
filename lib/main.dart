// Painter Work Tracker - single-file Flutter app (lib/main.dart)
// Features:
// - Add / Edit / Delete painter work entries (no login, no backend)
// - Local persistence using SharedPreferences (JSON)
// - Search, totals, export CSV (copied to clipboard)
// - Simple, beginner-friendly code with comments

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // for Clipboard

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PainterWorkTrackerApp());
}

class PainterWorkTrackerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Painter Work Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: HomePage(),
    );
  }
}

class WorkEntry {
  String id;
  String clientName;
  DateTime date;
  String location;
  String description;
  double hours;
  double amount;
  String materials;

  WorkEntry({
    required this.id,
    required this.clientName,
    required this.date,
    required this.location,
    required this.description,
    required this.hours,
    required this.amount,
    required this.materials,
  });

  factory WorkEntry.fromJson(Map<String, dynamic> json) => WorkEntry(
        id: json['id'],
        clientName: json['clientName'],
        date: DateTime.parse(json['date']),
        location: json['location'],
        description: json['description'],
        hours: (json['hours'] ?? 0).toDouble(),
        amount: (json['amount'] ?? 0).toDouble(),
        materials: json['materials'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientName': clientName,
        'date': date.toIso8601String(),
        'location': location,
        'description': description,
        'hours': hours,
        'amount': amount,
        'materials': materials,
      };
}

class StorageService {
  static const _kEntriesKey = 'painter_entries_v1';

  Future<void> saveEntries(List<WorkEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_kEntriesKey, jsonStr);
  }

  Future<List<WorkEntry>> loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_kEntriesKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      return list.map((e) => WorkEntry.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final StorageService _storage = StorageService();
  List<WorkEntry> _entries = [];
  List<WorkEntry> _filtered = [];
  final DateFormat _fmt = DateFormat('yyyy-MM-dd');
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applySearch);
  }

  void _applySearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      if (q.isEmpty) _filtered = List.from(_entries);
      else
        _filtered = _entries.where((e) {
          return e.clientName.toLowerCase().contains(q) ||
              e.location.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q) ||
              e.materials.toLowerCase().contains(q);
        }).toList();
    });
  }

  Future<void> _load() async {
    final list = await _storage.loadEntries();
    list.sort((a, b) => b.date.compareTo(a.date));
    setState(() {
      _entries = list;
      _filtered = List.from(_entries);
    });
  }

  Future<void> _saveAndRefresh() async {
    await _storage.saveEntries(_entries);
    _applySearch();
  }

  void _addOrEditEntry({WorkEntry? existing}) async {
    final result = await showModalBottomSheet<WorkEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: EntryForm(entry: existing),
      ),
    );

    if (result != null) {
      setState(() {
        if (existing != null) {
          final idx = _entries.indexWhere((e) => e.id == existing.id);
          if (idx != -1) _entries[idx] = result;
        } else {
          _entries.insert(0, result);
        }
      });
      await _saveAndRefresh();
    }
  }

  void _deleteEntry(WorkEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete entry?'),
        content: Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _entries.removeWhere((e) => e.id == entry.id);
      });
      await _saveAndRefresh();
    }
  }

  double get _totalAmount => _entries.fold(0.0, (s, e) => s + e.amount);
  double get _totalHours => _entries.fold(0.0, (s, e) => s + e.hours);

  void _exportCsvToClipboard() {
    final sb = StringBuffer();
    sb.writeln('Date,Client,Location,Description,Hours,Amount,Materials');
    for (final e in _entries) {
      final row = [
        _fmt.format(e.date),
        _escape(e.clientName),
        _escape(e.location),
        _escape(e.description),
        e.hours.toString(),
        e.amount.toString(),
        _escape(e.materials),
      ].join(',');
      sb.writeln(row);
    }

    Clipboard.setData(ClipboardData(text: sb.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CSV copied to clipboard')),
    );
  }

  String _escape(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"' + s.replaceAll('"', '""') + '"';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Painter Work Tracker'),
        actions: [
          IconButton(onPressed: _exportCsvToClipboard, icon: Icon(Icons.file_copy)),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by client, location, description or materials',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total hours: ${_totalHours.toStringAsFixed(1)}'),
                Text('Total amount: ₹${_totalAmount.toStringAsFixed(2)}'),
              ],
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(child: Text('No entries yet. Tap + to add one.'))
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, idx) {
                      final e = _filtered[idx];
                      return Dismissible(
                        key: Key(e.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteEntry(e),
                        child: ListTile(
                          title: Text(e.clientName),
                          subtitle: Text('${_fmt.format(e.date)} • ${e.location}'),
                          trailing: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('₹${e.amount.toStringAsFixed(0)}'),
                              Text('${e.hours.toStringAsFixed(1)} hrs'),
                            ],
                          ),
                          onTap: () => _addOrEditEntry(existing: e),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditEntry(),
        child: Icon(Icons.add),
      ),
    );
  }
}

class EntryForm extends StatefulWidget {
  final WorkEntry? entry;
  EntryForm({this.entry});

  @override
  _EntryFormState createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _clientCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _hoursCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _materialsCtrl;
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _clientCtrl = TextEditingController(text: e?.clientName ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _hoursCtrl = TextEditingController(text: e != null ? e.hours.toString() : '');
    _amountCtrl = TextEditingController(text: e != null ? e.amount.toString() : '');
    _materialsCtrl = TextEditingController(text: e?.materials ?? '');
    _selectedDate = e?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _locationCtrl.dispose();
    _descCtrl.dispose();
    _hoursCtrl.dispose();
    _amountCtrl.dispose();
    _materialsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _selectedDate = d);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final id = widget.entry?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final entry = WorkEntry(
      id: id,
      clientName: _clientCtrl.text.trim(),
      date: _selectedDate,
      location: _locationCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      hours: double.tryParse(_hoursCtrl.text.trim()) ?? 0.0,
      amount: double.tryParse(_amountCtrl.text.trim()) ?? 0.0,
      materials: _materialsCtrl.text.trim(),
    );
    Navigator.pop(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _clientCtrl,
                      decoration: InputDecoration(labelText: 'Client name'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Enter client name' : null,
                    ),
                  ),
                  SizedBox(width: 12),
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: InputDecoration(labelText: 'Date'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                          SizedBox(width: 6),
                          Icon(Icons.calendar_today, size: 18),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _locationCtrl,
                decoration: InputDecoration(labelText: 'Location'),
              ),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(labelText: 'Work description'),
                maxLines: 2,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _hoursCtrl,
                      decoration: InputDecoration(labelText: 'Hours'),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _amountCtrl,
                      decoration: InputDecoration(labelText: 'Amount (₹)'),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              TextFormField(
                controller: _materialsCtrl,
                decoration: InputDecoration(labelText: 'Materials used (optional)'),
              ),
              SizedBox(height: 12),
              ElevatedButton(onPressed: _submit, child: Text(widget.entry == null ? 'Add entry' : 'Save')),
            ],
          ),
        ),
      ),
    );
  }
}

/*
Instructions:
1. Create a new flutter project (or use an existing one):
   flutter create painter_work_tracker

2. Replace the contents of lib/main.dart with this file.

3. Add dependencies in pubspec.yaml under dependencies:
   shared_preferences: ^2.1.1
   intl: ^0.18.1

   then run:
   flutter pub get

4. Run the app on an emulator or device:
   flutter run

Notes:
- This app stores all data locally using SharedPreferences as a JSON string. No backend required.
- You can search entries, add/edit/delete, and copy a CSV of all entries to clipboard using the top-right icon.
- If you want photos, backups, or file export later, I can add that (requires extra packages and a little platform setup).
*/
