 import 'package:flutter/material.dart';
import 'package:service_keeper/widgets/page_animated.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget PageBanner({required String pref, 
required bool dismissed, 
required String text, 
required VoidCallback onDismiss, 
IconData icon = Icons.info_outline, 
Color? color,
Color? textColor,
Color? iconColor,
int pageIndex = 0,
PageController? pageController}) {
    if (dismissed) return const SizedBox.shrink();
    final banner = Container(
      color: color ?? Colors.black87.withAlpha(102),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: iconColor ?? textColor ?? Colors.black87),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: textColor ?? Colors.black87)),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(pref, true);
            onDismiss();
          },
          child: Icon(Icons.close, size: 16, color: iconColor ?? textColor ?? Colors.black87),
        ),
      ]),
    );
    if (pageController == null) return banner;
    return PageAnimated(banner, pageIndex, pageController);
  }

  

