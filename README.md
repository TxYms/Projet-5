# LiVrai – CRM

Ce dépôt contient :
- l'**application existante** (Java EE / JSP, dossier `app/`, script MySQL `db/init-script.sql`), analysée dans le rapport d'audit ;
- les **scripts PostgreSQL de la refonte** (`db/migration/`) et les **diagrammes d'architecture** (`docs/diagrammes/`).

## Refonte : base de données PostgreSQL

| Script | Contenu |
|---|---|
| `db/migration/V1__schema_initial.sql` | Tables, contraintes, index, séquences de numérotation, déclencheur `updated_at` |
| `db/migration/V2__donnees_demo.sql` | Données de démonstration (dev / recette uniquement) – mot de passe des comptes : `Demo2026!` |

Les noms suivent la convention **Flyway** : dans le futur back-end Spring Boot, ces fichiers iront dans
`src/main/resources/db/migration` et seront appliqués au démarrage.

### Lancer la base en local

```bash
docker compose up -d          # PostgreSQL 18, scripts appliqués à la première initialisation
psql -h localhost -U livrai livrai -c "SELECT reference, status FROM delivery;"
```

Sans Docker :

```bash
createdb livrai
psql -d livrai -v ON_ERROR_STOP=1 -f db/migration/V1__schema_initial.sql -f db/migration/V2__donnees_demo.sql
```

Comptes de démonstration : `achats@bricopro.fr` (client autonome), `eco@hotel-garonne.fr` (client géré),
`commercial@livrai.fr` (service commercial), `livraisons@livrai.fr` (service livraisons).

### Diagrammes

Les sources PlantUML (`.puml`) et leurs rendus (`.png`) sont dans `docs/diagrammes/` :
cas d'utilisation et composants de l'existant (`audit-*`), cas d'utilisation, composants/déploiement et schéma de données de la cible (`archi-*`).

---

# Application existante – mise en place de l'environnement de développement

## Initialisation de la base de données
Télécharger MySql 8

Créer un utilisateur

Créer une nouvelle base de données nommée `livrai`

Appliquer le script SQL db/init-script.sql

## Lancement du serveur
Télécharger Eclipse (un jdk > 6 est nécessaire)

Importer le projet Maven dans Eclipse.

Télécharger tomcat 8.5 et l'ajouter à la vue Server d'Eclipse.

Ajouter le projet `app` au server.

Modifier le fichier `AbstractDao.java` et ajuster le port, username et password de votre base de données.

Lancer le serveur.

Visiter l'URL localhost:8080/app

## 1ère connexion
Il est nécessaire de créer un utilisateur admin en base:
```
INSERT INTO user (email, name, password, admin) VALUES
  ('<email>', 'Livrai', '<password>', TRUE);

```
