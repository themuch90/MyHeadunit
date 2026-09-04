import 'package:flutter/material.dart';
import '../services/phone_service.dart';

class ContactsScreen extends StatefulWidget {
  final PhoneService phoneService;
  const ContactsScreen({super.key, required this.phoneService});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Contact> _contacts = [];
  String _filter = '';

  @override
  void initState() {
    super.initState();
    widget.phoneService.contacts.listen((c) {
      setState(() => _contacts = c..sort((a, b) => a.name.compareTo(b.name)));
    });
    // Richiede una sync fresca allo smartphone all'apertura della schermata
    widget.phoneService.syncContacts();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _contacts
        .where((c) => c.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Cerca contatto',
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.grey),
                tooltip: 'Aggiorna rubrica dal telefono',
                onPressed: widget.phoneService.syncContacts,
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('Nessun contatto. Sincronizza dal telefono.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(c.name.isNotEmpty ? c.name[0] : '?'),
                      ),
                      title: Text(c.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        c.numbers.isNotEmpty ? c.numbers.first : '',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: c.numbers.isEmpty
                            ? null
                            : () => widget.phoneService.dial(c.numbers.first),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
