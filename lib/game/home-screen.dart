import 'package:flutter/material.dart';
import 'collection-screen.dart';
import 'find-pokemon.dart';

class MainNavigation extends StatefulWidget {
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    FindPokemonScreen(),
    CollectionScreen(),
  ];

  final List<String> _titles = ['Поиск Покемонов', 'Коллекция'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
    );
  }
}
