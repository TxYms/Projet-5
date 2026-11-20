-- =============================================================================
-- LiVrai CRM – refonte
-- V1 : schéma initial PostgreSQL (≥ 16, cible 18)
-- Script de migration Flyway : à placer dans src/main/resources/db/migration
-- =============================================================================
-- Conventions :
--   * tables et colonnes en snake_case, noms de tables au singulier ;
--   * clés primaires techniques BIGINT générées (IDENTITY) ;
--   * montants en NUMERIC(12,2), jamais en type flottant ;
--   * horodatages en TIMESTAMPTZ (UTC) ;
--   * colonne "version" pour le verrouillage optimiste (JPA @Version)
--     sur les entités modifiées par plusieurs services.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Comptes clients (entreprises)
-- -----------------------------------------------------------------------------
CREATE TABLE customer (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    company_name      VARCHAR(150) NOT NULL,
    siret             CHAR(14)     UNIQUE,
    vat_number        VARCHAR(20),
    phone             VARCHAR(20),
    billing_email     VARCHAR(255),
    -- Clients pris en charge par le service commercial (« clients gérés »)
    managed_by_sales  BOOLEAN      NOT NULL DEFAULT FALSE,
    -- Origine du compte : inscription autonome ou création par un commercial
    origin            VARCHAR(20)  NOT NULL DEFAULT 'SELF_SIGNUP',
    active            BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version           INTEGER      NOT NULL DEFAULT 0,
    CONSTRAINT ck_customer_origin CHECK (origin IN ('SELF_SIGNUP', 'SALES')),
    CONSTRAINT ck_customer_siret  CHECK (siret IS NULL OR siret ~ '^[0-9]{14}$')
);

COMMENT ON TABLE customer IS 'Entreprise cliente de LiVrai (compte client).';
COMMENT ON COLUMN customer.managed_by_sales IS 'TRUE si le client reste suivi par le service commercial.';

-- -----------------------------------------------------------------------------
-- Utilisateurs de l'application (clients et personnel LiVrai)
-- -----------------------------------------------------------------------------
CREATE TABLE app_user (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email             VARCHAR(255) NOT NULL,
    password_hash     VARCHAR(100) NOT NULL,          -- BCrypt / Argon2, jamais en clair
    first_name        VARCHAR(80)  NOT NULL,
    last_name         VARCHAR(80)  NOT NULL,
    role              VARCHAR(20)  NOT NULL,
    customer_id       BIGINT       REFERENCES customer (id),
    enabled           BOOLEAN      NOT NULL DEFAULT TRUE,
    password_change_required BOOLEAN NOT NULL DEFAULT FALSE,  -- TRUE pour les comptes repris de l'ancien CRM
    last_login_at     TIMESTAMPTZ,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    version           INTEGER      NOT NULL DEFAULT 0,
    CONSTRAINT ck_app_user_role CHECK (role IN ('CLIENT', 'SALES', 'DELIVERY')),
    -- Un utilisateur CLIENT est rattaché à une entreprise ; le personnel LiVrai non.
    CONSTRAINT ck_app_user_customer CHECK (
        (role = 'CLIENT' AND customer_id IS NOT NULL) OR
        (role <> 'CLIENT' AND customer_id IS NULL)
    )
);

-- Unicité de l'e-mail insensible à la casse
CREATE UNIQUE INDEX ux_app_user_email ON app_user (lower(email));
CREATE INDEX ix_app_user_customer ON app_user (customer_id);

COMMENT ON TABLE app_user IS 'Compte de connexion. Rôles : CLIENT, SALES (service commercial), DELIVERY (service livraisons).';

-- Commercial référent des clients gérés (un commercial suit plusieurs clients)
ALTER TABLE customer
    ADD COLUMN sales_rep_id BIGINT REFERENCES app_user (id);
CREATE INDEX ix_customer_sales_rep ON customer (sales_rep_id);

