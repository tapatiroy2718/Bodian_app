import 'package:flutter/material.dart';

class WeddingCategory {
  final String id;
  final String name;
  final IconData icon;
  final List<String> subcategories;
  const WeddingCategory(this.id, this.name, this.icon, this.subcategories);
}

/// Mirrors the rows seeded into public.service_categories.
const categories = <WeddingCategory>[
  WeddingCategory('venues', 'Venues', Icons.location_city, ['Banquet', 'Marriage hall', 'Resort', 'Garden']),
  WeddingCategory('catering', 'Catering', Icons.restaurant, ['Veg', 'Non-veg', 'Bengali cuisine']),
  WeddingCategory('decoration', 'Decoration', Icons.local_florist, ['Stage', 'Flowers', 'Lighting', 'Entrance']),
  WeddingCategory('photography', 'Photography', Icons.photo_camera, ['Wedding photography', 'Pre-wedding']),
  WeddingCategory('makeup', 'Makeup', Icons.face_retouching_natural, ['Bridal', 'Groom', 'Party makeup']),
  WeddingCategory('mehendi', 'Mehendi', Icons.back_hand, ['Bridal mehendi', 'Guest mehendi']),
  WeddingCategory('entertainment', 'Entertainment', Icons.music_note, ['DJ', 'Music', 'Performers']),
  WeddingCategory('planning', 'Planning', Icons.event_note, ['Wedding planners', 'Coordinators']),
  WeddingCategory('transportation', 'Transport', Icons.directions_car, ['Cars', 'Buses', 'Luxury vehicles']),
  WeddingCategory('other', 'Other', Icons.card_giftcard, ['Florists', 'Invitations', 'Gifts', 'Priest']),
];

WeddingCategory categoryById(String? id) =>
    categories.firstWhere((c) => c.id == id, orElse: () => categories.last);

const weddingEvents = <String>[
  'Aiburo Bhat',
  'Ashirbad',
  'Engagement',
  'Mehendi',
  'Gaye Holud',
  'Biye',
  'Bou Bhat',
  'Reception',
];

const documentTypes = <String, String>{
  'trade_licence': 'Trade licence',
  'business_registration': 'Business registration',
  'business_card': 'Business card',
  'other': 'Other supporting document',
};

const bookingStatusLabels = <String, String>{
  'pending': 'Pending',
  'accepted': 'Confirmed',
  'rejected': 'Declined',
  'cancelled': 'Cancelled',
  'completed': 'Completed',
};
