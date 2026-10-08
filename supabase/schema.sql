-- Schéma de la base du générateur de devis.
-- À exécuter une fois dans Supabase : SQL Editor > New query > coller ce fichier > Run.
-- Chaque utilisateur ne voit que ses propres données (Row Level Security).

-- Profils enregistrés : entreprises émettrices, clients et prestations de la bibliothèque.
create table if not exists public.profils (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  type text not null check (type in ('entreprise', 'client')),
  donnees jsonb not null default '{}',
  created_at timestamptz not null default now()
);
-- Les profils servent aussi à la bibliothèque de prestations (type « prestation »).
alter table public.profils drop constraint if exists profils_type_check;
alter table public.profils add constraint profils_type_check
  check (type in ('entreprise', 'client', 'prestation'));

-- Devis. L'entreprise et le client sont copiés au moment de l'enregistrement,
-- pour que le document reste identique même si le profil change ensuite.
create table if not exists public.devis (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  numero text not null,
  date_devis date not null default current_date,
  valide_jusqu date,
  statut text not null default 'brouillon'
    check (statut in ('brouillon', 'envoye', 'accepte', 'refuse', 'facture')),
  entreprise jsonb not null default '{}',
  client jsonb not null default '{}',
  lignes jsonb not null default '[]',
  tva numeric not null default 20,
  notes text not null default '',
  total_ht numeric not null default 0,
  total_tva numeric not null default 0,
  total_ttc numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, numero)
);

-- Factures. Créées uniquement par convertir_devis_en_facture (numérotation
-- continue, sans trou) et non modifiables ensuite, sauf leur statut et leur date de paiement.
create table if not exists public.factures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  devis_id uuid references public.devis on delete set null,
  devis_numero text,
  numero text not null,
  date_facture date not null,
  echeance date not null,
  statut text not null default 'emise' check (statut in ('emise', 'payee')),
  entreprise jsonb not null,
  client jsonb not null,
  lignes jsonb not null,
  tva numeric not null,
  notes text not null,
  total_ht numeric not null,
  total_tva numeric not null,
  total_ttc numeric not null,
  created_at timestamptz not null default now(),
  unique (user_id, numero)
);

-- Date de paiement (facultative), renseignée quand la facture est marquée payée.
-- Ajoutée après coup : le script peut être relancé sur une base existante.
alter table public.factures add column if not exists payee_le date;
alter table public.factures drop constraint if exists factures_payee_le_check;
alter table public.factures add constraint factures_payee_le_check
  check (payee_le is null or (statut = 'payee' and payee_le >= date_facture));

-- Dernier numéro de facture attribué, par utilisateur et par année.
create table if not exists public.compteurs_factures (
  user_id uuid not null references auth.users on delete cascade,
  annee int not null,
  dernier int not null,
  primary key (user_id, annee)
);

alter table public.profils enable row level security;
alter table public.devis enable row level security;
alter table public.factures enable row level security;
alter table public.compteurs_factures enable row level security;

drop policy if exists "profils du propriétaire" on public.profils;
create policy "profils du propriétaire" on public.profils for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Un devis facturé ne peut plus être modifié ni supprimé.
drop policy if exists "lecture devis" on public.devis;
create policy "lecture devis" on public.devis for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "ajout devis" on public.devis;
create policy "ajout devis" on public.devis for insert to authenticated
  with check (user_id = auth.uid() and statut <> 'facture');
drop policy if exists "modification devis" on public.devis;
create policy "modification devis" on public.devis for update to authenticated
  using (user_id = auth.uid() and statut <> 'facture')
  with check (user_id = auth.uid() and statut <> 'facture');
drop policy if exists "suppression devis" on public.devis;
create policy "suppression devis" on public.devis for delete to authenticated
  using (user_id = auth.uid() and statut <> 'facture');

drop policy if exists "lecture factures" on public.factures;
create policy "lecture factures" on public.factures for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "statut factures" on public.factures;
create policy "statut factures" on public.factures for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pas de création, de suppression ni de modification directe des factures
-- (seuls le statut et la date de paiement peuvent changer), ni d'accès direct aux compteurs.
revoke insert, update, delete, truncate on public.factures from anon, authenticated;
grant update (statut, payee_le) on public.factures to authenticated;
revoke all on public.compteurs_factures from anon, authenticated;

-- Transforme un devis en facture : attribue le numéro suivant (F-2026-001…),
-- copie le devis dans la facture et passe le devis au statut « facture ».
create or replace function public.convertir_devis_en_facture(
  p_devis_id uuid,
  p_date date default current_date,
  p_echeance date default current_date + 30
) returns public.factures
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  d public.devis;
  f public.factures;
  v_annee int := extract(year from p_date)::int;
  n int;
