import 'package:flutter/material.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// Shows the system tab bar that holds the whole app (iOS 27+). On iPhone Duo
/// it moves into the vertical bar. Leaving the page hides it again.
class NativeRootTabDemoPage extends StatefulWidget {
  const NativeRootTabDemoPage({super.key});

  @override
  State<NativeRootTabDemoPage> createState() => _NativeRootTabDemoPageState();
}

class _NativeRootTabDemoPageState extends State<NativeRootTabDemoPage> {
  static const _destinations = [
    AdaptiveNavigationDestination(
      icon: 'house',
      selectedIcon: 'house.fill',
      label: 'Home',
    ),
    AdaptiveNavigationDestination(icon: 'bell', label: 'Alerts', badgeCount: 3),
    AdaptiveNavigationDestination(
      icon: 'person.crop.circle',
      label: 'Profile',
    ),
  ];

  var _selectedIndex = 0;
  var _createCount = 0;

  @override
  Widget build(BuildContext context) {
    final isSupported = NativeRootTabBar.isSupported;
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Native Root Tab Bar'),
      body: Stack(
        children: [
          Center(
            child: Text(
              isSupported
                  ? '${_destinations[_selectedIndex].label} tab\nCreate tapped $_createCount times'
                  : 'Needs iOS 27 or later',
              textAlign: TextAlign.center,
            ),
          ),
          if (isSupported)
            NativeRootTabBar(
              destinations: _destinations,
              selectedIndex: _selectedIndex,
              onTap: (value) => setState(() => _selectedIndex = value),
              action: NativeTabAction(
                sfSymbol: 'plus',
                label: 'Create',
                onPressed: () => setState(() => _createCount++),
              ),
            ),
        ],
      ),
    );
  }
}
