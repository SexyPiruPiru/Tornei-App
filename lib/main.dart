import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sms/flutter_sms.dart';

void main() {
  runApp(const TorneoManagerApp());
}

class TorneoManagerApp extends StatelessWidget {
  const TorneoManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torneo Beach Tennis Manager',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TorneoMainScreen(),
    );
  }
}

class Participant {
  final String timestamp;
  final String name;
  final String surname;
  final String nickname;
  final String phone;
  String status; // "Confermato" o "Lista d'Attesa"
  String lastSentStatus;

  Participant({
    required this.timestamp,
    required this.name,
    required this.surname,
    required this.nickname,
    required this.phone,
    this.status = '',
    this.lastSentStatus = '',
  });
}

class CancellationItem {
  final String timestamp;
  final String name;
  final String surname;
  final String nickname;
  final String phone;
  String lastSentStatus;

  CancellationItem({
    required this.timestamp,
    required this.name,
    required this.surname,
    required this.nickname,
    required this.phone,
    this.lastSentStatus = '',
  });
}

class TorneoMainScreen extends StatefulWidget {
  const TorneoMainScreen({super.key});

  @override
  State<TorneoMainScreen> createState() => _TorneoMainScreenState();
}

class _TorneoMainScreenState extends State<TorneoMainScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      const TorneoHomePage(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Partecipanti',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Impostazioni & SMS',
          ),
        ],
      ),
    );
  }
}

class TorneoHomePage extends StatefulWidget {
  const TorneoHomePage({super.key});

  @override
  State<TorneoHomePage> createState() => _TorneoHomePageState();
}

