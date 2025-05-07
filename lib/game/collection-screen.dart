import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class CollectionScreen extends StatefulWidget {
  @override
  _CollectionScreenState createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  final userId = 'default_user';
  final DatabaseReference _collectionRef =
  FirebaseDatabase.instance.ref().child('users/default_user/collection');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DatabaseEvent>(
        future: _collectionRef.once(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text('Ошибка загрузки 😢'));
          }

          final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>?;
          if (data == null || data.isEmpty) {
            return Center(child: Text('Пока нет пойманных Покемонов 😢'));
          }

          final pokemons = data.values.toList();

          return GridView.builder(
            padding: EdgeInsets.all(16),
            itemCount: pokemons.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 20,
            ),
            itemBuilder: (context, index) {
              final pokemon = pokemons[index] as Map<dynamic, dynamic>;
              final name = (pokemon['name'] ?? '???').toString();
              final image = (pokemon['image'] ?? '').toString();

              return Column(
                children: [
                  Image.network(
                    image,
                    height: 80,
                    errorBuilder: (context, _, __) => Icon(Icons.error),
                  ),
                  SizedBox(height: 5),
                  Text(
                    name.toUpperCase(),
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