begin
  if uid is null then
    raise exception 'Connexion requise';
  end if;
  if p_echeance < p_date then
    raise exception 'La date d''échéance doit suivre la date de facture';
  end if;

  select * into d from public.devis where id = p_devis_id and user_id = uid for update;
  if not found then
    raise exception 'Devis introuvable';
  end if;
  if d.statut = 'facture' then
    raise exception 'Ce devis a déjà été facturé';
  end if;

  insert into public.compteurs_factures as c (user_id, annee, dernier)
  values (uid, v_annee, 1)
  on conflict (user_id, annee) do update set dernier = c.dernier + 1
  returning dernier into n;

  insert into public.factures (user_id, devis_id, devis_numero, numero, date_facture, echeance,
    entreprise, client, lignes, tva, notes, total_ht, total_tva, total_ttc)
  values (uid, d.id, d.numero, 'F-' || v_annee || '-' || lpad(n::text, 3, '0'), p_date, p_echeance,
    d.entreprise, d.client, d.lignes, d.tva, d.notes, d.total_ht, d.total_tva, d.total_ttc)
  returning * into f;

  update public.devis set statut = 'facture', updated_at = now() where id = d.id;
  return f;
end;
$$;

revoke execute on function public.convertir_devis_en_facture(uuid, date, date) from public, anon;
grant execute on function public.convertir_devis_en_facture(uuid, date, date) to authenticated;

-- ---- Avoirs ----
-- Un avoir annule tout ou partie d'une facture émise. Il est enregistré dans la table
-- factures (type « avoir »), relié à sa facture, avec sa propre numérotation continue
-- (AV-2026-001…), et, comme une facture, il ne peut être ni modifié ni supprimé.
alter table public.factures add column if not exists type text not null default 'facture';
alter table public.factures drop constraint if exists factures_type_check;
alter table public.factures add constraint factures_type_check check (type in ('facture', 'avoir'));
alter table public.factures add column if not exists avoir_de uuid references public.factures on delete restrict;
alter table public.factures add column if not exists motif text;

create table if not exists public.compteurs_avoirs (
  user_id uuid not null references auth.users on delete cascade,
  annee int not null,
  dernier int not null,
  primary key (user_id, annee)
);
alter table public.compteurs_avoirs enable row level security;
revoke all on public.compteurs_avoirs from anon, authenticated;

-- Crée un avoir sur une facture. Les montants sont recalculés ici à partir des lignes
-- (quantité × prix unitaire HT) et du taux de TVA de la facture ; le total des avoirs
-- ne peut pas dépasser le montant de la facture.
create or replace function public.creer_avoir(
  p_facture_id uuid,
  p_lignes jsonb,
  p_motif text default '',
  p_date date default current_date
) returns public.factures
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  f public.factures;
  a public.factures;
  v_annee int := extract(year from p_date)::int;
  n int;
  l jsonb;
  ht numeric := 0;
  v_tva numeric;
  ttc numeric;
  deja numeric;
begin
  if uid is null then
    raise exception 'Connexion requise';
  end if;
  select * into f from public.factures where id = p_facture_id and user_id = uid for update;
  if not found or f.type <> 'facture' then
    raise exception 'Facture introuvable';
  end if;
  if p_date < f.date_facture then
    raise exception 'L''avoir ne peut pas être daté avant la facture';
  end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then
    raise exception 'L''avoir doit contenir au moins une ligne';
  end if;
  for l in select * from jsonb_array_elements(p_lignes) loop
    if (l->>'q') is null or (l->>'p') is null or (l->>'q')::numeric <= 0 or (l->>'p')::numeric < 0 then
      raise exception 'Ligne d''avoir invalide';
    end if;
    ht := ht + (l->>'q')::numeric * (l->>'p')::numeric;
  end loop;
  ht := round(ht, 2);
  v_tva := round(ht * f.tva / 100, 2);
  ttc := ht + v_tva;
  if ht <= 0 then
    raise exception 'Le montant de l''avoir doit être positif';
  end if;
  select coalesce(sum(total_ttc), 0) into deja from public.factures where avoir_de = f.id;
  if ttc > f.total_ttc - deja + 0.01 then
    raise exception 'L''avoir dépasse le montant restant de la facture';
  end if;

  insert into public.compteurs_avoirs as c (user_id, annee, dernier)
  values (uid, v_annee, 1)
  on conflict (user_id, annee) do update set dernier = c.dernier + 1
  returning dernier into n;

  insert into public.factures (user_id, type, avoir_de, devis_id, devis_numero, numero, date_facture, echeance,
    entreprise, client, lignes, tva, notes, motif, total_ht, total_tva, total_ttc)
  values (uid, 'avoir', f.id, f.devis_id, f.numero, 'AV-' || v_annee || '-' || lpad(n::text, 3, '0'), p_date, p_date,
    f.entreprise, f.client, p_lignes, f.tva, coalesce(p_motif, ''), coalesce(p_motif, ''), ht, v_tva, ttc)
  returning * into a;
  return a;
end;
$$;

revoke execute on function public.creer_avoir(uuid, jsonb, text, date) from public, anon;
grant execute on function public.creer_avoir(uuid, jsonb, text, date) to authenticated;
