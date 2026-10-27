import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'weather.dart';

void main() {
  runApp(const BusBookingApp());
}

class SeatBooking {
  SeatBooking(
      {required this.seatNumber,
      required this.passengerName,
      required this.cashPaid});
  final int seatNumber;
  final String passengerName;
  final int cashPaid;

  Map<String, dynamic> toJson() => {
        'seatNumber': seatNumber,
        'passengerName': passengerName,
        'cashPaid': cashPaid
      };
  factory SeatBooking.fromJson(Map<String, dynamic> json) => SeatBooking(
        seatNumber: json['seatNumber'] as int,
        passengerName: json['passengerName'] as String,
        cashPaid: json['cashPaid'] as int,
      );
}

class WaitlistPerson {
  WaitlistPerson({required this.name, required this.isPriority});
  final String name;
  final bool isPriority;

  Map<String, dynamic> toJson() => {'name': name, 'isPriority': isPriority};
  factory WaitlistPerson.fromJson(Map<String, dynamic> json) => WaitlistPerson(
        name: json['name'] as String,
        isPriority: json['isPriority'] as bool,
      );
}

class BusBookingApp extends StatelessWidget {
  const BusBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bus Dispatcher - Kigali to Huye',
      theme: ThemeData(
          colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: const BusHomeScreen(),
    );
  }
}

class BusHomeScreen extends StatefulWidget {
  const BusHomeScreen({super.key});

  @override
  State<BusHomeScreen> createState() => _BusHomeScreenState();
}

class _BusHomeScreenState extends State<BusHomeScreen> {
  final int ticketPrice = 3000;
  final int totalSeats = 12;

  Map<int, SeatBooking> bookings = {};
  List<WaitlistPerson> waitlist = [];

  Weather? huyeWeather;
  bool weatherLoading = true;
  bool isWeatherOfflineCached = false;
  String? weatherCachedTime;
  String? statusMessage;
  bool isAppOffline = false;

  @override
  void initState() {
    super.initState();
    loadAppDataAndWeather();
  }

  // Load local data first (always works offline), then try fetching live weather
  Future<void> loadAppDataAndWeather() async {
    setState(() {
      weatherLoading = true;
      isAppOffline = false;
    });

    // 1. Load local saved bookings and waitlist (Guaranteed offline safety)
    final prefs = await SharedPreferences.getInstance();
    final savedB = prefs.getString('bookings');
    final savedW = prefs.getString('waitlist');

    setState(() {
      if (savedB != null) {
        final list = jsonDecode(savedB) as List;
        bookings.clear();
        for (var item in list) {
          final b = SeatBooking.fromJson(item as Map<String, dynamic>);
          bookings[b.seatNumber] = b;
        }
      }
      if (savedW != null) {
        final list = jsonDecode(savedW) as List;
        waitlist = list
            .map((x) => WaitlistPerson.fromJson(x as Map<String, dynamic>))
            .toList();
      }
    });

    // 2. Try fetching live weather, fallback to cached weather if offline
    try {
      const huye = City('Huye', -2.5967, 29.7394);
      final weather = await fetchWeather(huye);

      await prefs.setString(
          'cached_huye_weather', jsonEncode(weather.toJson()));

      setState(() {
        huyeWeather = weather;
        weatherLoading = false;
        isWeatherOfflineCached = false;
        isAppOffline = false;
      });
    } catch (_) {
      final cachedJson = prefs.getString('cached_huye_weather');

      if (cachedJson != null) {
        final cachedWeather =
            Weather.fromJson(jsonDecode(cachedJson) as Map<String, dynamic>);
        setState(() {
          huyeWeather = cachedWeather;
          weatherLoading = false;
          isWeatherOfflineCached = true;
          weatherCachedTime = cachedWeather.time;
          isAppOffline = true;
        });
      } else {
        setState(() {
          weatherLoading = false;
          isAppOffline = true;
        });
      }
    }
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    final bList = bookings.values.map((b) => b.toJson()).toList();
    final wList = waitlist.map((w) => w.toJson()).toList();
    await prefs.setString('bookings', jsonEncode(bList));
    await prefs.setString('waitlist', jsonEncode(wList));
  }

