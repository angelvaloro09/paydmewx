enum BusinessCategory {
  food('food', 'Comida'),
  tailoring('tailoring', 'Sastrería'),
  footwear('footwear', 'Calzado'),
  clothing('clothing', 'Ropa'),
  department('department', 'Departamental'),
  grocery('grocery', 'Abarrotes'),
  services('services', 'Servicios'),
  other('other', 'Otros');

  final String apiValue;
  final String labelEs;
  const BusinessCategory(this.apiValue, this.labelEs);

  static BusinessCategory fromApi(String? value) {
    return BusinessCategory.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => BusinessCategory.other,
    );
  }
}

enum PrepType {
  instant('instant', 'Entrega inmediata'),
  madeToOrder('made_to_order', 'Con tiempo de elaboración');

  final String apiValue;
  final String labelEs;
  const PrepType(this.apiValue, this.labelEs);

  static PrepType fromApi(String? value) {
    return PrepType.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => PrepType.instant,
    );
  }
}

class User {
  final String id;
  final String email;
  final String name;
  final int? createdAt;

  const User({
    required this.id,
    required this.email,
    required this.name,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      createdAt: json['createdAt'] is num
          ? (json['createdAt'] as num).toInt()
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        if (createdAt != null) 'createdAt': createdAt,
      };
}

class Business {
  final String id;
  final String? ownerId;
  final String name;
  final BusinessCategory category;
  final PrepType prepType;
  final String? description;
  final String? address;
  final double? lat;
  final double? lng;
  final String? codiStatus;
  final bool active;

  const Business({
    required this.id,
    this.ownerId,
    required this.name,
    required this.category,
    required this.prepType,
    this.description,
    this.address,
    this.lat,
    this.lng,
    this.codiStatus,
    this.active = true,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: (json['id'] ?? '').toString(),
      ownerId: json['ownerId']?.toString(),
      name: (json['name'] ?? '').toString(),
      category: BusinessCategory.fromApi(json['category']?.toString()),
      prepType: PrepType.fromApi(json['prepType']?.toString()),
      description: json['description']?.toString(),
      address: json['address']?.toString(),
      lat: (json['lat'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble(),
      codiStatus: json['codiStatus']?.toString(),
      active: json['active'] is bool ? json['active'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (ownerId != null) 'ownerId': ownerId,
        'name': name,
        'category': category.apiValue,
        'prepType': prepType.apiValue,
        if (description != null) 'description': description,
        if (address != null) 'address': address,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (codiStatus != null) 'codiStatus': codiStatus,
        'active': active,
      };
}

class Product {
  final String id;
  final String? businessId;
  final String name;
  final String? description;
  final int priceCents;
  final bool trackStock;
  final int stock;
  final int? prepMinutes;
  final String? imageUrl;
  final bool active;

  const Product({
    required this.id,
    this.businessId,
    required this.name,
    this.description,
    required this.priceCents,
    this.trackStock = false,
    this.stock = 0,
    this.prepMinutes,
    this.imageUrl,
    this.active = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['priceCents'] ?? json['price'] ?? 0;
    return Product(
      id: (json['id'] ?? '').toString(),
      businessId: json['businessId']?.toString(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
      priceCents: rawPrice is num
          ? rawPrice.toInt()
          : int.tryParse(rawPrice.toString()) ?? 0,
      trackStock:
          json['trackStock'] is bool ? json['trackStock'] as bool : false,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      prepMinutes: (json['prepMinutes'] as num?)?.toInt(),
      imageUrl: json['imageUrl']?.toString(),
      active: json['active'] is bool ? json['active'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (businessId != null) 'businessId': businessId,
        'name': name,
        if (description != null) 'description': description,
        'priceCents': priceCents,
        'trackStock': trackStock,
        'stock': stock,
        if (prepMinutes != null) 'prepMinutes': prepMinutes,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'active': active,
      };
}

class AuthResponse {
  final String token;
  final User user;

  const AuthResponse({
    required this.token,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: (json['token'] ?? '').toString(),
      user: User.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

class MeResponse {
  final User user;
  final Business? business;

  const MeResponse({
    required this.user,
    this.business,
  });

  factory MeResponse.fromJson(Map<String, dynamic> json) {
    final businessJson = json['business'];
    return MeResponse(
      user: User.fromJson(
        (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      business: businessJson is Map
          ? Business.fromJson(businessJson.cast<String, dynamic>())
          : null,
    );
  }
}
