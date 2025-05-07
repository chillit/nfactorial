import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'battle-screen.dart';

class FindPokemonScreen extends StatefulWidget {
  @override
  _FindPokemonScreenState createState() => _FindPokemonScreenState();
}

class _FindPokemonScreenState extends State<FindPokemonScreen> {
  int currentLocationIndex = 0;

  final List<Map<String, dynamic>> locations = [
    {
      'name': 'Forest',
      'background': 'assets/images/background-forest.png',
    },
    {
      'name': 'Desert',
      'background': 'assets/images/background-desert.png',
    },
    {
      'name': 'Ocean',
      'background': 'assets/images/background-ocean.png',
    },
  ];

  bool loading = false;
  Map<String, dynamic>? foundPokemon;
  Map<String, dynamic>? myPokemon;
  String result = '';
  bool battleOver = false;
  bool caught = false;
  List<Map<String, dynamic>> myCollection = [];
  Map<String, dynamic>? selectedPokemon;
  String? primaryPokemonId;

  @override
  Widget build(BuildContext context) {
    final location = locations[currentLocationIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('PokeGame'),
        actions: [
          IconButton(
            icon: Icon(Icons.list_alt),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  insetPadding: EdgeInsets.all(20),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.8,
                    height: MediaQuery.of(context).size.height * 0.8,
                    child: PokemonCollectionDialog(),
                  ),
                ),
              );
            },
          )
        ],
      ),
      body: Stack(
        children: [
          // Background Image
          Positioned.fill(
            child: Image.asset(
              location['background'],
              fit: BoxFit.cover,
            ),
          ),
          // Location Name and Arrows
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_left, size: 32, color: Colors.white,),
                  onPressed: () {
                    setState(() {
                      currentLocationIndex =
                          (currentLocationIndex - 1 + locations.length) % locations.length;
                    });
                  },
                ),
                Text(
                  location['name'],
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                IconButton(
                  icon: Icon(Icons.arrow_right, size: 32,color: Colors.white),
                  onPressed: () {
                    setState(() {
                      currentLocationIndex = (currentLocationIndex + 1) % locations.length;
                    });
                  },
                ),
              ],
            ),
          ),
          // Pokeball Tap
          Center(
            child: InkWell(
              onTap: () => startFindAndBattle(context),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white, // Белый фон
                  shape: BoxShape.circle, // Если хотите сделать фон круглым
                ),
                padding: EdgeInsets.all(2), // Добавьте отступ, если нужно
                child: Image.asset(
                  'assets/images/pokeball.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> loadCollection() async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();
    final snapshot = await db.child('users/$userId/collection').get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final list = data.entries.map((e) {
        return {
          'firebaseKey': e.key,
          ...Map<String, dynamic>.from(e.value),
        };
      }).toList();

      setState(() {
        myCollection = list;
      });
    }
  }
  Future<Map<String, dynamic>?> getPrimaryPokemon() async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();

    final primaryKeySnapshot = await db.child('users/$userId/primaryPokemon').get();
    if (!primaryKeySnapshot.exists) return null;

    final primaryKey = primaryKeySnapshot.value as String;
    final collectionSnapshot = await db.child('users/$userId/collection/$primaryKey').get();
    if (!collectionSnapshot.exists) return null;

    return Map<String, dynamic>.from(collectionSnapshot.value as Map);
  }
  // Остальные методы остаются без изменений до метода startFindAndBattle
  String getRandomPokeball() {
    final rand = Random().nextInt(100); // 0 to 99

    if (rand < 65) return "Ультра Покебол";
    else if (rand < 85) return "Супер Покебол";
    else return "Обычный Покебол";
  }
  Future<void> savePokeballToFirebase(String pokeball) async {
    final ref = FirebaseDatabase.instance.ref("users/default_user/pokeballs");
    await ref.push().set({"type": pokeball, "receivedAt": DateTime.now().toIso8601String()});
  }

  Future<void> startFindAndBattle(BuildContext context) async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();

    try {
      // Получаем ключ основного покемона
      final primarySnapshot = await db.child('users/$userId/primaryPokemon').get();
      if (!primarySnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Выберите основного покемона.")),
        );
        return;
      }

      final primaryKey = primarySnapshot.value as String;

      // Получаем данные основного покемона
      final pokemonSnapshot = await db.child('users/$userId/collection/$primaryKey').get();
      if (!pokemonSnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Основной покемон не найден в коллекции.")),
        );
        return;
      }

      final myPokemon = Map<String, dynamic>.from(pokemonSnapshot.value as Map);

      // Получаем случайного дикого покемона
      final randomId = 1 + Random().nextInt(151);
      final response = await http.get(Uri.parse('https://pokeapi.co/api/v2/pokemon/$randomId'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final wildPokemon = {
          'id': data['id'],
          'name': data['name'],
          'image': data['sprites']['front_default'],
          'stats': {
            'hp': data['stats'][0]['base_stat'],
            'attack': data['stats'][1]['base_stat'],
            'defense': data['stats'][2]['base_stat'],
            'special-attack': data['stats'][3]['base_stat'],
            'special-defense': data['stats'][4]['base_stat'],
            'speed': data['stats'][5]['base_stat'],
          },
          'types': (data['types'] as List)
              .map((type) => type['type']['name'])
              .toList(),
          'height': data['height'],
          'weight': data['weight'],
          'abilities': (data['abilities'] as List)
              .map((ability) => ability['ability']['name'])
              .toList(),
        };

        // Запускаем битву
        final caught = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BattleScreen(
              myPokemon: myPokemon,
              wildPokemon: wildPokemon,
            ),
          ),
        );

        // Если поймали - сохраняем
        if (caught == 1) {
          await savePokemonToFirebase(wildPokemon);
          AwesomeDialog(
            context: context,
            dialogType: DialogType.success,
            animType: AnimType.scale,
            title: 'Поймано!',
            desc: "${wildPokemon['name']} теперь с тобой!",
            btnOkOnPress: () {},
            btnOkText: "Ура!",
            btnOkColor: Colors.green,
          ).show();
        }
        else if (caught == 2) {
          AwesomeDialog(
            context: context,
            dialogType: DialogType.error,
            animType: AnimType.bottomSlide,
            title: 'Твой покемон пал...',
            desc: 'В следующий раз повезёт больше.',
            btnOkOnPress: () {},
            btnOkText: "Печально",
            btnOkColor: Colors.redAccent,
          ).show();
        }
        else if (caught == 3) {
          String pokeball = getRandomPokeball();
          await savePokeballToFirebase(pokeball);

          AwesomeDialog(
            context: context,
            dialogType: DialogType.info,
            animType: AnimType.leftSlide,
            title: 'Победа!',
            desc: 'Ты победил дикого ${wildPokemon['name']}!\n\nНаграда: $pokeball 🎁',
            btnOkOnPress: () {},
            btnOkText: "Отлично!",
            btnOkColor: Colors.blueAccent,
          ).show();
        }
      }
    } catch (e) {
      print("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Ошибка: ${e.toString()}")),
      );
    }
  }


  Future<void> savePokemonToFirebase(Map<String, dynamic> pokemon) async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();
    final newRef = db.child('users/$userId/collection').push();

    await newRef.set({
      'id': pokemon['id'],
      'name': pokemon['name'],
      'image': pokemon['image'],
      'stats': pokemon['stats'],
      'types': pokemon['types'],
      'height': pokemon['height'],
      'weight': pokemon['weight'],
      'abilities': pokemon['abilities'],
      'caught_at': ServerValue.timestamp,
    });
  }
}

