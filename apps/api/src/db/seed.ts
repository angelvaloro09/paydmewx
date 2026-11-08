import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import bcrypt from 'bcryptjs';
import { and, eq } from 'drizzle-orm';
import { ulid } from 'ulid';
import { db } from './index.js';
import { runMigrations } from './migrate.js';
import {
  businesses,
  products,
  users,
  type BusinessCategory,
  type PrepType,
} from './schema.js';

interface SeedProductSpec {
  name: string;
  priceCents: number;
  trackStock: boolean;
  stock: number;
  prepMinutes: number | null;
}

interface SeedBusinessSpec {
  ownerEmail: string;
  ownerName: string;
  name: string;
  description: string;
  category: BusinessCategory;
  prepType: PrepType;
  address: string;
  lat: number;
  lng: number;
  clabe: string;
  products: SeedProductSpec[];
}

const SEED_DATA: SeedBusinessSpec[] = [
  {
    ownerEmail: 'demo@paydmewx.mx',
    ownerName: 'Don Carlos Hernández',
    name: 'Taquería El Tizoncito Callejero',
    description: 'Tacos al pastor, suadero y volcanes al carbón en la Roma Norte.',
    category: 'food',
    prepType: 'made_to_order',
    address: 'Av. Álvaro Obregón 120, Roma Norte, Cuauhtémoc, CDMX',
    lat: 19.4173,
    lng: -99.1621,
    clabe: '012180015826225713',
    products: [
      { name: 'Orden de Tacos al Pastor (5 pzas)', priceCents: 9500, trackStock: true, stock: 45, prepMinutes: 8 },
      { name: 'Taco de Suadero', priceCents: 2200, trackStock: true, stock: 60, prepMinutes: 5 },
      { name: 'Gringa al Pastor', priceCents: 5500, trackStock: true, stock: 30, prepMinutes: 10 },
      { name: 'Volcán con Queso', priceCents: 3800, trackStock: true, stock: 25, prepMinutes: 7 },
      { name: 'Agua de Horchata 500ml', priceCents: 2500, trackStock: true, stock: 20, prepMinutes: 2 },
    ],
  },
  {
    ownerEmail: 'zapateria@paydmewx.mx',
    ownerName: 'Elena Morales',
    name: 'Zapatería Paso Firme Coyoacán',
    description: 'Calzado artesanal mexicano en piel, botas y tenis casuales.',
    category: 'footwear',
    prepType: 'instant',
    address: 'Calle Ignacio Allende 45, Del Carmen, Coyoacán, CDMX',
    lat: 19.3502,
    lng: -99.1625,
    clabe: '012180015826225713',
    products: [
      { name: 'Botín de Piel Artesanal Café', priceCents: 125000, trackStock: true, stock: 12, prepMinutes: null },
      { name: 'Tenis Urbano Blanco', priceCents: 89000, trackStock: true, stock: 18, prepMinutes: null },
      { name: 'Huarache Tradicional Tejido', priceCents: 54000, trackStock: true, stock: 15, prepMinutes: null },
      { name: 'Mocasín Clásico Negro', priceCents: 98000, trackStock: true, stock: 8, prepMinutes: null },
      { name: 'Kit de Limpieza para Piel', priceCents: 18000, trackStock: true, stock: 25, prepMinutes: null },
    ],
  },
  {
    ownerEmail: 'sastreria@paydmewx.mx',
    ownerName: 'Maestro Roberto Vega',
    name: 'Sastrería y Composturas Don Roberto',
    description: 'Ajustes de trajes, bastillas, cierres y confección a la medida.',
    category: 'tailoring',
    prepType: 'made_to_order',
    address: 'Calle República de Cuba 32, Centro Histórico, CDMX',
    lat: 19.4366,
    lng: -99.1369,
    clabe: '012180015826225713',
    products: [
      { name: 'Bastilla de Pantalón de Vestir', priceCents: 12000, trackStock: true, stock: 50, prepMinutes: 45 },
      { name: 'Ajuste de Cintura en Saco o Pantalón', priceCents: 25000, trackStock: true, stock: 30, prepMinutes: 90 },
      { name: 'Cambio de Cierre Metálico', priceCents: 15000, trackStock: true, stock: 20, prepMinutes: 60 },
      { name: 'Camisa a la Medida (Algodón Egipcio)', priceCents: 115000, trackStock: true, stock: 10, prepMinutes: 240 },
      { name: 'Planchado a Vapor de Traje Completo', priceCents: 18000, trackStock: true, stock: 40, prepMinutes: 30 },
    ],
  },
];

export async function runSeed(): Promise<void> {
  await runMigrations();

  // Fixture owners get a random password nobody knows unless SEED_OWNER_PASSWORD is set.
  const seedPassword =
    process.env.SEED_OWNER_PASSWORD?.trim() || randomBytes(24).toString('base64url');

  const now = Math.floor(Date.now() / 1000);

  for (const spec of SEED_DATA) {
    const email = spec.ownerEmail.toLowerCase();
    let [user] = await db.select().from(users).where(eq(users.email, email)).limit(1);

    if (!user) {
      const passwordHash = await bcrypt.hash(seedPassword, 10);
      user = {
        id: ulid(),
        email,
        passwordHash,
        name: spec.ownerName,
        createdAt: now,
      };
      await db.insert(users).values(user);
    }

    let [business] = await db
      .select()
      .from(businesses)
      .where(eq(businesses.ownerId, user.id))
      .limit(1);

    if (!business) {
      business = {
        id: ulid(),
        ownerId: user.id,
        name: spec.name,
        description: spec.description,
        category: spec.category,
        prepType: spec.prepType,
        address: spec.address,
        lat: spec.lat,
        lng: spec.lng,
        active: true,
        peyBankAccountId: null,
        clabe: spec.clabe,
        codiStatus: null,
        createdAt: now,
      };
      await db.insert(businesses).values(business);
    }

    for (const prodSpec of spec.products) {
      const [existingProd] = await db
        .select()
        .from(products)
        .where(
          and(
            eq(products.businessId, business.id),
            eq(products.name, prodSpec.name)
          )
        )
        .limit(1);

      if (!existingProd) {
        await db.insert(products).values({
          id: ulid(),
          businessId: business.id,
          name: prodSpec.name,
          priceCents: prodSpec.priceCents,
          trackStock: prodSpec.trackStock,
          stock: prodSpec.stock,
          prepMinutes: prodSpec.prepMinutes,
          imageUrl: null,
          active: true,
          createdAt: now,
        });
      }
    }
  }
}

const isMain =
  process.argv[1] &&
  fileURLToPath(import.meta.url).toLowerCase() === process.argv[1].toLowerCase();

if (isMain) {
  runSeed()
    .then(() => {
      console.log('Seed completed successfully.');
      process.exit(0);
    })
    .catch((err) => {
      console.error('Seed failed:', err);
      process.exit(1);
    });
}
