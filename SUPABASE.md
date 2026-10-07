# Base de données Supabase

Le générateur de devis peut enregistrer devis, factures, entreprises et clients dans une base
Supabase (offre gratuite). Sans configuration, il continue de fonctionner comme avant : les
entreprises et clients restent dans le navigateur, et les devis ne sont pas enregistrés.

## 1. Créer le projet

1. Créez un compte sur https://supabase.com, puis un nouveau projet (offre **Free**).
2. Choisissez une région en Europe (par exemple Paris ou Francfort) et notez le mot de passe
   de la base proposé.

## 2. Créer les tables

1. Dans le projet, ouvrez **SQL Editor**, puis **New query**.
2. Collez tout le contenu de [`supabase/schema.sql`](supabase/schema.sql) et cliquez sur **Run**.

Le script peut être relancé sans risque, par exemple après une mise à jour.

## 3. Créer votre compte utilisateur

Le plus simple est de créer le compte depuis Supabase :

1. **Authentication** > **Users** > **Add user** > **Create new user**.
2. Saisissez votre email et un mot de passe, et cochez **Auto Confirm User**.

Ensuite, désactivez les inscriptions pour que personne d'autre ne puisse créer de compte :
**Authentication** > **Sign In / Providers**, désactivez **Allow new users to sign up**.
(Même avec les inscriptions ouvertes, chaque compte ne voit que ses propres données.)

Le bouton « Créer un compte » de la page fonctionne aussi tant que les inscriptions sont
ouvertes ; Supabase envoie alors un email de confirmation à valider avant de se connecter.

## 4. Relier la page à la base

1. Dans Supabase, ouvrez **Project Settings** > **API Keys** (ou **Data API**) et copiez :
   - l'**URL du projet** (`https://xxxx.supabase.co`) ;
   - la clé **publishable** (`sb_publishable_…`) ou, à défaut, la clé **anon**.
2. Dans la page, ouvrez **Configuration Supabase**, collez l'URL et la clé, puis
   **Enregistrer la configuration**.
3. Connectez-vous avec l'email et le mot de passe du compte.

La clé publique peut être visible dans la page : ce sont les règles de la base (Row Level
Security) qui protègent les données. **N'utilisez jamais la clé secrète** (`service_role` ou
`sb_secret_…`) : la page la refuse.

À la première connexion, les entreprises et clients déjà saisis dans le navigateur sont copiés
dans la base.

## Fonctionnement

- **Enregistrer le devis** : enregistre le devis affiché (ou met à jour le devis ouvert).
- **Mes devis** : liste des devis avec leur statut (brouillon, envoyé, accepté, refusé),
  à ouvrir, convertir en facture ou supprimer.
- **Convertir en facture** : crée une facture numérotée `F-2026-001`, `F-2026-002`… (numérotation
  continue par année, sans trou), datée du jour, avec une échéance à 30 jours. Le devis passe au
  statut « Facturé » et ne peut plus être modifié ni supprimé.
- **Mes factures** : statut de paiement (à payer / payée) et téléchargement du PDF.
  Une facture émise ne peut être ni modifiée ni supprimée (la base le refuse) ; pour corriger
  une facture, il faudra émettre un avoir.

## Limites de l'offre gratuite

- Le projet est mis en **pause après 7 jours sans utilisation**. Les données sont conservées :
  relancez-le depuis le tableau de bord Supabase (**Restore project**).
- Pas de sauvegarde automatique téléchargeable : exportez régulièrement les tables
  (**Table Editor** > table > **Export to CSV**), surtout `factures`, à conserver 10 ans.
