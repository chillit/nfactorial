import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import 'package:http/http.dart' as http;

class BattleScreen extends StatefulWidget {
  final Map<String, dynamic> myPokemon;
  final Map<String, dynamic> wildPokemon;

  const BattleScreen({
    required this.myPokemon,
    required this.wildPokemon,
    Key? key,
  }) : super(key: key);

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen> {
  String? selectedPokeball;
  bool showPokeballSelection = false;
  List<Pokeball> pokeballs = [];
  late int myCurrentHp;
  late int wildCurrentHp;
  bool isWildAsleep = false;
  final Random _random = Random();
  String? wildDescription;
  bool isLoadingDescription = true;
  bool isLoadingPokeballs = true;


@override
void initState() {
  super.initState();
  myCurrentHp = (widget.myPokemon['stats']['hp'] * 2).toInt();
  wildCurrentHp = (widget.wildPokemon['stats']['hp'] * 2).toInt();
  _fetchWildDescription();
  _loadPokeballs();
  // ... остальная инициализация
}

  Future<void> _loadPokeballs() async {
    setState(() => isLoadingPokeballs = true);
    try {
      final ref = FirebaseDatabase.instance.ref("users/default_user/pokeballs");
      final snapshot = await ref.get();

      if (snapshot.exists) {
        final loadedPokeballs = <Pokeball>[];
        (snapshot.value as Map<dynamic, dynamic>).forEach((id, value) {
          loadedPokeballs.add(Pokeball.fromMap(id.toString(), value));
        });
        setState(() => pokeballs = loadedPokeballs);
      }
    } catch (e) {
      debugPrint("Ошибка загрузки покеболов: $e");
    } finally {
      setState(() => isLoadingPokeballs = false);
    }
  }
  Future<void> _usePokeball(Pokeball pokeball) async {
    // Удаляем из базы данных
    try {
      final ref = FirebaseDatabase.instance.ref("users/default_user/pokeballs/${pokeball.id}");
      await ref.remove();

      // Обновляем локальный список
      setState(() {
        pokeballs.removeWhere((p) => p.id == pokeball.id);
      });

      // Рассчитываем шанс поимки
      final hpRatio = 1 - (wildCurrentHp / getMaxHp(widget.wildPokemon));
      final baseChance = hpRatio * 0.6;
      final sleepBonus = isWildAsleep ? 0.3 : 0.0;
      final pokeballBonus = _getPokeballBonus(pokeball.type);
      final totalChance = (baseChance + sleepBonus + pokeballBonus).clamp(0.1, 0.95);

      // Анимация броска
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Используем ${pokeball.type}...")),
      );
      await Future.delayed(const Duration(seconds: 1));

      if (_random.nextDouble() < totalChance) {
        Navigator.pop(context, 1); // Успешная поимка
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${pokeball.type} не сработал!")),
        );
        _enemyAttack();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ошибка использования покебола")),
      );
      debugPrint("Ошибка использования покебола: $e");
    }
  }
  Future<void> _showPokeballSelection() async {
    if (isLoadingPokeballs) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Загрузка покеболов...")),
      );
      return;
    }

    if (pokeballs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("У вас нет покеболов!")),
      );
      return;
    }

    // Группируем покеболы по типам
    final pokeballCounts = <String, int>{};
    for (var pokeball in pokeballs) {
      pokeballCounts[pokeball.type] = (pokeballCounts[pokeball.type] ?? 0) + 1;
    }

    final selectedType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Выберите Покебол"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: pokeballCounts.entries.map((entry) {
              final type = entry.key;
              final count = entry.value;
              return ListTile(
                leading: _getPokeballIcon(type),
                title: Text(type),
                subtitle: Text("Доступно: $count"),
                trailing: Text("+${(_getPokeballBonus(type) * 100).toInt()}%"),
                onTap: () => Navigator.pop(context, type),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
        ],
      ),
    );

    if (selectedType != null) {
      // Выбираем самый старый покебол этого типа
      final pokeballToUse = pokeballs
          .where((p) => p.type == selectedType)
          .toList()
          .reduce((a, b) => a.receivedAt.isBefore(b.receivedAt) ? a : b);

      await _usePokeball(pokeballToUse);
    }
  }
