# Base de données Supabase

Le générateur de devis enregistre devis, factures, entreprises et clients dans Supabase.
Un **seul projet Supabase** sert tous les utilisateurs : chacun crée son compte depuis la page
et ne voit que ses propres données (Row Level Security). Les utilisateurs n'ont rien à installer
ni à configurer.

Sans projet configuré, la page fonctionne comme avant : entreprises et clients restent dans le
navigateur et les devis ne sont pas enregistrés.

## 1. Créer le projet

1. Créez un compte sur https://supabase.com, puis un nouveau projet.
2. Choisissez une région en Europe (Paris ou Francfort) : les données de vos utilisateurs
   restent dans l'Union européenne.

## 2. Créer les tables

1. Dans le projet, ouvrez **SQL Editor**, puis **New query**.
2. Collez tout le contenu de [`supabase/schema.sql`](supabase/schema.sql) et cliquez sur **Run**.

Le script peut être relancé sans risque après une mise à jour.

## 3. Mettre la page en ligne

Les liens envoyés par email (confirmation du compte, mot de passe oublié) doivent ramener vers
une adresse web, pas vers un fichier ouvert sur l'ordinateur. Avec GitHub Pages :

1. Sur GitHub, **Settings** > **Pages** > **Deploy from a branch**, branche `main`, dossier `/ (root)`.
2. La page est alors disponible à une adresse du type `https://kmds81.github.io/Dev-Site/`.

(GitHub Pages est gratuit pour un dépôt public ; pour un dépôt privé, il faut un abonnement GitHub.)

## 4. Régler l'authentification

Dans Supabase, menu **Authentication** :

1. **URL Configuration** : mettez l'adresse de la page dans **Site URL** et ajoutez-la dans
   **Redirect URLs**.
2. **Emails** > **SMTP Settings** : branchez un service d'envoi d'emails (par exemple Brevo ou
   Resend, qui ont une offre gratuite). Le service intégré de Supabase n'envoie qu'aux membres de
   votre équipe Supabase, avec quelques emails par heure : sans SMTP, vos utilisateurs ne
   recevront ni la confirmation d'inscription ni le lien de mot de passe oublié.
3. **Emails** > **Templates** (facultatif) : traduisez les emails de confirmation et de
   réinitialisation en français.
4. Laissez les inscriptions ouvertes (**Sign In / Providers** > **Allow new users to sign up**).

## 5. Relier la page au projet

1. Dans Supabase, **Project Settings** > **API Keys** : copiez l'**URL du projet**
   (`https://xxxx.supabase.co`) et la clé **publishable** (`sb_publishable_…`, ou à défaut la
   clé **anon**).
2. Dans `index.html`, renseignez-les en haut du script :

   ```js
   const SUPABASE_URL = 'https://xxxx.supabase.co';
   const SUPABASE_KEY = 'sb_publishable_…';
   ```

3. Publiez la modification. La section « Mon compte » de la page propose alors connexion,
   création de compte et mot de passe oublié, et la configuration manuelle disparaît.

La clé publique peut être visible dans la page : ce sont les règles de la base qui protègent les
données. **N'utilisez jamais la clé secrète** (`service_role` ou `sb_secret_…`).

Si ces deux valeurs restent vides, la page affiche une section « Configuration Supabase » qui
permet à chacun de la relier à son propre projet.

## Fonctionnement

- **Créer un compte** : l'utilisateur reçoit un email de confirmation, puis se connecte.
  À la première connexion, les entreprises et clients déjà saisis dans son navigateur sont copiés
  dans son compte.
- **Mot de passe oublié** : envoie un lien par email ; en le suivant, la page demande le nouveau
  mot de passe.
- **Enregistrer le devis** : enregistre le devis affiché (ou met à jour le devis ouvert).
- **Mes devis** : liste des devis avec leur statut (brouillon, envoyé, accepté, refusé),
  à ouvrir, convertir en facture ou supprimer.
- **Convertir en facture** : crée une facture numérotée `F-2026-001`, `F-2026-002`… (numérotation
  continue par année et par compte, sans trou), datée du jour, avec une échéance à 30 jours. Le
  devis passe au statut « Facturé » et ne peut plus être modifié ni supprimé.
- **Factures** : statut de paiement (à payer / payée), date de paiement facultative et
  téléchargement du PDF. Une facture émise ne peut être ni modifiée ni supprimée (la base le
  refuse) ; seuls son statut et sa date de paiement peuvent changer. Pour corriger une facture,
  il faudra émettre un avoir.

## Mettre à jour la base

Quand une nouvelle version ajoute quelque chose à la base (par exemple la date de paiement des
factures ou la bibliothèque de prestations), relancez simplement tout le contenu de `supabase/schema.sql` dans **SQL Editor**. Le
script ne touche pas aux données existantes. Tant qu'il n'est pas relancé, la page continue de
fonctionner, sans la nouveauté (elle prévient quand c'est le cas).

## Offre gratuite ou payante

L'offre gratuite suffit pour tester avec quelques utilisateurs, mais :

- le projet est mis en **pause après 7 jours sans activité** (données conservées, à relancer
  depuis le tableau de bord avec **Restore project**) ;
- il n'y a **pas de sauvegarde automatique** : exportez régulièrement les tables
  (**Table Editor** > table > **Export to CSV**), surtout `factures`, à conserver 10 ans.

Dès que de vrais utilisateurs y mettent leurs factures, passez à l'offre **Pro** (environ
25 $/mois) : pas de mise en pause et sauvegardes quotidiennes.
