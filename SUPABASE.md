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
factures, la bibliothèque de prestations, les avoirs ou les factures d'acompte), relancez simplement tout le contenu de `supabase/schema.sql` dans **SQL Editor**. Le
script ne touche pas aux données existantes. Tant qu'il n'est pas relancé, la page continue de
fonctionner, sans la nouveauté (elle prévient quand c'est le cas).

## Assistant IA (facultatif)

Le bouton **Assistant IA** de l'éditeur propose les lignes d'un devis à partir d'une description
du chantier (en reprenant les prix de la bibliothèque) et reformule les descriptions. L'IA est appelée par
une fonction Supabase, `assistant-devis`, qui garde la clé secrète : la page n'y a jamais accès.
Chaque compte est limité à 30 demandes par jour.

L'IA conseillée est **Groq** (modèles ouverts), dont l'API a une offre gratuite sans carte
bancaire. Gemini, Mistral et Claude restent possibles, voir « Changer d'IA » plus bas.

1. **Base** : relancez `supabase/schema.sql` dans **SQL Editor** (il ajoute le compteur de
   demandes).
2. **Clé de l'IA** : sur [console.groq.com](https://console.groq.com), créez un compte, puis
   **API Keys** > **Create API Key**. La clé commence par `gsk_` et ne s'affiche qu'une fois. Elle
   est secrète : ne la mettez jamais dans `index.html`.
3. **Secret** : dans Supabase, **Edge Functions** > **Secrets**, ajoutez `GROQ_API_KEY`
   avec cette clé.
4. **Fonction** : **Edge Functions** > **Deploy a new function** > **Via Editor**. Nommez-la
   exactement `assistant-devis`, remplacez le code d'exemple par tout le contenu de
   `supabase/functions/assistant-devis/index.ts`, puis **Deploy function**. Pour une mise à jour,
   ouvrez la fonction, onglet **Code**, remplacez tout le code puis **Deploy**.

Pour vérifier que la fonction est installée, ouvrez
`https://<votre-projet>.supabase.co/functions/v1/assistant-devis` dans le navigateur : la réponse
attendue est `{"error":"Méthode non autorisée"}`. « Requested function was not found » signifie
qu'elle n'est pas dans ce projet, ou sous un autre nom.

C'est tout : le bouton fonctionne pour tous les comptes connectés, avec votre clé (les autres
utilisateurs n'ont pas besoin de compte chez le fournisseur d'IA). Si l'assistant répond
« Invalid JWT », ouvrez la fonction, onglet **Details**, et désactivez **Verify JWT** : la fonction
vérifie elle-même que l'utilisateur est connecté.

Les offres gratuites limitent le nombre de demandes par minute et par jour, ce qui suffit pour
quelques utilisateurs ; la fonction réessaie automatiquement quand la limite est atteinte. Le
message d'erreur indique l'IA utilisée et sa réponse exacte. Les textes envoyés passent par le
fournisseur d'IA (consultez ses conditions d'utilisation des données). C'est pourquoi la page limite
ce qu'elle envoie :
- seules la description du chantier, les libellés de la bibliothèque et les descriptions des lignes
  sont envoyés : jamais les fiches clients, les factures ni **les prix** (la page remet elle-même
  vos prix sur les lignes reconnues) ;
- avant l'envoi, le nom, l'adresse, l'email et le téléphone du client et de l'entreprise, ainsi que
  tout email, numéro de téléphone ou adresse repéré dans le texte, sont remplacés par des repères
  ([CLIENT], [ADRESSE]…), remis en clair dans la réponse ;
- le bouton **Voir ce qui sera envoyé** affiche le texte exact transmis.

Un nom qui n'est pas celui du client du devis (un voisin, un autre artisan) ne peut pas être
reconnu à coup sûr : vérifiez l'aperçu en cas de doute.

**Changer d'IA** : sans toucher au code, en changeant les secrets.
- Groq : `GROQ_API_KEY` (et `GROQ_MODEL` pour un autre modèle, `openai/gpt-oss-120b` par défaut,
  à choisir parmi les modèles de la console Groq qui gèrent les « tool calls »).
- Gemini : `GEMINI_API_KEY`, une clé de [aistudio.google.com](https://aistudio.google.com) (et
  `GEMINI_MODEL`, `gemini-flash-latest` par défaut). Certains comptes Google sont refusés
  (« Your project has been denied access ») : utilisez alors une autre IA.
- Mistral : `MISTRAL_API_KEY`, une clé de [console.mistral.ai](https://console.mistral.ai). Attention,
  les clés API Mistral ne fonctionnent qu'avec un abonnement (le plan gratuit ne permet de tester
  que dans leur interface).
- Claude (Anthropic, payant à l'usage) : `ANTHROPIC_API_KEY`, une clé de
  [console.anthropic.com](https://console.anthropic.com).

Si plusieurs clés sont présentes, Groq est utilisée en priorité, puis Gemini, Mistral et Claude. Pour
en imposer une, ajoutez le secret `AI_PROVIDER` avec `groq`, `gemini`, `mistral` ou `claude`.

## Offre gratuite ou payante

L'offre gratuite suffit pour tester avec quelques utilisateurs, mais :

- le projet est mis en **pause après 7 jours sans activité** (données conservées, à relancer
  depuis le tableau de bord avec **Restore project**) ;
- il n'y a **pas de sauvegarde automatique** : exportez régulièrement les tables
  (**Table Editor** > table > **Export to CSV**), surtout `factures`, à conserver 10 ans.

Dès que de vrais utilisateurs y mettent leurs factures, passez à l'offre **Pro** (environ
25 $/mois) : pas de mise en pause et sauvegardes quotidiennes.