class _TorneoHomePageState extends State<TorneoHomePage> {
  final TextEditingController _urlController = TextEditingController(
    text:
        'https://script.google.com/macros/s/AKfycbzBj1uJKS8POWtHA4I1I3KXvrmLRytpPfhiuUrVdloPFA3MiSczfBbVfydCFGRTGFhNJA/exec',
  );
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  List<Participant> _activeParticipants = [];
  List<CancellationItem> _cancellations = [];
  String _selectedFilter = 'Tutti';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSavedStatus();
  }

  Future<void> _loadSavedStatus() async {
    final prefs = await SharedPreferences.getInstance();
    String? sentJson = prefs.getString('sent_status_map');
    if (sentJson != null) {
      Map<String, dynamic> sentMap = json.decode(sentJson);
      for (var p in _activeParticipants) {
        if (sentMap.containsKey(p.phone)) {
          p.lastSentStatus = sentMap[p.phone];
        }
      }
      for (var d in _cancellations) {
        if (sentMap.containsKey(d.phone)) {
          d.lastSentStatus = sentMap[d.phone];
        }
      }
    }
  }

  Future<void> _saveStatusToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> sentMap = {};
    for (var p in _activeParticipants) {
      if (p.lastSentStatus.isNotEmpty) {
        sentMap[p.phone] = p.lastSentStatus;
      }
    }
    for (var d in _cancellations) {
      if (d.lastSentStatus.isNotEmpty) {
        sentMap[d.phone] = d.lastSentStatus;
      }
    }
    await prefs.setString('sent_status_map', json.encode(sentMap));
  }

  String _formatDate(String isoString) {
    if (isoString.isEmpty) {
      return 'Data non disponibile';
    }
    try {
      DateTime dt = DateTime.parse(isoString).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }

  Future<void> _fetchAndProcessData() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        List rawIscrizioni = data['iscrizioni'] ?? [];
        List rawDisiscrizioni = data['disiscrizioni'] ?? [];

        Set<String> disiscrizioniPhones = rawDisiscrizioni
            .map((d) => d['phone'].toString().replaceAll(RegExp(r'[^\d]'), ''))
            .toSet();

        List<Participant> tempParticipants = [];
        for (var item in rawIscrizioni) {
          String phone = item['phone']?.toString() ?? '';
          String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

          if (!disiscrizioniPhones.contains(cleanPhone)) {
            tempParticipants.add(Participant(
              timestamp: item['timestamp']?.toString() ?? '',
              name: item['name']?.toString() ?? '',
              surname: item['surname']?.toString() ?? '',
              nickname: item['nickname']?.toString() ?? '',
              phone: phone,
            ));
          }
        }

        tempParticipants.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        List<Participant> uniqueParticipants = [];
        Set<String> seenPhones = {};
        for (var p in tempParticipants) {
          String cleanPhone = p.phone.replaceAll(RegExp(r'[^\d]'), '');
          if (cleanPhone.isNotEmpty) {
            if (!seenPhones.contains(cleanPhone)) {
              seenPhones.add(cleanPhone);
              uniqueParticipants.add(p);
            }
          } else {
            uniqueParticipants.add(p);
          }
        }

        int total = uniqueParticipants.length;
        int confirmedLimit = (total ~/ 4) * 4;

        for (int i = 0; i < total; i++) {
          if (i < confirmedLimit) {
            uniqueParticipants[i].status = 'Confermato';
          } else {
            uniqueParticipants[i].status = "Lista d'Attesa";
          }
        }

        List<CancellationItem> tempCancellations = [];
        for (var item in rawDisiscrizioni) {
          tempCancellations.add(CancellationItem(
            timestamp: item['timestamp']?.toString() ?? '',
            name: item['name']?.toString() ?? '',
            surname: item['surname']?.toString() ?? '',
            nickname: item['nickname']?.toString() ?? '',
            phone: item['phone']?.toString() ?? '',
          ));
        }

        setState(() {
          _activeParticipants = uniqueParticipants;
          _cancellations = tempCancellations;
          _isLoading = false;
        });

        await _loadSavedStatus();
      } else {
        throw Exception('Errore server: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore di sincronizzazione: $e')),
      );
    }
  }

  Future<void> _sendSingleSMS(String phone, String message) async {
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
    }
  }

  Future<void> _sendSmartBulkSMS() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String date = prefs.getString('tourney_date') ?? 'Data non impostata';
    String confTmpl = prefs.getString('tmpl_confirmed') ??
        'Ciao {nome}, sei confermato per il torneo del {data}!';
    String waitTmpl = prefs.getString('tmpl_waiting') ??
        'Ciao {nome}, sei in lista d\'attesa per il torneo del {data}.';
    String cancTmpl = prefs.getString('tmpl_cancelled') ??
        'Ciao {nome}, abbiamo registrato la tua disiscrizione dal torneo del {data}.';

    List<Map<String, dynamic>> queue = [];

    // Raccoglie i partecipanti attivi da notificare
    for (var p in _activeParticipants) {
      if (p.status != p.lastSentStatus && p.phone.isNotEmpty) {
        String template = p.status == 'Confermato' ? confTmpl : waitTmpl;
        String msg =
            template.replaceAll('{nome}', p.name).replaceAll('{data}', date);
        queue.add(
            {'phone': p.phone, 'message': msg, 'type': p.status, 'target': p});
      }
    }

    // Raccoglie i disiscritti da notificare
    for (var d in _cancellations) {
      if (d.lastSentStatus != 'Disiscritto' && d.phone.isNotEmpty) {
        String playerName = d.name.isNotEmpty ? d.name : 'Giocatore';
        String msg = cancTmpl
            .replaceAll('{nome}', playerName)
            .replaceAll('{data}', date);
        queue.add({
          'phone': d.phone,
          'message': msg,
          'type': 'Disiscritto',
          'target': d
        });
      }
    }

    if (queue.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Nessun nuovo SMS in coda. Tutti i partecipanti sono aggiornati!')),
      );
      return;
    }

    if (!mounted) {
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Invio SMS in corso...'),
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Expanded(
                child: Text(
                    'Invio massivo di ${queue.length} messaggi (1 ogni 2 sec)...')),
          ],
        ),
      ),
    );

    for (int i = 0; i < queue.length; i++) {
      var item = queue[i];
      String phone = item['phone'];
      String message = item['message'];
      String type = item['type'];
      var target = item['target'];

      try {
        await sendSMS(message: message, recipients: [phone], sendDirect: true);

        if (target is Participant) {
          target.lastSentStatus = type;
        } else if (target is CancellationItem) {
          target.lastSentStatus = type;
        }
      } catch (e) {
        // Ignora errore singolo per proseguire
      }

      if (i < queue.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    await _saveStatusToPrefs();

    if (!mounted) {
      return;
    }
    Navigator.pop(context);
    setState(() {});

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Invio massivo completato! Inviati ${queue.length} SMS.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    int confermatiCount =
        _activeParticipants.where((p) => p.status == 'Confermato').length;
    int attesaCount =
        _activeParticipants.where((p) => p.status == "Lista d'Attesa").length;
    int disiscrittiCount = _cancellations.length;

    int pendingSmsCount = _activeParticipants
            .where((p) => p.status != p.lastSentStatus)
            .length +
        _cancellations.where((d) => d.lastSentStatus != 'Disiscritto').length;

    List displayList = [];
    if (_selectedFilter == 'Disiscritti') {
      displayList = _cancellations.where((d) {
        if (_searchQuery.isEmpty) {
          return true;
        }
        String query = _searchQuery.toLowerCase();
        return d.name.toLowerCase().contains(query) ||
            d.surname.toLowerCase().contains(query) ||
            d.nickname.toLowerCase().contains(query) ||
            d.phone.toLowerCase().contains(query);
      }).toList();
    } else {
      displayList = _activeParticipants.where((p) {
        bool matchesCategory = true;
        if (_selectedFilter == 'Confermati') {
          matchesCategory = p.status == 'Confermato';
        }
        if (_selectedFilter == "In Attesa") {
          matchesCategory = p.status == "Lista d'Attesa";
        }

        if (!matchesCategory) {
          return false;
        }

        if (_searchQuery.isEmpty) {
          return true;
        }
        String query = _searchQuery.toLowerCase();
        return p.name.toLowerCase().contains(query) ||
            p.surname.toLowerCase().contains(query) ||
            p.nickname.toLowerCase().contains(query) ||
            p.phone.toLowerCase().contains(query);
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Torneo Beach Tennis'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'URL Google Apps Script',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _fetchAndProcessData,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      label: const Text('Sincronizza',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 45,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _sendSmartBulkSMS,
                      icon: const Icon(Icons.send_to_mobile),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      label: Text('Invia in Coda ($pendingSmsCount)',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCard(
                    'Totale', '${_activeParticipants.length}', Colors.grey),
                _buildStatCard('Confermati', '$confermatiCount', Colors.green),
                _buildStatCard('In Attesa', '$attesaCount', Colors.orange),
                _buildStatCard('Disiscritti', '$disiscrittiCount', Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Cerca per nome, cognome, nickname o tel...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['Tutti', 'Confermati', "In Attesa", 'Disiscritti']
                    .map((filter) {
                  bool isSelected = _selectedFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedFilter = filter;
                        });
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 20),
            Expanded(
              child: displayList.isEmpty
                  ? const Center(child: Text('Nessun elemento trovato.'))
                  : ListView.builder(
                      itemCount: displayList.length,
                      itemBuilder: (context, index) {
                        if (_selectedFilter == 'Disiscritti') {
                          CancellationItem d = displayList[index];
                          bool smsInviato = d.lastSentStatus == 'Disiscritto';
                          return Card(
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.red,
                                child: Icon(Icons.cancel, color: Colors.white),
                              ),
                              title: Text(
                                  '${d.name} ${d.surname} (${d.nickname})'),
                              subtitle: Text(
                                  'Tel: ${d.phone} • Data: ${_formatDate(d.timestamp)}'),
                              trailing: Icon(
                                smsInviato ? Icons.check_circle : Icons.pending,
                                color: smsInviato ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                            ),
                          );
                        } else {
                          Participant p = displayList[index];
                          bool isConfermato = p.status == 'Confermato';
                          bool smsInviato = p.status == p.lastSentStatus;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    isConfermato ? Colors.green : Colors.orange,
                                child: Text('${index + 1}',
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ),
                              title: Text(
                                  '${p.name} ${p.surname} (${p.nickname})'),
                              subtitle:
                                  Text('Tel: ${p.phone} • Stato: ${p.status}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    smsInviato
                                        ? Icons.check_circle
                                        : Icons.pending,
                                    color:
                                        smsInviato ? Colors.green : Colors.grey,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.message,
                                        color: Colors.blue),
                                    onPressed: () async {
                                      SharedPreferences prefs =
                                          await SharedPreferences.getInstance();
                                      String date =
                                          prefs.getString('tourney_date') ??
                                              'Data non impostata';
                                      String template = isConfermato
                                          ? (prefs.getString(
                                                  'tmpl_confirmed') ??
                                              'Ciao {nome}, sei confermato per il torneo del {data}!')
                                          : (prefs.getString('tmpl_waiting') ??
                                              'Ciao {nome}, sei in lista d\'attesa per il torneo del {data}.');

                                      String msg = template
                                          .replaceAll('{nome}', p.name)
                                          .replaceAll('{data}', date);

                                      await _sendSingleSMS(p.phone, msg);
                                      if (!mounted) {
                                        return;
                                      }
                                      setState(() {
                                        p.lastSentStatus = p.status;
                                      });
                                      _saveStatusToPrefs();
                                    },
                                    tooltip: 'Invia SMS Singolo',
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Column(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _confirmedTmplController =
      TextEditingController();
  final TextEditingController _waitingTmplController = TextEditingController();
  final TextEditingController _cancelledTmplController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dateController.text = prefs.getString('tourney_date') ?? '2026-06-15';
      _confirmedTmplController.text = prefs.getString('tmpl_confirmed') ??
          'Ciao {nome}, sei ufficialmente CONFERMATO nel torneo di Beach Tennis del {data}!';
      _waitingTmplController.text = prefs.getString('tmpl_waiting') ??
          'Ciao {nome}, sei in LISTA D\'ATTESA per il torneo di Beach Tennis del {data}.';
      _cancelledTmplController.text = prefs.getString('tmpl_cancelled') ??
          'Ciao {nome}, abbiamo registrato la tua disiscrizione dal torneo di Beach Tennis del {data}.';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tourney_date', _dateController.text);
    await prefs.setString('tmpl_confirmed', _confirmedTmplController.text);
    await prefs.setString('tmpl_waiting', _waitingTmplController.text);
    await prefs.setString('tmpl_cancelled', _cancelledTmplController.text);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impostazioni salvate con successo!')),
    );
  }

  Future<void> _pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _dateController.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni & Modelli SMS'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            const Text(
              'Data del Torneo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Data Evento',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: _pickDate,
                ),
              ),
            ),
            const Divider(height: 30),
            const Text(
              'Modelli Messaggi SMS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Usa i tag {nome} e {data} per personalizzare il testo.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmedTmplController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Messaggio Confermati',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _waitingTmplController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Messaggio Lista d\'Attesa',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cancelledTmplController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Messaggio Disiscritti',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Salva Impostazioni'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