  void bookSeat(int seatNumber) {
    final nameController = TextEditingController();
    final cashController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Book Seat #$seatNumber (3,000 RWF)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Passenger Name')),
            const SizedBox(height: 12),
            TextField(
                controller: cashController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Cash Handed Over (RWF)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final cash = int.tryParse(cashController.text.trim()) ?? 0;

              if (name.isEmpty) {
                _showSnack('Name cannot be empty.');
                return;
              }
              if (bookings.values.any(
                  (b) => b.passengerName.toLowerCase() == name.toLowerCase())) {
                _showSnack('This passenger already holds a seat.');
                return;
              }
              if (cash < ticketPrice || cash % 100 != 0) {
                _showSnack(
                    'Invalid cash. Must be >= 3,000 RWF and a multiple of 100.');
                return;
              }

              int change = cash - ticketPrice;
              Navigator.pop(context);
              _showChangeDialog(seatNumber, name, cash, change);
            },
            child: const Text('Pay & Book'),
          ),
        ],
      ),
    );
  }

  void _showChangeDialog(int seatNumber, String name, int cash, int change) {
    Map<int, int> notes = {5000: 0, 2000: 0, 1000: 0, 500: 0, 200: 0, 100: 0};
    int temp = change;
    for (var denom in [5000, 2000, 1000, 500, 200, 100]) {
      if (temp >= denom) {
        notes[denom] = temp ~/ denom;
        temp %= denom;
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Breakdown'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Change: $change RWF'),
            const SizedBox(height: 8),
            ...notes.entries
                .where((e) => e.value > 0)
                .map((e) => Text('${e.key} RWF × ${e.value}')),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              setState(() {
                bookings[seatNumber] = SeatBooking(
                    seatNumber: seatNumber,
                    passengerName: name,
                    cashPaid: cash);
                statusMessage = null;
              });
              saveData();
              Navigator.pop(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void showBookingDetails(int seatNumber) {
    final booking = bookings[seatNumber]!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Seat #$seatNumber Details'),
        content: Text(
            'Passenger: ${booking.passengerName}\nPaid: ${booking.cashPaid} RWF'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _confirmCancel(seatNumber);
            },
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }

  void _confirmCancel(int seatNumber) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: Text('Cancel booking for seat #$seatNumber?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('No')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              cancelBooking(seatNumber);
            },
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
  }

  void cancelBooking(int seatNumber) {
    setState(() {
      bookings.remove(seatNumber);

      if (waitlist.isNotEmpty) {
        final nextPerson = waitlist.removeAt(0);
        bookings[seatNumber] = SeatBooking(
            seatNumber: seatNumber,
            passengerName: nextPerson.name,
            cashPaid: ticketPrice);
        statusMessage = '${nextPerson.name} moved into seat $seatNumber';
      } else {
        statusMessage = null;
      }
    });
    saveData();
  }

  void joinWaitlist() {
    final nameController = TextEditingController();
    bool isPriority = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Join Waitlist'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: 'Passenger Name')),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Priority (Elderly/Pregnant/Disabled)'),
                value: isPriority,
                onChanged: (val) => setDialogState(() => isPriority = val),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                setState(() {
                  final newPerson =
                      WaitlistPerson(name: name, isPriority: isPriority);
                  if (isPriority) {
                    int insertIndex = waitlist.indexWhere((p) => !p.isPriority);
                    if (insertIndex == -1) {
                      waitlist.add(newPerson);
                    } else {
                      waitlist.insert(insertIndex, newPerson);
                    }
                  } else {
                    waitlist.add(newPerson);
                  }
                });
                saveData();
                Navigator.pop(context);
              },
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    int soldCount = bookings.length;
    int totalMoney = soldCount * ticketPrice;
    bool isBusFull = soldCount >= totalSeats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bus Dispatcher: Kigali ➔ Huye'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadAppDataAndWeather,
            tooltip: 'Retry Connection',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadAppDataAndWeather,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // Global Offline Warning Banner with Retry Option
            if (isAppOffline)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline mode: App data loaded locally. Weather cached from ${weatherCachedTime ?? "earlier"}.',
                        style: TextStyle(
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w500,
                            fontSize: 13),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white),
                      onPressed: loadAppDataAndWeather,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),

            // Live Weather Banner for Huye
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade900.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade400),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.wb_sunny, color: Colors.amber),
                      SizedBox(width: 8),
                      Text('Huye Weather Destination',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  weatherLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : huyeWeather != null
                          ? Text('${huyeWeather!.temperature.round()}°C',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16))
                          : const Text('Offline',
                              style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Statistics Header
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Seats Sold',
                            style: TextStyle(color: Colors.grey)),
                        Text('$soldCount / $totalSeats',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Total Revenue',
                            style: TextStyle(color: Colors.grey)),
                        Text('$totalMoney RWF',
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (statusMessage != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(statusMessage!,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),

            // Seat Grid (12 Seats)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2.2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: totalSeats,
              itemBuilder: (context, index) {
                int seatNum = index + 1;
                bool isTaken = bookings.containsKey(seatNum);

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isTaken ? Colors.red.shade800 : Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    if (isTaken) {
                      showBookingDetails(seatNum);
                    } else {
                      bookSeat(seatNum);
                    }
                  },
                  child: Text('Seat $seatNum\n${isTaken ? "Taken" : "Free"}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12)),
                );
              },
            ),
            const SizedBox(height: 24),

            // Waitlist Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Waitlist',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (isBusFull)
                  FilledButton.icon(
                    onPressed: joinWaitlist,
                    icon: const Icon(Icons.person_add),
                    label: const Text('Join Waitlist'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: waitlist.isEmpty
                  ? const Text('Nobody is waiting.',
                      style: TextStyle(color: Colors.grey))
                  : Column(
                      children: waitlist.map((p) {
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              p.isPriority ? Icons.star : Icons.person,
                              color:
                                  p.isPriority ? Colors.amber : Colors.white70),
                          title: Text(p.name),
                          trailing: Text(p.isPriority ? 'Priority' : 'Ordinary',
                              style: TextStyle(
                                  color: p.isPriority
                                      ? Colors.amber
                                      : Colors.grey)),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