Future<void> _fetchWildDescription() async {
  setState(() {
    isLoadingDescription = true;
  });

  final name = widget.wildPokemon['name'];
  final prompt = "Write a short (1-2 sentence) description of the Pokémon $name in a fun and friendly tone.";

  final response = await http.post(
    Uri.parse("https://api.openai.com/v1/chat/completions"),
    headers: {
      'Authorization': 'Bearer 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',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({
      "model": "gpt-3.5-turbo",
      "messages": [
        {"role": "user", "content": prompt}
      ],
      "max_tokens": 60,
      "temperature": 0.7
    }),
  );

  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    final desc = json['choices'][0]['message']['content'];
    setState(() {
      wildDescription = desc.trim();
      isLoadingDescription = false;
    });
  } else {
    setState(() {
      wildDescription = "Couldn't load description.";
      isLoadingDescription = false;
    });
  }
}


int getMaxHp(Map<String, dynamic> pokemon) {
  return (pokemon['stats']['hp'] * 2).toInt();
}


void _attack() {
  final attackStat = widget.myPokemon['stats']['attack'].toDouble();
  final defenseStat = widget.wildPokemon['stats']['defense'].toDouble();
  final damage = ((22 * attackStat * _random.nextDouble()) / defenseStat).round();

  setState(() {
    wildCurrentHp = (wildCurrentHp - damage).clamp(0, getMaxHp(widget.wildPokemon));
    if (wildCurrentHp <= 0) {
      wildCurrentHp = 0;
      Future.delayed(const Duration(seconds: 1), () {
        Navigator.pop(context, 3); // 3 — убил врага
      });
    }
  });

  if (wildCurrentHp > 0 && !isWildAsleep) {
    _enemyAttack();
  }
}




void _enemyAttack() {
  final attackStat = widget.wildPokemon['stats']['attack'].toDouble();
  final defenseStat = widget.myPokemon['stats']['defense'].toDouble();
  final damage = ((22 * attackStat * _random.nextDouble()) / defenseStat).round();

  setState(() {
    myCurrentHp = (myCurrentHp - damage).clamp(0, getMaxHp(widget.myPokemon));
    if (myCurrentHp <= 0) {
      myCurrentHp = 0;
      Future.delayed(const Duration(seconds: 1), () {
        Navigator.pop(context, 2); // 2 — моего покемона убили
      });
    }
  });
}


void _trySleep() {
  final successChance = 0.3 + (widget.myPokemon['stats']['special-attack'] / 100);
  final success = _random.nextDouble() < successChance;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    setState(() {
      isWildAsleep = success;
    });

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Не удалось усыпить!")),
      );
    }

    _enemyAttack();
  });
}



  void _tryCatch() async {
    if (pokeballs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("У вас нет покеболов!")),
      );
      return;
    }

    // Group pokeballs by type with counts
    final pokeballGroups = <String, List<Pokeball>>{};
    for (var pokeball in pokeballs) {
      pokeballGroups.putIfAbsent(pokeball.type, () => []).add(pokeball);
    }

    // Show pokeball selection dialog
    final selectedType = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Выберите Покебол"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: pokeballGroups.entries.map((entry) {
              final type = entry.key;
              final count = entry.value.length;
              return ListTile(
                leading: _getPokeballIcon(type),
                title: Text(type),
                subtitle: Text(
                  "Доступно: $count | +${(_getPokeballBonus(type) * 100).toInt()}%",
                  style: TextStyle(color: Colors.green[700]),
                ),
                onTap: () => Navigator.pop(context, type),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Отмена"),
          ),
        ],
      ),
    );

    if (selectedType == null) return;

    // Get the oldest pokeball of selected type (FIFO)
    final pokeballToUse = pokeballGroups[selectedType]!
        .reduce((a, b) => a.receivedAt.isBefore(b.receivedAt) ? a : b);

    // Remove used pokeball from Firebase
    final ref = FirebaseDatabase.instance
        .ref("users/default_user/pokeballs/${pokeballToUse.id}");
    await ref.remove();

    // Update local list
    setState(() {
      pokeballs.removeWhere((p) => p.id == pokeballToUse.id);
    });

    // Calculate catch chance
    final hpRatio = 1 - (wildCurrentHp / getMaxHp(widget.wildPokemon));
    final baseChance = hpRatio * 0.7;
    final sleepBonus = isWildAsleep ? 0.25 : 0.0;
    final pokeballBonus = _getPokeballBonus(pokeballToUse.type);
    final totalChance = (baseChance + sleepBonus + pokeballBonus).clamp(0.1, 0.9);

    // Show throw animation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Бросаем ${pokeballToUse.type}...")),
    );

    await Future.delayed(const Duration(seconds: 1));

    if (_random.nextDouble() < totalChance) {
      Navigator.pop(context, 1); // Success
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${pokeballToUse.type} не сработал!")),
      );
      _enemyAttack();
    }
  }