class PokemonCollectionDialog extends StatefulWidget {
  @override
  _PokemonCollectionDialogState createState() => _PokemonCollectionDialogState();
}

class _PokemonCollectionDialogState extends State<PokemonCollectionDialog> {
  List<Map<String, dynamic>> myCollection = [];
  Map<String, dynamic>? selectedPokemon;
  String? primaryPokemonId;

  @override
  void initState() {
    super.initState();
    loadCollection();
  }

  void setPrimary(String firebaseKey) async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();

    await db.child('users/$userId/primaryPokemon').set(firebaseKey);

    setState(() {
      primaryPokemonId = firebaseKey;
    });
  }

  Future<void> loadCollection() async {
    final userId = 'default_user';
    final db = FirebaseDatabase.instance.ref();
    final snapshot = await db.child('users/$userId/collection').get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final list = data.entries.map((e) {
        return {
          'firebaseKey': e.key,
          ...Map<String, dynamic>.from(e.value),
        };
      }).toList();

      setState(() {
        myCollection = list;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ListView.builder(
                itemCount: myCollection.length,
                itemBuilder: (context, index) {
                  final pokemon = myCollection[index];
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(12),
                      leading: Image.network(pokemon['image'], width: 50),
                      title: Text(
                        pokemon['name'],
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: Checkbox(
                        value: pokemon['firebaseKey'] == primaryPokemonId,
                        onChanged: (_) {
                          setPrimary(pokemon['firebaseKey']);
                        },
                      ),
                      onTap: () {
                        setState(() {
                          selectedPokemon = pokemon;
                        });
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: selectedPokemon == null
                ? Center(child: Text('Выберите покемона', style: TextStyle(fontSize: 18)))
                : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Image.network(
                            selectedPokemon!['image'].toString(),
                            height: 400,
                            width: 400,
                            fit: BoxFit.contain,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text('Имя: ${selectedPokemon!['name']}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        SizedBox(height: 10),
                        Text('Типы: ${selectedPokemon!['types'].join(', ')}'),
                        Text('Рост: ${selectedPokemon!['height']}'),
                        Text('Вес: ${selectedPokemon!['weight']}'),
                        SizedBox(height: 16),
                        Divider(),
                        SizedBox(height: 10),
                        Text('Статы:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ...selectedPokemon!['stats'].entries
                            .map((entry) => Text('${entry.key}: ${entry.value}'))
                            .toList(),
                        SizedBox(height: 16),
                        Divider(),
                        SizedBox(height: 10),
                        Text('Способности:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ...selectedPokemon!['abilities']
                            .map<Widget>((a) => Text('• $a'))
                            .toList(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
