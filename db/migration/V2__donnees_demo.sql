-- =============================================================================
-- LiVrai CRM – refonte
-- V2 : jeu de données de démonstration (environnements de dev / recette uniquement)
-- Mot de passe de tous les comptes de démo : Demo2026!  (hash BCrypt, coût 10)
-- =============================================================================

-- Personnel LiVrai
INSERT INTO app_user (email, password_hash, first_name, last_name, role) VALUES
  ('commercial@livrai.fr', '$2a$10$o501lLeLQhKhkVZ73Bl8hOclWvLovfWXpyko.9vYSNuHN3LeXu.HG', 'Meilin', 'Durand',  'SALES'),
  ('livraisons@livrai.fr', '$2a$10$o501lLeLQhKhkVZ73Bl8hOclWvLovfWXpyko.9vYSNuHN3LeXu.HG', 'Karim',  'Benali',  'DELIVERY');

-- Clients : un client autonome, un client géré par le service commercial
INSERT INTO customer (company_name, siret, phone, billing_email, managed_by_sales, origin, sales_rep_id) VALUES
  ('BricoPro Distribution', '41234567800019', '0561000000', 'compta@bricopro.fr', FALSE, 'SELF_SIGNUP', NULL),
  ('Hôtel Garonne',         '52345678900027', '0562000000', 'factures@hotel-garonne.fr', TRUE, 'SALES',
      (SELECT id FROM app_user WHERE email = 'commercial@livrai.fr'));

INSERT INTO app_user (email, password_hash, first_name, last_name, role, customer_id) VALUES
  ('achats@bricopro.fr',  '$2a$10$o501lLeLQhKhkVZ73Bl8hOclWvLovfWXpyko.9vYSNuHN3LeXu.HG', 'Julie', 'Martin', 'CLIENT',
      (SELECT id FROM customer WHERE siret = '41234567800019')),
  ('eco@hotel-garonne.fr', '$2a$10$o501lLeLQhKhkVZ73Bl8hOclWvLovfWXpyko.9vYSNuHN3LeXu.HG', 'Paul', 'Lefèvre', 'CLIENT',
      (SELECT id FROM customer WHERE siret = '52345678900027'));

INSERT INTO address (customer_id, label, line1, postal_code, city, is_billing) VALUES
  ((SELECT id FROM customer WHERE siret = '41234567800019'), 'Siège',          '12 rue des Artisans',     '31000', 'Toulouse', TRUE),
  ((SELECT id FROM customer WHERE siret = '41234567800019'), 'Magasin Blagnac', '5 avenue de Grenade',     '31700', 'Blagnac',  FALSE),
  ((SELECT id FROM customer WHERE siret = '52345678900027'), 'Hôtel',           '1 quai de la Daurade',    '31000', 'Toulouse', TRUE),
  ((SELECT id FROM customer WHERE siret = '52345678900027'), 'Fournisseur linge', '8 chemin du Lin',       '31120', 'Portet-sur-Garonne', FALSE);

-- Livraisons (une par statut significatif)
INSERT INTO delivery (reference, customer_id, ordered_by_id, pickup_address_id, delivery_address_id,
                      requested_date, planned_date, volume_m3, weight_kg, package_count, status, quoted_price)
SELECT v.reference, c.id, u.id, pa.id, da.id, v.requested_date, v.planned_date,
       v.volume_m3, v.weight_kg, v.package_count, v.status, v.quoted_price