// Helper method to get pokeball icon
  Widget _getPokeballIcon(String type) {
    switch (type) {
      case 'Обычный Покебол':
        return const Icon(Icons.circle, color: Colors.red);
      case 'Супер Покебол':
        return const Icon(Icons.circle, color: Colors.blue);
      case 'Ультра Покебол':
        return const Icon(Icons.circle, color: Colors.yellow);
      default:
        return const Icon(Icons.circle);
    }
  }

// Helper method to get catch bonus
  double _getPokeballBonus(String type) {
    switch (type) {
      case 'Обычный Покебол': return 0.0;
      case 'Супер Покебол': return 0.2;
      case 'Ультра Покебол': return 0.35;
      default: return 0.0;
    }
  }


@override
Widget build(BuildContext context) {
  final myMaxHp = getMaxHp(widget.myPokemon);
  final wildMaxHp = getMaxHp(widget.wildPokemon);

  return Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    body: SafeArea(
      child: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background-fighting.jpg', // make sure this path is correct
              fit: BoxFit.cover,
            ),
          ),

          // Foreground content
          Column(
            children: [
              const SizedBox(height: 20),

              // HP Bars
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _PokemonStatus(
                    name: widget.myPokemon['name'],
                    hp: myCurrentHp,
                    maxHp: myMaxHp,
                  ),
                  _PokemonStatus(
                    name: widget.wildPokemon['name'],
                    hp: wildCurrentHp,
                    maxHp: wildMaxHp,
                    status: isWildAsleep ? "Спит" : null,
                    stats: widget.wildPokemon['stats'],
                    description: isLoadingDescription ? "Загрузка..." : wildDescription,
                  )
                ],
              ),

              const Spacer(),

              // Pokémon Sprites
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Image.network(
                    widget.myPokemon['image'].toString(),
                    height: 400,
                    width: 400,
                    fit: BoxFit.contain,
                  ),
                  Image.network(
                    widget.wildPokemon['image'].toString(),
                    height: 400,
                    width: 400,
                    fit: BoxFit.contain,
                  ),
                ],
              ),

              const SizedBox(height: 150),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 75,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: _attack,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text("Атаковать"),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 75,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: _trySleep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text("Усыпить"),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 75,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ElevatedButton(
                        onPressed: _showPokeballSelection,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Поймать"),
                            if (!isLoadingPokeballs)
                              Text(
                                "Покеболов: ${pokeballs.length}",
                                style: const TextStyle(fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    ),
  );
}
}

class _PokemonStatus extends StatefulWidget {
  final String name;
  final int hp;
  final int maxHp;
  final String? status;
  final Map<String, dynamic>? stats;
  final String? description;

  const _PokemonStatus({
    required this.name,
    required this.hp,
    required this.maxHp,
    this.status,
    this.stats,
    this.description,
  });

  @override
  State<_PokemonStatus> createState() => _PokemonStatusState();
}

class _PokemonStatusState extends State<_PokemonStatus> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: screenWidth * 0.4,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text("HP: ${widget.hp}/${widget.maxHp}"),
            if (widget.status != null) Text("Статус: ${widget.status}"),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: widget.hp / widget.maxHp,
              color: _getHpColor(widget.hp / widget.maxHp),
              backgroundColor: Colors.grey[300],
              minHeight: 10,
            ),
            if (_hovering && widget.stats != null) ...[
              const SizedBox(height: 10),
              Text("⚔️ Attack: ${widget.stats!['attack']}"),
              Text("🛡️ Defense: ${widget.stats!['defense']}"),
              Text("✨ Sp. Atk: ${widget.stats!['special-attack']}"),
              if (widget.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text("🧠 ${widget.description!}", style: const TextStyle(fontStyle: FontStyle.italic)),
                )
            ]
          ],
        ),
      ),
    );
  }

  Color _getHpColor(double ratio) {
    if (ratio > 0.5) return Colors.green;
    if (ratio > 0.2) return Colors.orange;
    return Colors.red;
  }
}

class Pokeball {
  final String id;
  final String type;
  final DateTime receivedAt;

  Pokeball({
    required this.id,
    required this.type,
    required this.receivedAt,
  });

  factory Pokeball.fromMap(String id, Map<dynamic, dynamic> map) {
    return Pokeball(
      id: id,
      type: map['type'],
      receivedAt: DateTime.parse(map['receivedAt']),
    );
  }
}