-- -----------------------------------------------------------------------------
-- Adresses (enlèvement / livraison / facturation)
-- -----------------------------------------------------------------------------
CREATE TABLE address (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id       BIGINT       NOT NULL REFERENCES customer (id),
    label             VARCHAR(80)  NOT NULL,              -- ex. « Entrepôt Nord »
    line1             VARCHAR(150) NOT NULL,
    line2             VARCHAR(150),
    postal_code       VARCHAR(10)  NOT NULL,
    city              VARCHAR(100) NOT NULL,
    country_code      CHAR(2)      NOT NULL DEFAULT 'FR',
    is_billing        BOOLEAN      NOT NULL DEFAULT FALSE,
    archived          BOOLEAN      NOT NULL DEFAULT FALSE, -- jamais supprimée : référencée par l'historique
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX ix_address_customer ON address (customer_id);
-- Une seule adresse de facturation active par client
CREATE UNIQUE INDEX ux_address_billing ON address (customer_id) WHERE is_billing AND NOT archived;

-- -----------------------------------------------------------------------------
-- Livraisons (commandes de livraison)
-- -----------------------------------------------------------------------------
CREATE TABLE delivery (
    id                    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reference             VARCHAR(20)   NOT NULL UNIQUE,   -- ex. LIV-2027-000123, affichée au client
    customer_id           BIGINT        NOT NULL REFERENCES customer (id),
    ordered_by_id         BIGINT        NOT NULL REFERENCES app_user (id),
    pickup_address_id     BIGINT        NOT NULL REFERENCES address (id),
    delivery_address_id   BIGINT        NOT NULL REFERENCES address (id),
    requested_date        DATE          NOT NULL,
    planned_date          DATE,
    volume_m3             NUMERIC(8,2)  NOT NULL,
    weight_kg             NUMERIC(10,2) NOT NULL,
    package_count         INTEGER       NOT NULL DEFAULT 1,
    instructions          VARCHAR(500),
    status                VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    quoted_price          NUMERIC(12,2),                 -- prix HT proposé / validé
    created_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now(),
    version               INTEGER       NOT NULL DEFAULT 0,
    CONSTRAINT ck_delivery_status CHECK (status IN
        ('PENDING', 'ACCEPTED', 'REJECTED', 'PLANNED', 'IN_TRANSIT', 'DELIVERED', 'CANCELLED')),
    CONSTRAINT ck_delivery_volume  CHECK (volume_m3 > 0),
    CONSTRAINT ck_delivery_weight  CHECK (weight_kg > 0),
    CONSTRAINT ck_delivery_packages CHECK (package_count > 0),
    CONSTRAINT ck_delivery_price   CHECK (quoted_price IS NULL OR quoted_price >= 0)
);

-- Numéros lisibles générés par le back-end : LIV-<année>-<séquence>, FAC-<année>-<séquence>
CREATE SEQUENCE delivery_reference_seq;
CREATE SEQUENCE invoice_number_seq;

-- Listes paginées « mes livraisons » (client) et tableau de bord par statut (service livraisons)
CREATE INDEX ix_delivery_customer_created ON delivery (customer_id, created_at DESC);
CREATE INDEX ix_delivery_status_date      ON delivery (status, requested_date);
CREATE INDEX ix_delivery_ordered_by       ON delivery (ordered_by_id);
CREATE INDEX ix_delivery_pickup_address   ON delivery (pickup_address_id);
CREATE INDEX ix_delivery_delivery_address ON delivery (delivery_address_id);

-- -----------------------------------------------------------------------------
-- Historique des statuts (suivi et traçabilité)
-- -----------------------------------------------------------------------------
CREATE TABLE delivery_status_history (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    delivery_id       BIGINT       NOT NULL REFERENCES delivery (id) ON DELETE CASCADE,
    from_status       VARCHAR(20),
    to_status         VARCHAR(20)  NOT NULL,
    changed_by_id     BIGINT       REFERENCES app_user (id),
    comment           VARCHAR(500),
    changed_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX ix_status_history_delivery ON delivery_status_history (delivery_id, changed_at);

-- -----------------------------------------------------------------------------
-- Facturation
-- -----------------------------------------------------------------------------
CREATE TABLE invoice (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    number            VARCHAR(20)   UNIQUE,              -- attribué à l'émission : numérotation continue (obligation légale)
    customer_id       BIGINT        NOT NULL REFERENCES customer (id),
    billing_address_id BIGINT       NOT NULL REFERENCES address (id),
    status            VARCHAR(20)   NOT NULL DEFAULT 'DRAFT',
    issue_date        DATE,
    due_date          DATE,
    total_excl_tax    NUMERIC(12,2) NOT NULL DEFAULT 0,
    vat_rate          NUMERIC(5,2)  NOT NULL DEFAULT 20.00,
    total_incl_tax    NUMERIC(12,2) NOT NULL DEFAULT 0,
    paid_at           TIMESTAMPTZ,
    created_by_id     BIGINT        NOT NULL REFERENCES app_user (id),
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    version           INTEGER       NOT NULL DEFAULT 0,
    CONSTRAINT ck_invoice_status CHECK (status IN ('DRAFT', 'ISSUED', 'PAID', 'CANCELLED')),
    CONSTRAINT ck_invoice_totals CHECK (total_excl_tax >= 0 AND total_incl_tax >= total_excl_tax),
    CONSTRAINT ck_invoice_issued CHECK (status = 'DRAFT' OR (number IS NOT NULL AND issue_date IS NOT NULL AND due_date >= issue_date)),
    CONSTRAINT ck_invoice_paid   CHECK ((status = 'PAID') = (paid_at IS NOT NULL))
);

CREATE INDEX ix_invoice_customer_date ON invoice (customer_id, issue_date DESC);
CREATE INDEX ix_invoice_status        ON invoice (status);
CREATE INDEX ix_invoice_billing_address ON invoice (billing_address_id);
CREATE INDEX ix_invoice_created_by    ON invoice (created_by_id);

CREATE TABLE invoice_line (
    id                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    invoice_id        BIGINT        NOT NULL REFERENCES invoice (id) ON DELETE CASCADE,
    delivery_id       BIGINT        NOT NULL REFERENCES delivery (id),
    description       VARCHAR(255)  NOT NULL,
    amount_excl_tax   NUMERIC(12,2) NOT NULL,
    CONSTRAINT ck_invoice_line_amount CHECK (amount_excl_tax >= 0),
    -- Une livraison n'est facturée qu'une seule fois
    CONSTRAINT ux_invoice_line_delivery UNIQUE (delivery_id)
);

CREATE INDEX ix_invoice_line_invoice ON invoice_line (invoice_id);

-- -----------------------------------------------------------------------------
-- Mise à jour automatique de updated_at
-- -----------------------------------------------------------------------------
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customer_updated_at BEFORE UPDATE ON customer
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_app_user_updated_at BEFORE UPDATE ON app_user
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_delivery_updated_at BEFORE UPDATE ON delivery
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_invoice_updated_at BEFORE UPDATE ON invoice
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
