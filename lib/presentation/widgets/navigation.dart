import 'package:flutter/material.dart';

class Navbar extends StatelessWidget {

  const Navbar({
    required this.selectedIndex, required this.onItemSelected, required this.labels, required this.icons, super.key,
  });
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<String> labels;
  final List<IconData> icons;

  @override
  Widget build(BuildContext context) => BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: onItemSelected,
      type: BottomNavigationBarType.fixed,
      items: List.generate(
        labels.length,
        (index) => BottomNavigationBarItem(
          icon: Icon(icons[index]),
          label: labels[index],
        ),
      ),
    );
}

class Sidebar extends StatelessWidget {

  const Sidebar({
    required this.selectedIndex, required this.onItemSelected, required this.labels, required this.icons, required this.userName, required this.onLogout, super.key,
  });
  final int selectedIndex;
  final Function(int) onItemSelected;
  final List<String> labels;
  final List<IconData> icons;
  final String userName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2ECC71)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Randil Grocery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Welcome, $userName',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          ...List.generate(
            labels.length,
            (index) => ListTile(
              leading: Icon(
                icons[index],
                color: selectedIndex == index
                    ? const Color(0xFF2ECC71)
                    : Colors.grey,
              ),
              title: Text(
                labels[index],
                style: TextStyle(
                  color: selectedIndex == index
                      ? const Color(0xFF2ECC71)
                      : const Color(0xFF2C3E50),
                  fontWeight: selectedIndex == index
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              onTap: () => onItemSelected(index),
              selected: selectedIndex == index,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout'),
            onTap: onLogout,
          ),
        ],
      ),
    );
}
