import 'package:flutter/material.dart';

import 'domain.dart';

const eventIconData = <String, IconData>{
  'Sapin de Noël': Icons.park,
  'Brocante': Icons.storefront,
  'Loto': Icons.casino,
  'Spectacle': Icons.theater_comedy,
  'Événement': Icons.event,
  'Café': Icons.local_cafe,
  'Repas': Icons.restaurant,
  'Musique': Icons.music_note,
  'Fête': Icons.celebration,
  'Conférence': Icons.groups,
  'Sport': Icons.sports_soccer,
  'Atelier': Icons.palette,
  'Association': Icons.volunteer_activism,
  'Cadeau': Icons.card_giftcard,
};
IconData eventIcon(Json event) => eventIconData[eventIconName(event)]!;