FROM (VALUES
  ('LIV-2027-000001', '41234567800019', 'achats@bricopro.fr',  'Siège', 'Magasin Blagnac',  DATE '2027-01-11', DATE '2027-01-11', 12.00, 800.00,  10, 'DELIVERED', 149.90),
  ('LIV-2027-000002', '41234567800019', 'achats@bricopro.fr',  'Siège', 'Magasin Blagnac',  DATE '2027-01-25', DATE '2027-01-26', 30.00, 2400.00, 24, 'PLANNED',   320.00),
  ('LIV-2027-000003', '41234567800019', 'achats@bricopro.fr',  'Siège', 'Magasin Blagnac',  DATE '2027-02-02', NULL,              4.50,  150.00,  3,  'PENDING',   NULL),
  ('LIV-2027-000004', '52345678900027', 'eco@hotel-garonne.fr', 'Fournisseur linge', 'Hôtel', DATE '2027-01-15', DATE '2027-01-15', 6.00, 420.00, 12, 'DELIVERED', 95.00)
) AS v(reference, siret, email, pickup_label, delivery_label, requested_date, planned_date, volume_m3, weight_kg, package_count, status, quoted_price)
JOIN customer c  ON c.siret = v.siret
JOIN app_user u  ON u.email = v.email
JOIN address pa  ON pa.customer_id = c.id AND pa.label = v.pickup_label
JOIN address da  ON da.customer_id = c.id AND da.label = v.delivery_label;

SELECT setval('delivery_reference_seq', 4);

-- Historique de suivi
INSERT INTO delivery_status_history (delivery_id, from_status, to_status, changed_by_id, changed_at)
SELECT d.id, h.from_status, h.to_status, u.id, h.changed_at
FROM (VALUES
  ('LIV-2027-000001', NULL,         'PENDING',    'achats@bricopro.fr',   TIMESTAMPTZ '2027-01-05 09:12+01'),
  ('LIV-2027-000001', 'PENDING',    'ACCEPTED',   'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-05 14:30+01'),
  ('LIV-2027-000001', 'ACCEPTED',   'PLANNED',    'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-08 10:00+01'),
  ('LIV-2027-000001', 'PLANNED',    'IN_TRANSIT', 'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-11 07:45+01'),
  ('LIV-2027-000001', 'IN_TRANSIT', 'DELIVERED',  'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-11 11:20+01'),
  ('LIV-2027-000002', NULL,         'PENDING',    'achats@bricopro.fr',   TIMESTAMPTZ '2027-01-18 16:02+01'),
  ('LIV-2027-000002', 'PENDING',    'ACCEPTED',   'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-19 09:10+01'),
  ('LIV-2027-000002', 'ACCEPTED',   'PLANNED',    'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-20 11:00+01'),
  ('LIV-2027-000003', NULL,         'PENDING',    'achats@bricopro.fr',   TIMESTAMPTZ '2027-01-27 08:40+01'),
  ('LIV-2027-000004', NULL,         'PENDING',    'commercial@livrai.fr', TIMESTAMPTZ '2027-01-10 10:00+01'),
  ('LIV-2027-000004', 'PENDING',    'ACCEPTED',   'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-10 15:00+01'),
  ('LIV-2027-000004', 'ACCEPTED',   'DELIVERED',  'livraisons@livrai.fr', TIMESTAMPTZ '2027-01-15 12:00+01')
) AS h(reference, from_status, to_status, email, changed_at)
JOIN delivery d ON d.reference = h.reference
JOIN app_user u ON u.email = h.email;

-- Une facture émise et payée pour BricoPro, regroupant sa livraison terminée
INSERT INTO invoice (number, customer_id, billing_address_id, status, issue_date, due_date,
                     total_excl_tax, vat_rate, total_incl_tax, paid_at, created_by_id)
SELECT 'FAC-2027-000001', c.id, a.id, 'PAID', DATE '2027-01-31', DATE '2027-03-02',
       149.90, 20.00, 179.88, TIMESTAMPTZ '2027-02-14 10:00+01', u.id
FROM customer c
JOIN address a  ON a.customer_id = c.id AND a.is_billing
JOIN app_user u ON u.email = 'livraisons@livrai.fr'
WHERE c.siret = '41234567800019';

INSERT INTO invoice_line (invoice_id, delivery_id, description, amount_excl_tax)
SELECT i.id, d.id, 'Livraison ' || d.reference || ' – 12 m³ / 800 kg', 149.90
FROM invoice i JOIN delivery d ON d.reference = 'LIV-2027-000001'
WHERE i.number = 'FAC-2027-000001';

SELECT setval('invoice_number_seq', 1);
